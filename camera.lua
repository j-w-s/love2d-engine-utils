--- camera system
--- @module camera

local vector = require("vector")
local matrix = require("matrix")
local vec2 = vector.vec2
local vec3 = vector.vec3
local mat4 = matrix.mat4

local min, max, floor, abs = math.min, math.max, math.floor, math.abs
local sin, cos, exp = math.sin, math.cos, math.exp
local lg = love.graphics

local camera = {}
local camera_mt = { __index = camera }

--- create a new camera
--- @param x number|nil initial x position
--- @param y number|nil initial y position
--- @param zoom number|nil initial zoom level
--- @param rot number|nil initial rotation (radians)
--- @return table camera instance
function camera.new(x, y, zoom, rot)
    local self = setmetatable({}, camera_mt)

    -- state
    self.pos = vec2(x or 0, y or 0)
    self.target_pos = vec2(x or 0, y or 0)
    self.scale = zoom or 1
    self.target_scale = zoom or 1
    self.rot = rot or 0
    self.target_rot = rot or 0

    -- tracking configuration
    self.mode = "smooth" -- "locked", "smooth", "window", "look_ahead"
    self.lerp_speed = 5  -- for smooth follow
    self.look_ahead_dist = 0
    self.look_ahead_lerp = 2
    self.deadzone = nil -- {x, y, w, h} relative to screen center (for window mode)

    -- zoom configuration
    self.zoom_mode = "manual" -- "manual", "fit"
    self.zoom_lerp_speed = 5

    -- rotation configuration
    self.rot_lerp_speed = 5

    -- constraints
    self.bounds = nil -- {x, y, w, h} world bounds

    -- shake
    self.shake_amount = 0
    self.shake_timer = 0
    self.shake_duration = 0
    self.shake_offset = vec2(0, 0)

    -- matrices (cached)
    self.view_matrix = mat4()
    self.inv_view_matrix = mat4()
    self.dirty = true

    -- context
    self.screen_w = lg.getWidth()
    self.screen_h = lg.getHeight()

    return self
end

--- set camera position directly
--- @param x number
--- @param y number
function camera:set_position(x, y)
    self.pos:set(x, y)
    self.target_pos:set(x, y)
    self.dirty = true
end

--- get camera position
--- @return number x, number y
function camera:get_position()
    return self.pos.x, self.pos.y
end

--- set target position for tracking
--- @param x number
--- @param y number
function camera:set_target(x, y)
    self.target_pos:set(x, y)
end

--- move camera relative to current position
--- @param dx number
--- @param dy number
function camera:move(dx, dy)
    self.pos.x = self.pos.x + dx
    self.pos.y = self.pos.y + dy
    self.target_pos.x = self.target_pos.x + dx
    self.target_pos.y = self.target_pos.y + dy
    self.dirty = true
end

--- set zoom level directly
--- @param z number
function camera:set_zoom(z)
    self.scale = z
    self.target_scale = z
    self.dirty = true
end

--- get current zoom level
--- @return number
function camera:get_zoom()
    return self.scale
end

--- set target zoom level
--- @param z number
function camera:zoom_to(z)
    self.target_scale = z
end

--- set rotation directly (radians)
--- @param r number
function camera:set_rotation(r)
    self.rot = r
    self.target_rot = r
    self.dirty = true
end

--- get current rotation
--- @return number
function camera:get_rotation()
    return self.rot
end

--- set target rotation
--- @param r number
function camera:rotate_to(r)
    self.target_rot = r
end

--- set tracking mode
--- @param mode string "locked", "smooth", "window", "look_ahead"
function camera:set_mode(mode)
    self.mode = mode
end

--- set lerp speeds
--- @param pos_speed number
--- @param zoom_speed number|nil
--- @param rot_speed number|nil
function camera:set_lerp_speed(pos_speed, zoom_speed, rot_speed)
    self.lerp_speed = pos_speed or 0
    self.zoom_lerp_speed = zoom_speed or pos_speed or 0
    self.rot_lerp_speed = rot_speed or pos_speed or 0
end

--- set world bounds
--- @param x number|nil
--- @param y number|nil
--- @param w number|nil
--- @param h number|nil
function camera:set_bounds(x, y, w, h)
    if x then
        self.bounds = { x = x, y = y, w = w, h = h }
    else
        self.bounds = nil
    end
    self.dirty = true
end

--- clear world bounds
function camera:clear_bounds()
    self.bounds = nil
    self.dirty = true
end

--- set deadzone for window mode
--- @param x number
--- @param y number
--- @param w number
--- @param h number
function camera:set_deadzone(x, y, w, h)
    self.deadzone = { x = x, y = y, w = w, h = h }
end

--- clear deadzone
function camera:clear_deadzone()
    self.deadzone = nil
end

--- trigger camera shake
--- @param amount number intensity
--- @param duration number seconds
function camera:shake(amount, duration)
    self.shake_amount = amount
    self.shake_duration = duration
    self.shake_timer = duration
end

--- update camera state
--- @param dt number delta time
function camera:update(dt)
    -- update screen dimensions
    -- removed automatic resize to prevent conflict with virtual resolution
    -- use camera:resize(w, h) explicitly

    -- update shake
    if self.shake_timer > 0 then
        self.shake_timer = max(0, self.shake_timer - dt)
        local progress = self.shake_timer / self.shake_duration
        local damping = progress * progress -- quadratic falloff
        local current_amount = self.shake_amount * damping

        self.shake_offset:set(
            (math.random() * 2 - 1) * current_amount,
            (math.random() * 2 - 1) * current_amount
        )
        self.dirty = true
    else
        if self.shake_offset.x ~= 0 or self.shake_offset.y ~= 0 then
            self.shake_offset:set(0, 0)
            self.dirty = true
        end
    end

    -- update position based on mode
    if self.mode == "locked" then
        self.pos:copy(self.target_pos)
        self.dirty = true
    elseif self.mode == "smooth" then
        local t = 1 - exp(-self.lerp_speed * dt)
        self.pos:lerp(self.target_pos, t)
        self.dirty = true
    elseif self.mode == "window" then
        if self.deadzone then
            local dx = self.target_pos.x - self.pos.x
            local dy = self.target_pos.y - self.pos.y

            -- convert deadzone to world units based on current zoom
            local dz_w = self.deadzone.w / self.scale
            local dz_h = self.deadzone.h / self.scale
            local dz_x = self.deadzone.x / self.scale -- offset from center
            local dz_y = self.deadzone.y / self.scale

            -- deadzone bounds relative to camera center
            local left = dz_x - dz_w * 0.5
            local right = dz_x + dz_w * 0.5
            local top = dz_y - dz_h * 0.5
            local bottom = dz_y + dz_h * 0.5

            local move_x, move_y = 0, 0

            if dx < left then
                move_x = dx - left
            elseif dx > right then
                move_x = dx - right
            end

            if dy < top then
                move_y = dy - top
            elseif dy > bottom then
                move_y = dy - bottom
            end

            if move_x ~= 0 or move_y ~= 0 then
                -- smooth movement towards the edge
                local t = 1 - exp(-self.lerp_speed * dt)
                self.pos.x = self.pos.x + move_x * t
                self.pos.y = self.pos.y + move_y * t
                self.dirty = true
            end
        else
            -- fallback to smooth if no deadzone
            local t = 1 - exp(-self.lerp_speed * dt)
            self.pos:lerp(self.target_pos, t)
            self.dirty = true
        end
    elseif self.mode == "look_ahead" then
        -- TODO: implement velocity-based look ahead (SMOOTH BRAIN ATM)
        local t = 1 - exp(-self.lerp_speed * dt)
        self.pos:lerp(self.target_pos, t)
        self.dirty = true
    end

    -- update zoom
    if abs(self.target_scale - self.scale) > 0.001 then
        local t = 1 - exp(-self.zoom_lerp_speed * dt)
        self.scale = self.scale + (self.target_scale - self.scale) * t
        self.dirty = true
    else
        self.scale = self.target_scale
    end

    -- update rotation
    if abs(self.target_rot - self.rot) > 0.001 then
        local t = 1 - exp(-self.rot_lerp_speed * dt)
        self.rot = self.rot + (self.target_rot - self.rot) * t
        self.dirty = true
    else
        self.rot = self.target_rot
    end

    -- constrain to bounds
    if self.bounds then
        local view_w = self.screen_w / self.scale
        local view_h = self.screen_h / self.scale
        local half_w = view_w * 0.5
        local half_h = view_h * 0.5

        local min_x = self.bounds.x + half_w
        local max_x = self.bounds.x + self.bounds.w - half_w
        local min_y = self.bounds.y + half_h
        local max_y = self.bounds.y + self.bounds.h - half_h

        -- if bounds are smaller than view, center on bounds
        if max_x < min_x then
            self.pos.x = self.bounds.x + self.bounds.w * 0.5
        else
            self.pos.x = max(min_x, min(max_x, self.pos.x))
        end

        if max_y < min_y then
            self.pos.y = self.bounds.y + self.bounds.h * 0.5
        else
            self.pos.y = max(min_y, min(max_y, self.pos.y))
        end
        self.dirty = true
    end

    if self.dirty then
        self:update_matrices()
    end
end

--- update internal matrices
function camera:update_matrices()
    local cx = self.screen_w * 0.5
    local cy = self.screen_h * 0.5

    local x = floor(self.pos.x + self.shake_offset.x)
    local y = floor(self.pos.y + self.shake_offset.y)

    self.view_matrix:identity()
    self.view_matrix:mul(mat4():translation(cx, cy))
    if self.rot ~= 0 then
        self.view_matrix:mul(mat4():rotation_z(self.rot))
    end
    self.view_matrix:mul(mat4():scale(self.scale, self.scale, 1))
    self.view_matrix:mul(mat4():translation(-x, -y))

    self.inv_view_matrix:copy(self.view_matrix)
    self.inv_view_matrix:invert()

    self.dirty = false
end

--- apply camera transform to love.graphics
function camera:apply()
    if self.dirty then
        self:update_matrices()
    end

    local cx = self.screen_w * 0.5
    local cy = self.screen_h * 0.5
    local x = floor(self.pos.x + self.shake_offset.x)
    local y = floor(self.pos.y + self.shake_offset.y)

    lg.translate(cx, cy)
    if self.rot ~= 0 then
        lg.rotate(self.rot)
    end
    lg.scale(self.scale, self.scale)
    lg.translate(-x, -y)
end

--- convert screen coordinates to world coordinates
--- @param x number
--- @param y number
--- @return number wx, number wy
function camera:screen_to_world(x, y)
    if self.dirty then self:update_matrices() end
    local m = self.inv_view_matrix.m
    local wx = m[0] * x + m[1] * y + m[3]
    local wy = m[4] * x + m[5] * y + m[7]
    return wx, wy
end

--- convert world coordinates to screen coordinates
--- @param x number
--- @param y number
--- @return number sx, number sy
function camera:world_to_screen(x, y)
    if self.dirty then self:update_matrices() end
    local m = self.view_matrix.m
    local sx = m[0] * x + m[1] * y + m[3]
    local sy = m[4] * x + m[5] * y + m[7]
    return sx, sy
end

--- resize camera viewport
--- @param w number
--- @param h number
function camera:resize(w, h)
    if self.screen_w ~= w or self.screen_h ~= h then
        self.screen_w = w
        self.screen_h = h
        self.dirty = true
    end
end

--- get view matrix (for shaders)
--- @return table mat4
function camera:get_view_matrix()
    if self.dirty then self:update_matrices() end
    return self.view_matrix
end

return camera
