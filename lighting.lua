-- high-performance 2d dynamic lighting system
-- completely standalone - no love2d dependency, returns light data for external rendering
-- optimized for luajit with ieee 754 hex floats, minimal allocations, and aggressive caching
-- @module lighting

local lighting = {}

-- ============================================================================
-- constants (ieee 754 hex floats for exact binary representation)
-- ============================================================================

local ZERO = 0x0p0
local ONE = 0x1p0
local HALF = 0x1p-1
local TWO = 0x1p1
local PI = 0x1.921fb54442d18p1
local TWO_PI = 0x1.921fb54442d18p2
local HALF_PI = 0x1.921fb54442d18p0
local EPSILON = 0x1p-10  -- small value for float comparisons
local DEG_TO_RAD = 0x1.1df46a2529d39p-6  -- pi / 180
local RAD_TO_DEG = 0x1.ca5dc1a63c1f8p5   -- 180 / pi

-- ============================================================================
-- module state
-- ============================================================================

-- dependencies (injected)
local deps = {
    math = math,
    table = table,
    ffi = nil, -- will be loaded if available
}

local math_floor
local math_ceil
local math_max
local math_min
local math_sin
local math_cos
local math_sqrt
local math_atan2
local math_abs
local math_huge
local table_insert
local table_remove

-- global config
local default_config = {
    max_lights = 256,
    max_occluders = 1024,
    ambient_color = {ZERO, ZERO, ZERO},
    default_attenuation = "quadratic",
    world_bounds = {min_x = -math.huge, min_y = -math.huge, max_x = math.huge, max_y = math.huge},
}

local config = {}
for k, v in pairs(default_config) do config[k] = v end

-- storage
local lights = { count = 0 }
local occluders = { count = 0 }
local ffi_available = false

-- spatial hash for occluder culling (logic queries only)
local spatial_hash = {
    cells = {},
    cell_size = 64,
    enabled = true,
}

-- statistics
local stats = {
    lights_processed = 0,
    occluders_tested = 0,
}

-- id counters
local next_light_id = 1
local next_occluder_id = 1

-- ============================================================================
-- ffi definitions
-- ============================================================================

local function init_ffi()
    local status, ffi = pcall(require, "ffi")
    if not status then return false end

    deps.ffi = ffi
    
    ffi.cdef[[
    typedef struct {
        float x, y, z;
        float r, g, b, intensity;
        float range;
        float att_const, att_linear, att_quad;
        float direction, cone_angle, cone_falloff;
        int type;
        bool enabled;
        bool cast_shadows;
        int id;
        int layer;
        bool dirty;
    } Light;

    typedef struct {
        float x1, y1, x2, y2;
        bool enabled;
        bool two_sided;
        int id;
        int layer;
    } Occluder;
    ]]
    
    return true
end

-- ============================================================================
-- private helpers
-- ============================================================================

--- fast integer division by power of 2
local function fast_div(n, divisor)
    return math_floor(n / divisor)
end

--- normalize angle to [0, 2pi)
local function normalize_angle(angle)
    angle = angle % TWO_PI
    if angle < ZERO then angle = angle + TWO_PI end
    return angle
end

--- calculate shortest angular distance
local function angle_diff(a1, a2)
    local diff = normalize_angle(a2 - a1)
    if diff > PI then diff = diff - TWO_PI end
    return diff
end

--- line-line intersection (parametric)
local function line_intersect(x1, y1, x2, y2, x3, y3, x4, y4)
    local dx1 = x2 - x1
    local dy1 = y2 - y1
    local dx2 = x4 - x3
    local dy2 = y4 - y3
    
    local denom = dx1 * dy2 - dy1 * dx2
    
    if math_abs(denom) < EPSILON then return nil, nil end
    
    local t1 = ((x3 - x1) * dy2 - (y3 - y1) * dx2) / denom
    local t2 = ((x3 - x1) * dy1 - (y3 - y1) * dx1) / denom
    
    return t1, t2
end

--- ray-segment intersection
local function ray_segment_intersect(ray_x, ray_y, ray_dx, ray_dy, seg_x1, seg_y1, seg_x2, seg_y2)
    local t1, t2 = line_intersect(
        ray_x, ray_y,
        ray_x + ray_dx, ray_y + ray_dy,
        seg_x1, seg_y1,
        seg_x2, seg_y2
    )
    
    if t1 and t1 >= ZERO and t2 >= ZERO and t2 <= ONE then
        return t1
    end
    return nil
end

--- calculate attenuation factor
local function calculate_attenuation(distance, range, att_const, att_linear, att_quad)
    if distance >= range then return ZERO end
    if distance < EPSILON then return ONE end
    
    local d = distance
    local denom = att_const + att_linear * d + att_quad * d * d
    
    if denom < EPSILON then return ONE end
    
    local attenuation = ONE / denom
    
    -- smooth falloff
    local d_sq = d * d
    local r_sq = range * range
    local falloff = ONE - (d_sq / r_sq)
    attenuation = attenuation * falloff * falloff
    
    return math_min(ONE, math_max(ZERO, attenuation))
end

--- add occluder to spatial hash
local function spatial_hash_add(idx)
    if not spatial_hash.enabled then return end
    
    local x1, y1, x2, y2
    if ffi_available then
        local occ = occluders.data[idx]
        x1, y1, x2, y2 = occ.x1, occ.y1, occ.x2, occ.y2
    else
        x1, y1 = occluders.x1[idx], occluders.y1[idx]
        x2, y2 = occluders.x2[idx], occluders.y2[idx]
    end
    
    local min_x = math_min(x1, x2)
    local max_x = math_max(x1, x2)
    local min_y = math_min(y1, y2)
    local max_y = math_max(y1, y2)
    
    local cell_size = spatial_hash.cell_size
    local start_cx = fast_div(min_x, cell_size)
    local end_cx = fast_div(max_x, cell_size)
    local start_cy = fast_div(min_y, cell_size)
    local end_cy = fast_div(max_y, cell_size)
    
    for cy = start_cy, end_cy do
        for cx = start_cx, end_cx do
            local key = cx .. "," .. cy
            local cell = spatial_hash.cells[key]
            if not cell then
                cell = {}
                spatial_hash.cells[key] = cell
            end
            table_insert(cell, idx)
        end
    end
end

--- remove occluder from spatial hash
local function spatial_hash_remove(idx)
    if not spatial_hash.enabled then return end
    
    for key, cell in pairs(spatial_hash.cells) do
        for i = #cell, 1, -1 do
            if cell[i] == idx then
                table_remove(cell, i)
            end
        end
    end
end

--- query occluders near a position
local function spatial_hash_query(lx, ly, range)
    if not spatial_hash.enabled then
        local result = {}
        local count = 0
        local max = occluders.count
        if ffi_available then max = max - 1 end -- 0-based for ffi
        
        local start = ffi_available and 0 or 1
        for i = start, max do
            local enabled
            if ffi_available then
                enabled = occluders.data[i].enabled
            else
                enabled = occluders.enabled[i]
            end
            
            if enabled then
                count = count + 1
                result[count] = i
            end
        end
        return result, count
    end
    
    local cell_size = spatial_hash.cell_size
    local start_cx = fast_div(lx - range, cell_size)
    local end_cx = fast_div(lx + range, cell_size)
    local start_cy = fast_div(ly - range, cell_size)
    local end_cy = fast_div(ly + range, cell_size)
    
    local seen = {}
    local result = {}
    local count = 0
    
    for cy = start_cy, end_cy do
        for cx = start_cx, end_cx do
            local key = cx .. "," .. cy
            local cell = spatial_hash.cells[key]
            if cell then
                for i = 1, #cell do
                    local idx = cell[i]
                    local enabled
                    if ffi_available then
                        enabled = occluders.data[idx].enabled
                    else
                        enabled = occluders.enabled[idx]
                    end
                    
                    if not seen[idx] and enabled then
                        seen[idx] = true
                        count = count + 1
                        result[count] = idx
                    end
                end
            end
        end
    end
    
    return result, count
end

--- rebuild spatial hash
local function spatial_hash_rebuild()
    spatial_hash.cells = {}
    local max = occluders.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local enabled
        if ffi_available then
            enabled = occluders.data[i].enabled
        else
            enabled = occluders.enabled[i]
        end
        
        if enabled then
            spatial_hash_add(i)
        end
    end
end

--- check if point is illuminated by a light
local function point_illuminated(light_idx, px, py)
    local lx, ly, range, type, direction, cone_angle, cone_falloff
    local att_const, att_linear, att_quad
    
    if ffi_available then
        local l = lights.data[light_idx]
        lx, ly, range = l.x, l.y, l.range
        type = l.type
        direction, cone_angle, cone_falloff = l.direction, l.cone_angle, l.cone_falloff
        att_const, att_linear, att_quad = l.att_const, l.att_linear, l.att_quad
    else
        lx = lights.x[light_idx]
        ly = lights.y[light_idx]
        range = lights.range[light_idx]
        type = lights.type[light_idx]
        direction = lights.direction[light_idx]
        cone_angle = lights.cone_angle[light_idx]
        cone_falloff = lights.cone_falloff[light_idx]
        att_const = lights.att_const[light_idx]
        att_linear = lights.att_linear[light_idx]
        att_quad = lights.att_quad[light_idx]
    end
    
    local dx = px - lx
    local dy = py - ly
    local dist_sq = dx * dx + dy * dy
    local range_sq = range * range
    
    if dist_sq > range_sq then return false, ZERO end
    
    local dist = math_sqrt(dist_sq)
    
    -- spotlight
    if type == 2 then
        local angle_to_point = math_atan2(dy, dx)
        local diff = math_abs(angle_diff(direction, angle_to_point))
        
        if diff > cone_falloff then return false, ZERO end
        
        local cone_factor = ONE
        if diff > cone_angle then
            cone_factor = ONE - (diff - cone_angle) / (cone_falloff - cone_angle)
        end
        
        local attenuation = calculate_attenuation(dist, range, att_const, att_linear, att_quad)
        return true, attenuation * cone_factor
    end
    
    local attenuation = calculate_attenuation(dist, range, att_const, att_linear, att_quad)
    return true, attenuation
end

-- ============================================================================
-- public api
-- ============================================================================

--- initialize lighting system
--- @param dependencies table optional dependencies {math=..., table=...}
--- @param configuration table optional config {max_lights=..., max_occluders=...}
function lighting.init(dependencies, configuration)
    -- inject dependencies
    if dependencies then
        for k, v in pairs(dependencies) do deps[k] = v end
    end
    
    -- reset config to defaults
    for k, v in pairs(default_config) do config[k] = v end
    
    -- update local refs
    math_floor = deps.math.floor
    math_ceil = deps.math.ceil
    math_max = deps.math.max
    math_min = deps.math.min
    math_sin = deps.math.sin
    math_cos = deps.math.cos
    math_sqrt = deps.math.sqrt
    math_atan2 = deps.math.atan2 or deps.math.atan
    math_abs = deps.math.abs
    math_huge = deps.math.huge
    table_insert = deps.table.insert
    table_remove = deps.table.remove
    
    -- config
    if configuration then
        for k, v in pairs(configuration) do config[k] = v end
    end
    
    -- try ffi
    ffi_available = init_ffi()
    
    -- init storage
    if ffi_available then
        lights.data = deps.ffi.new("Light[?]", config.max_lights)
        occluders.data = deps.ffi.new("Occluder[?]", config.max_occluders)
    else
        -- lua table fallback struct of arrays
        lights.x = {}
        lights.y = {}
        lights.z = {}
        lights.type = {}
        lights.r = {}
        lights.g = {}
        lights.b = {}
        lights.intensity = {}
        lights.range = {}
        lights.att_const = {}
        lights.att_linear = {}
        lights.att_quad = {}
        lights.direction = {}
        lights.cone_angle = {}
        lights.cone_falloff = {}
        lights.enabled = {}
        lights.cast_shadows = {}
        lights.id = {}
        lights.layer = {}
        lights.dirty = {}
        
        occluders.x1 = {}
        occluders.y1 = {}
        occluders.x2 = {}
        occluders.y2 = {}
        occluders.enabled = {}
        occluders.two_sided = {}
        occluders.id = {}
        occluders.layer = {}
    end
    
    lights.count = 0
    occluders.count = 0
    spatial_hash.cells = {}
end

--- set ambient light color
function lighting.set_ambient(r, g, b)
    config.ambient_color = {r, g, b}
end

--- get ambient light color
function lighting.get_ambient()
    return config.ambient_color
end

--- set world bounds
function lighting.set_world_bounds(min_x, min_y, max_x, max_y)
    config.world_bounds = {min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y}
end

--- enable/disable spatial hashing
function lighting.set_spatial_hashing(enabled)
    spatial_hash.enabled = enabled
    if enabled then spatial_hash_rebuild() end
end

--- set default attenuation preset
function lighting.set_default_attenuation(preset)
    config.default_attenuation = preset
end

-- ============================================================================
-- lights
-- ============================================================================

--- create a new point light
function lighting.add_light(x, y, r, g, b, intensity, range)
    if lights.count >= config.max_lights then return nil end
    
    local idx = ffi_available and lights.count or (lights.count + 1)
    lights.count = lights.count + 1
    local id = next_light_id
    next_light_id = next_light_id + 1
    
    -- defaults
    x = x or ZERO
    y = y or ZERO
    r = r or ONE
    g = g or ONE
    b = b or ONE
    intensity = intensity or ONE
    range = range or 100
    
    -- attenuation
    local att_const, att_linear, att_quad
    local preset = config.default_attenuation
    if preset == "none" then
        att_const, att_linear, att_quad = ONE, ZERO, ZERO
    elseif preset == "linear" then
        att_const, att_linear, att_quad = ONE, ONE/range, ZERO
    elseif preset == "quadratic" then
        att_const, att_linear, att_quad = ONE, ZERO, TWO/(range*range + EPSILON)
    else
        att_const, att_linear, att_quad = ONE, ZERO, ZERO
    end
    
    if ffi_available then
        local l = lights.data[idx]
        l.x, l.y, l.z = x, y, ZERO
        l.type = 1
        l.r, l.g, l.b = r, g, b
        l.intensity = intensity
        l.range = range
        l.att_const, l.att_linear, l.att_quad = att_const, att_linear, att_quad
        l.direction, l.cone_angle, l.cone_falloff = ZERO, HALF_PI, HALF_PI
        l.enabled = true
        l.cast_shadows = true
        l.id = id
        l.layer = 0
        l.dirty = true
    else
        lights.x[idx] = x
        lights.y[idx] = y
        lights.z[idx] = ZERO
        lights.type[idx] = 1
        lights.r[idx] = r
        lights.g[idx] = g
        lights.b[idx] = b
        lights.intensity[idx] = intensity
        lights.range[idx] = range
        lights.att_const[idx] = att_const
        lights.att_linear[idx] = att_linear
        lights.att_quad[idx] = att_quad
        lights.direction[idx] = ZERO
        lights.cone_angle[idx] = HALF_PI
        lights.cone_falloff[idx] = HALF_PI
        lights.enabled[idx] = true
        lights.cast_shadows[idx] = true
        lights.id[idx] = id
        lights.layer[idx] = 0
        lights.dirty[idx] = true
    end
    
    return id
end

--- create a new spotlight
function lighting.add_spotlight(x, y, direction, cone_angle, cone_falloff, r, g, b, intensity, range)
    local id = lighting.add_light(x, y, r, g, b, intensity, range)
    if not id then return nil end
    
    local idx = ffi_available and (lights.count - 1) or lights.count
    
    direction = direction or ZERO
    cone_angle = cone_angle or (PI / 0x1p2)
    cone_falloff = cone_falloff or (PI / 0x1.8p1)
    
    if ffi_available then
        local l = lights.data[idx]
        l.type = 2
        l.direction = direction
        l.cone_angle = cone_angle
        l.cone_falloff = cone_falloff
    else
        lights.type[idx] = 2
        lights.direction[idx] = direction
        lights.cone_angle[idx] = cone_angle
        lights.cone_falloff[idx] = cone_falloff
    end
    
    return id
end

--- remove a light
function lighting.remove_light(id)
    local idx = nil
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            idx = i
            break
        end
    end
    
    if not idx then return end
    
    local last = ffi_available and (lights.count - 1) or lights.count
    
    if idx < last then
        if ffi_available then
            lights.data[idx] = lights.data[last]
        else
            lights.x[idx] = lights.x[last]
            lights.y[idx] = lights.y[last]
            lights.z[idx] = lights.z[last]
            lights.type[idx] = lights.type[last]
            lights.r[idx] = lights.r[last]
            lights.g[idx] = lights.g[last]
            lights.b[idx] = lights.b[last]
            lights.intensity[idx] = lights.intensity[last]
            lights.range[idx] = lights.range[last]
            lights.att_const[idx] = lights.att_const[last]
            lights.att_linear[idx] = lights.att_linear[last]
            lights.att_quad[idx] = lights.att_quad[last]
            lights.direction[idx] = lights.direction[last]
            lights.cone_angle[idx] = lights.cone_angle[last]
            lights.cone_falloff[idx] = lights.cone_falloff[last]
            lights.enabled[idx] = lights.enabled[last]
            lights.cast_shadows[idx] = lights.cast_shadows[last]
            lights.id[idx] = lights.id[last]
            lights.layer[idx] = lights.layer[last]
            lights.dirty[idx] = lights.dirty[last]
        end
    end
    
    lights.count = lights.count - 1
end

--- set light position
function lighting.set_light_position(id, x, y, z)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].x = x
                lights.data[i].y = y
                if z then lights.data[i].z = z end
                lights.data[i].dirty = true
            else
                lights.x[i] = x
                lights.y[i] = y
                if z then lights.z[i] = z end
                lights.dirty[i] = true
            end
            return
        end
    end
end

--- set light color
function lighting.set_light_color(id, r, g, b)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].r = r
                lights.data[i].g = g
                lights.data[i].b = b
            else
                lights.r[i] = r
                lights.g[i] = g
                lights.b[i] = b
            end
            return
        end
    end
end

--- set light intensity
function lighting.set_light_intensity(id, intensity)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].intensity = intensity
            else
                lights.intensity[i] = intensity
            end
            return
        end
    end
end

--- set light range
function lighting.set_light_range(id, range)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].range = range
                lights.data[i].dirty = true
            else
                lights.range[i] = range
                lights.dirty[i] = true
            end
            return
        end
    end
end

--- set light attenuation coefficients
function lighting.set_light_attenuation(id, constant, linear, quadratic)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].att_const = constant
                lights.data[i].att_linear = linear
                lights.data[i].att_quad = quadratic
            else
                lights.att_const[i] = constant
                lights.att_linear[i] = linear
                lights.att_quad[i] = quadratic
            end
            return
        end
    end
end

--- set spotlight direction and cone
function lighting.set_spotlight_direction(id, direction, cone_angle, cone_falloff)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                if lights.data[i].type == 2 then
                    lights.data[i].direction = direction
                    if cone_angle then lights.data[i].cone_angle = cone_angle end
                    if cone_falloff then lights.data[i].cone_falloff = cone_falloff end
                    lights.data[i].dirty = true
                end
            else
                if lights.type[i] == 2 then
                    lights.direction[i] = direction
                    if cone_angle then lights.cone_angle[i] = cone_angle end
                    if cone_falloff then lights.cone_falloff[i] = cone_falloff end
                    lights.dirty[i] = true
                end
            end
            return
        end
    end
end

--- enable/disable light
function lighting.set_light_enabled(id, enabled)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].enabled = enabled
            else
                lights.enabled[i] = enabled
            end
            return
        end
    end
end

--- enable/disable shadow casting
function lighting.set_light_shadows(id, cast_shadows)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].cast_shadows = cast_shadows
                lights.data[i].dirty = true
            else
                lights.cast_shadows[i] = cast_shadows
                lights.dirty[i] = true
            end
            return
        end
    end
end

--- set light layer
function lighting.set_light_layer(id, layer)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                lights.data[i].layer = layer
            else
                lights.layer[i] = layer
            end
            return
        end
    end
end

--- get light data
function lighting.get_light(id)
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == id then
            if ffi_available then
                local l = lights.data[i]
                return {
                    x = l.x, y = l.y, z = l.z,
                    type = l.type,
                    r = l.r, g = l.g, b = l.b,
                    intensity = l.intensity,
                    range = l.range,
                    att_const = l.att_const, att_linear = l.att_linear, att_quad = l.att_quad,
                    direction = l.direction, cone_angle = l.cone_angle, cone_falloff = l.cone_falloff,
                    enabled = l.enabled, cast_shadows = l.cast_shadows,
                    layer = l.layer
                }
            else
                return {
                    x = lights.x[i], y = lights.y[i], z = lights.z[i],
                    type = lights.type[i],
                    r = lights.r[i], g = lights.g[i], b = lights.b[i],
                    intensity = lights.intensity[i],
                    range = lights.range[i],
                    att_const = lights.att_const[i], att_linear = lights.att_linear[i], att_quad = lights.att_quad[i],
                    direction = lights.direction[i], cone_angle = lights.cone_angle[i], cone_falloff = lights.cone_falloff[i],
                    enabled = lights.enabled[i], cast_shadows = lights.cast_shadows[i],
                    layer = lights.layer[i]
                }
            end
        end
    end
    return nil
end

--- get all lights
function lighting.get_all_lights(layer)
    local result = {}
    local count = 0
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local enabled, l_layer
        if ffi_available then
            enabled = lights.data[i].enabled
            l_layer = lights.data[i].layer
        else
            enabled = lights.enabled[i]
            l_layer = lights.layer[i]
        end
        
        if enabled and (not layer or l_layer == layer) then
            count = count + 1
            if ffi_available then
                local l = lights.data[i]
                result[count] = {
                    id = l.id, x = l.x, y = l.y, z = l.z,
                    type = l.type, r = l.r, g = l.g, b = l.b,
                    intensity = l.intensity, range = l.range,
                    direction = l.direction, cone_angle = l.cone_angle, cone_falloff = l.cone_falloff,
                    layer = l.layer
                }
            else
                result[count] = {
                    id = lights.id[i], x = lights.x[i], y = lights.y[i], z = lights.z[i],
                    type = lights.type[i], r = lights.r[i], g = lights.g[i], b = lights.b[i],
                    intensity = lights.intensity[i], range = lights.range[i],
                    direction = lights.direction[i], cone_angle = lights.cone_angle[i], cone_falloff = lights.cone_falloff[i],
                    layer = lights.layer[i]
                }
            end
        end
    end
    return result
end

--- clear all lights
function lighting.clear_lights()
    lights.count = 0
    next_light_id = 1
end

-- ============================================================================
-- occluders
-- ============================================================================

--- add a line segment occluder
function lighting.add_occluder(x1, y1, x2, y2, two_sided)
    if occluders.count >= config.max_occluders then return nil end
    
    local idx = ffi_available and occluders.count or (occluders.count + 1)
    occluders.count = occluders.count + 1
    local id = next_occluder_id
    next_occluder_id = next_occluder_id + 1
    
    if ffi_available then
        local o = occluders.data[idx]
        o.x1, o.y1 = x1, y1
        o.x2, o.y2 = x2, y2
        o.enabled = true
        o.two_sided = two_sided ~= false
        o.id = id
        o.layer = 0
    else
        occluders.x1[idx] = x1
        occluders.y1[idx] = y1
        occluders.x2[idx] = x2
        occluders.y2[idx] = y2
        occluders.enabled[idx] = true
        occluders.two_sided[idx] = two_sided ~= false
        occluders.id[idx] = id
        occluders.layer[idx] = 0
    end
    
    spatial_hash_add(idx)
    
    -- mark lights dirty
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    for i = start, max do
        if ffi_available then lights.data[i].dirty = true else lights.dirty[i] = true end
    end
    
    return id
end

--- add a rectangle occluder
function lighting.add_rect_occluder(x, y, w, h)
    local ids = {}
    ids[1] = lighting.add_occluder(x, y, x + w, y)
    ids[2] = lighting.add_occluder(x + w, y, x + w, y + h)
    ids[3] = lighting.add_occluder(x + w, y + h, x, y + h)
    ids[4] = lighting.add_occluder(x, y + h, x, y)
    return ids
end

--- add a circle occluder
function lighting.add_circle_occluder(cx, cy, radius, segments)
    segments = segments or 16
    local ids = {}
    local angle_step = TWO_PI / segments
    
    for i = 0, segments - 1 do
        local angle1 = i * angle_step
        local angle2 = (i + 1) * angle_step
        
        local x1 = cx + math_cos(angle1) * radius
        local y1 = cy + math_sin(angle1) * radius
        local x2 = cx + math_cos(angle2) * radius
        local y2 = cy + math_sin(angle2) * radius
        
        ids[i + 1] = lighting.add_occluder(x1, y1, x2, y2)
    end
    return ids
end

--- add a polygon occluder
function lighting.add_polygon_occluder(vertices)
    local ids = {}
    for i = 1, #vertices do
        local v1 = vertices[i]
        local v2 = vertices[(i % #vertices) + 1]
        ids[i] = lighting.add_occluder(v1[1], v1[2], v2[1], v2[2])
    end
    return ids
end

--- remove an occluder
function lighting.remove_occluder(id)
    local idx = nil
    local max = occluders.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local oid = ffi_available and occluders.data[i].id or occluders.id[i]
        if oid == id then
            idx = i
            break
        end
    end
    
    if not idx then return end
    
    spatial_hash_remove(idx)
    
    local last = ffi_available and (occluders.count - 1) or occluders.count
    
    if idx < last then
        if ffi_available then
            occluders.data[idx] = occluders.data[last]
        else
            occluders.x1[idx] = occluders.x1[last]
            occluders.y1[idx] = occluders.y1[last]
            occluders.x2[idx] = occluders.x2[last]
            occluders.y2[idx] = occluders.y2[last]
            occluders.enabled[idx] = occluders.enabled[last]
            occluders.two_sided[idx] = occluders.two_sided[last]
            occluders.id[idx] = occluders.id[last]
            occluders.layer[idx] = occluders.layer[last]
        end
    end
    
    occluders.count = occluders.count - 1
    
    -- mark lights dirty
    local lmax = lights.count
    if ffi_available then lmax = lmax - 1 end
    local lstart = ffi_available and 0 or 1
    for i = lstart, lmax do
        if ffi_available then lights.data[i].dirty = true else lights.dirty[i] = true end
    end
end

--- remove multiple occluders
function lighting.remove_occluders(ids)
    for i = 1, #ids do
        lighting.remove_occluder(ids[i])
    end
end

--- set occluder endpoints
function lighting.set_occluder_position(id, x1, y1, x2, y2)
    local max = occluders.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local oid = ffi_available and occluders.data[i].id or occluders.id[i]
        if oid == id then
            spatial_hash_remove(i)
            if ffi_available then
                occluders.data[i].x1 = x1
                occluders.data[i].y1 = y1
                occluders.data[i].x2 = x2
                occluders.data[i].y2 = y2
            else
                occluders.x1[i] = x1
                occluders.y1[i] = y1
                occluders.x2[i] = x2
                occluders.y2[i] = y2
            end
            spatial_hash_add(i)
            
            -- mark lights dirty
            local lmax = lights.count
            if ffi_available then lmax = lmax - 1 end
            local lstart = ffi_available and 0 or 1
            for j = lstart, lmax do
                if ffi_available then lights.data[j].dirty = true else lights.dirty[j] = true end
            end
            return
        end
    end
end

--- enable/disable occluder
function lighting.set_occluder_enabled(id, enabled)
    local max = occluders.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local oid = ffi_available and occluders.data[i].id or occluders.id[i]
        if oid == id then
            if ffi_available then
                occluders.data[i].enabled = enabled
            else
                occluders.enabled[i] = enabled
            end
            
            if enabled then spatial_hash_add(i) else spatial_hash_remove(i) end
            
            -- mark lights dirty
            local lmax = lights.count
            if ffi_available then lmax = lmax - 1 end
            local lstart = ffi_available and 0 or 1
            for j = lstart, lmax do
                if ffi_available then lights.data[j].dirty = true else lights.dirty[j] = true end
            end
            return
        end
    end
end

--- set occluder layer
function lighting.set_occluder_layer(id, layer)
    local max = occluders.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local oid = ffi_available and occluders.data[i].id or occluders.id[i]
        if oid == id then
            if ffi_available then
                occluders.data[i].layer = layer
            else
                occluders.layer[i] = layer
            end
            return
        end
    end
end

--- clear all occluders
function lighting.clear_occluders()
    occluders.count = 0
    next_occluder_id = 1
    spatial_hash.cells = {}
    
    -- mark lights dirty
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    for i = start, max do
        if ffi_available then lights.data[i].dirty = true else lights.dirty[i] = true end
    end
end

-- ============================================================================
-- updates and queries
-- ============================================================================

--- update lighting system (no-op for now)
function lighting.update()
    -- rendering logic removed, so no shadow polygons to calculate
end

--- get light contribution at a point (cpu)
function lighting.get_light_at_point(x, y, layer)
    local total_r = config.ambient_color[1]
    local total_g = config.ambient_color[2]
    local total_b = config.ambient_color[3]
    
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local enabled, l_layer, r, g, b, intensity
        if ffi_available then
            local l = lights.data[i]
            enabled, l_layer = l.enabled, l.layer
            r, g, b, intensity = l.r, l.g, l.b, l.intensity
        else
            enabled = lights.enabled[i]
            l_layer = lights.layer[i]
            r, g, b, intensity = lights.r[i], lights.g[i], lights.b[i], lights.intensity[i]
        end
        
        if enabled and (not layer or l_layer == layer) then
            local illuminated, attenuation = point_illuminated(i, x, y)
            
            if illuminated then
                local final_intensity = intensity * attenuation
                total_r = total_r + r * final_intensity
                total_g = total_g + g * final_intensity
                total_b = total_b + b * final_intensity
            end
        end
    end
    
    return math_min(ONE, math_max(ZERO, total_r)),
           math_min(ONE, math_max(ZERO, total_g)),
           math_min(ONE, math_max(ZERO, total_b))
end

--- check if point is in shadow (cpu)
function lighting.is_point_in_shadow(x, y, light_id)
    local light_idx = nil
    local max = lights.count
    if ffi_available then max = max - 1 end
    local start = ffi_available and 0 or 1
    
    for i = start, max do
        local lid = ffi_available and lights.data[i].id or lights.id[i]
        if lid == light_id then
            light_idx = i
            break
        end
    end
    
    if not light_idx then return true end
    
    local enabled, lx, ly, range
    if ffi_available then
        local l = lights.data[light_idx]
        enabled, lx, ly, range = l.enabled, l.x, l.y, l.range
    else
        enabled = lights.enabled[light_idx]
        lx, ly, range = lights.x[light_idx], lights.y[light_idx], lights.range[light_idx]
    end
    
    if not enabled then return true end
    
    local dx = x - lx
    local dy = y - ly
    local dist = math_sqrt(dx * dx + dy * dy)
    
    if dist > range then return true end
    
    local nearby_occluders, occ_count = spatial_hash_query(lx, ly, range)
    
    for i = 1, occ_count do
        local idx = nearby_occluders[i]
        local x1, y1, x2, y2
        if ffi_available then
            local o = occluders.data[idx]
            x1, y1, x2, y2 = o.x1, o.y1, o.x2, o.y2
        else
            x1, y1 = occluders.x1[idx], occluders.y1[idx]
            x2, y2 = occluders.x2[idx], occluders.y2[idx]
        end
        
        local t = ray_segment_intersect(lx, ly, dx, dy, x1, y1, x2, y2)
        if t and t < ONE then return true end
    end
    
    return false
end

--- get raw gpu data
--- @return cdata/table lights, cdata/table occluders, number light_count, number occluder_count
function lighting.get_gpu_data()
    if ffi_available then
        return lights.data, occluders.data, lights.count, occluders.count
    else
        -- return tables for non-ffi fallback
        return lights, occluders, lights.count, occluders.count
    end
end

--- get statistics
function lighting.get_stats()
    return {
        lights = lights.count,
        occluders = occluders.count,
        lights_processed = stats.lights_processed,
        occluders_tested = stats.occluders_tested,
    }
end

--- clear all data
function lighting.clear()
    lighting.clear_lights()
    lighting.clear_occluders()
end

-- ============================================================================
-- utilities
-- ============================================================================

function lighting.deg_to_rad(deg)
    return deg * DEG_TO_RAD
end

function lighting.rad_to_deg(rad)
    return rad * RAD_TO_DEG
end

function lighting.attenuation_preset(preset, range)
    if preset == "none" then
        return ONE, ZERO, ZERO
    elseif preset == "linear" then
        return ONE, ONE / range, ZERO
    elseif preset == "quadratic" then
        return ONE, ZERO, TWO / (range * range)
    else
        return ONE, ZERO, ZERO
    end
end

-- ============================================================================
-- direct access
-- ============================================================================

lighting.lights = lights
lighting.occluders = occluders

return lighting