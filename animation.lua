-- automatic spritesheet animation system
-- handles frame sequences, timing, and state transitions
-- integrates with renderer.lua for batched sprite rendering
-- call animation.update(dt) once per frame to update all animations
-- @module animation

local animation = {}

local floor = math.floor
local min = math.min
local max = math.max
local random = math.random
local insert = table.insert
local pairs = pairs

-- ieee 754 hex constants
local F0 = 0x0.0p0   -- 0.0
local F1 = 0x1.0p0   -- 1.0
local F05 = 0x1.0p-1 -- 0.5
local F2 = 0x1.0p1   -- 2.0
local FN1 = -0x1.0p0 -- -1.0

-- ============================================================================
-- internal state
-- ============================================================================

-- spritesheet definitions: { id -> { image, frame_width, frame_height, quads } }
local spritesheets = {}

-- animation sequence definitions: { id -> { sheet_id, frames, duration, loop } }
local sequences = {}

-- active animation instances: { id -> component }
local instances = {}
local next_instance_id = 1

-- sparse array of playing instance ids (optimization)
local playing_instances = {}

-- instance pool (fixed size, circular buffer)
local instance_pool_size = 1000
local instance_pool = {}
local instance_pool_top = 0

-- renderer module reference (set once at init)
local renderer_module = nil

-- animation state machines: { id -> state_machine }
local state_machines = {}

-- directional animation sets: { id -> direction_map }
local directional_sets = {}

-- frame event callbacks: { instance_id -> { frame_num -> callback } }
local frame_events = {}

-- pre-allocate instance pool
for i = 1, instance_pool_size do
    instance_pool[i] = {
        sequence_id = nil,
        current_frame = 1,
        timer = F0,
        playing = true,
        speed = F1,
        on_complete = nil,
        _sequence = nil,
        _sheet = nil,
        _cached_image = nil,
        _cached_quad = nil,
        _cached_fw = 0,
        _cached_fh = 0,
        flip_x = false,
        flip_y = false,
        playback_direction = 1,
        state_machine = nil,
        current_state = nil,
        direction = nil
    }
end

-- ============================================================================
-- private helpers
-- ============================================================================

-- get instance from pool
local function get_pooled_instance()
    if instance_pool_top > 0 then
        local inst = instance_pool[instance_pool_top]
        instance_pool_top = instance_pool_top - 1
        return inst
    end
    -- fallback: create new
    return {
        sequence_id = nil,
        current_frame = 1,
        timer = F0,
        playing = true,
        speed = F1,
        on_complete = nil,
        _sequence = nil,
        _sheet = nil,
        _cached_image = nil,
        _cached_quad = nil,
        _cached_fw = 0,
        _cached_fh = 0,
        flip_x = false,
        flip_y = false,
        playback_direction = 1,
        state_machine = nil,
        current_state = nil,
        direction = nil
    }
end

-- return instance to pool
local function return_instance_to_pool(inst)
    if instance_pool_top < instance_pool_size then
        instance_pool_top = instance_pool_top + 1
        instance_pool[instance_pool_top] = inst
    end
end

-- update cached frame data for instance (warm)
local function update_instance_cache(anim)
    local seq = anim._sequence
    local sheet = anim._sheet
    
    if not seq or not sheet then
        anim._cached_image = nil
        anim._cached_quad = nil
        anim._cached_fw = 0
        anim._cached_fh = 0
        return
    end
    
    local frame_index = seq.frames[anim.current_frame]
    local quad = sheet.quads[frame_index]
    
    anim._cached_image = sheet.image
    anim._cached_quad = quad
    anim._cached_fw = sheet.frame_width
    anim._cached_fh = sheet.frame_height
end

-- trigger frame event callbacks (warm)
local function trigger_frame_events(id, frame_num)
    local events = frame_events[id]
    if not events then return end
    
    local callback = events[frame_num]
    if callback then
        callback(id, frame_num)
    end
end

-- trigger frame tag callbacks
local function trigger_frame_tags(id, anim, frame_num)
    local seq = anim._sequence
    if not seq or not seq.tags then return end
    
    local tags = seq.tags[frame_num]
    if not tags then return end
    
    for i = 1, #tags do
        local tag_callback = seq.tag_callbacks and seq.tag_callbacks[tags[i]]
        if tag_callback then
            tag_callback(id, tags[i], frame_num)
        end
    end
end

-- ============================================================================
-- spritesheet management
-- ============================================================================

--- register a spritesheet for use in animations
-- automatically generates quads for the entire sheet
--- @param id string unique spritesheet id (e.g., "player", "enemy")
--- @param image_path string path to spritesheet image
--- @param frame_width number width of each frame in pixels
--- @param frame_height number height of each frame in pixels
--- @param options table (optional) { spacing=0, margin=0, columns=nil, rows=nil }
--- @return table spritesheet definition
function animation.spritesheet(id, image_path, frame_width, frame_height, options)
    options = options or {}
    local spacing = options.spacing or 0
    local margin = options.margin or 0
    
    local image = love.graphics.newImage(image_path)
    image:setFilter("nearest", "nearest")
    
    local img_width = image:getWidth()
    local img_height = image:getHeight()
    
    -- calculate grid dimensions
    local columns = options.columns or floor((img_width - margin * 2 + spacing) / (frame_width + spacing))
    local rows = options.rows or floor((img_height - margin * 2 + spacing) / (frame_height + spacing))
    
    -- generate quads for each frame
    local quads = {}
    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local x = margin + col * (frame_width + spacing)
            local y = margin + row * (frame_height + spacing)
            
            insert(quads, love.graphics.newQuad(
                x, y,
                frame_width, frame_height,
                img_width, img_height
            ))
        end
    end
    
    local sheet = {
        id = id,
        image = image,
        frame_width = frame_width,
        frame_height = frame_height,
        columns = columns,
        rows = rows,
        quads = quads,
        frame_count = #quads
    }
    
    spritesheets[id] = sheet
    return sheet
end

--- get a spritesheet by id
--- @param id string spritesheet id
--- @return table spritesheet or nil
function animation.get_spritesheet(id)
    return spritesheets[id]
end

--- get a specific quad from a spritesheet by index
--- @param sheet_id string spritesheet id
--- @param index number quad index (1-based)
--- @return love.Quad quad or nil
function animation.get_quad(sheet_id, index)
    local sheet = spritesheets[sheet_id]
    if not sheet then return nil end
    return sheet.quads[index]
end

--- get quad from spritesheet by row and column
--- @param sheet_id string spritesheet id
--- @param col number column (0-based)
--- @param row number row (0-based)
--- @return love.Quad quad or nil
function animation.get_quad_at(sheet_id, col, row)
    local sheet = spritesheets[sheet_id]
    if not sheet then return nil end
    local index = row * sheet.columns + col + 1
    return sheet.quads[index]
end

-- ============================================================================
-- animation sequence definitions
-- ============================================================================

--- define an animation sequence
--- @param id string unique sequence id (e.g., "player_walk", "enemy_attack")
--- @param sheet_id string spritesheet id this sequence uses
--- @param frames table array of frame indices (1-based)
--- @param duration number or table duration of each frame in seconds (or array of per-frame durations)
--- @param options table (optional) { loop=true, on_complete=nil, pingpong=false }
--- @return table sequence definition
function animation.sequence(id, sheet_id, frames, duration, options)
    options = options or {}
    
    -- allow duration to be number or table of per-frame durations
    local durations = nil
    local base_duration = duration
    if type(duration) == "table" then
        durations = duration
        base_duration = duration[1] or 0.1  -- fallback
    end
    
    local seq = {
        id = id,
        sheet_id = sheet_id,
        frames = frames,
        duration = base_duration,
        durations = durations,  -- per-frame timing
        loop = options.loop ~= false, -- default true
        on_complete = options.on_complete,
        pingpong = options.pingpong or false,
        tags = {},  -- frame tags
        tag_callbacks = {}  -- tag-specific callbacks
    }
    
    sequences[id] = seq
    return seq
end

--- create a sequence from a frame range
--- @param id string sequence id
--- @param sheet_id string spritesheet id
--- @param start_frame number first frame (1-based)
--- @param end_frame number last frame (1-based)
--- @param duration number or table duration per frame
--- @param options table (optional) same as sequence()
--- @return table sequence definition
function animation.sequence_range(id, sheet_id, start_frame, end_frame, duration, options)
    local frames = {}
    for i = start_frame, end_frame do
        insert(frames, i)
    end
    return animation.sequence(id, sheet_id, frames, duration, options)
end

--- create a sequence from row/column grid coordinates
--- @param id string sequence id
--- @param sheet_id string spritesheet id
--- @param row number row index (0-based)
--- @param start_col number starting column (0-based)
--- @param end_col number ending column (0-based)
--- @param duration number or table duration per frame
--- @param options table (optional) same as sequence()
--- @return table sequence definition
function animation.sequence_grid(id, sheet_id, row, start_col, end_col, duration, options)
    local sheet = spritesheets[sheet_id]
    if not sheet then
        error("spritesheet not found: " .. sheet_id)
    end
    
    local frames = {}
    for col = start_col, end_col do
        local index = row * sheet.columns + col + 1
        insert(frames, index)
    end
    
    return animation.sequence(id, sheet_id, frames, duration, options)
end

--- get a sequence by id
--- @param id string sequence id
--- @return table sequence or nil
function animation.get_sequence(id)
    return sequences[id]
end

-- ============================================================================
-- directional animation sets
-- ============================================================================

--- create a directional animation set (4-way or 8-way)
-- automatically creates sequences for each direction
--- @param id string base id for the set
--- @param sheet_id string spritesheet id
--- @param directions table map of direction -> {row=N, start_col=N, end_col=N}
--- @param duration number or table duration per frame
--- @param options table (optional) same as sequence()
--- @return table directional set
function animation.directional(id, sheet_id, directions, duration, options)
    local dir_set = {
        id = id,
        sheet_id = sheet_id,
        directions = {}
    }
    
    for dir_name, dir_def in pairs(directions) do
        local seq_id = id .. "_" .. dir_name
        animation.sequence_grid(
            seq_id,
            sheet_id,
            dir_def.row,
            dir_def.start_col or 0,
            dir_def.end_col or 0,
            duration,
            options
        )
        dir_set.directions[dir_name] = seq_id
    end
    
    directional_sets[id] = dir_set
    return dir_set
end

--- create auto-directional (4-way: up/down/left/right)
--- @param id string base id
--- @param sheet_id string spritesheet id
--- @param frames_per_dir number frames per direction
--- @param duration number or table duration per frame
--- @param options table (optional) same as sequence()
--- @return table directional set
function animation.auto_directional(id, sheet_id, frames_per_dir, duration, options)
    local directions = {
        down = {row = 0, start_col = 0, end_col = frames_per_dir - 1},
        left = {row = 1, start_col = 0, end_col = frames_per_dir - 1},
        right = {row = 2, start_col = 0, end_col = frames_per_dir - 1},
        up = {row = 3, start_col = 0, end_col = frames_per_dir - 1}
    }
    
    return animation.directional(id, sheet_id, directions, duration, options)
end

--- get sequence id for a specific direction
--- @param set_id string directional set id
--- @param direction string direction name (e.g., "up", "down", "left", "right")
--- @return string sequence id or nil
function animation.get_directional_sequence(set_id, direction)
    local dir_set = directional_sets[set_id]
    if not dir_set then return nil end
    return dir_set.directions[direction]
end

-- ============================================================================
-- animation state machines
-- ============================================================================

--- create an animation state machine
--- @param id string state machine id
--- @param states table map of state_name -> {sequence=seq_id, priority=N, transitions={}}
--- @param initial_state string initial state name
--- @return table state machine
function animation.state_machine(id, states, initial_state)
    local sm = {
        id = id,
        states = states,
        initial_state = initial_state
    }
    
    state_machines[id] = sm
    return sm
end

--- create animation instance with state machine
--- @param state_machine_id string state machine id
--- @param options table (optional) same as create()
--- @return number animation instance id
function animation.create_with_state_machine(state_machine_id, options)
    local sm = state_machines[state_machine_id]
    if not sm then
        error("state machine not found: " .. state_machine_id)
    end
    
    local initial_seq = sm.states[sm.initial_state].sequence
    local anim_id = animation.create(initial_seq, options)
    
    local anim = instances[anim_id]
    anim.state_machine = sm
    anim.current_state = sm.initial_state
    
    return anim_id
end

--- transition animation to a new state
--- @param id number animation instance id
--- @param new_state string new state name
--- @param force boolean (optional) force transition even if lower priority
function animation.transition(id, new_state, force)
    local anim = instances[id]
    if not anim or not anim.state_machine then return end
    
    local sm = anim.state_machine
    local current_state_def = sm.states[anim.current_state]
    local new_state_def = sm.states[new_state]
    
    if not new_state_def then return end
    
    -- check priority
    if not force then
        local current_priority = current_state_def.priority or 0
        local new_priority = new_state_def.priority or 0
        if new_priority < current_priority then
            return
        end
    end
    
    -- check if transition is allowed
    if current_state_def.transitions then
        local allowed = false
        for i = 1, #current_state_def.transitions do
            if current_state_def.transitions[i] == new_state then
                allowed = true
                break
            end
        end
        if not allowed and not force then
            return
        end
    end
    
    -- perform transition
    anim.current_state = new_state
    animation.play(id, new_state_def.sequence, true)
end

-- ============================================================================
-- animation instances
-- ============================================================================

--- create an animation instance
-- returns an id that you store with your entity data
--- @param sequence_id string initial animation sequence
--- @param options table (optional) { playing=true, speed=1.0, on_complete=nil, flip_x=false, flip_y=false, random_start=false, reverse=false }
--- @return number animation instance id
function animation.create(sequence_id, options)
    options = options or {}
    
    local seq = sequences[sequence_id]
    if not seq then
        error("animation sequence not found: " .. sequence_id)
    end
    
    local id = next_instance_id
    next_instance_id = id + 1
    
    local anim = get_pooled_instance()
    
    -- current state
    anim.sequence_id = sequence_id
    anim.current_frame = options.random_start and random(1, #seq.frames) or 1
    anim.timer = F0
    anim.playing = options.playing ~= false
    anim.speed = options.speed or F1
    
    -- callbacks
    anim.on_complete = options.on_complete
    
    -- flip flags
    anim.flip_x = options.flip_x or false
    anim.flip_y = options.flip_y or false
    
    -- playback direction
    anim.playback_direction = options.reverse and -1 or 1
    
    -- cached for performance
    anim._sequence = seq
    anim._sheet = spritesheets[seq.sheet_id]
    
    -- state machine (set later if needed)
    anim.state_machine = nil
    anim.current_state = nil
    
    -- direction (for directional sets)
    anim.direction = nil
    
    -- update cache
    update_instance_cache(anim)
    
    instances[id] = anim
    
    -- add to playing instances if playing
    if anim.playing then
        playing_instances[id] = true
    end
    
    return id
end

--- destroy an animation instance
--- @param id number animation instance id
function animation.destroy(id)
    local anim = instances[id]
    if anim then
        return_instance_to_pool(anim)
        instances[id] = nil
        frame_events[id] = nil
        playing_instances[id] = nil
    end
end

--- get an animation instance
--- @param id number animation instance id
--- @return table animation data or nil
function animation.get(id)
    return instances[id]
end

-- ============================================================================
-- animation control
-- ============================================================================

--- change an animation's sequence
--- @param id number animation instance id
--- @param sequence_id string new sequence id
--- @param reset boolean (optional) reset to frame 1 (default true)
function animation.play(id, sequence_id, reset)
    local anim = instances[id]
    if not anim then return end
    
    if reset == nil then reset = true end
    
    -- if already playing this sequence and reset is false, do nothing
    if anim.sequence_id == sequence_id and not reset then
        return
    end
    
    local seq = sequences[sequence_id]
    if not seq then
        error("animation sequence not found: " .. sequence_id)
    end
    
    anim.sequence_id = sequence_id
    anim._sequence = seq
    anim._sheet = spritesheets[seq.sheet_id]
    
    if reset then
        anim.current_frame = 1
        anim.timer = F0
    end
    
    anim.playing = true
    playing_instances[id] = true
    
    -- update cache
    update_instance_cache(anim)
end

--- pause an animation
--- @param id number animation instance id
function animation.pause(id)
    local anim = instances[id]
    if anim then 
        anim.playing = false
        playing_instances[id] = nil
    end
end

--- resume an animation
--- @param id number animation instance id
function animation.resume(id)
    local anim = instances[id]
    if anim then 
        anim.playing = true
        playing_instances[id] = true
    end
end

--- reset an animation to first frame
--- @param id number animation instance id
function animation.reset(id)
    local anim = instances[id]
    if not anim then return end
    anim.current_frame = 1
    anim.timer = F0
    update_instance_cache(anim)
end

--- set animation playback speed
--- @param id number animation instance id
--- @param speed number speed multiplier (1.0 = normal, 2.0 = double speed, etc)
function animation.set_speed(id, speed)
    local anim = instances[id]
    if anim then anim.speed = speed end
end

--- set animation flip flags
--- @param id number animation instance id
--- @param flip_x boolean flip horizontally
--- @param flip_y boolean flip vertically
function animation.set_flip(id, flip_x, flip_y)
    local anim = instances[id]
    if not anim then return end
    anim.flip_x = flip_x
    anim.flip_y = flip_y
end

--- set playback direction
--- @param id number animation instance id
--- @param reverse boolean true for reverse playback
function animation.set_reverse(id, reverse)
    local anim = instances[id]
    if not anim then return end
    anim.playback_direction = reverse and -1 or 1
end

--- set direction for directional animation set
--- @param id number animation instance id
--- @param set_id string directional set id
--- @param direction string direction name
function animation.set_direction(id, set_id, direction)
    local anim = instances[id]
    if not anim then return end
    
    local seq_id = animation.get_directional_sequence(set_id, direction)
    if seq_id then
        anim.direction = direction
        animation.play(id, seq_id, false)
    end
end

-- ============================================================================
-- frame events and tags
-- ============================================================================

--- register a callback for a specific frame
--- @param id number animation instance id
--- @param frame_num number frame number (1-based)
--- @param callback function callback(anim_id, frame_num)
function animation.on_frame(id, frame_num, callback)
    if not frame_events[id] then
        frame_events[id] = {}
    end
    frame_events[id][frame_num] = callback
end

--- clear all frame events for an instance
--- @param id number animation instance id
function animation.clear_frame_events(id)
    frame_events[id] = nil
end

--- add a named tag to a sequence frame
--- @param seq_id string sequence id
--- @param frame_num number frame number (1-based)
--- @param tag_name string tag name (e.g., "hit", "footstep", "spawn_particle")
function animation.add_frame_tag(seq_id, frame_num, tag_name)
    local seq = sequences[seq_id]
    if not seq then return end
    
    seq.tags[frame_num] = seq.tags[frame_num] or {}
    insert(seq.tags[frame_num], tag_name)
end

--- register callback for a frame tag
--- @param seq_id string sequence id
--- @param tag_name string tag name
--- @param callback function callback(anim_id, tag_name, frame_num)
function animation.on_tag(seq_id, tag_name, callback)
    local seq = sequences[seq_id]
    if not seq then return end
    
    seq.tag_callbacks[tag_name] = callback
end

--- check if current frame has a specific tag
--- @param id number animation instance id
--- @param tag_name string tag name
--- @return boolean true if tag exists on current frame
function animation.has_tag(id, tag_name)
    local anim = instances[id]
    if not anim or not anim._sequence then return false end
    
    local tags = anim._sequence.tags[anim.current_frame]
    if not tags then return false end
    
    for i = 1, #tags do
        if tags[i] == tag_name then return true end
    end
    return false
end

-- ============================================================================
-- update all animations (call once per frame)
-- ============================================================================

--- update all animation instances
-- call this in love.update(dt) - updates timing for all active animations
--- @param dt number delta time
function animation.update(dt)
    -- only iterate playing instances (sparse iteration optimization)
    for id in pairs(playing_instances) do
        local anim = instances[id]
        
        -- safety check and remove if destroyed
        if not anim or not anim.playing then
            playing_instances[id] = nil
            goto continue
        end
        
        local seq = anim._sequence
        if not seq then
            goto continue
        end
        
        -- accumulate time
        anim.timer = anim.timer + dt * anim.speed
        
        -- get frame duration (per-frame or global)
        local frame_duration = seq.durations and seq.durations[anim.current_frame] or seq.duration
        
        if anim.timer >= frame_duration then
            anim.timer = anim.timer - frame_duration
            local old_frame = anim.current_frame
            
            -- advance frame with direction
            anim.current_frame = anim.current_frame + anim.playback_direction
            
            local frame_count = #seq.frames
            
            -- handle boundaries
            if anim.current_frame > frame_count then
                if seq.pingpong then
                    anim.playback_direction = -1
                    anim.current_frame = frame_count - 1
                elseif seq.loop then
                    anim.current_frame = 1
                else
                    anim.current_frame = frame_count
                    anim.playing = false
                    playing_instances[id] = nil
                    
                    -- trigger completion callbacks
                    if anim.on_complete then
                        anim.on_complete(id)
                    end
                    if seq.on_complete then
                        seq.on_complete(id)
                    end
                end
            elseif anim.current_frame < 1 then
                if seq.pingpong then
                    anim.playback_direction = 1
                    anim.current_frame = 2
                elseif seq.loop then
                    anim.current_frame = frame_count
                else
                    anim.current_frame = 1
                    anim.playing = false
                    playing_instances[id] = nil
                end
            end
            
            -- only update cache and trigger events if frame actually changed
            if old_frame ~= anim.current_frame then
                update_instance_cache(anim)
                trigger_frame_events(id, anim.current_frame)
                trigger_frame_tags(id, anim, anim.current_frame)
            end
        end
        
        ::continue::
    end
end

-- ============================================================================
-- rendering
-- ============================================================================

--- set the renderer module reference (optional convenience)
-- alternatively, pass renderer directly to draw_batched()
--- @param renderer table renderer module
function animation.set_renderer(renderer)
    renderer_module = renderer
end

--- get the current frame's quad and image for an animation
--- @param id number animation instance id
--- @return love.Image image
--- @return love.Quad quad
--- @return number frame_width
--- @return number frame_height
function animation.get_frame(id)
    local anim = instances[id]
    if not anim then return nil, nil, 0, 0 end
    
    return anim._cached_image, anim._cached_quad, anim._cached_fw, anim._cached_fh
end

--- draw an animation (standalone, without renderer)
--- @param id number animation instance id
--- @param x number
--- @param y number
--- @param options table (optional) { r=0, sx=1, sy=1, ox=0, oy=0, color={1,1,1,1} }
function animation.draw(id, x, y, options)
    options = options or {}
    
    local anim = instances[id]
    if not anim then return end
    
    local image = anim._cached_image
    local quad = anim._cached_quad
    local fw = anim._cached_fw
    local fh = anim._cached_fh
    
    if not image then return end
    
    local r = options.r or F0
    local sx = options.sx or F1
    local sy = options.sy or F1
    local ox = options.ox or fw * F05
    local oy = options.oy or fh * F05
    
    -- apply flip
    if anim.flip_x then sx = -sx end
    if anim.flip_y then sy = -sy end
    
    -- apply color
    if options.color then
        local c = options.color
        love.graphics.setColor(c[1], c[2], c[3], c[4])
    end
    
    love.graphics.draw(image, quad, x, y, r, sx, sy, ox, oy)
    
    if options.color then
        love.graphics.setColor(1, 1, 1, 1)
    end
end

--- draw an animation using renderer.lua's batched system (convenience wrapper)
-- NOTE: requires renderer_module to be set via animation.set_renderer()
--- @param id number animation instance id
--- @param layer number render layer
--- @param x number
--- @param y number
--- @param options table (optional) { r=0, sx=1, sy=1, ox=0, oy=0, color={1,1,1,1}, z=0 }
function animation.draw_batched(id, layer, x, y, options, renderer)
    -- allow passing renderer directly or use module-level reference
    local rend = renderer or renderer_module
    if not rend then
        error("renderer not provided - pass as argument or call animation.set_renderer()")
    end
    
    options = options or {}
    
    local anim = instances[id]
    if not anim then return end
    
    local image = anim._cached_image
    local quad = anim._cached_quad
    local fw = anim._cached_fw
    local fh = anim._cached_fh
    
    if not image then return end
    
    -- default origin to center of frame
    if not options.ox then options.ox = fw * F05 end
    if not options.oy then options.oy = fh * F05 end
    
    -- apply flip by negating scale
    local sx = options.sx or F1
    local sy = options.sy or F1
    if anim.flip_x then sx = -sx end
    if anim.flip_y then sy = -sy end
    
    options.sx = sx
    options.sy = sy
    
    rend.draw_sprite(layer, image, x, y, quad, options)
end

--- draw animation debug info
--- @param id number animation instance id
--- @param x number screen x position
--- @param y number screen y position
function animation.draw_debug(id, x, y)
    local anim = instances[id]
    if not anim then return end
    
    local seq = anim._sequence
    if not seq then return end
    
    local info = string.format(
        "Anim ID: %d\nSeq: %s\nFrame: %d/%d\nTimer: %.2f/%.2f\nSpeed: %.2fx\n%s",
        id,
        seq.id,
        anim.current_frame,
        #seq.frames,
        anim.timer,
        seq.durations and seq.durations[anim.current_frame] or seq.duration,
        anim.speed,
        anim.playing and "Playing" or "Paused"
    )
    
    if anim.state_machine then
        info = info .. "\nState: " .. (anim.current_state or "none")
    end
    
    if anim.direction then
        info = info .. "\nDir: " .. anim.direction
    end
    
    love.graphics.print(info, x, y)
    
    -- draw frame boundaries
    local fw, fh = anim._cached_fw, anim._cached_fh
    love.graphics.rectangle("line", x, y + 100, fw, fh)
end

-- ============================================================================
-- queries
-- ============================================================================

--- check if an animation is playing
--- @param id number animation instance id
--- @return boolean true if playing
function animation.is_playing(id)
    local anim = instances[id]
    return anim and anim.playing or false
end

--- check if an animation has finished (for non-looping animations)
--- @param id number animation instance id
--- @return boolean true if finished
function animation.is_finished(id)
    local anim = instances[id]
    if not anim then return false end
    local seq = anim._sequence
    return not seq.loop and anim.current_frame == #seq.frames and not anim.playing
end

--- get current frame number (1-based)
--- @param id number animation instance id
--- @return number current frame
function animation.get_current_frame(id)
    local anim = instances[id]
    return anim and anim.current_frame or 0
end

--- get total frame count for current sequence
--- @param id number animation instance id
--- @return number frame count
function animation.get_frame_count(id)
    local anim = instances[id]
    if not anim then return 0 end
    local seq = anim._sequence
    return seq and #seq.frames or 0
end

--- get current state name (for state machine animations)
--- @param id number animation instance id
--- @return string state name or nil
function animation.get_state(id)
    local anim = instances[id]
    return anim and anim.current_state or nil
end

--- get current direction (for directional animations)
--- @param id number animation instance id
--- @return string direction name or nil
function animation.get_direction(id)
    local anim = instances[id]
    return anim and anim.direction or nil
end

--- check if animation is flipped
--- @param id number animation instance id
--- @return boolean flip_x
--- @return boolean flip_y
function animation.get_flip(id)
    local anim = instances[id]
    if not anim then return false, false end
    return anim.flip_x, anim.flip_y
end

--- get number of active animation instances
--- @return number count
function animation.count()
    local count = 0
    for _ in pairs(instances) do
        count = count + 1
    end
    return count
end

--- get number of currently playing instances
--- @return number count
function animation.count_playing()
    local count = 0
    for _ in pairs(playing_instances) do
        count = count + 1
    end
    return count
end

--- get animation progress as percentage (0.0 to 1.0)
--- @param id number animation instance id
--- @return number progress
function animation.get_progress(id)
    local anim = instances[id]
    if not anim or not anim._sequence then return F0 end
    local seq = anim._sequence
    local total_frames = #seq.frames
    local current = anim.current_frame - 1 + (anim.timer / seq.duration)
    return current / total_frames
end

--- get current sequence id
--- @param id number animation instance id
--- @return string sequence id or nil
function animation.get_sequence_id(id)
    local anim = instances[id]
    return anim and anim.sequence_id or nil
end

--- get animation speed
--- @param id number animation instance id
--- @return number speed multiplier
function animation.get_speed(id)
    local anim = instances[id]
    return anim and anim.speed or F1
end

--- check if animation is reversed
--- @param id number animation instance id
--- @return boolean true if reversed
function animation.is_reversed(id)
    local anim = instances[id]
    return anim and anim.playback_direction == -1 or false
end

-- ============================================================================
-- batch operations
-- ============================================================================

--- create multiple sequences from a grid layout at once
--- @param base_id string base id for sequences
--- @param sheet_id string spritesheet id
--- @param rows table array of {id_suffix, row, start_col, end_col}
--- @param duration number or table duration per frame
--- @param options table (optional) same as sequence()
function animation.batch_sequences(base_id, sheet_id, rows, duration, options)
    for i = 1, #rows do
        local row_def = rows[i]
        local seq_id = base_id .. "_" .. row_def[1]
        animation.sequence_grid(seq_id, sheet_id, row_def[2], row_def[3], row_def[4], duration, options)
    end
end

--- clone an existing sequence with a new id
--- @param new_id string new sequence id
--- @param source_id string source sequence id
--- @param override_options table (optional) override options
--- @return table new sequence definition
function animation.clone_sequence(new_id, source_id, override_options)
    local source = sequences[source_id]
    if not source then
        error("source sequence not found: " .. source_id)
    end
    
    local frames = {}
    for i = 1, #source.frames do
        frames[i] = source.frames[i]
    end
    
    override_options = override_options or {}
    
    return animation.sequence(new_id, source.sheet_id, frames, source.duration, {
        loop = override_options.loop or source.loop,
        on_complete = override_options.on_complete or source.on_complete,
        pingpong = override_options.pingpong or source.pingpong
    })
end

--- create multiple animation instances at once
--- @param sequence_id string sequence id
--- @param count number number of instances to create
--- @param options table (optional) same as create()
--- @return table array of animation instance ids
function animation.create_batch(sequence_id, count, options)
    local ids = {}
    for i = 1, count do
        ids[i] = animation.create(sequence_id, options)
    end
    return ids
end

--- destroy multiple animation instances at once
--- @param ids table array of animation instance ids
function animation.destroy_batch(ids)
    for i = 1, #ids do
        animation.destroy(ids[i])
    end
end

-- ============================================================================
-- utility functions
-- ============================================================================

--- warmup instance pool
--- @param count number number of instances to pre-allocate
function animation.warmup(count)
    local temp_seq = "___warmup___"
    sequences[temp_seq] = {
        id = temp_seq,
        sheet_id = "___dummy___",
        frames = {1},
        duration = 1,
        loop = false
    }
    
    spritesheets["___dummy___"] = {
        quads = {true},
        frame_width = 1,
        frame_height = 1,
        image = {getWidth = function() return 1 end, getHeight = function() return 1 end}
    }
    
    for i = 1, count do
        local id = animation.create(temp_seq, {playing = false})
        animation.destroy(id)
    end
    
    sequences[temp_seq] = nil
    spritesheets["___dummy___"] = nil
end

--- clear all registered spritesheets, sequences, and instances
function animation.clear()
    -- destroy all instances
    for id in pairs(instances) do
        animation.destroy(id)
    end
    
    spritesheets = {}
    sequences = {}
    instances = {}
    state_machines = {}
    directional_sets = {}
    frame_events = {}
    playing_instances = {}
    next_instance_id = 1
    
    -- reset pool
    instance_pool_top = instance_pool_size
end

--- clear all instances but keep definitions
function animation.clear_instances()
    for id in pairs(instances) do
        animation.destroy(id)
    end
    
    instances = {}
    frame_events = {}
    playing_instances = {}
    next_instance_id = 1
    
    -- reset pool
    instance_pool_top = instance_pool_size
end

--- get statistics
--- @return table stats {total_instances, playing_instances, sequences, spritesheets}
function animation.get_stats()
    return {
        total_instances = animation.count(),
        playing_instances = animation.count_playing(),
        sequences = (function()
            local count = 0
            for _ in pairs(sequences) do count = count + 1 end
            return count
        end)(),
        spritesheets = (function()
            local count = 0
            for _ in pairs(spritesheets) do count = count + 1 end
            return count
        end)(),
        pool_available = instance_pool_top
    }
end

--- print statistics to console
function animation.print_stats()
    local stats = animation.get_stats()
    print("=== Animation Statistics ===")
    print("Total instances: " .. stats.total_instances)
    print("Playing instances: " .. stats.playing_instances)
    print("Sequences: " .. stats.sequences)
    print("Spritesheets: " .. stats.spritesheets)
    print("Pool available: " .. stats.pool_available)
end

-- ============================================================================
-- builder pattern api (fluent interface)
-- ============================================================================

--- create a builder-style animation creator
--- @param sequence_id string sequence id
--- @return table builder object with fluent interface
function animation.builder(sequence_id)
    local builder = {
        _seq_id = sequence_id,
        _options = {}
    }
    
    function builder:speed(s)
        self._options.speed = s
        return self
    end
    
    function builder:flip_x()
        self._options.flip_x = true
        return self
    end
    
    function builder:flip_y()
        self._options.flip_y = true
        return self
    end
    
    function builder:flip(x, y)
        self._options.flip_x = x
        self._options.flip_y = y
        return self
    end
    
    function builder:reverse()
        self._options.reverse = true
        return self
    end
    
    function builder:random_start()
        self._options.random_start = true
        return self
    end
    
    function builder:paused()
        self._options.playing = false
        return self
    end
    
    function builder:on_complete(callback)
        self._options.on_complete = callback
        return self
    end
    
    function builder:create()
        return animation.create(self._seq_id, self._options)
    end
    
    return builder
end

-- ============================================================================
-- composite animations (multiple animations in sync)
-- ============================================================================

local composites = {}
local next_composite_id = 1

--- create a composite animation from multiple instances
-- all instances will be controlled together
--- @param instance_ids table array of animation instance ids
--- @return number composite id
function animation.create_composite(instance_ids)
    local composite_id = next_composite_id
    next_composite_id = composite_id + 1
    
    composites[composite_id] = {
        ids = instance_ids
    }
    
    return composite_id
end

--- destroy a composite animation
--- @param composite_id number composite id
--- @param destroy_instances boolean also destroy the individual instances
function animation.destroy_composite(composite_id, destroy_instances)
    local composite = composites[composite_id]
    if not composite then return end
    
    if destroy_instances then
        for i = 1, #composite.ids do
            animation.destroy(composite.ids[i])
        end
    end
    
    composites[composite_id] = nil
end

--- play all animations in a composite
--- @param composite_id number composite id
--- @param sequence_id string sequence id (or table of sequence_ids per instance)
--- @param reset boolean reset to frame 1
function animation.play_composite(composite_id, sequence_id, reset)
    local composite = composites[composite_id]
    if not composite then return end
    
    if type(sequence_id) == "table" then
        for i = 1, #composite.ids do
            animation.play(composite.ids[i], sequence_id[i], reset)
        end
    else
        for i = 1, #composite.ids do
            animation.play(composite.ids[i], sequence_id, reset)
        end
    end
end

--- pause all animations in a composite
--- @param composite_id number composite id
function animation.pause_composite(composite_id)
    local composite = composites[composite_id]
    if not composite then return end
    
    for i = 1, #composite.ids do
        animation.pause(composite.ids[i])
    end
end

--- resume all animations in a composite
--- @param composite_id number composite id
function animation.resume_composite(composite_id)
    local composite = composites[composite_id]
    if not composite then return end
    
    for i = 1, #composite.ids do
        animation.resume(composite.ids[i])
    end
end

--- set speed for all animations in a composite
--- @param composite_id number composite id
--- @param speed number speed multiplier
function animation.set_composite_speed(composite_id, speed)
    local composite = composites[composite_id]
    if not composite then return end
    
    for i = 1, #composite.ids do
        animation.set_speed(composite.ids[i], speed)
    end
end

--- get composite instance ids
--- @param composite_id number composite id
--- @return table array of instance ids or nil
function animation.get_composite_instances(composite_id)
    local composite = composites[composite_id]
    return composite and composite.ids or nil
end

return animation