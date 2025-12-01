local matrix = require("matrix")
local noise = require("noise")
local renderer = require("renderer")
local lighting = require("lighting")

if not math.atanh then
    function math.atanh(x) return 0.5 * math.log((1 + x) / (1 - x)) end
end

-- ============================================================================
-- constants
-- ============================================================================
local SCREEN_WIDTH = 800
local SCREEN_HEIGHT = 600
local PLANET_RADIUS = 220

-- resolution settings
local RES_HIGH = 4    
local RES_LOW = 10  

-- ============================================================================
-- global state
-- ============================================================================
local game_state = {
    planet = nil,
    seed = os.time() * 300,
    rotation = matrix.mat3():identity(),
    rotation_speed = 2.0,
    light_id = nil,
    ui_visible = true,
}

-- ============================================================================
-- planet generator
-- ============================================================================
local Planet = {}
Planet.__index = Planet

--- create new planet instance
-- @param seed number random seed for noise generation
-- @return table planet instance
function Planet:new(seed)
    local instance = setmetatable({}, Planet)
    instance.radius = PLANET_RADIUS
    instance.rotation = matrix.mat3():identity()
    instance.rotation_speed = 2.5
    instance.seed = seed or os.time() * 300
    instance.current_res = RES_HIGH
    instance.is_moving = false
    
    -- reseed noise for new planet
    noise.seed(instance.seed)
    
    -- create planet texture (static, pre-rendered)
    instance.texture = instance:create_planet_texture(RES_HIGH)
    
    return instance
end

--- create planet texture (using imagedata)
-- @param resolution number pixel size (stride)
-- @return userdata love2d image
function Planet:create_planet_texture(resolution)
    local dim = self.radius * 2
    -- create imagedata to manipulate pixels directly
    local id = love.image.newImageData(dim, dim)
    
    local r2 = self.radius * self.radius
    local m = self.rotation.m
    
    -- we map (x,y) 0..dim to local -radius..radius
    for y = 0, dim - 1, resolution do
        local dy = y - self.radius
        for x = 0, dim - 1, resolution do
            local dx = x - self.radius
            
            local dist_sq = dx*dx + dy*dy
            if dist_sq <= r2 then
                local z = math.sqrt(r2 - dist_sq)
                
                -- normalize to get normals (nx, ny, nz)
                -- these are screen space normals
                local inv_r = 1 / self.radius
                local nx, ny, nz = dx * inv_r, dy * inv_r, z * inv_r
                
                -- rotate the normal to world space to sample noise
                -- this effectively spins the planet while keeping light fixed
                local rx = m[0]*nx + m[1]*ny + m[2]*nz
                local ry = m[3]*nx + m[4]*ny + m[5]*nz
                local rz = m[6]*nx + m[7]*ny + m[8]*nz
                
                -- get biome color
                local r, g, b, height = self:get_biome_color(rx, ry, rz)
                
                -- lighting (fixed screen space direction)
                -- light comes from top-left-front
                local lx, ly, lz = 0.5, -0.5, 0.7
                -- dot product
                local diff = math.max(0, nx*lx + ny*ly + nz*lz)
                local lighting = 0.3 + diff * 0.7 -- ambient + diffuse
                
                r = r * lighting
                g = g * lighting
                b = b * lighting
                
                -- fill the block of pixels defined by resolution
                -- we iterate by resolution, so we fill a small square
                for by = 0, resolution - 1 do
                    for bx = 0, resolution - 1 do
                        if (x + bx < dim) and (y + by < dim) then
                             id:setPixel(x + bx, y + by, r, g, b, 1)
                        end
                    end
                end
            else
                -- transparent background
                -- (imagedata defaults to 0,0,0,0 so strictly not needed if new)
            end
        end
    end
    
    -- convert imagedata to image for rendering
    return love.graphics.newImage(id)
end

--- get biome color at normalized sphere coordinates
function Planet:get_biome_color(x, y, z)
    local continent_scale = 1.2
    local continent = noise.fbm3(x*continent_scale, y*continent_scale, z*continent_scale, 3, 0.6, 2.1)
    local continent2 = noise.fbm3(x*0.8, y*0.8, z*0.8, 2, 0.5, 2.0)
    continent = continent * 0.7 + continent2 * 0.3
    
    local is_land = continent > 0.52
    
    -- altitude map (latitude-based temperature)
    local latitude = math.abs(y)
    local altitude_temp = 1.0 - latitude
    local lat_noise = noise.fbm3(x*2.5, y*2.5, z*2.5, 2)
    altitude_temp = altitude_temp + (lat_noise - 0.5) * 0.3
    altitude_temp = math.max(0, math.min(1, altitude_temp))
    
    -- proximity map (distance from ocean)
    local proximity = 0
    if is_land then
        proximity = (continent - 0.52) / 0.48
    end
    
    -- height map with erosion
    local height_scale = 3.5
    local height = noise.fbm3(x*height_scale, y*height_scale, z*height_scale, 5, 0.5, 2.0)
    
    -- domain warping
    local wx = x + noise.fbm3(x*2, y*2, z*2, 2) * 0.2
    local wy = y + noise.fbm3(y*2, z*2, x*2, 2) * 0.2
    local wz = z + noise.fbm3(z*2, x*2, y*2, 2) * 0.2
    
    -- mountains
    local mtn_scale = 5.0
    local mountains = noise.ridged3(wx*mtn_scale, wy*mtn_scale, wz*mtn_scale, 4, 0.5, 2.2)
    
    if is_land then
        height = height * 0.7 + 0.1
        height = height + mountains * 0.35 * proximity
        local erosion_factor = 1.0 - math.pow(1.0 - proximity, 2) * 0.4
        height = height * erosion_factor
        local slope = math.abs(mountains - 0.5) * 2
        height = height - slope * 0.05
    else
        height = -0.3 + continent * 0.25
    end
    
    -- rivers
    local river = 0
    if is_land and height > 0.08 and height < 0.7 then
        local river_noise = noise.ridged3(x*8, y*8, z*8, 3, 0.6, 2.0)
        local river_threshold = 0.92 - proximity * 0.15
        if river_noise > river_threshold then
            river = (river_noise - river_threshold) * 10
            river = math.min(river, 1.0)
            height = height - river * 0.08
        end
    end
    
    -- lakes
    local lake = 0
    if is_land and height > 0.08 and height < 0.35 then
        local lake_noise = noise.worley3(x*4, y*4, z*4, 0.8)
        if lake_noise < 0.15 then
            lake = 1.0 - (lake_noise / 0.15)
            height = 0.08
        end
    end
    
    -- temperature map
    local temperature = altitude_temp
    temperature = temperature - (1.0 - proximity) * 0.15
    if is_land then
        temperature = temperature - math.max(0, height - 0.2) * 0.8
    end
    temperature = math.max(0, math.min(1, temperature))
    
    -- humidity map
    local humidity_scale = 2.0
    local humidity = noise.fbm3(x*humidity_scale, y*humidity_scale, z*humidity_scale, 3)
    humidity = humidity + (1.0 - proximity) * 0.3
    if is_land then
        humidity = humidity - math.max(0, height - 0.3) * 0.4
    end
    humidity = humidity + (1.0 - math.abs(y)) * 0.2
    humidity = math.max(0, math.min(1, humidity))
    
    -- colors
    if not is_land or lake > 0 then
        if lake > 0 then return 0.15, 0.35, 0.65, height
        elseif height < -0.2 then return 0.05, 0.05, 0.25, height
        else return 0.1, 0.2, 0.5, height end
    end
    if river > 0.3 then return 0.2, 0.4, 0.7, height end
    if height < 0.12 then return 0.85, 0.8, 0.6, height end
    if temperature < 0.15 then return 0.9, 0.95, 1.0, height
    elseif temperature < 0.25 then return 0.6, 0.65, 0.6, height
    elseif height > 0.7 then return 0.85, 0.9, 0.95, height
    elseif height > 0.55 then return 0.45, 0.45, 0.5, height
    else
        if humidity < 0.3 then
            if temperature > 0.6 then return 0.8, 0.7, 0.4, height
            else return 0.7, 0.65, 0.5, height end
        elseif humidity < 0.5 then
            if temperature > 0.6 then return 0.7, 0.7, 0.4, height
            else return 0.5, 0.7, 0.4, height end
        elseif humidity < 0.7 then
            if temperature > 0.6 then return 0.2, 0.5, 0.2, height
            else return 0.25, 0.45, 0.25, height end
        else
            if temperature > 0.55 then return 0.1, 0.4, 0.2, height
            else return 0.15, 0.35, 0.2, height end
        end
    end
end

--- regenerate planet with new seed
function Planet:regenerate(new_seed)
    self.seed = new_seed or (os.time() * 300 + math.random(1000))
    noise.seed(self.seed)
    if self.texture then self.texture:release() end
    -- force high res update on regen
    self.texture = self:create_planet_texture(RES_HIGH)
end

--- update planet rotation
function Planet:update(dt, keys)
    local speed = self.rotation_speed * dt
    local delta = matrix.mat3()
    local input_active = false

    -- left/right keys rotate around y axis (yaw)
    if keys.left then
        delta:rotation_y(-speed)
        delta:mul(self.rotation)
        self.rotation:copy(delta)
        input_active = true
    end
    if keys.right then
        delta:rotation_y(speed)
        delta:mul(self.rotation)
        self.rotation:copy(delta)
        input_active = true
    end
    
    -- up/down keys rotate around x axis (pitch)
    if keys.up then
        delta:rotation_x(speed)
        delta:mul(self.rotation)
        self.rotation:copy(delta)
        input_active = true
    end
    if keys.down then
        delta:rotation_x(-speed)
        delta:mul(self.rotation)
        self.rotation:copy(delta)
        input_active = true
    end
    
    -- level of detail (lod) system
    -- if we are moving, switch to low res for performance
    if input_active then
        self.is_moving = true
        if self.texture then self.texture:release() end
        self.texture = self:create_planet_texture(RES_LOW)
    elseif self.is_moving and not input_active then
        -- if we just stopped moving, snap back to high res
        self.is_moving = false
        if self.texture then self.texture:release() end
        self.texture = self:create_planet_texture(RES_HIGH)
    end
end

-- ============================================================================
-- game manager
-- ============================================================================
local Game = {}

function Game:load()
    renderer.init(SCREEN_WIDTH, SCREEN_HEIGHT, 1)
    renderer.set_clear_color(0.05, 0.05, 0.1)
    lighting.init(32, 512)
    lighting.set_ambient(0.2, 0.2, 0.25)
    lighting.set_ray_count(64)
    
    game_state.light_id = lighting.add_light(
        SCREEN_WIDTH / 2 + 150, SCREEN_HEIGHT / 2 - 150,
        1.0, 0.95, 0.9, 2.0, 600
    )
    lighting.set_light_shadows(game_state.light_id, false)
    game_state.planet = Planet:new(game_state.seed)
    
    self.keys = {
        up = false, down = false, left = false, right = false,
        space = false, space_trigger = false,
        r = false, r_trigger = false,
    }
end

function Game:update(dt)
    renderer.update(dt)
    lighting.update()
    game_state.planet:update(dt, self.keys)
    
    if self.keys.r_trigger then
        game_state.planet:regenerate()
    end
    if self.keys.space_trigger then
        game_state.ui_visible = not game_state.ui_visible
    end
    self.keys.space_trigger = false
    self.keys.r_trigger = false
end

function Game:draw()
    local cx, cy = SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2
    love.graphics.draw(game_state.planet.texture, cx, cy, 0, 1, 1, game_state.planet.radius, game_state.planet.radius)
    
    if game_state.ui_visible then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print("procedural planet explorer", 10, 10)
        love.graphics.print("seed: " .. game_state.planet.seed, 10, 30)
        love.graphics.print("quality: " .. (game_state.planet.is_moving and "low (moving)" or "high (static)"), 10, 50)
        love.graphics.print("arrow keys: rotate planet", 10, 70)
        love.graphics.print("r: regenerate", 10, 90)
        love.graphics.print("fps: " .. love.timer.getFPS(), 10, 160)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function Game:keypressed(k)
    if k == "space" then self.keys.space = true; self.keys.space_trigger = true end
    if k == "up" or k == "w" then self.keys.up = true end
    if k == "down" or k == "s" then self.keys.down = true end
    if k == "left" or k == "a" then self.keys.left = true end
    if k == "right" or k == "d" then self.keys.right = true end
    if k == "r" then self.keys.r = true; self.keys.r_trigger = true end
    if k == "escape" then love.event.quit() end
end

function Game:keyreleased(k)
    if k == "space" then self.keys.space = false end
    if k == "up" or k == "w" then self.keys.up = false end
    if k == "down" or k == "s" then self.keys.down = false end
    if k == "left" or k == "a" then self.keys.left = false end
    if k == "right" or k == "d" then self.keys.right = false end
    if k == "r" then self.keys.r = false end
end

-- ============================================================================
-- love2d callbacks
-- ============================================================================
function love.load()
    love.window.setTitle("procedural planets sim")
    love.window.setMode(SCREEN_WIDTH, SCREEN_HEIGHT)
    Game:load()
end

function love.update(dt) Game:update(dt) end
function love.draw() Game:draw() end
function love.keypressed(k) Game:keypressed(k) end
function love.keyreleased(k) Game:keyreleased(k) end