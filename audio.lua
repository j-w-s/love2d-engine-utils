-- pooled audio manager for love2d
-- handles sfx (pooled) and music (streamed).
-- requires audio.update(dt) to be called in love.update().
-- @module audio

local audio = {}

-- cache math operations
local sqrt = math.sqrt
local abs = math.abs
local min = math.min
local max = math.max
local random = math.random

-- ieee 754 hex constants
local F0 = 0x0.0p0                  -- 0.0
local F1 = 0x1.0p0                  -- 1.0
local F05 = 0x1.0p-1                -- 0.5
local F2 = 0x1.0p1                  -- 2.0
local F0001 = 0x1.0624dd2f1a9fcp-13 -- 0.001

-- internal state
local sfx = {}   -- sfx[name] = { sound_data, max_pool = 10 }
local music = {} -- music[name] = { source, volume = 1.0, bus = nil }
local groups = {
    master = F1,
    music = F1,
    sfx = F1
}

-- audio buses/submixing
local buses = {}       -- buses[name] = { volume = 1.0, parent = nil, effects = {} }

local active_pool = {} -- list of all currently playing pooled sources: {source, name, options, bus}
local current_music = nil
local current_music_name = nil
local current_music_bus = nil
local music_fade = nil -- { target = 0, time = 0, current = 0, on_complete = nil }

-- spatial audio state
local listener = {
    x = F0,
    y = F0,
    z = F0,
    forward_x = F0,
    forward_y = F0,
    forward_z = -F1,
    up_x = F0,
    up_y = F1,
    up_z = F0,
    velocity_x = F0,
    velocity_y = F0,
    velocity_z = F0
}

-- reverb zones
local reverb_zones = {} -- { { x, y, z, radius, decay, density } }

-- doppler effect settings
local doppler = {
    enabled = true,
    factor = F1,
    speed_of_sound = 343.3 -- meters per second
}

local DEFAULT_POOL_SIZE = 8
local SPATIAL_ROLLOFF = F1
local SPATIAL_REF_DISTANCE = F1
local SPATIAL_MAX_DISTANCE = 100.0

-- pre-allocated default options to avoid table allocation
local default_sfx_options = {
    vol = F1,
    pitch = F1,
    vol_var = F0,
    pitch_var = F0,
    x = nil,
    y = nil,
    z = nil,
    vx = F0,
    vy = F0,
    vz = F0,
    lowpass = nil,
    highpass = nil,
    bus = nil
}

local default_music_options = {
    vol = F1,
    loop = true,
    fade_in = F0,
    lowpass = nil,
    highpass = nil,
    bus = nil
}

-- ============================================================================
-- private helpers
-- ============================================================================

--- calculate distance between two 3d points
local function distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return sqrt(dx * dx + dy * dy + dz * dz)
end

--- calculate spatial attenuation based on distance
local function calculate_spatial_volume(x, y, z)
    local dist = distance_3d(listener.x, listener.y, listener.z, x, y, z)

    if dist <= SPATIAL_REF_DISTANCE then
        return F1
    elseif dist >= SPATIAL_MAX_DISTANCE then
        return F0
    else
        -- inverse distance attenuation
        local attenuation = SPATIAL_REF_DISTANCE /
            (SPATIAL_REF_DISTANCE + SPATIAL_ROLLOFF * (dist - SPATIAL_REF_DISTANCE))
        return max(F0, min(F1, attenuation))
    end
end

--- calculate doppler pitch shift
local function calculate_doppler_pitch(source_x, source_y, source_z,
                                       source_vx, source_vy, source_vz)
    if not doppler.enabled then return F1 end

    -- vector from listener to source
    local dx = source_x - listener.x
    local dy = source_y - listener.y
    local dz = source_z - listener.z
    local dist = sqrt(dx * dx + dy * dy + dz * dz)

    if dist < F0001 then return F1 end

    -- normalize direction
    dx, dy, dz = dx / dist, dy / dist, dz / dist

    -- relative velocity along the line connecting listener and source
    local source_vel = source_vx * dx + source_vy * dy + source_vz * dz
    local listener_vel = listener.velocity_x * dx + listener.velocity_y * dy + listener.velocity_z * dz
    local relative_vel = source_vel - listener_vel

    -- doppler: pitch = (speed_of_sound - listener_vel) / (speed_of_sound - source_vel)
    local c = doppler.speed_of_sound
    local pitch = (c + listener_vel) / (c + source_vel)

    -- apply doppler factor and clamp
    pitch = F1 + (pitch - F1) * doppler.factor
    return max(F05, min(F2, pitch))
end

--- check if a position is inside any reverb zone and return reverb parameters
local function get_reverb_params(x, y, z)
    for i = 1, #reverb_zones do
        local zone = reverb_zones[i]
        local dist = distance_3d(x, y, z, zone.x, zone.y, zone.z)
        if dist <= zone.radius then
            -- calculate blend factor based on distance
            local blend = F1 - (dist / zone.radius)
            return {
                decay = zone.decay,
                density = zone.density,
                blend = blend
            }
        end
    end
    return nil
end

--- apply lowpass filter to a source
local function apply_lowpass(source, cutoff, resonance)
    if source.setEffect then
        local effect = {
            type = "lowpass",
            volume = F1,
            highgain = F1,
            lowgain = cutoff or F1
        }
        source:setEffect("lowpass", effect)
    end
end

--- apply highpass filter to a source
local function apply_highpass(source, cutoff, resonance)
    if source.setEffect then
        local effect = {
            type = "highpass",
            volume = F1,
            highgain = cutoff or F1,
            lowgain = F1
        }
        source:setEffect("highpass", effect)
    end
end

--- apply reverb effect to a source
local function apply_reverb(source, params)
    if source.setEffect and params then
        local effect = {
            type = "reverb",
            gain = params.blend or F05,
            decaytime = params.decay or 1.5,
            density = params.density or F1
        }
        source:setEffect("reverb", effect)
    end
end

--- get a free source from sfx pool, or create one
local function get_free_source(name)
    local sfx_def = sfx[name]
    if not sfx_def then return nil end

    -- check active pool for finished sources with this name
    local pool_count = 0
    for i = #active_pool, 1, -1 do
        local entry = active_pool[i]
        if entry.name == name then
            if not entry.source:isPlaying() then
                -- reuse this source
                return table.remove(active_pool, i).source
            else
                pool_count = pool_count + 1
            end
        end
    end

    -- if pool is full, don't play
    if pool_count >= sfx_def.max_pool then
        return nil
    end

    -- create a new source if pool isn't full
    local new_source = love.audio.newSource(sfx_def.sound_data, "static")
    return new_source
end

--- get effective volume for a bus (recursive through parent buses)
local function get_bus_volume(bus_name)
    local bus = buses[bus_name]
    if not bus then return F1 end

    local vol = bus.volume
    if bus.parent then
        vol = vol * get_bus_volume(bus.parent)
    end
    return vol
end

--- updates a single source's volume based on groups and buses
local function update_source_volume(source, type, individual_vol, bus_name)
    local g_vol = groups.master
    local t_vol = (type == 'music') and groups.music or groups.sfx
    local b_vol = bus_name and get_bus_volume(bus_name) or F1
    local final_vol = g_vol * t_vol * b_vol * (individual_vol or F1)

    if music_fade and type == 'music' and source == current_music then
        final_vol = final_vol * music_fade.current
    end

    source:setVolume(final_vol)
end

-- ============================================================================
-- public api
-- ============================================================================

--- load a sound effect (static, pooled)
--- @param name string asset name (e.g., 'jump')
--- @param path_or_data string|SoundData file path or existing SoundData
--- @param max_pool number (optional) max concurrent plays
function audio.load_sfx(name, path_or_data, max_pool)
    local sound_data

    if type(path_or_data) == "string" then
        -- file path
        sound_data = love.sound.newSoundData(path_or_data)
    else
        -- assume SoundData
        sound_data = path_or_data
    end

    -- verify that we have valid SoundData
    if sound_data and sound_data:typeOf("SoundData") then
        sfx[name] = {
            sound_data = sound_data,
            max_pool = max_pool or DEFAULT_POOL_SIZE
        }
    else
        print("audio error: failed to load sfx: " .. name)
    end
end

--- load a music track (streamed)
--- @param name string asset name (e.g., 'level1')
--- @param path string file path (e.g., 'music/level1.ogg')
function audio.load_music(name, path)
    local source = love.audio.newSource(path, "stream")
    if source then
        music[name] = {
            source = source,
            volume = F1,
            bus = nil
        }
    else
        print("audio error: failed to load music: " .. name)
    end
end

--- play a sound effect
--- @param name string asset name
--- @param options table (optional) { vol=1, pitch=1, pitch_var=0, vol_var=0, x=nil, y=nil, z=nil, vx=0, vy=0, vz=0, lowpass=nil, highpass=nil, bus=nil }
--- @return boolean true if played, false if pool full or not loaded
function audio.play_sfx(name, options)
    local sfx_def = sfx[name]
    if not sfx_def then return false end

    local source = get_free_source(name)
    if not source then return false end -- full pool, go eating and wait for 30

    -- use default options if none provided
    if not options then
        options = default_sfx_options
    end

    local vol = options.vol or F1
    local pitch = options.pitch or F1

    -- apply variation
    if options.vol_var and options.vol_var > F0 then
        vol = vol + (random() * F2 - F1) * options.vol_var
    end
    if options.pitch_var and options.pitch_var > F0 then
        pitch = pitch + (random() * F2 - F1) * options.pitch_var
    end

    -- spatial audio
    if options.x and options.y and options.z then
        local spatial_vol = calculate_spatial_volume(options.x, options.y, options.z)
        vol = vol * spatial_vol

        -- doppler effect
        local vx = options.vx or F0
        local vy = options.vy or F0
        local vz = options.vz or F0
        local doppler_pitch = calculate_doppler_pitch(options.x, options.y, options.z, vx, vy, vz)
        pitch = pitch * doppler_pitch

        -- set 3d position
        source:setPosition(options.x, options.y, options.z)
        source:setVelocity(vx, vy, vz)

        -- check for reverb zones
        local reverb = get_reverb_params(options.x, options.y, options.z)
        if reverb then
            apply_reverb(source, reverb)
        end
    end

    -- apply filters
    if options.lowpass then
        apply_lowpass(source, options.lowpass, options.lowpass_resonance)
    end
    if options.highpass then
        apply_highpass(source, options.highpass, options.highpass_resonance)
    end

    source:setPitch(pitch)
    update_source_volume(source, 'sfx', vol, options.bus)
    source:setLooping(false)
    source:play()

    -- add to active pool
    table.insert(active_pool, {
        source = source,
        name = name,
        options = options,
        bus = options.bus,
        volume = vol
    })

    return true
end

--- check if any instance of an sfx is currently playing
--- @param name string asset name
--- @return boolean true if any instance is playing
function audio.is_playing_sfx(name)
    for i = 1, #active_pool do
        local entry = active_pool[i]
        if entry.name == name and entry.source:isPlaying() then
            return true
        end
    end
    return false
end

--- stop all instances of an sfx
--- @param name string asset name
function audio.stop_sfx(name)
    for i = #active_pool, 1, -1 do
        local entry = active_pool[i]
        if entry.name == name then
            entry.source:stop()
            table.remove(active_pool, i)
        end
    end
end

--- stop all currently playing sfx
function audio.stop_all_sfx()
    for i = 1, #active_pool do
        active_pool[i].source:stop()
    end
    active_pool = {}
end

--- play a music track
--- @param name string asset name
--- @param options table (optional) { vol=1, loop=true, fade_in=0, lowpass=nil, highpass=nil, bus=nil }
function audio.play_music(name, options)
    local music_def = music[name]
    if not music_def then return end

    -- use default options if none provided
    if not options then
        options = default_music_options
    end

    local vol = options.vol or F1
    local loop = options.loop == nil and true or options.loop
    local fade_in = options.fade_in or F0

    -- stop old music if it's different
    if current_music and current_music_name ~= name then
        current_music:stop()
    end

    current_music = music_def.source
    current_music_name = name
    current_music_bus = options.bus
    music_def.volume = vol
    music_def.bus = options.bus

    current_music:setLooping(loop)
    current_music:seek(0)

    -- apply filters
    if options.lowpass then
        apply_lowpass(current_music, options.lowpass, options.lowpass_resonance)
    end
    if options.highpass then
        apply_highpass(current_music, options.highpass, options.highpass_resonance)
    end

    if fade_in > F0 then
        music_fade = { target = F1, time = fade_in, current = F0, on_complete = nil }
        update_source_volume(current_music, 'music', vol, options.bus)
    else
        music_fade = nil
        update_source_volume(current_music, 'music', vol, options.bus)
    end

    current_music:play()
end

--- check if music is currently playing
--- @param name string (optional) specific track name, or nil to check any music
--- @return boolean true if playing
function audio.is_playing_music(name)
    if not current_music then return false end
    if name and current_music_name ~= name then return false end
    return current_music:isPlaying()
end

--- pause the currently playing music
function audio.pause_music()
    if current_music then
        current_music:pause()
    end
end

--- resume the currently paused music
function audio.resume_music()
    if current_music then
        current_music:play()
    end
end

--- set music pitch
--- @param pitch number pitch multiplier
function audio.set_music_pitch(pitch)
    if current_music then
        current_music:setPitch(pitch)
    end
end

--- stop the currently playing music
--- @param options table (optional) { fade_out=0 }
function audio.stop_music(options)
    if not current_music then return end

    options = options or {}
    local fade_out = options.fade_out or F0

    if fade_out > F0 then
        music_fade = {
            target = F0,
            time = fade_out,
            current = F1,
            on_complete = function()
                current_music:stop()
                current_music = nil
                current_music_name = nil
                current_music_bus = nil
                music_fade = nil
            end
        }
    else
        current_music:stop()
        current_music = nil
        current_music_name = nil
        current_music_bus = nil
        music_fade = nil
    end
end

--- set volume for a group
--- @param group string 'master', 'music', or 'sfx'
--- @param vol number 0.0 to 1.0
function audio.set_volume(group, vol)
    vol = max(F0, min(F1, vol))
    if groups[group] == nil then return end

    groups[group] = vol

    -- update all playing sources
    if current_music and current_music_name then
        local music_def = music[current_music_name]
        if music_def then
            update_source_volume(current_music, 'music', music_def.volume, music_def.bus)
        end
    end
    for i = 1, #active_pool do
        local entry = active_pool[i]
        update_source_volume(entry.source, 'sfx', entry.volume, entry.bus)
    end
end

--- get volume for a group
--- @param group string 'master', 'music', or 'sfx'
--- @return number volume (0.0 to 1.0)
function audio.get_volume(group)
    return groups[group] or F1
end

--- create or update an audio bus
--- @param name string bus name
--- @param volume number 0.0 to 1.0
--- @param parent string (optional) parent bus name
function audio.create_bus(name, volume, parent)
    buses[name] = {
        volume = volume or F1,
        parent = parent,
        effects = {}
    }
end

--- set bus volume
--- @param name string bus name
--- @param volume number 0.0 to 1.0
function audio.set_bus_volume(name, volume)
    if not buses[name] then return end
    buses[name].volume = max(F0, min(F1, volume))

    -- update all sources using this bus
    if current_music and current_music_bus == name then
        local music_def = music[current_music_name]
        if music_def then
            update_source_volume(current_music, 'music', music_def.volume, music_def.bus)
        end
    end
    for i = 1, #active_pool do
        local entry = active_pool[i]
        if entry.bus == name then
            update_source_volume(entry.source, 'sfx', entry.volume, entry.bus)
        end
    end
end

--- get bus volume
--- @param name string bus name
--- @return number effective volume (0.0 to 1.0) including parent buses
function audio.get_bus_volume(name)
    return get_bus_volume(name)
end

--- set listener position and orientation for 3d audio
--- @param x number x position
--- @param y number y position
--- @param z number z position
--- @param forward_x number (optional) forward vector x
--- @param forward_y number (optional) forward vector y
--- @param forward_z number (optional) forward vector z
--- @param up_x number (optional) up vector x
--- @param up_y number (optional) up vector y
--- @param up_z number (optional) up vector z
function audio.set_listener(x, y, z, forward_x, forward_y, forward_z, up_x, up_y, up_z)
    listener.x = x or listener.x
    listener.y = y or listener.y
    listener.z = z or listener.z
    listener.forward_x = forward_x or listener.forward_x
    listener.forward_y = forward_y or listener.forward_y
    listener.forward_z = forward_z or listener.forward_z
    listener.up_x = up_x or listener.up_x
    listener.up_y = up_y or listener.up_y
    listener.up_z = up_z or listener.up_z
end

--- set listener velocity for doppler effect
--- @param vx number velocity x
--- @param vy number velocity y
--- @param vz number velocity z
function audio.set_listener_velocity(vx, vy, vz)
    listener.velocity_x = vx or F0
    listener.velocity_y = vy or F0
    listener.velocity_z = vz or F0
end

--- create a reverb zone
--- @param x number center x
--- @param y number center y
--- @param z number center z
--- @param radius number zone radius
--- @param decay number reverb decay time
--- @param density number reverb density
function audio.create_reverb_zone(x, y, z, radius, decay, density)
    table.insert(reverb_zones, {
        x = x,
        y = y,
        z = z,
        radius = radius,
        decay = decay or 1.5,
        density = density or F1
    })
end

--- clear all reverb zones
function audio.clear_reverb_zones()
    reverb_zones = {}
end

--- set doppler effect parameters
--- @param enabled boolean enable/disable doppler
--- @param factor number doppler factor (0-1)
--- @param speed_of_sound number speed of sound in m/s
function audio.set_doppler(enabled, factor, speed_of_sound)
    doppler.enabled = enabled ~= false
    doppler.factor = factor or doppler.factor
    doppler.speed_of_sound = speed_of_sound or doppler.speed_of_sound
end

--- set spatial audio parameters
--- @param rolloff number distance attenuation rolloff
--- @param ref_distance number reference distance for attenuation
--- @param max_distance number maximum hearing distance
function audio.set_spatial_params(rolloff, ref_distance, max_distance)
    SPATIAL_ROLLOFF = rolloff or SPATIAL_ROLLOFF
    SPATIAL_REF_DISTANCE = ref_distance or SPATIAL_REF_DISTANCE
    SPATIAL_MAX_DISTANCE = max_distance or SPATIAL_MAX_DISTANCE
end

--- update fade timers and spatial audio (call in love.update)
--- @param dt number delta time
function audio.update(dt)
    -- update music fade
    if music_fade and current_music then
        local mf = music_fade
        if mf.current < mf.target then
            mf.current = min(mf.target, mf.current + dt / mf.time)
        elseif mf.current > mf.target then
            mf.current = max(mf.target, mf.current - dt / mf.time)
        end

        if current_music_name then
            local music_def = music[current_music_name]
            if music_def then
                update_source_volume(current_music, 'music', music_def.volume, music_def.bus)
            end
        end

        -- check for completion
        if mf.current == mf.target then
            if mf.on_complete then
                mf.on_complete()
            else
                music_fade = nil
            end
        end
    end

    -- clean up finished sources and update spatial audio
    for i = #active_pool, 1, -1 do
        local entry = active_pool[i]
        if not entry.source:isPlaying() then
            table.remove(active_pool, i)
        elseif entry.options.x and entry.options.y and entry.options.z then
            -- recalculate spatial volume
            local vol = entry.options.vol or F1
            local spatial_vol = calculate_spatial_volume(
                entry.options.x, entry.options.y, entry.options.z
            )
            update_source_volume(entry.source, 'sfx', vol * spatial_vol, entry.bus)
        end
    end
end

return audio
