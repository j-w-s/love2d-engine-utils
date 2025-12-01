-- zero-setup input management for love2d
-- automatically detects and routes all input devices with unified api
-- no configuration, just include as system and go
-- @module input

local input = {}

-- cache math operations
local abs = math.abs
local sqrt = math.sqrt
local min = math.min
local max = math.max

-- action codes
local ACT_UP, ACT_DOWN, ACT_LEFT, ACT_RIGHT = 1, 2, 3, 4
local ACT_JUMP, ACT_ACTION, ACT_CANCEL, ACT_START = 5, 6, 7, 8
local ACT_MENU, ACT_INVENTORY, ACT_MAP = 9, 10, 11

-- state codes
local STATE_PRESSED, STATE_DOWN, STATE_RELEASED = 1, 2, 3

-- device type codes
local DEV_KEYBOARD, DEV_MOUSE, DEV_GAMEPAD, DEV_TOUCH = 1, 2, 3, 4

-- ieee 754 hex constants
local F0 = 0x0.0p0  -- 0.0
local F1 = 0x1.0p0  -- 1.0
local F015 = 0x1.3333333333333p-3  -- 0.15
local F05 = 0x1.0p-1  -- 0.5
local Fneg05 = -0x1.0p-1  -- -0.5
local F2 = 0x1.0p1  -- 2.0

-- internal state
local devices = {}
local action_state = {}
local action_frames = {}
local bindings = {}
local deadzone = F015
local deadzone_type = "radial"  -- "radial" or "axial"
local frame = 0

-- input buffering
local input_buffer_frames = 6

-- pre-allocated tables for zero gc
local axis_values = {x = F0, y = F0}
local pointer = {x = F0, y = F0, down = false}

local lk = love.keyboard

-- ============================================================================
-- default bindings
-- ============================================================================

local function init_bindings()
    bindings = {
        -- directional (supports wasd, arrows, dpad, stick)
        [ACT_UP] = {
            keys = {"w", "up"},
            scancodes = {"w", "up"},
            gamepad_buttons = {"dpup"},
            gamepad_axes = {{"lefty", Fneg05}},
            mouse = nil,
            touch = nil
        },
        [ACT_DOWN] = {
            keys = {"s", "down"},
            scancodes = {"s", "down"},
            gamepad_buttons = {"dpdown"},
            gamepad_axes = {{"lefty", F05}},
            mouse = nil,
            touch = nil
        },
        [ACT_LEFT] = {
            keys = {"a", "left"},
            scancodes = {"a", "left"},
            gamepad_buttons = {"dpleft"},
            gamepad_axes = {{"leftx", Fneg05}},
            mouse = nil,
            touch = nil
        },
        [ACT_RIGHT] = {
            keys = {"d", "right"},
            scancodes = {"d", "right"},
            gamepad_buttons = {"dpright"},
            gamepad_axes = {{"leftx", F05}},
            mouse = nil,
            touch = nil
        },
        
        -- actions
        [ACT_JUMP] = {
            keys = {"space", "z"},
            scancodes = {"space", "z"},
            gamepad_buttons = {"a"},
            gamepad_axes = nil,
            mouse = {1},
            touch = true
        },
        [ACT_ACTION] = {
            keys = {"e", "x"},
            scancodes = {"e", "x"},
            gamepad_buttons = {"b"},
            gamepad_axes = nil,
            mouse = {1},
            touch = true
        },
        [ACT_CANCEL] = {
            keys = {"escape", "backspace"},
            scancodes = {"escape", "backspace"},
            gamepad_buttons = {"back"},
            gamepad_axes = nil,
            mouse = {2},
            touch = nil
        },
        [ACT_START] = {
            keys = {"return", "space"},
            scancodes = {"return", "space"},
            gamepad_buttons = {"start"},
            gamepad_axes = nil,
            mouse = nil,
            touch = nil
        },
        [ACT_MENU] = {
            keys = {"escape", "tab"},
            scancodes = {"escape", "tab"},
            gamepad_buttons = {"back", "start"},
            gamepad_axes = nil,
            mouse = nil,
            touch = nil
        },
        [ACT_INVENTORY] = {
            keys = {"i", "tab"},
            scancodes = {"i", "tab"},
            gamepad_buttons = {"y"},
            gamepad_axes = nil,
            mouse = nil,
            touch = nil
        },
        [ACT_MAP] = {
            keys = {"m"},
            scancodes = {"m"},
            gamepad_buttons = {"x"},
            gamepad_axes = nil,
            mouse = nil,
            touch = nil
        }
    }
end

-- ============================================================================
-- device detection and management
-- ============================================================================

local function detect_devices()
    devices = {}
    
    -- keyboard always available
    devices[#devices + 1] = {
        type = DEV_KEYBOARD,
        id = 1,
        active = false,
        last_frame = 0
    }
    
    -- mouse always available
    devices[#devices + 1] = {
        type = DEV_MOUSE,
        id = 1,
        active = false,
        last_frame = 0
    }
    
    -- detect gamepads
    local joysticks = love.joystick.getJoysticks()
    for i = 1, #joysticks do
        local joy = joysticks[i]
        if joy:isGamepad() then
            devices[#devices + 1] = {
                type = DEV_GAMEPAD,
                id = i,
                joystick = joy,
                active = false,
                last_frame = 0
            }
        end
    end
    
    -- touch available on mobile
    if love.system.getOS() == "Android" or love.system.getOS() == "iOS" then
        devices[#devices + 1] = {
            type = DEV_TOUCH,
            id = 1,
            active = false,
            last_frame = 0,
            touches = {}
        }
    end
end

local function mark_device_active(dev_type, dev_id)
    for i = 1, #devices do
        local dev = devices[i]
        if dev.type == dev_type and dev.id == dev_id then
            dev.active = true
            dev.last_frame = frame
            return
        end
    end
end

local function get_active_device()
    local most_recent = nil
    local most_recent_frame = -1
    
    for i = 1, #devices do
        local dev = devices[i]
        if dev.active and dev.last_frame > most_recent_frame then
            most_recent = dev
            most_recent_frame = dev.last_frame
        end
    end
    
    return most_recent
end

-- ============================================================================
-- input sampling
-- ============================================================================

local function apply_deadzone(value)
    if value > -deadzone and value < deadzone then
        return F0
    end
    local sign = value > F0 and F1 or -F1
    return (abs(value) - deadzone) / (F1 - deadzone) * sign
end

local function apply_deadzone_radial(x, y)
    local magnitude = sqrt(x*x + y*y)
    if magnitude < deadzone then
        return F0, F0
    end
    local scale = (magnitude - deadzone) / (F1 - deadzone) / magnitude
    return x * scale, y * scale
end

local function apply_deadzone_axial(x, y)
    x = apply_deadzone(x)
    y = apply_deadzone(y)
    return x, y
end

local function check_keyboard(action)
    local bind = bindings[action]
    if not bind or not bind.keys then return false end
    
    for i = 1, #bind.keys do
        if lk.isDown(bind.keys[i]) then
            mark_device_active(DEV_KEYBOARD, 1)
            return true
        end
    end
    
    return false
end

local function check_mouse(action)
    local bind = bindings[action]
    if not bind or not bind.mouse then return false end
    
    for i = 1, #bind.mouse do
        if love.mouse.isDown(bind.mouse[i]) then
            mark_device_active(DEV_MOUSE, 1)
            return true
        end
    end
    
    return false
end

local function check_gamepad(action, dev)
    local bind = bindings[action]
    if not bind then return false end
    
    local joy = dev.joystick
    if not joy or not joy:isConnected() then return false end
    
    -- check buttons
    if bind.gamepad_buttons then
        for i = 1, #bind.gamepad_buttons do
            if joy:isGamepadDown(bind.gamepad_buttons[i]) then
                mark_device_active(DEV_GAMEPAD, dev.id)
                return true
            end
        end
    end
    
    -- check axes
    if bind.gamepad_axes then
        for i = 1, #bind.gamepad_axes do
            local axis_def = bind.gamepad_axes[i]
            local axis_name = axis_def[1]
            local threshold = axis_def[2]
            local value = joy:getGamepadAxis(axis_name)
            
            if threshold > F0 and value > threshold then
                mark_device_active(DEV_GAMEPAD, dev.id)
                return true
            elseif threshold < F0 and value < threshold then
                mark_device_active(DEV_GAMEPAD, dev.id)
                return true
            end
        end
    end
    
    return false
end

local function check_touch(action)
    local bind = bindings[action]
    if not bind or not bind.touch then return false end
    
    local touches = love.touch.getTouches()
    if #touches > 0 then
        mark_device_active(DEV_TOUCH, 1)
        return true
    end
    
    return false
end

local function sample_action(action)
    -- check all input sources
    if check_keyboard(action) then return true end
    if check_mouse(action) then return true end
    if check_touch(action) then return true end
    
    -- check all gamepads
    for i = 1, #devices do
        local dev = devices[i]
        if dev.type == DEV_GAMEPAD then
            if check_gamepad(action, dev) then return true end
        end
    end
    
    return false
end

-- ============================================================================
-- axis reading
-- ============================================================================

local function sample_axis()
    axis_values.x = F0
    axis_values.y = F0
    
    -- keyboard/scancode (digital to analog)
    if lk.isDown("w", "up") then
        axis_values.y = axis_values.y - F1
        mark_device_active(DEV_KEYBOARD, 1)
    end
    if lk.isDown("s", "down") then
        axis_values.y = axis_values.y + F1
        mark_device_active(DEV_KEYBOARD, 1)
    end
    if lk.isDown("a", "left") then
        axis_values.x = axis_values.x - F1
        mark_device_active(DEV_KEYBOARD, 1)
    end
    if lk.isDown("d", "right") then
        axis_values.x = axis_values.x + F1
        mark_device_active(DEV_KEYBOARD, 1)
    end
    
    -- gamepad analog sticks
    for i = 1, #devices do
        local dev = devices[i]
        if dev.type == DEV_GAMEPAD then
            local joy = dev.joystick
            if joy and joy:isConnected() then
                local x = joy:getGamepadAxis("leftx")
                local y = joy:getGamepadAxis("lefty")
                
                -- apply deadzone based on type
                if deadzone_type == "radial" then
                    x, y = apply_deadzone_radial(x, y)
                else
                    x, y = apply_deadzone_axial(x, y)
                end
                
                if x ~= F0 or y ~= F0 then
                    axis_values.x = axis_values.x + x
                    axis_values.y = axis_values.y + y
                    mark_device_active(DEV_GAMEPAD, dev.id)
                end
            end
        end
    end
    
    -- touch (virtual stick from first touch)
    if love.touch then
        local touches = love.touch.getTouches()
        if #touches > 0 then
            local id = touches[1]
            local x, y = love.touch.getPosition(id)
            local w, h = love.graphics.getDimensions()
            
            -- convert to normalized -1 to 1
            axis_values.x = (x / w) * F2 - F1
            axis_values.y = (y / h) * F2 - F1
            mark_device_active(DEV_TOUCH, 1)
        end
    end
    
    -- normalize if multiple inputs
    local len = sqrt(axis_values.x * axis_values.x + axis_values.y * axis_values.y)
    if len > F1 then
        axis_values.x = axis_values.x / len
        axis_values.y = axis_values.y / len
    end
    
    return axis_values.x, axis_values.y
end

-- ============================================================================
-- pointer (mouse/touch position)
-- ============================================================================

local function sample_pointer()
    -- mouse position
    pointer.x, pointer.y = love.mouse.getPosition()
    pointer.down = love.mouse.isDown(1)
    
    -- override with touch if active
    if love.touch then
        local touches = love.touch.getTouches()
        if #touches > 0 then
            local id = touches[1]
            pointer.x, pointer.y = love.touch.getPosition(id)
            pointer.down = true
        end
    end
    
    return pointer.x, pointer.y, pointer.down
end

-- ============================================================================
-- state management
-- ============================================================================

local function update_action_states()
    for action = 1, 11 do
        local was_down = action_state[action] == STATE_DOWN or action_state[action] == STATE_PRESSED
        local is_down = sample_action(action)
        
        if is_down and not was_down then
            action_state[action] = STATE_PRESSED
            action_frames[action] = frame
        elseif is_down and was_down then
            action_state[action] = STATE_DOWN
        elseif not is_down and was_down then
            action_state[action] = STATE_RELEASED
            action_frames[action] = frame
        else
            action_state[action] = nil
        end
    end
end

-- ============================================================================
-- public api
-- ============================================================================

--- check if action was just pressed this frame
--- @param action integer action code
--- @return boolean true if pressed
function input.pressed(action)
    return action_state[action] == STATE_PRESSED
end

--- check if action is currently held down
--- @param action integer action code
--- @return boolean true if down
function input.down(action)
    local state = action_state[action]
    return state == STATE_DOWN or state == STATE_PRESSED
end

--- check if action was just released this frame
--- @param action integer action code
--- @return boolean true if released
function input.released(action)
    return action_state[action] == STATE_RELEASED
end

--- check if action was pressed within buffer window (great for game feel!)
--- @param action integer action code
--- @param frames integer (optional) buffer window in frames, default 6
--- @return boolean true if buffered
function input.buffered(action, frames)
    frames = frames or input_buffer_frames
    local f = action_frames[action]
    local state = action_state[action]
    if not f then return false end
    if state ~= STATE_PRESSED and state ~= STATE_DOWN then return false end
    return (frame - f) <= frames
end

--- check if any of the given actions are pressed
--- @param ... integer action codes
--- @return boolean true if any pressed
function input.any_pressed(...)
    for i = 1, select('#', ...) do
        if input.pressed(select(i, ...)) then
            return true
        end
    end
    return false
end

--- check if any of the given actions are down
--- @param ... integer action codes
--- @return boolean true if any down
function input.any_down(...)
    for i = 1, select('#', ...) do
        if input.down(select(i, ...)) then
            return true
        end
    end
    return false
end

--- check if all of the given actions are down (for combos)
--- @param ... integer action codes
--- @return boolean true if all down
function input.all_down(...)
    for i = 1, select('#', ...) do
        if not input.down(select(i, ...)) then
            return false
        end
    end
    return true
end

--- get directional axis values
--- @return number x axis (-1 to 1)
--- @return number y axis (-1 to 1)
function input.axis()
    return axis_values.x, axis_values.y
end

--- get pointer position (mouse/touch)
--- @return number x position
--- @return number y position
--- @return boolean is pressed
function input.pointer()
    return pointer.x, pointer.y, pointer.down
end

--- get currently active device
--- @return table device info or nil
function input.device()
    return get_active_device()
end

--- set custom deadzone for analog inputs
--- @param zone number deadzone value (0 to 1)
--- @param type string (optional) "radial" or "axial", default "radial"
function input.set_deadzone(zone, type)
    deadzone = zone
    if type then
        deadzone_type = type
    end
end

--- set input buffer window
--- @param frames integer buffer window in frames
function input.set_buffer_frames(frames)
    input_buffer_frames = frames
end

--- bind action to custom inputs
--- @param action integer action code
--- @param config table binding configuration
function input.bind(action, config)
    bindings[action] = config
end

--- add additional bindings to an action without replacing existing ones
--- @param action integer action code
--- @param config table binding configuration (same format as bind)
function input.add_binding(action, config)
    local bind = bindings[action]
    if not bind then
        bindings[action] = config
        return
    end
    
    -- merge keys
    if config.keys and bind.keys then
        for i = 1, #config.keys do
            bind.keys[#bind.keys + 1] = config.keys[i]
        end
    end
    
    -- merge gamepad buttons
    if config.gamepad_buttons and bind.gamepad_buttons then
        for i = 1, #config.gamepad_buttons do
            bind.gamepad_buttons[#bind.gamepad_buttons + 1] = config.gamepad_buttons[i]
        end
    end
    
    -- merge other fields as needed
    if config.mouse then bind.mouse = config.mouse end
    if config.touch then bind.touch = config.touch end
    if config.gamepad_axes then bind.gamepad_axes = config.gamepad_axes end
end

--- get current bindings for an action (useful for displaying controls)
--- @param action integer action code
--- @return table binding configuration
function input.get_binding(action)
    return bindings[action]
end

--- get action code by name (for readability)
--- @param name string action name
--- @return integer action code
function input.action(name)
    local map = {
        up = ACT_UP, down = ACT_DOWN, left = ACT_LEFT, right = ACT_RIGHT,
        jump = ACT_JUMP, action = ACT_ACTION, cancel = ACT_CANCEL,
        start = ACT_START, menu = ACT_MENU, inventory = ACT_INVENTORY,
        map = ACT_MAP
    }
    return map[name]
end

--- update input state (call once per frame in love.update)
--- @param dt number delta time
function input.update(dt)
    frame = frame + 1
    sample_axis()
    sample_pointer()
    update_action_states()
end

--- hot-reload device list (call when controller connected/disconnected)
function input.refresh()
    detect_devices()
end

function input.keypressed(key, scancode, isrepeat)
    mark_device_active(DEV_KEYBOARD, 1)
end

function input.mousepressed(x, y, button, istouch, presses)
    mark_device_active(DEV_MOUSE, 1)
end

function input.touchpressed(id, x, y, dx, dy, pressure)
    mark_device_active(DEV_TOUCH, 1)
end

function input.gamepadpressed(joystick, button)
    for i = 1, #devices do
        local dev = devices[i]
        if dev.type == DEV_GAMEPAD and dev.joystick == joystick then
            mark_device_active(DEV_GAMEPAD, dev.id)
            break
        end
    end
end

function input.joystickadded(joystick)
    detect_devices()
end

function input.joystickremoved(joystick)
    detect_devices()
end

-- ============================================================================
-- initialization
-- ============================================================================

init_bindings()
detect_devices()

-- export action codes
input.UP = ACT_UP
input.DOWN = ACT_DOWN
input.LEFT = ACT_LEFT
input.RIGHT = ACT_RIGHT
input.JUMP = ACT_JUMP
input.ACTION = ACT_ACTION
input.CANCEL = ACT_CANCEL
input.START = ACT_START
input.MENU = ACT_MENU
input.INVENTORY = ACT_INVENTORY
input.MAP = ACT_MAP

return input