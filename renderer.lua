-- hyper-optimized, layer-based, batched renderer with aggressive luajit optimizations
-- @module renderer

local renderer = {}

local lg = love.graphics
local lg_newCanvas = lg.newCanvas
local lg_newSpriteBatch = lg.newSpriteBatch
local lg_setCanvas = lg.setCanvas
local lg_clear = lg.clear
local lg_setColor = lg.setColor
local lg_setShader = lg.setShader
local lg_setBlendMode = lg.setBlendMode
local lg_setScissor = lg.setScissor
local lg_push = lg.push
local lg_pop = lg.pop
local lg_translate = lg.translate
local lg_scale = lg.scale
local lg_rotate = lg.rotate
local lg_draw = lg.draw
local lg_rectangle = lg.rectangle
local lg_circle = lg.circle
local lg_line = lg.line
local lg_polygon = lg.polygon
local lg_arc = lg.arc
local lg_getWidth = lg.getWidth
local lg_getHeight = lg.getHeight

-- local math functions
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local math_cos = math.cos
local math_sqrt = math.sqrt
local math_atan2 = math.atan
local math_random = math.random
local math_exp = math.exp

-- local table functions
local table_insert = table.insert
local table_sort = table.sort

-- ieee 754 hex constants
local F05 = 0x1.0p-1 -- 0.5

-- ============================================================================
-- internal state
-- ============================================================================

local main_canvas = nil
local screen_size = { w = 0, h = 0 }
local target_size = { w = 0, h = 0 }
local final_scale = 1
local clear_color = { 0.1, 0.1, 0.1, 1 }

-- lighting state
local light_canvas = nil
local light_shader = nil
local lighting_enabled = false
local current_lights = nil
local current_light_count = 0
local current_ambient = { 0, 0, 0 }

-- fixed-size pre-allocated sprite queue (avoid table resizing)
local max_sprites_per_layer = 10000
local sprite_queues = {} -- [layer] = {sprites = array, count = n}

-- pre-allocated primitive queue
local max_primitives_per_layer = 1000
local primitive_queues = {} -- [layer] = {primitives = array, count = n}

-- sprite batches: { texture_id = SpriteBatch }
local sprite_batches = {}
local batch_usage_hint = "stream" -- stream is best for dynamic per-frame updates

-- batch size configuration
local batch_sizes = {}
local default_batch_size = 1000

-- static layer caching: { layer = {canvas, dirty, draw_func} }
local static_layers = {}

-- layer shaders: { layer = {shader, uniforms} }
local layer_shaders = {}

-- blend modes per layer: { layer = {mode, alpha} }
local layer_blend_modes = {}

-- layer visibility and opacity (direct indexing, no defaults table)
local layer_visible = {}
local layer_opacity = {}

-- texture atlas support
local texture_atlases = {}

-- sprite animation tracking
local animations = {}
local animation_counter = 0

local active_camera = nil
-- viewport/scissor
local viewport = nil -- {x, y, w, h}

-- render statistics (updated per frame)
local stats_draw_calls = 0
local stats_sprites_drawn = 0
local stats_primitives_drawn = 0
local stats_batches_used = 0
local stats_triangles = 0

-- memory pool for sprite objects (fixed size, circular buffer)
local sprite_pool_size = 20000
local sprite_pool = {}
local sprite_pool_top = 0

-- pre-allocate sprite pool
for i = 1, sprite_pool_size do
    sprite_pool[i] = {
        tex = nil,
        x = 0,
        y = 0,
        q = nil,
        r = 0,
        sx = 1,
        sy = 1,
        ox = 0,
        oy = 0,
        color = { 1, 1, 1, 1 },
        z = 0
    }
end

-- frustum culling
local frustum_culling_enabled = true
local frustum_left, frustum_right, frustum_top, frustum_bottom = 0, 0, 0, 0

-- sorted layer keys cache (reused every frame)
local sorted_layer_keys = {}
local sorted_layer_count = 0

-- post-processing pipeline
local post_process_stack = {}   -- array of {shader, uniforms, blend_mode}
local post_process_buffers = {} -- ping-pong buffers for multi-pass
local post_process_enabled = false

-- default light shader code
local default_light_shader_code = [[
    extern vec3 light_color;
    extern vec3 light_pos; // x, y, z (z is unused for 2D but good for alignment)
    extern vec3 light_params; // range, intensity, unused
    extern vec3 attenuation; // constant, linear, quadratic

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        // Calculate distance
        float dist = distance(screen_coords, light_pos.xy);

        // Range check
        if (dist > light_params.x) {
            return vec4(0.0);
        }

        // Calculate attenuation
        float att = 1.0 / (attenuation.x + attenuation.y * dist + attenuation.z * dist * dist);

        // Apply intensity
        att *= light_params.y;

        // Smooth falloff at edge of range
        float falloff = 1.0 - smoothstep(light_params.x * 0.8, light_params.x, dist);
        att *= falloff;

        return vec4(light_color * att, 1.0);
    }
]]

-- ============================================================================
-- private helpers (inlined where possible)
-- ============================================================================

-- get sprite from pool (hot: inline-friendly)
local function get_pooled_sprite()
    if sprite_pool_top > 0 then
        local sprite = sprite_pool[sprite_pool_top]
        sprite_pool_top = sprite_pool_top - 1
        return sprite
    end
    -- fallback: create new (rare after warmup)
    return {
        tex = nil,
        x = 0,
        y = 0,
        q = nil,
        r = 0,
        sx = 1,
        sy = 1,
        ox = 0,
        oy = 0,
        color = { 1, 1, 1, 1 },
        z = 0
    }
end

-- return sprite to pool (hot)
local function return_to_pool(sprite)
    if sprite_pool_top < sprite_pool_size then
        sprite_pool_top = sprite_pool_top + 1
        sprite_pool[sprite_pool_top] = sprite
    end
end

-- check if sprite is in camera frustum (hot: minimal branching)
local function is_in_frustum(x, y, w, h)
    return not (x + w < frustum_left or x > frustum_right or
        y + h < frustum_top or y > frustum_bottom)
end

-- update frustum bounds (called once per frame before culling)
local function update_frustum_bounds()
    if not active_camera then return end
    local cam_x, cam_y = active_camera:get_position()
    local cam_zoom = active_camera:get_zoom()

    local inv_zoom = 1 / cam_zoom
    local half_w = target_size.w * F05 * inv_zoom
    local half_h = target_size.h * F05 * inv_zoom
    frustum_left = cam_x - half_w
    frustum_right = cam_x + half_w
    frustum_top = cam_y - half_h
    frustum_bottom = cam_y + half_h
end

-- get or create sprite queue for layer (warm)
local function get_sprite_queue(layer)
    local queue = sprite_queues[layer]
    if not queue then
        -- pre-allocate fixed-size array
        local sprites = {}
        for i = 1, max_sprites_per_layer do
            sprites[i] = false -- placeholder
        end
        queue = { sprites = sprites, count = 0 }
        sprite_queues[layer] = queue
    end
    return queue
end

-- get or create primitive queue for layer (warm)
local function get_primitive_queue(layer)
    local queue = primitive_queues[layer]
    if not queue then
        local primitives = {}
        for i = 1, max_primitives_per_layer do
            primitives[i] = false
        end
        queue = { primitives = primitives, count = 0 }
        primitive_queues[layer] = queue
    end
    return queue
end

-- sort sprites by z-index within a layer (warm)
local function sort_sprites_by_z(sprites, count)
    -- only sort if we have sprites with z-index
    if count == 0 then return end

    -- check if first sprite has z-index
    local first_sprite = sprites[1]
    if not first_sprite or first_sprite.z == 0 then
        -- check if any sprite has non-zero z
        local has_z = false
        for i = 1, count do
            local s = sprites[i]
            if s and s.z ~= 0 then
                has_z = true
                break
            end
        end
        if not has_z then return end
    end

    -- build temp array with only valid sprites (avoid sorting false placeholders)
    local temp = {}
    for i = 1, count do
        temp[i] = sprites[i]
    end

    -- use numeric for loop for jit-friendliness
    -- simple insertion sort for small counts, quicksort for large
    if count < 50 then
        for i = 2, count do
            local sprite = temp[i]
            local j = i - 1
            while j > 0 and temp[j].z > sprite.z do
                temp[j + 1] = temp[j]
                j = j - 1
            end
            temp[j + 1] = sprite
        end
    else
        table_sort(temp, function(a, b) return a.z < b.z end)
    end

    -- copy back
    for i = 1, count do
        sprites[i] = temp[i]
    end
end

-- apply shader uniforms (warm)
local function apply_shader_uniforms(shader, uniforms)
    if not uniforms then return end
    for name, value in pairs(uniforms) do
        local success, err = pcall(shader.send, shader, name, value)
        if not success then
            -- silently ignore missing uniforms (shader might not use them)
        end
    end
end

-- draw all dynamic (non-cached) elements (hot)
local function draw_dynamic_queues()
    -- reset stats
    stats_draw_calls = 0
    stats_sprites_drawn = 0
    stats_primitives_drawn = 0
    stats_batches_used = 0
    stats_triangles = 0

    -- local list of keys, do not reuse the shared list
    local sorted_layer_keys = {}
    local sorted_layer_count = 0

    -- collect visible layers
    for layer, queue in pairs(sprite_queues) do
        if layer_visible[layer] ~= false then
            sorted_layer_count = sorted_layer_count + 1
            sorted_layer_keys[sorted_layer_count] = layer
        end
    end
    for layer, queue in pairs(primitive_queues) do
        if layer_visible[layer] ~= false and not sprite_queues[layer] then
            sorted_layer_count = sorted_layer_count + 1
            sorted_layer_keys[sorted_layer_count] = layer
        end
    end
    table_sort(sorted_layer_keys, function(a, b) return a < b end)

    -- update frustum bounds
    if frustum_culling_enabled then
        update_frustum_bounds()
    end

    -- draw batches and primitives in layer order (hot)
    for i = 1, sorted_layer_count do
        local layer = sorted_layer_keys[i]
        local sprite_queue = sprite_queues[layer]
        local primitive_queue = primitive_queues[layer]
        local layer_opacity_val = layer_opacity[layer] or 1.0

        -- pop. batches for this layer
        if sprite_queue and sprite_queue.count > 0 then
            local sprites = sprite_queue.sprites
            local count = sprite_queue.count

            -- sort by z-index if needed
            sort_sprites_by_z(sprites, count)

            -- process sprites (hot)
            for j = 1, count do
                local s = sprites[j]

                -- frustum culling (inline)
                if frustum_culling_enabled then
                    local w, h
                    if s.q then
                        local _, _, qw, qh = s.q:getViewport()
                        w = qw * s.sx
                        h = qh * s.sy
                    else
                        w = s.tex:getWidth() * s.sx
                        h = s.tex:getHeight() * s.sy
                    end

                    if not is_in_frustum(s.x - s.ox, s.y - s.oy, w, h) then
                        goto continue
                    end
                end

                -- get or create batch for texture
                local batch = sprite_batches[s.tex]
                if not batch then
                    local size = batch_sizes[s.tex] or default_batch_size
                    batch = lg_newSpriteBatch(s.tex, size, batch_usage_hint)
                    sprite_batches[s.tex] = batch
                end

                -- apply layer opacity to sprite color
                local color = s.color
                if layer_opacity_val < 1.0 then
                    batch:setColor(color[1], color[2], color[3], color[4] * layer_opacity_val)
                else
                    batch:setColor(color[1], color[2], color[3], color[4])
                end

                -- add to batch (with or without quad)
                if s.q then
                    batch:add(s.q, s.x, s.y, s.r, s.sx, s.sy, s.ox, s.oy)
                else
                    batch:add(s.x, s.y, s.r, s.sx, s.sy, s.ox, s.oy)
                end

                batch:setColor(1, 1, 1, 1)

                stats_sprites_drawn = stats_sprites_drawn + 1
                stats_triangles = stats_triangles + 2

                -- return to pool
                return_to_pool(s)

                ::continue::
            end

            -- reset queue count
            sprite_queue.count = 0
        end

        -- apply layer effects
        local shader_data = layer_shaders[layer]
        if shader_data then
            lg_setShader(shader_data.shader)
            apply_shader_uniforms(shader_data.shader, shader_data.uniforms)
        end

        local blend = layer_blend_modes[layer]
        if blend then
            lg_setBlendMode(blend.mode, blend.alpha)
        end

        -- apply layer opacity
        if layer_opacity_val < 1.0 then
            lg_setColor(1, 1, 1, layer_opacity_val)
        end

        -- draw all populated batches
        for tex, batch in pairs(sprite_batches) do
            local batch_count = batch:getCount()
            if batch_count > 0 then
                lg_draw(batch)
                stats_draw_calls = stats_draw_calls + 1
                stats_batches_used = stats_batches_used + 1
            end
            -- clear batch after drawing
            batch:clear()
        end

        -- draw primitives
        if primitive_queue and primitive_queue.count > 0 then
            local primitives = primitive_queue.primitives
            local count = primitive_queue.count

            local current_color = nil

            for j = 1, count do
                local p = primitives[j]

                -- apply opacity to primitive color
                local color = p.color
                if layer_opacity_val < 1.0 then
                    local r, g, b, a = color[1], color[2], color[3], color[4]
                    if current_color ~= p then
                        lg_setColor(r, g, b, a * layer_opacity_val)
                        current_color = p
                    end
                else
                    if current_color ~= p then
                        lg_setColor(color[1], color[2], color[3], color[4])
                        current_color = p
                    end
                end

                -- draw primitive based on type
                local ptype = p.type
                if ptype == 'rect' then
                    lg_rectangle(p.mode, p.x, p.y, p.w, p.h)
                    stats_triangles = stats_triangles + (p.mode == "fill" and 2 or 4)
                elseif ptype == 'circle' then
                    lg_circle(p.mode, p.x, p.y, p.r, p.segments or 32)
                    stats_triangles = stats_triangles + (p.segments or 32)
                elseif ptype == 'line' then
                    lg_line(p.points)
                    stats_triangles = stats_triangles + (#p.points / 2 - 1)
                elseif ptype == 'polygon' then
                    lg_polygon(p.mode, p.points)
                    stats_triangles = stats_triangles + (#p.points / 2 - 2)
                elseif ptype == 'arc' then
                    lg_arc(p.mode, p.x, p.y, p.r, p.angle1, p.angle2, p.segments or 32)
                    stats_triangles = stats_triangles + (p.segments or 32)
                end

                stats_primitives_drawn = stats_primitives_drawn + 1
                stats_draw_calls = stats_draw_calls + 1
            end

            -- reset primitive queue count
            primitive_queue.count = 0
        end

        -- reset state
        lg_setColor(1, 1, 1, 1)

        if shader_data then
            lg_setShader()
        end
        if blend then
            lg_setBlendMode("alpha")
        end
    end
end

-- apply post-processing effects (cold, once per frame)
local function apply_post_processing(source_canvas)
    if #post_process_stack == 0 then
        return source_canvas
    end

    -- ensure we have buffers
    if not post_process_buffers[1] then
        post_process_buffers[1] = lg_newCanvas(target_size.w, target_size.h)
        post_process_buffers[1]:setFilter("nearest", "nearest")
    end
    if not post_process_buffers[2] then
        post_process_buffers[2] = lg_newCanvas(target_size.w, target_size.h)
        post_process_buffers[2]:setFilter("nearest", "nearest")
    end

    local src = source_canvas
    local dst_idx = 1

    -- apply each post-process pass
    for i = 1, #post_process_stack do
        local pass = post_process_stack[i]
        local dst = post_process_buffers[dst_idx]

        lg_setCanvas(dst)
        lg_clear(0, 0, 0, 0)

        lg_setShader(pass.shader)
        apply_shader_uniforms(pass.shader, pass.uniforms)

        if pass.blend_mode then
            lg_setBlendMode(pass.blend_mode.mode, pass.blend_mode.alpha)
        end

        lg_setColor(1, 1, 1, 1)
        lg_draw(src)

        lg_setShader()
        if pass.blend_mode then
            lg_setBlendMode("alpha")
        end

        src = dst
        dst_idx = dst_idx == 1 and 2 or 1
    end

    lg_setCanvas()
    return src
end

-- render lighting pass
local function render_lighting()
    if not lighting_enabled or not light_canvas or not active_camera then return end

    -- set render target to light canvas
    lg_setCanvas(light_canvas)
    -- clear to ambient color
    lg_clear(current_ambient[1], current_ambient[2], current_ambient[3], 1)

    if current_light_count > 0 and current_lights then
        -- enable additive blending for lights
        lg_setBlendMode("add")
        lg_setShader(light_shader)

        local is_ffi = type(current_lights) == "cdata"
        local cam_x, cam_y = active_camera:get_position()
        local cam_zoom = active_camera:get_zoom()

        for i = 1, current_light_count do
            local lx, ly, range, r, g, b, intensity, att_c, att_l, att_q

            if is_ffi then
                -- FFI is 0-based
                local l = current_lights[i - 1]
                if l.enabled then
                    lx, ly = l.x, l.y
                    range = l.range
                    r, g, b = l.r, l.g, l.b
                    intensity = l.intensity
                    att_c, att_l, att_q = l.att_const, l.att_linear, l.att_quad
                end
            else
                -- table is SOA, 1-based
                if current_lights.enabled[i] then
                    lx = current_lights.x[i]
                    ly = current_lights.y[i]
                    range = current_lights.range[i]
                    r = current_lights.r[i]
                    g = current_lights.g[i]
                    b = current_lights.b[i]
                    intensity = current_lights.intensity[i]
                    att_c = current_lights.att_const[i]
                    att_l = current_lights.att_linear[i]
                    att_q = current_lights.att_quad[i]
                end
            end

            if lx then
                -- transform world pos to screen pos for shader
                local sx = (lx - cam_x) * cam_zoom + target_size.w * 0.5
                local sy = (ly - cam_y) * cam_zoom + target_size.h * 0.5
                local s_range = range * cam_zoom

                -- cull if off screen
                if sx + s_range > 0 and sx - s_range < target_size.w and
                    sy + s_range > 0 and sy - s_range < target_size.h then
                    light_shader:send("light_pos", { sx, sy, 0 })
                    light_shader:send("light_color", { r, g, b })
                    light_shader:send("light_params", { s_range, intensity, 0 })
                    light_shader:send("attenuation", { att_c, att_l, att_q })

                    -- draw a rectangle covering the light's influence
                    lg_rectangle("fill", sx - s_range, sy - s_range, s_range * 2, s_range * 2)
                end
            end
        end

        lg_setShader()
        lg_setBlendMode("alpha")
    end

    lg_setCanvas()
end

-- ============================================================================
-- public api
-- ============================================================================

--- initialize the renderer
--- @param target_w number internal game width
--- @param target_h number internal game height
--- @param scale number integer scaling factor
function renderer.init(target_w, target_h, scale)
    target_size = { w = target_w, h = target_h }
    final_scale = scale or 1
    screen_size = {
        w = lg_getWidth(),
        h = lg_getHeight()
    }

    main_canvas = lg_newCanvas(target_w, target_h)
    main_canvas:setFilter("nearest", "nearest")

    -- init light canvas
    light_canvas = lg_newCanvas(target_w, target_h)
    light_canvas:setFilter("nearest", "nearest")

    -- init light shader
    light_shader = lg.newShader(default_light_shader_code)

    -- initialize visibility/opacity for common layers
    for i = 0, 100 do
        layer_visible[i] = true
        layer_opacity[i] = 1.0
    end

    -- warm up sprite pool (force allocation)
    sprite_pool_top = sprite_pool_size
end

--- set the canvas clear color
function renderer.set_clear_color(r, g, b)
    clear_color = { r, g, b, 1 }
end

--- set pre-allocated batch size for a texture
function renderer.set_batch_size(texture, size)
    batch_sizes[texture] = size
end

--- set default batch size
function renderer.set_default_batch_size(size)
    default_batch_size = size
end

--- set blend mode for a layer
function renderer.set_layer_blend_mode(layer, mode, alphamode)
    layer_blend_modes[layer] = {
        mode = mode,
        alpha = alphamode or "alphamultiply"
    }
end

--- clear blend mode for a layer
function renderer.clear_layer_blend_mode(layer)
    layer_blend_modes[layer] = nil
end

--- set shader for a layer with optional uniforms
--- @param layer number layer index
--- @param shader Shader love2d shader object
--- @param uniforms table optional uniform name-value pairs
function renderer.set_layer_shader(layer, shader, uniforms)
    if not shader then
        layer_shaders[layer] = nil
        return
    end
    layer_shaders[layer] = {
        shader = shader,
        uniforms = uniforms or {}
    }
end

--- update shader uniforms for a layer without changing the shader
--- @param layer number layer index
--- @param uniforms table uniform name-value pairs to update
--- @return boolean success
function renderer.update_layer_shader_uniforms(layer, uniforms)
    local shader_data = layer_shaders[layer]
    if not shader_data then
        return false
    end

    for name, value in pairs(uniforms) do
        shader_data.uniforms[name] = value
    end

    return true
end

--- clear shader for a layer
function renderer.clear_layer_shader(layer)
    layer_shaders[layer] = nil
end

--- set layer visibility
function renderer.set_layer_visible(layer, visible)
    layer_visible[layer] = visible
end

--- get layer visibility
function renderer.get_layer_visible(layer)
    return layer_visible[layer] ~= false
end

--- set layer opacity
function renderer.set_layer_opacity(layer, opacity)
    layer_opacity[layer] = math_max(0, math_min(1, opacity))
end

--- get layer opacity
function renderer.get_layer_opacity(layer)
    return layer_opacity[layer] or 1.0
end

--- add a post-processing effect to the stack
--- @param shader Shader love2d shader object
--- @param uniforms table optional uniform name-value pairs
--- @param blend_mode table optional {mode = "add", alpha = "alphamultiply"}
function renderer.add_post_process(shader, uniforms, blend_mode)
    if not shader then return end

    table_insert(post_process_stack, {
        shader = shader,
        uniforms = uniforms or {},
        blend_mode = blend_mode
    })

    post_process_enabled = true
end

--- update uniforms for a post-processing effect
--- @param index number position in the post-process stack (1-based)
--- @param uniforms table uniform name-value pairs to update
--- @return boolean success
function renderer.update_post_process_uniforms(index, uniforms)
    local pass = post_process_stack[index]
    if not pass then return false end

    for name, value in pairs(uniforms) do
        pass.uniforms[name] = value
    end

    return true
end

--- remove a post-processing effect from the stack
--- @param index number position in the post-process stack (1-based)
function renderer.remove_post_process(index)
    table.remove(post_process_stack, index)
    post_process_enabled = #post_process_stack > 0
end

--- clear all post-processing effects
function renderer.clear_post_process()
    post_process_stack = {}
    post_process_enabled = false
end

--- create a texture atlas
function renderer.create_atlas(id, texture, tile_width, tile_height)
    if not texture then
        return nil, "texture is nil"
    end

    local atlas = {
        texture = texture,
        tile_w = tile_width,
        tile_h = tile_height,
        quads = {}
    }

    local img_w = texture:getWidth()
    local img_h = texture:getHeight()
    local cols = math_floor(img_w / tile_width)
    local rows = math_floor(img_h / tile_height)

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local idx = row * cols + col
            atlas.quads[idx] = lg.newQuad(
                col * tile_width,
                row * tile_height,
                tile_width,
                tile_height,
                img_w,
                img_h
            )
        end
    end

    texture_atlases[id] = atlas
    return atlas
end

--- get quad from atlas
--- @return Quad, error
function renderer.get_atlas_quad(atlas_id, index)
    local atlas = texture_atlases[atlas_id]
    if not atlas then
        return nil, "atlas not found: " .. tostring(atlas_id)
    end
    local quad = atlas.quads[index]
    if not quad then
        return nil, "quad index out of bounds: " .. tostring(index)
    end
    return quad
end

--- create a sprite animation
function renderer.create_animation(frames, frame_duration, loop)
    if not frames or #frames == 0 then
        return nil, "frames table is empty or nil"
    end

    animation_counter = animation_counter + 1
    animations[animation_counter] = {
        frames = frames,
        duration = frame_duration,
        current_frame = 1,
        timer = 0,
        loop = loop ~= false,
        playing = true
    }
    return animation_counter
end

--- update animations
function renderer.update_animations(dt)
    for id, anim in pairs(animations) do
        if anim.playing then
            anim.timer = anim.timer + dt
            if anim.timer >= anim.duration then
                anim.timer = anim.timer - anim.duration
                anim.current_frame = anim.current_frame + 1
                if anim.current_frame > #anim.frames then
                    if anim.loop then
                        anim.current_frame = 1
                    else
                        anim.current_frame = #anim.frames
                        anim.playing = false
                    end
                end
            end
        end
    end
end

--- play animation
function renderer.play_animation(animation_id)
    local anim = animations[animation_id]
    if anim then anim.playing = true end
end

--- pause animation
function renderer.pause_animation(animation_id)
    local anim = animations[animation_id]
    if anim then anim.playing = false end
end

--- reset animation to first frame
function renderer.reset_animation(animation_id)
    local anim = animations[animation_id]
    if anim then
        anim.current_frame = 1
        anim.timer = 0
    end
end

--- get current frame from animation
--- @return atlas_id, tile_index or nil, error
function renderer.get_animation_frame(animation_id)
    local anim = animations[animation_id]
    if not anim then
        return nil, "animation not found: " .. tostring(animation_id)
    end
    local frame = anim.frames[anim.current_frame]
    return frame[1], frame[2]
end

--- update camera (shake, lerp, etc)
function renderer.update(dt)
    -- update animations
    renderer.update_animations(dt)

    -- update active camera if it exists
    if active_camera then
        active_camera:update(dt)
    end

    -- clear post process stack for next frame (safety)
    post_process_stack = {}
    post_process_enabled = false
end

--- set active camera
function renderer.set_active_camera(cam)
    active_camera = cam
end

--- get active camera
function renderer.get_active_camera()
    return active_camera
end

--- create a static layer canvas with dirty flag support
function renderer.create_static_layer(layer, draw_function)
    renderer.clear_static_layer(layer)

    local canvas = lg_newCanvas(target_size.w, target_size.h)
    canvas:setFilter("nearest", "nearest")

    static_layers[layer] = {
        canvas = canvas,
        dirty = true,
        draw_func = draw_function
    }

    renderer.mark_static_layer_dirty(layer)
end

--- mark a static layer as dirty (needs redraw)
function renderer.mark_static_layer_dirty(layer)
    local layer_data = static_layers[layer]
    if layer_data then
        layer_data.dirty = true
    end
end

--- redraw dirty static layers
function renderer.update_static_layers()
    for layer, data in pairs(static_layers) do
        if data.dirty then
            lg_setCanvas(data.canvas)
            lg_clear(0, 0, 0, 0)
            data.draw_func()
            lg_setCanvas()
            data.dirty = false
        end
    end
end

--- clear a cached static layer
function renderer.clear_static_layer(layer)
    static_layers[layer] = nil
end

--- clear all cached static layers
function renderer.clear_all_static_layers()
    static_layers = {}
end

--- add a dynamic sprite to the draw queue (hot path)
function renderer.draw_sprite(layer, texture, x, y, quad, options)
    if not texture then return end

    local queue = get_sprite_queue(layer)
    local count = queue.count + 1

    if count > max_sprites_per_layer then
        return
    end

    options = options or {}

    local sprite = get_pooled_sprite()
    sprite.tex = texture
    sprite.x = x
    sprite.y = y
    sprite.q = quad
    sprite.r = options.r or 0
    sprite.sx = options.sx or 1
    sprite.sy = options.sy or 1
    sprite.ox = options.ox or 0
    sprite.oy = options.oy or 0

    -- reuse or set color
    local color = options.color
    if color then
        sprite.color[1] = color[1]
        sprite.color[2] = color[2]
        sprite.color[3] = color[3]
        sprite.color[4] = color[4]
    else
        sprite.color[1] = 1
        sprite.color[2] = 1
        sprite.color[3] = 1
        sprite.color[4] = 1
    end

    sprite.z = options.z or 0

    queue.sprites[count] = sprite
    queue.count = count
end

--- draw sprite from atlas
function renderer.draw_atlas_sprite(layer, atlas_id, tile_index, x, y, options)
    local atlas = texture_atlases[atlas_id]
    if not atlas then return end
    local quad = atlas.quads[tile_index]
    if not quad then return end

    renderer.draw_sprite(layer, atlas.texture, x, y, quad, options)
end

--- draw animated sprite
function renderer.draw_animated_sprite(layer, animation_id, x, y, options)
    local atlas_id, tile_index = renderer.get_animation_frame(animation_id)
    if not atlas_id then return end
    renderer.draw_atlas_sprite(layer, atlas_id, tile_index, x, y, options)
end

--- add a rectangle primitive to the dynamic draw queue
function renderer.draw_rect(layer, mode, x, y, w, h, color)
    local queue = get_primitive_queue(layer)
    local count = queue.count + 1

    if count > max_primitives_per_layer then
        return
    end

    local prim = queue.primitives[count]
    if not prim then
        prim = {}
        queue.primitives[count] = prim
    end

    prim.type = 'rect'
    prim.mode = mode
    prim.x = x
    prim.y = y
    prim.w = w
    prim.h = h
    prim.color = color or { 1, 1, 1, 1 }

    queue.count = count
end

--- add a circle primitive to the dynamic draw queue
function renderer.draw_circle(layer, mode, x, y, radius, color, segments)
    local queue = get_primitive_queue(layer)
    local count = queue.count + 1

    if count > max_primitives_per_layer then
        return
    end

    local prim = queue.primitives[count]
    if not prim then
        prim = {}
        queue.primitives[count] = prim
    end

    prim.type = 'circle'
    prim.mode = mode
    prim.x = x
    prim.y = y
    prim.r = radius
    prim.color = color or { 1, 1, 1, 1 }
    prim.segments = segments

    queue.count = count
end

--- add a line primitive to the dynamic draw queue
function renderer.draw_line(layer, points, color)
    local queue = get_primitive_queue(layer)
    local count = queue.count + 1

    if count > max_primitives_per_layer then
        return
    end

    local prim = queue.primitives[count]
    if not prim then
        prim = {}
        queue.primitives[count] = prim
    end

    prim.type = 'line'
    prim.points = points
    prim.color = color or { 1, 1, 1, 1 }

    queue.count = count
end

--- add a polygon primitive to the dynamic draw queue
function renderer.draw_polygon(layer, mode, points, color)
    local queue = get_primitive_queue(layer)
    local count = queue.count + 1

    if count > max_primitives_per_layer then
        return
    end

    local prim = queue.primitives[count]
    if not prim then
        prim = {}
        queue.primitives[count] = prim
    end

    prim.type = 'polygon'
    prim.mode = mode
    prim.points = points
    prim.color = color or { 1, 1, 1, 1 }

    queue.count = count
end

--- add an arc primitive to the dynamic draw queue
function renderer.draw_arc(layer, mode, x, y, radius, angle1, angle2, color, segments)
    local queue = get_primitive_queue(layer)
    local count = queue.count + 1

    if count > max_primitives_per_layer then
        return
    end

    local prim = queue.primitives[count]
    if not prim then
        prim = {}
        queue.primitives[count] = prim
    end

    prim.type = 'arc'
    prim.mode = mode
    prim.x = x
    prim.y = y
    prim.r = radius
    prim.angle1 = angle1
    prim.angle2 = angle2
    prim.color = color or { 1, 1, 1, 1 }
    prim.segments = segments

    queue.count = count
end

--- look at a world position
function renderer.camera_look_at(x, y)
    if active_camera then
        active_camera:look_at(x, y)
    end
end

--- set camera zoom
function renderer.set_camera_zoom(zoom)
    if active_camera then
        active_camera:set_zoom(zoom)
    end
end

--- get camera zoom
function renderer.get_camera_zoom()
    if active_camera then
        return active_camera:get_zoom()
    end
    return 1
end

--- set camera rotation
function renderer.set_camera_rotation(rotation)
    if active_camera then
        active_camera:set_rotation(rotation)
    end
end

--- get camera rotation
function renderer.get_camera_rotation()
    if active_camera then
        return active_camera:get_rotation()
    end
    return 0
end

--- set viewport/scissor region
function renderer.set_viewport(x, y, w, h)
    viewport = { x = x, y = y, w = w, h = h }
end

--- clear viewport/scissor
function renderer.clear_viewport()
    viewport = nil
end

--- enable or disable frustum culling
function renderer.set_frustum_culling(enabled)
    frustum_culling_enabled = enabled
end

--- get render statistics
function renderer.get_stats()
    return {
        draw_calls = stats_draw_calls,
        sprites_drawn = stats_sprites_drawn,
        primitives_drawn = stats_primitives_drawn,
        batches_used = stats_batches_used,
        triangles = stats_triangles
    }
end

--- world to screen coordinates
function renderer.world_to_screen(world_x, world_y)
    if not active_camera then return world_x, world_y end
    local cam_x, cam_y = active_camera:get_position()
    local cam_zoom = active_camera:get_zoom()
    local screen_x = (world_x - cam_x) * cam_zoom + target_size.w * F05
    local screen_y = (world_y - cam_y) * cam_zoom + target_size.h * F05
    return screen_x, screen_y
end

--- screen to world coordinates
function renderer.screen_to_world(screen_x, screen_y)
    if not active_camera then return screen_x, screen_y end
    local cam_x, cam_y = active_camera:get_position()
    local cam_zoom = active_camera:get_zoom()
    local inv_zoom = 1 / cam_zoom
    local world_x = (screen_x - target_size.w * F05) * inv_zoom + cam_x
    local world_y = (screen_y - target_size.h * F05) * inv_zoom + cam_y
    return world_x, world_y
end

--- present all draw queues to the screen (main draw function)
function renderer.present()
    -- update any dirty static layers
    renderer.update_static_layers()

    -- update screen size (handle resize)
    screen_size.w = lg_getWidth()
    screen_size.h = lg_getHeight()

    -- draw game world to target canvas
    lg_setCanvas(main_canvas)
    lg_clear(clear_color[1], clear_color[2], clear_color[3], 1)

    -- apply viewport if set
    if viewport then
        lg_setScissor(viewport.x, viewport.y, viewport.w, viewport.h)
    end

    -- apply camera
    lg_push()

    if active_camera then
        active_camera:resize(target_size.w, target_size.h)
        active_camera:apply()
    end

    -- collect all layer keys (static and dynamic)
    sorted_layer_count = 0
    for k in pairs(static_layers) do
        if layer_visible[k] ~= false then
            sorted_layer_count = sorted_layer_count + 1
            sorted_layer_keys[sorted_layer_count] = k
        end
    end

    -- ensure we don't double-count layers that have both static and dynamic
    local static_layer_set = {}
    for i = 1, sorted_layer_count do
        static_layer_set[sorted_layer_keys[i]] = true
    end

    for k in pairs(sprite_queues) do
        if layer_visible[k] ~= false and not static_layer_set[k] then
            sorted_layer_count = sorted_layer_count + 1
            sorted_layer_keys[sorted_layer_count] = k
        end
    end

    for k in pairs(primitive_queues) do
        if layer_visible[k] ~= false and not static_layer_set[k] and not sprite_queues[k] then
            sorted_layer_count = sorted_layer_count + 1
            sorted_layer_keys[sorted_layer_count] = k
        end
    end

    table_sort(sorted_layer_keys, function(a, b) return a < b end)

    -- draw all static layers first (in order)
    for i = 1, sorted_layer_count do
        local layer_idx = sorted_layer_keys[i]
        local layer_data = static_layers[layer_idx]

        if layer_data then
            -- apply layer shader if exists
            local shader_data = layer_shaders[layer_idx]
            if shader_data then
                lg_setShader(shader_data.shader)
                apply_shader_uniforms(shader_data.shader, shader_data.uniforms)
            end

            -- apply layer blend mode if exists
            local blend = layer_blend_modes[layer_idx]
            if blend then
                lg_setBlendMode(blend.mode, blend.alpha)
            end

            lg_draw(layer_data.canvas, 0, 0)

            -- reset shader and blend mode
            if shader_data then
                lg_setShader()
            end
            if blend then
                lg_setBlendMode("alpha")
            end
        end
    end

    draw_dynamic_queues()

    lg_pop()
    lg_setCanvas()

    if lighting_enabled then
        render_lighting()
    end

    local final_texture = main_canvas
    if post_process_enabled then
        final_texture = apply_post_processing(main_canvas)
    end

    lg_push()
    -- scale to window
    local sx = screen_size.w / target_size.w
    local sy = screen_size.h / target_size.h
    local s = math_min(sx, sy)

    lg_translate(screen_size.w * 0.5, screen_size.h * 0.5)
    lg_scale(s, s)
    lg_translate(-target_size.w * 0.5, -target_size.h * 0.5)

    -- draw scene
    lg_setColor(1, 1, 1, 1)
    lg_draw(final_texture, 0, 0)

    -- draw lighting overlay (multiply)
    if lighting_enabled and light_canvas then
        lg_setBlendMode("multiply", "premultiplied")
        lg_draw(light_canvas, 0, 0)
        lg_setBlendMode("alpha")
    end

    lg_pop()
    
    -- reset lighting state for next frame
    lighting_enabled = false
    current_lights = nil
    current_light_count = 0
end

--- submit lighting data for this frame
--- @param lights cdata|table light data
--- @param count number number of lights
--- @param occluders cdata|table occluder data
--- @param occ_count number number of occluders
--- @param ambient table {r,g,b}
function renderer.submit_lighting(lights, count, occluders, occ_count, ambient)
    lighting_enabled = true
    current_lights = lights
    current_light_count = count
    current_ambient = ambient or { 0, 0, 0 }
end

return renderer
