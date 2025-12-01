-- high-performance, pooled, stateful particle system
-- supports emitters, affectors, and custom behaviors
-- optimized for luajit with ieee 754 hex floats and minimal allocations
-- @module particles

local floor, ceil = math.floor, math.ceil
local sin, cos, sqrt = math.sin, math.cos, math.sqrt
local min, max, abs = math.min, math.max, math.abs
local random = math.random
local insert, remove = table.insert, table.remove

-- pre-load table.new
local table_new
local ok, new_mod = pcall(require, "table.new")
if ok then table_new = new_mod end

local PI = 0x1.921fb54442d18p1          -- math.pi
local TWO_PI = 0x1.921fb54442d18p2      -- 2 * pi
local HALF_PI = 0x1.921fb54442d18p0     -- pi / 2
local EPSILON = 0x1.0c6f7a0b5ed8dp-10   -- 0.001
local ONE = 0x1p0                        -- 1.0
local ZERO = 0x0p0                       -- 0.0

-- particle state flags (bitwise, compact storage)
local FLAG_ACTIVE = 1
local FLAG_IMMORTAL = 2
local FLAG_COLLIDE = 4
local FLAG_FADE_IN = 8
local FLAG_FADE_OUT = 16

-- ============================================================================
-- module state
-- ============================================================================

local particles = {}

-- global particle pool
local pool = {
    -- position and velocity
    x = {},           -- x position
    y = {},           -- y position
    vx = {},          -- x velocity
    vy = {},          -- y velocity
    
    -- acceleration and forces
    ax = {},          -- x acceleration
    ay = {},          -- y acceleration
    
    -- rotation and angular velocity
    rot = {},         -- rotation (radians)
    vrot = {},        -- angular velocity
    
    -- scale
    scale = {},       -- current scale
    scale_start = {}, -- starting scale
    scale_end = {},   -- ending scale
    
    -- color 
    r = {},           -- red (0-1)
    g = {},           -- green (0-1)
    b = {},           -- blue (0-1)
    a = {},           -- alpha (0-1)
    
    r_start = {},     -- start red
    g_start = {},     -- start green
    b_start = {},     -- start blue
    a_start = {},     -- start alpha
    
    r_end = {},       -- end red
    g_end = {},       -- end green
    b_end = {},       -- end blue
    a_end = {},       -- end alpha
    
    -- timing
    life = {},        -- current lifetime
    life_max = {},    -- maximum lifetime
    
    -- metadata
    flags = {},       -- bit flags
    emitter_id = {},  -- owning emitter
    group = {},       -- collision/behavior group
    
    -- custom data slots
    data1 = {},
    data2 = {},
    data3 = {},
    data4 = {},
    
    -- pool management
    count = 0,        -- active particle count
    capacity = 0,     -- allocated capacity
    free_list = {},   -- recycled indices
}

-- emitter registry
local emitters = {}
local emitter_count = 0

-- affector registry (global forces/behaviors)
local affectors = {}
local affector_count = 0

-- collision grid (spatial partitioning)
local collision_grid = {
    cells = {},
    cell_size = 16,
    enabled = false
}

-- global config
local config = {
    max_particles = 10000,
    spatial_hash_enabled = false,
    blend_mode = "alpha",      -- alpha, add, multiply
    coordinate_mode = "local", -- local, world
}

local lg = love.graphics

-- ============================================================================
-- pool management (zero-allocation particle recycling)
-- ============================================================================

--- clear all particles
local function pool_clear()
    pool.count = 0
    pool.free_list = table_new and table_new(pool.capacity, 0) or {}
    for i = 1, pool.capacity do
        pool.free_list[i] = i
        if pool.flags then -- check if flags exists, as init might not be done
            pool.flags[i] = 0
        end
    end
end

--- initialize particle pool
--- @param capacity number initial capacity
local function pool_init(capacity)
    capacity = capacity or config.max_particles
    
    pool.capacity = capacity
    
    -- pre-allocate all arrays
    local arrays = {
    }
    
    for i = 1, #arrays do
        local key = arrays[i]
        pool[key] = table_new and table_new(capacity, 0) or {}
    end
    
    -- initialize free list and flags by calling clear
    pool_clear()
end

--- allocate particle from pool
--- @return number particle index or nil if pool full
local function pool_alloc()
    if #pool.free_list == 0 then
        return nil -- pool exhausted
    end
    
    local idx = remove(pool.free_list)
    pool.count = pool.count + 1
    
    -- reset to defaults (zero-cost, just writes)
    pool.x[idx] = ZERO
    pool.y[idx] = ZERO
    pool.vx[idx] = ZERO
    pool.vy[idx] = ZERO
    pool.ax[idx] = ZERO
    pool.ay[idx] = ZERO
    pool.rot[idx] = ZERO
    pool.vrot[idx] = ZERO
    pool.scale[idx] = ONE
    pool.scale_start[idx] = ONE
    pool.scale_end[idx] = ONE
    pool.r[idx] = ONE
    pool.g[idx] = ONE
    pool.b[idx] = ONE
    pool.a[idx] = ONE
    pool.r_start[idx] = ONE
    pool.g_start[idx] = ONE
    pool.b_start[idx] = ONE
    pool.a_start[idx] = ONE
    pool.r_end[idx] = ONE
    pool.g_end[idx] = ONE
    pool.b_end[idx] = ONE
    pool.a_end[idx] = ONE
    pool.life[idx] = ZERO
    pool.life_max[idx] = ONE
    pool.flags[idx] = FLAG_ACTIVE
    pool.emitter_id[idx] = 0
    pool.group[idx] = 0
    pool.data1[idx] = ZERO
    pool.data2[idx] = ZERO
    pool.data3[idx] = ZERO
    pool.data4[idx] = ZERO
    
    return idx
end

--- free particle back to pool
--- @param idx number particle index
local function pool_free(idx)
    pool.flags[idx] = 0 -- mark inactive
    insert(pool.free_list, idx)
    pool.count = pool.count - 1
end

-- forward declaration for emitters
local affector_create, affector_destroy

-- ============================================================================
-- emitter system
-- ============================================================================

--- create particle emitter
--- @param x number spawn x position
--- @param y number spawn y position
--- @param config table emitter configuration
--- @return table emitter instance
local function emitter_create(x, y, config)
    config = config or {}
    
    emitter_count = emitter_count + 1
    
    local em = {
        id = emitter_count,
        active = true,
        
        -- position
        x = x or ZERO,
        y = y or ZERO,
        
        -- emission
        rate = config.rate or 10,               -- particles per second
        burst_count = config.burst_count or 0,  -- particles per burst
        burst_delay = config.burst_delay or ONE,
        burst_timer = ZERO,
        emission_timer = ZERO,
        
        -- lifetime
        duration = config.duration or -1,       -- -1 = infinite
        time = ZERO,
        
        -- spawn area
        shape = config.shape or "point",        -- point, circle, rect, line
        radius = config.radius or ZERO,
        width = config.width or ZERO,
        height = config.height or ZERO,
        angle = config.angle or ZERO,           -- for line shape
        
        -- particle properties
        life_min = config.life_min or ONE,
        life_max = config.life_max or 0x1p1,    -- 2.0
        
        -- velocity
        speed_min = config.speed_min or 10,
        speed_max = config.speed_max or 50,
        direction = config.direction or ZERO,
        spread = config.spread or PI,           -- angular spread
        
        -- angular velocity
        vrot_min = config.vrot_min or ZERO,
        vrot_max = config.vrot_max or ZERO,
        
        -- scale
        scale_min = config.scale_min or 0x1p1,
        scale_max = config.scale_max or 0x1p2,    -- 4.0
        scale_end_min = config.scale_end_min or ZERO,
        scale_end_max = config.scale_end_max or ZERO,
        
        -- color
        color_start = config.color_start or {ONE, ONE, ONE, ONE},
        color_end = config.color_end or {ONE, ONE, ONE, ZERO},
        
        -- physics
        gravity_x = config.gravity_x or ZERO,
        gravity_y = config.gravity_y or ZERO,
        
        -- flags
        group = config.group or 0,
        immortal = config.immortal or false,
        fade_in = config.fade_in or false,
        fade_out = config.fade_out or true,
        
        -- pooling
        particle_indices = table_new and table_new(100, 0) or {},
    }
    
    emitters[em.id] = em
    return em
end

--- emit particles from emitter
--- @param em table emitter instance
--- @param count number particles to emit
local function emitter_emit(em, count)
    for i = 1, count do
        local idx = pool_alloc()
        if not idx then return end -- pool full
        
        insert(em.particle_indices, idx)
        
        -- spawn position
        local spawn_x, spawn_y = em.x, em.y
        
        if em.shape == "circle" then
            local r = random() * em.radius
            local theta = random() * TWO_PI
            spawn_x = spawn_x + cos(theta) * r
            spawn_y = spawn_y + sin(theta) * r
            
        elseif em.shape == "rect" then
            spawn_x = spawn_x + (random() - 0x1p-1) * em.width
            spawn_y = spawn_y + (random() - 0x1p-1) * em.height
            
        elseif em.shape == "line" then
            local t = random()
            local length = em.radius
            spawn_x = spawn_x + cos(em.angle) * length * t
            spawn_y = spawn_y + sin(em.angle) * length * t
        end
        
        pool.x[idx] = spawn_x
        pool.y[idx] = spawn_y
        
        -- velocity
        local speed = em.speed_min + random() * (em.speed_max - em.speed_min)
        local dir = em.direction + (random() - 0x1p-1) * em.spread
        pool.vx[idx] = cos(dir) * speed
        pool.vy[idx] = sin(dir) * speed
        
        -- acceleration (gravity)
        pool.ax[idx] = em.gravity_x
        pool.ay[idx] = em.gravity_y
        
        -- rotation
        pool.rot[idx] = random() * TWO_PI
        pool.vrot[idx] = em.vrot_min + random() * (em.vrot_max - em.vrot_min)
        
        -- scale
        local scale_start = em.scale_min + random() * (em.scale_max - em.scale_min)
        local scale_end = em.scale_end_min + random() * (em.scale_end_max - em.scale_end_min)
        
        pool.scale[idx] = scale_start
        pool.scale_start[idx] = scale_start
        pool.scale_end[idx] = scale_end
        
        -- color
        local cs = em.color_start
        local ce = em.color_end
        pool.r_start[idx] = cs[1]
        pool.g_start[idx] = cs[2]
        pool.b_start[idx] = cs[3]
        pool.a_start[idx] = cs[4]
        pool.r_end[idx] = ce[1]
        pool.g_end[idx] = ce[2]
        pool.b_end[idx] = ce[3]
        pool.a_end[idx] = ce[4]
        pool.r[idx] = cs[1]
        pool.g[idx] = cs[2]
        pool.b[idx] = cs[3]
        pool.a[idx] = cs[4]
        
        -- lifetime
        local life_max = em.life_min + random() * (em.life_max - em.life_min)
        pool.life[idx] = ZERO
        pool.life_max[idx] = life_max
        
        -- metadata
        pool.emitter_id[idx] = em.id
        pool.group[idx] = em.group
        
        -- flags
        local flags = FLAG_ACTIVE
        if em.immortal then flags = flags + FLAG_IMMORTAL end
        if em.fade_in then flags = flags + FLAG_FADE_IN end
        if em.fade_out then flags = flags + FLAG_FADE_OUT end
        pool.flags[idx] = flags
    end
end

--- update emitter
--- @param em table emitter instance
--- @param dt number delta time
local function emitter_update(em, dt)
    if not em.active then return end
    
    -- update lifetime
    if em.duration > ZERO then
        em.time = em.time + dt
        if em.time >= em.duration then
            em.active = false
            return
        end
    end
    
    -- continuous emission
    if em.rate > ZERO then
        em.emission_timer = em.emission_timer + dt
        local interval = ONE / em.rate
        while em.emission_timer >= interval do
            em.emission_timer = em.emission_timer - interval
            emitter_emit(em, 1)
        end
    end
    
    -- burst emission
    if em.burst_count > 0 and em.burst_delay > 0 then
        em.burst_timer = em.burst_timer + dt
        if em.burst_timer >= em.burst_delay then
            em.burst_timer = ZERO
            emitter_emit(em, em.burst_count)
            em.burst_count = 0
        end
    end
    
    -- cleanup dead particles from emitter's list
    local indices = em.particle_indices
    for i = #indices, 1, -1 do
        local idx = indices[i]
        if pool.flags[idx] == 0 then
            remove(indices, i)
        end
    end
end

--- destroy emitter and its particles
--- @param em table emitter instance
local function emitter_destroy(em)
    -- free all particles
    for i = 1, #em.particle_indices do
        pool_free(em.particle_indices[i])
    end
    em.particle_indices = {}
    em.active = false
    
    -- destroy associated affector if exists
    if em.affector then
        affector_destroy(em.affector)
    end
    
    emitters[em.id] = nil
end

-- ============================================================================
-- affector system (global forces/behaviors)
-- ============================================================================

--- create affector (force/behavior that affects particles)
--- @param type string affector type
--- @param config table affector configuration
--- @return table affector instance
local function affector_create(type, config)
    config = config or {}
    
    affector_count = affector_count + 1
    
    local af = {
        id = affector_count,
        type = type,
        enabled = true,
        group_mask = config.group_mask or 0, -- 0 = all groups
        
        -- type-specific data
        x = config.x or ZERO,
        y = config.y or ZERO,
        strength = config.strength or ONE,
        radius = config.radius or 100,
        falloff = config.falloff or ONE, -- linear falloff
        
        -- vortex
        clockwise = config.clockwise or true,
        
        -- drag
        drag = config.drag or 0x1p-2, -- 0.25
        
        -- turbulence
        frequency = config.frequency or 0x1p-2,
        octaves = config.octaves or 1,
        
        -- bounds
        min_x = config.min_x or -math.huge,
        min_y = config.min_y or -math.huge,
        max_x = config.max_x or math.huge,
        max_y = config.max_y or math.huge,
        bounce = config.bounce or 0x1p-1, -- 0.5
    }
    
    affectors[af.id] = af
    return af
end

--- apply affector to particle
--- @param af table affector instance
--- @param idx number particle index
--- @param dt number delta time
local function affector_apply(af, idx, dt)
    if not af.enabled then return end
    
    -- group filtering
    if af.group_mask > 0 and pool.group[idx] ~= af.group_mask then
        return
    end
    
    local px, py = pool.x[idx], pool.y[idx]
    
    if af.type == "gravity" then
        -- directional gravity
        pool.ax[idx] = pool.ax[idx] + af.strength * cos(af.x)
        pool.ay[idx] = pool.ay[idx] + af.strength * sin(af.x)
        
    elseif af.type == "attractor" then
        -- point attractor
        local dx = af.x - px
        local dy = af.y - py
        local dist_sq = dx * dx + dy * dy
        local dist = sqrt(dist_sq + EPSILON)
        
        if dist < af.radius then
            local falloff = ONE - (dist / af.radius) ^ af.falloff
            local force = af.strength * falloff / (dist + EPSILON)
            pool.ax[idx] = pool.ax[idx] + dx * force
            pool.ay[idx] = pool.ay[idx] + dy * force
        end
        
    elseif af.type == "repulsor" then
        -- point repulsor
        local dx = px - af.x
        local dy = py - af.y
        local dist_sq = dx * dx + dy * dy
        local dist = sqrt(dist_sq + EPSILON)
        
        if dist < af.radius then
            local falloff = ONE - (dist / af.radius) ^ af.falloff
            local force = af.strength * falloff / (dist + EPSILON)
            pool.ax[idx] = pool.ax[idx] + dx * force
            pool.ay[idx] = pool.ay[idx] + dy * force
        end
        
    elseif af.type == "vortex" then
        -- swirling vortex
        local dx = px - af.x
        local dy = py - af.y
        local dist = sqrt(dx * dx + dy * dy + EPSILON)
        
        if dist < af.radius then
            local falloff = ONE - (dist / af.radius) ^ af.falloff
            local force = af.strength * falloff
            
            local tangent_x, tangent_y
            if af.clockwise then
                tangent_x = -dy
                tangent_y = dx
            else
                tangent_x = dy
                tangent_y = -dx
            end
            
            local len = sqrt(tangent_x * tangent_x + tangent_y * tangent_y + EPSILON)
            tangent_x = tangent_x / len
            tangent_y = tangent_y / len
            
            pool.ax[idx] = pool.ax[idx] + tangent_x * force
            pool.ay[idx] = pool.ay[idx] + tangent_y * force
        end
        
    elseif af.type == "drag" then
        -- velocity damping
        local drag_factor = ONE - af.drag * dt
        if drag_factor < ZERO then drag_factor = ZERO end
        pool.vx[idx] = pool.vx[idx] * drag_factor
        pool.vy[idx] = pool.vy[idx] * drag_factor
        
    elseif af.type == "turbulence" then
        -- simplex-style noise (not full it's just a turbulence effect)
        local noise_x = sin(px * af.frequency + af.y) * cos(py * af.frequency)
        local noise_y = cos(px * af.frequency) * sin(py * af.frequency + af.y)
        
        pool.ax[idx] = pool.ax[idx] + noise_x * af.strength
        pool.ay[idx] = pool.ay[idx] + noise_y * af.strength
        
    elseif af.type == "bounds" then
        -- boundary collision
        if px < af.min_x then
            pool.x[idx] = af.min_x
            pool.vx[idx] = abs(pool.vx[idx]) * af.bounce
        elseif px > af.max_x then
            pool.x[idx] = af.max_x
            pool.vx[idx] = -abs(pool.vx[idx]) * af.bounce
        end
        
        if py < af.min_y then
            pool.y[idx] = af.min_y
            pool.vy[idx] = abs(pool.vy[idx]) * af.bounce
        elseif py > af.max_y then
            pool.y[idx] = af.max_y
            pool.vy[idx] = -abs(pool.vy[idx]) * af.bounce
        end
    end
end

--- destroy affector
--- @param af table affector instance
local function affector_destroy(af)
    affectors[af.id] = nil
end

-- ============================================================================
-- particle update
-- ============================================================================

--- update all particles
--- @param dt number delta time
local function particles_update(dt)
    -- hot: direct array access, minimal branching
    local flags = pool.flags
    local life = pool.life
    local life_max = pool.life_max
    
    local x = pool.x
    local y = pool.y
    local vx = pool.vx
    local vy = pool.vy
    local ax = pool.ax
    local ay = pool.ay
    
    local rot = pool.rot
    local vrot = pool.vrot
    
    local scale = pool.scale
    local scale_start = pool.scale_start
    local scale_end = pool.scale_end
    
    local r = pool.r
    local g = pool.g
    local b = pool.b
    local a = pool.a
    
    local r_start = pool.r_start
    local g_start = pool.g_start
    local b_start = pool.b_start
    local a_start = pool.a_start
    
    local r_end = pool.r_end
    local g_end = pool.g_end
    local b_end = pool.b_end
    local a_end = pool.a_end
    
    local capacity = pool.capacity
    
    -- apply affectors (before integration)
    for aff_id, af in pairs(affectors) do
        if af.enabled then
            for i = 1, capacity do
                if flags[i] > 0 then
                    affector_apply(af, i, dt)
                end
            end
        end
    end
    
    -- main integration loop
    for i = 1, capacity do
        local flag = flags[i]
        if flag > 0 then
            -- integrate velocity
            vx[i] = vx[i] + ax[i] * dt
            vy[i] = vy[i] + ay[i] * dt
            
            -- integrate position
            x[i] = x[i] + vx[i] * dt
            y[i] = y[i] + vy[i] * dt
            
            -- integrate rotation
            rot[i] = rot[i] + vrot[i] * dt
            
            -- update lifetime
            life[i] = life[i] + dt
            
            -- interpolation factor
            local t = life[i] / life_max[i]
            if t > ONE then t = ONE end
            
            -- interpolate scale
            scale[i] = scale_start[i] + (scale_end[i] - scale_start[i]) * t
            
            -- interpolate color
            r[i] = r_start[i] + (r_end[i] - r_start[i]) * t
            g[i] = g_start[i] + (g_end[i] - g_start[i]) * t
            b[i] = b_start[i] + (b_end[i] - b_start[i]) * t
            a[i] = a_start[i] + (a_end[i] - a_start[i]) * t
            
            -- kill particles that exceeded lifetime
            if life[i] >= life_max[i] and flag % 2 == 1 then -- check FLAG_ACTIVE
                if flag < 2 or flag % 4 < 2 then -- check not FLAG_IMMORTAL
                    pool_free(i)
                end
            end
        end
    end
end

-- ============================================================================
-- debug visualization
-- ============================================================================

--- render debug information
local function particles_draw_debug()
    lg.setColor(ONE, ZERO, ONE, 0x1p-1)
    
    -- draw emitters
    for id, em in pairs(emitters) do
        if em.active then
            if em.shape == "point" then
                lg.circle("line", em.x, em.y, 5)
            elseif em.shape == "circle" then
                lg.circle("line", em.x, em.y, em.radius)
            elseif em.shape == "rect" then
                lg.rectangle("line", em.x - em.width/2, em.y - em.height/2, em.width, em.height)
            elseif em.shape == "line" then
                local ex = em.x + cos(em.angle) * em.radius
                local ey = em.y + sin(em.angle) * em.radius
                lg.line(em.x, em.y, ex, ey)
            end
        end
    end
    
    -- draw affectors
    lg.setColor(ZERO, ONE, ONE, 0x1p-1)
    for id, af in pairs(affectors) do
        if af.enabled then
            if af.type == "attractor" or af.type == "repulsor" or af.type == "vortex" then
                lg.circle("line", af.x, af.y, af.radius)
            elseif af.type == "bounds" then
                lg.rectangle("line", af.min_x, af.min_y, 
                    af.max_x - af.min_x, af.max_y - af.min_y)
            end
        end
    end
    
    -- draw particle count
    lg.setColor(ONE, ONE, ONE, ONE)
    lg.print(string.format("Particles: %d / %d", pool.count, pool.capacity), 10, 10)
    lg.print(string.format("Emitters: %d", emitter_count), 10, 30)
    lg.print(string.format("Affectors: %d", affector_count), 10, 50)
end

-- ============================================================================
-- spatial queries
-- ============================================================================

--- get particles in radius
--- @param cx number center x
--- @param cy number center y
--- @param radius number search radius
--- @param group number group filter (0 = all)
--- @return table array of particle indices
local function particles_in_radius(cx, cy, radius, group)
    local result = table_new and table_new(100, 0) or {}
    local count = 0
    local radius_sq = radius * radius
    
    local flags = pool.flags
    local x = pool.x
    local y = pool.y
    local grp = pool.group
    local capacity = pool.capacity
    
    for i = 1, capacity do
        if flags[i] > 0 then
            if group == 0 or grp[i] == group then
                local dx = x[i] - cx
                local dy = y[i] - cy
                local dist_sq = dx * dx + dy * dy
                
                if dist_sq <= radius_sq then
                    count = count + 1
                    result[count] = i
                end
            end
        end
    end
    
    return result
end

--- get particles in rectangle
--- @param rx number rect x
--- @param ry number rect y
--- @param rw number rect width
--- @param rh number rect height
--- @param group number group filter (0 = all)
--- @return table array of particle indices
local function particles_in_rect(rx, ry, rw, rh, group)
    local result = table_new and table_new(100, 0) or {}
    local count = 0
    
    local flags = pool.flags
    local x = pool.x
    local y = pool.y
    local grp = pool.group
    local capacity = pool.capacity
    
    local x2 = rx + rw
    local y2 = ry + rh
    
    for i = 1, capacity do
        if flags[i] > 0 then
            if group == 0 or grp[i] == group then
                local px = x[i]
                local py = y[i]
                
                if px >= rx and px <= x2 and py >= ry and py <= y2 then
                    count = count + 1
                    result[count] = i
                end
            end
        end
    end
    
    return result
end

--- get closest particle to point
--- @param cx number center x
--- @param cy number center y
--- @param max_dist number maximum distance
--- @param group number group filter (0 = all)
--- @return number particle index or nil
local function particles_closest(cx, cy, max_dist, group)
    local closest_idx = nil
    local closest_dist = max_dist * max_dist
    
    local flags = pool.flags
    local x = pool.x
    local y = pool.y
    local grp = pool.group
    local capacity = pool.capacity
    
    for i = 1, capacity do
        if flags[i] > 0 then
            if group == 0 or grp[i] == group then
                local dx = x[i] - cx
                local dy = y[i] - cy
                local dist_sq = dx * dx + dy * dy
                
                if dist_sq < closest_dist then
                    closest_dist = dist_sq
                    closest_idx = i
                end
            end
        end
    end
    
    return closest_idx
end

-- ============================================================================
-- particle manipulation
-- ============================================================================

--- apply force to particle
--- @param idx number particle index
--- @param fx number force x
--- @param fy number force y
local function particle_apply_force(idx, fx, fy)
    if pool.flags[idx] == 0 then return end
    pool.ax[idx] = pool.ax[idx] + fx
    pool.ay[idx] = pool.ay[idx] + fy
end

--- apply impulse to particle
--- @param idx number particle index
--- @param ix number impulse x
--- @param iy number impulse y
local function particle_apply_impulse(idx, ix, iy)
    if pool.flags[idx] == 0 then return end
    pool.vx[idx] = pool.vx[idx] + ix
    pool.vy[idx] = pool.vy[idx] + iy
end

--- set particle property
--- @param idx number particle index
--- @param prop string property name
--- @param value any property value
local function particle_set(idx, prop, value)
    if pool.flags[idx] == 0 then return end
    if pool[prop] then
        pool[prop][idx] = value
    end
end

--- get particle property
--- @param idx number particle index
--- @param prop string property name
--- @return any property value
local function particle_get(idx, prop)
    if pool.flags[idx] == 0 then return nil end
    if pool[prop] then
        return pool[prop][idx]
    end
    return nil
end

--- kill particle
--- @param idx number particle index
local function particle_kill(idx)
    if pool.flags[idx] > 0 then
        pool_free(idx)
    end
end

--- kill all particles in group
--- @param group number group id
local function particles_kill_group(group)
    local flags = pool.flags
    local grp = pool.group
    local capacity = pool.capacity
    
    for i = capacity, 1, -1 do
        if flags[i] > 0 and grp[i] == group then
            pool_free(i)
        end
    end
end

-- ============================================================================
-- presets (common particle effects)
-- ============================================================================

--- create explosion effect
--- @param x number position x
--- @param y number position y
--- @param intensity number explosion intensity
--- @return table emitter
local function preset_explosion(x, y, intensity)
    intensity = intensity or ONE
    
    return emitter_create(x, y, {
        burst_count = floor(50 * intensity),
        shape = "point",
        life_min = 0x1p-1,
        life_max = 0x1p1,
        speed_min = 50 * intensity,
        speed_max = 150 * intensity,
        direction = ZERO,
        spread = TWO_PI,
        scale_min = 0x1p1,
        scale_max = 0x1p2,
        scale_end_min = ZERO,
        scale_end_max = ZERO,
        color_start = {ONE, 0x1p-1, ZERO, ONE},
        color_end = {0x1p-2, ZERO, ZERO, ZERO},
        gravity_y = 50,
        fade_out = true,
        duration = 0x1p-3, -- 0.125
    })
end

--- create fire effect
--- @param x number position x
--- @param y number position y
--- @return table emitter
local function preset_fire(x, y)
    return emitter_create(x, y, {
        rate = 30,
        shape = "circle",
        radius = 5,
        life_min = 0x1p-1,
        life_max = ONE,
        speed_min = 20,
        speed_max = 60,
        direction = -HALF_PI,
        spread = 0x1p-2,
        scale_min = 0x1p1,
        scale_max = 0x1p2,
        scale_end_min = ZERO,
        scale_end_max = ZERO,
        color_start = {ONE, 0x1p-1, ZERO, ONE},
        color_end = {0x1p-1, ZERO, ZERO, ZERO},
        gravity_y = -30,
        fade_out = true,
    })
end

--- create smoke effect
--- @param x number position x
--- @param y number position y
--- @return table emitter
local function preset_smoke(x, y)
    return emitter_create(x, y, {
        rate = 10,
        shape = "circle",
        radius = 0x1p1,
        life_min = ONE,
        life_max = 0x1p2,
        speed_min = 5,
        speed_max = 20,
        direction = -HALF_PI,
        spread = 0x1p-1,
        scale_min = 0x1p1,
        scale_max = 0x1p3,
        scale_end_min = 0x1p3,
        scale_end_max = 0x1p4,
        color_start = {0x1p-1, 0x1p-1, 0x1p-1, 0x1p-1},
        color_end = {0x1p-2, 0x1p-2, 0x1p-2, ZERO},
        gravity_y = -10,
        fade_in = true,
        fade_out = true,
    })
end

--- create rain effect
--- @param x number position x
--- @param y number position y
--- @param width number rain width
--- @return table emitter
local function preset_rain(x, y, width)
    return emitter_create(x, y, {
        rate = 100,
        shape = "rect",
        width = width or 200,
        height = 0,
        life_min = 0x1p1,
        life_max = 0x1p2,
        speed_min = 200,
        speed_max = 300,
        direction = HALF_PI,
        spread = 0x1p-4,
        scale_min = ONE,
        scale_max = 0x1p1,
        scale_end_min = ONE,
        scale_end_max = ONE,
        color_start = {0x1p-1, 0x1p-1, ONE, 0x1p-1},
        color_end = {0x1p-1, 0x1p-1, ONE, 0x1p-1},
        gravity_y = 100,
    })
end

--- create sparkle effect
--- @param x number position x
--- @param y number position y
--- @return table emitter
local function preset_sparkle(x, y)
    return emitter_create(x, y, {
        rate = 20,
        shape = "circle",
        radius = 10,
        life_min = 0x1p-1,
        life_max = ONE,
        speed_min = 0,
        speed_max = 10,
        direction = ZERO,
        spread = TWO_PI,
        scale_min = ONE,
        scale_max = 0x1p1,
        scale_end_min = ZERO,
        scale_end_max = ZERO,
        color_start = {ONE, ONE, ZERO, ONE},
        color_end = {ONE, ONE, ONE, ZERO},
        fade_out = true,
    })
end

--- create trail effect
--- @param x number position x
--- @param y number position y
--- @param direction number trail direction
--- @return table emitter
local function preset_trail(x, y, direction)
    return emitter_create(x, y, {
        rate = 50,
        shape = "point",
        life_min = 0x1p-2,
        life_max = 0x1p-1,
        speed_min = 0,
        speed_max = 5,
        direction = direction or ZERO,
        spread = 0x1p-3,
        scale_min = 0x1p1,
        scale_max = 0x1p2,
        scale_end_min = ZERO,
        scale_end_max = ZERO,
        color_start = {ONE, ONE, ONE, 0x1p-1},
        color_end = {0x1p-1, 0x1p-1, ONE, ZERO},
        fade_out = true,
    })
end

--- create bubbles effect
--- @param x number position x
--- @param y number position y
--- @param width number bubble spawn width
--- @return table emitter
local function preset_bubbles(x, y, width)
    width = width or 100
    
    return emitter_create(x, y, {
        rate = 30,
        shape = "rect",
        width = width,
        height = 0,
        life_min = 0x1p3 + 0x1p4,
        life_max = 0x1p4,
        speed_min = 20,
        speed_max = 80,
        direction = -HALF_PI,
        spread = ZERO,
        scale_min = ONE,
        scale_max = 0x1p1 + ONE,
        scale_end_min = ONE,
        scale_end_max = 0x1p1 + ONE,
        color_start = {ONE, 0x1p-2, 0x1p-2, 0x1p-2 + 0x1p-3},
        color_end = {ONE, 0x1p-1 + 0x1p-2, ONE, ZERO},
        fade_out = true,
        group = 1,
    })
end

--- create petals effect 
--- @param x number position x
--- @param y number position y
--- @param width number petal spawn width
--- @return table emitter
local function preset_petals(x, y, width)
    width = width or 100
    
    local em = emitter_create(x, y, {
        rate = 20,
        shape = "rect",
        width = width,
        height = 0,
        life_min = 0x1p3 + 0x1p4,
        life_max = 0x1p4,
        speed_min = 30,
        speed_max = 50,
        direction = HALF_PI,
        spread = ZERO,
        scale_min = 0x1p1,
        scale_max = 0x1p1 + 0x1p1,
        scale_end_min = 0x1p1,
        scale_end_max = 0x1p1 + 0x1p1,
        color_start = {ONE, 0x1p-1 + 0x1p-2, 0x1p-1 + 0x1p-2, 0x1p-1 + 0x1p-2 + 0x1p-3},
        color_end = {0x1p-1 + 0x1p-2, 0x1p-1 + 0x1p-2, ONE, 0x1p-1 + 0x1p-2 + 0x1p-3},
        group = 2,
    })
    
    local af = affector_create("turbulence", {
        group_mask = 2, 
        strength = 8,
        frequency = 0x1p-3,
        y = 0,
    })
    
    em.affector = af
    
    return em
end

--- create sparks effect
--- @param x number position x
--- @param y number position y
--- @param intensity number spark intensity
--- @return table emitter
local function preset_sparks(x, y, intensity)
    intensity = intensity or ONE
    
    return emitter_create(x, y, {
        burst_count = floor(5 * intensity),
        shape = "point",
        life_min = 0x1p-1 + 0x1p0,
        life_max = 0x1p1 + 0x1p0,
        speed_min = 50 * intensity,
        speed_max = 125 * intensity,
        direction = -HALF_PI,
        spread = PI,
        scale_min = 0x1p1,
        scale_max = 0x1p1 + ONE,
        scale_end_min = ZERO,
        scale_end_max = ZERO,
        color_start = {ONE, ONE, 0x1p-1, ONE},
        color_end = {ONE, 0x1p-2, ZERO, ZERO},
        gravity_y = 100,
        fade_out = true,
        duration = 0x1p-3,
        group = 3,
    })
end

--- create background glimmers effect
--- @param x number position x
--- @param y number position y
--- @param width number glimmer spawn width
--- @param height number glimmer spawn height
--- @return table emitter
local function preset_glimmers(x, y, width, height)
    width = width or 128
    height = height or 128
    
    local em = emitter_create(x, y, {
        rate = 24,
        shape = "rect",
        width = width,
        height = height,
        life_min = 0x1p4,
        life_max = 0x1p5,
        speed_min = 5,
        speed_max = 50,
        direction = ZERO,
        spread = ZERO,
        scale_min = ONE,
        scale_max = 0x1p2,
        scale_end_min = ZERO,
        scale_end_max = ONE,
        color_start = {ONE, 0x1p-1 + 0x1p-2 + 0x1p-3, 0x1p-1 + 0x1p-2 + 0x1p-3, ONE},
        color_end = {ONE, ONE, ONE, ONE},
        fade_in = true,
        fade_out = false,
        group = 5,
    })
    
    local af = affector_create("turbulence", {
        group_mask = 5,
        strength = 2,
        frequency = 0x1p-4,
        y = 0,
    })
    
    em.affector = af
    
    return em
end

-- ============================================================================
-- public api
-- ============================================================================

--- initialize particle system
--- @param max_particles number maximum particles (default 10000)
function particles.init(max_particles)
    config.max_particles = max_particles or 10000
    pool_init(config.max_particles)
end

--- update particle system
--- @param dt number delta time
function particles.update(dt)
    -- update emitters
    for id, em in pairs(emitters) do
        emitter_update(em, dt)
    end
    
    -- update particles
    particles_update(dt)
end

--- render debug information
function particles.draw_debug()
    particles_draw_debug()
end

--- clear all particles
function particles.clear()
    pool_clear()
    
    -- destroy all emitters
    for id, em in pairs(emitters) do
        em.particle_indices = {}
        em.active = false
    end
    emitters = {}
    emitter_count = 0
    
    -- destroy all affectors
    affectors = {}
    affector_count = 0
end

--- set blend mode (now handled by renderer)
--- @param mode string "alpha", "add", or "multiply"
function particles.set_blend_mode(mode)
    config.blend_mode = mode
end

--- get particle count
--- @return number active particles
function particles.count()
    return pool.count
end

--- get pool capacity
--- @return number pool capacity
function particles.capacity()
    return pool.capacity
end

-- emitter functions
particles.emitter = {
    create = emitter_create,
    update = emitter_update,
    emit = emitter_emit,
    destroy = emitter_destroy,
}

-- affector functions
particles.affector = {
    create = affector_create,
    destroy = affector_destroy,
}

-- particle manipulation
particles.particle = {
    apply_force = particle_apply_force,
    apply_impulse = particle_apply_impulse,
    set = particle_set,
    get = particle_get,
    kill = particle_kill,
}

-- spatial queries
particles.query = {
    in_radius = particles_in_radius,
    in_rect = particles_in_rect,
    closest = particles_closest,
    kill_group = particles_kill_group,
}

-- presets
particles.preset = {
    explosion = preset_explosion,
    fire = preset_fire,
    smoke = preset_smoke,
    rain = preset_rain,
    sparkle = preset_sparkle,
    trail = preset_trail,
    bubbles = preset_bubbles,
    petals = preset_petals,
    sparks = preset_sparks,
    glimmers = preset_glimmers,
}

-- direct pool access
particles.pool = pool

return particles