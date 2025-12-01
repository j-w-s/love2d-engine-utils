-- weather-demo.lua
-- dynamic weather system using markov chains, renderer, and particles
-- demonstrates procedural weather generation with visual effects

local renderer = require("renderer")
local particles = require("particles")
local markov = require("markov")

local weather = {
    -- markov chain for weather prediction
    chain = nil,
    
    -- current weather state
    current = "clear",
    previous = "clear",
    
    -- weather transition timing
    state_timer = 0,
    state_duration = 8, -- seconds before next transition
    transition_timer = 0,
    transition_duration = 2, -- seconds to blend between states
    
    -- particle emitters for each weather type
    emitters = {},
    
    -- weather intensities (for blending)
    intensities = {
        clear = 1.0,
        cloudy = 0.0,
        rainy = 0.0,
        stormy = 0.0,
        foggy = 0.0,
        snowy = 0.0
    },
    
    -- background colors for each weather
    colors = {
        clear = {0.4, 0.6, 0.9},
        cloudy = {0.5, 0.5, 0.6},
        rainy = {0.3, 0.3, 0.4},
        stormy = {0.15, 0.15, 0.25},
        foggy = {0.6, 0.6, 0.65},
        snowy = {0.7, 0.75, 0.8}
    },
    
    -- ambient lighting
    ambient_color = {0.4, 0.6, 0.9},
    
    -- wind simulation
    wind_x = 0,
    wind_y = 0,
    wind_target_x = 0,
    wind_target_y = 0,
    
    -- thunder/lightning
    lightning_timer = 0,
    lightning_flash = 0,
    
    -- statistics
    total_transitions = 0,
    history = {},
    
    -- visual effects
    cloud_offset = 0,
    rain_intensity = 0,
    
    -- time of day (for visual variety)
    time = 12, -- 0-24 hours
}

-- weather state definitions
local weather_states = {
    "clear",
    "cloudy", 
    "rainy",
    "stormy",
    "foggy",
    "snowy"
}

-- historical weather data (for training)
local weather_history = {
    -- simulate realistic weather patterns
    "clear", "clear", "clear", "clear", "cloudy",
    "cloudy", "rainy", "rainy", "cloudy", "clear",
    "clear", "clear", "cloudy", "rainy", "rainy",
    "stormy", "rainy", "cloudy", "cloudy", "clear",
    "clear", "clear", "clear", "foggy", "foggy",
    "cloudy", "rainy", "rainy", "rainy", "cloudy",
    "clear", "clear", "cloudy", "cloudy", "snowy",
    "snowy", "cloudy", "clear", "clear", "clear",
    "cloudy", "rainy", "stormy", "rainy", "cloudy",
    "clear", "clear", "clear", "clear", "cloudy"
}

function love.load()
    love.window.setTitle("Markov Weather System Demo")
    love.window.setMode(1280, 720, {vsync = false})
    
    -- initialize systems
    renderer.init(320, 180, 4)
    particles.init(5000)
    
    -- create and train markov chain for weather prediction
    weather.chain = markov.train_discrete(weather_history, 1)
    
    -- add some manual biases for more interesting weather
    weather.chain:add_transition("clear", "clear", 15) -- clear tends to stay
    weather.chain:add_transition("clear", "cloudy", 8)
    weather.chain:add_transition("cloudy", "rainy", 10)
    weather.chain:add_transition("rainy", "stormy", 3)
    weather.chain:add_transition("stormy", "rainy", 8)
    weather.chain:add_transition("rainy", "cloudy", 10)
    weather.chain:add_transition("snowy", "snowy", 5)
    weather.chain:add_transition("foggy", "cloudy", 8)
    
    -- create particle emitters for each weather type
    create_weather_emitters()
    
    -- create background layer
    create_background_layer()
    
    -- initialize first state
    weather.current = "clear"
    weather.intensities.clear = 1.0
    update_ambient_color()
    
    print("=== Markov Weather System Demo ===")
    print("Press SPACE: Force weather transition")
    print("Press 1-6: Set specific weather")
    print("Press T: Toggle time of day")
    print("Press H: Show weather history")
    print("Press S: Show statistics")
    print("==============================")
end

function love.update(dt)
    -- update systems
    renderer.update(dt)
    particles.update(dt)
    
    -- update time of day (slow cycle)
    weather.time = weather.time + dt * 0.1
    if weather.time >= 24 then weather.time = 0 end
    
    -- update cloud animation
    weather.cloud_offset = weather.cloud_offset + dt * 10
    
    -- update state timer
    weather.state_timer = weather.state_timer + dt
    
    -- check for weather transition
    if weather.state_timer >= weather.state_duration then
        transition_weather()
    end
    
    -- update transition blending
    if weather.transition_timer > 0 then
        weather.transition_timer = weather.transition_timer - dt
        
        if weather.transition_timer <= 0 then
            weather.transition_timer = 0
            -- transition complete
            weather.intensities[weather.previous] = 0
            weather.intensities[weather.current] = 1.0
        else
            -- blend between states
            local blend = 1.0 - (weather.transition_timer / weather.transition_duration)
            weather.intensities[weather.previous] = 1.0 - blend
            weather.intensities[weather.current] = blend
        end
        
        update_ambient_color()
    end
    
    -- update wind (smooth interpolation)
    weather.wind_x = weather.wind_x + (weather.wind_target_x - weather.wind_x) * dt * 2
    weather.wind_y = weather.wind_y + (weather.wind_target_y - weather.wind_y) * dt * 2
    
    -- update emitter positions and states
    update_weather_emitters(dt)
    
    -- update lightning
    if weather.current == "stormy" or weather.intensities.stormy > 0 then
        weather.lightning_timer = weather.lightning_timer + dt
        
        if weather.lightning_timer >= 3.0 + math.random() * 4.0 then
            trigger_lightning()
            weather.lightning_timer = 0
        end
    end
    
    weather.lightning_flash = math.max(0, weather.lightning_flash - dt * 5)
    
    -- regenerate background if needed
    if weather.transition_timer > 0 or weather.lightning_flash > 0 then
        renderer.mark_static_layer_dirty(0)
    end
end

function love.draw()
    -- layer 0: background (static, regenerated when weather changes)
    -- (drawn by renderer from static layer)
    
    -- layer 1: clouds (particles)
    draw_clouds()
    
    -- layer 2: rain/snow (particles)
    draw_precipitation()
    
    -- layer 3: fog (particles)
    draw_fog()
    
    -- layer 4: ground effects
    draw_ground_effects()
    
    -- present renderer
    renderer.present()
    
    -- draw UI
    draw_ui()
end

function love.keypressed(key)
    if key == "space" then
        transition_weather()
    elseif key == "1" then
        set_weather("clear")
    elseif key == "2" then
        set_weather("cloudy")
    elseif key == "3" then
        set_weather("rainy")
    elseif key == "4" then
        set_weather("stormy")
    elseif key == "5" then
        set_weather("foggy")
    elseif key == "6" then
        set_weather("snowy")
    elseif key == "t" then
        weather.time = (weather.time + 6) % 24
        renderer.mark_static_layer_dirty(0)
    elseif key == "h" then
        print_weather_history()
    elseif key == "s" then
        print_statistics()
    elseif key == "escape" then
        love.event.quit()
    end
end

-- ============================================================================
-- weather system functions
-- ============================================================================

function transition_weather()
    -- predict next weather state using markov chain
    local next_state = weather.chain:predict(weather.current, false)
    
    if next_state and next_state ~= weather.current then
        weather.previous = weather.current
        weather.current = next_state
        weather.state_timer = 0
        weather.transition_timer = weather.transition_duration
        weather.total_transitions = weather.total_transitions + 1
        
        -- add to history
        table.insert(weather.history, {
            from = weather.previous,
            to = weather.current,
            time = love.timer.getTime()
        })
        
        -- keep history limited
        if #weather.history > 20 then
            table.remove(weather.history, 1)
        end
        
        -- update wind based on new weather
        update_wind()
        
        print(string.format("Weather: %s → %s", weather.previous, weather.current))
    end
end

function set_weather(state)
    weather.previous = weather.current
    weather.current = state
    weather.state_timer = 0
    weather.transition_timer = weather.transition_duration
    
    -- reset intensities
    for k in pairs(weather.intensities) do
        weather.intensities[k] = 0
    end
    weather.intensities[weather.current] = 1.0
    
    update_wind()
end

function update_wind()
    if weather.current == "clear" then
        weather.wind_target_x = (math.random() - 0.5) * 10
        weather.wind_target_y = 0
    elseif weather.current == "cloudy" then
        weather.wind_target_x = (math.random() - 0.5) * 20
        weather.wind_target_y = 0
    elseif weather.current == "rainy" then
        weather.wind_target_x = (math.random() - 0.5) * 30
        weather.wind_target_y = 5
    elseif weather.current == "stormy" then
        weather.wind_target_x = (math.random() - 0.5) * 50
        weather.wind_target_y = 10
    elseif weather.current == "foggy" then
        weather.wind_target_x = (math.random() - 0.5) * 5
        weather.wind_target_y = 0
    elseif weather.current == "snowy" then
        weather.wind_target_x = (math.random() - 0.5) * 15
        weather.wind_target_y = 0
    end
end

function update_ambient_color()
    -- blend colors based on current intensities
    local r, g, b = 0, 0, 0
    
    for state, intensity in pairs(weather.intensities) do
        local color = weather.colors[state]
        r = r + color[1] * intensity
        g = g + color[2] * intensity
        b = b + color[3] * intensity
    end
    
    -- apply time of day modulation
    local time_factor = 1.0
    if weather.time < 6 or weather.time > 20 then
        time_factor = 0.3 -- night
    elseif weather.time < 8 or weather.time > 18 then
        time_factor = 0.6 -- dawn/dusk
    end
    
    weather.ambient_color = {r * time_factor, g * time_factor, b * time_factor}
    renderer.set_clear_color(
        weather.ambient_color[1],
        weather.ambient_color[2],
        weather.ambient_color[3]
    )
end

function trigger_lightning()
    weather.lightning_flash = 1.0
end

-- ============================================================================
-- emitter creation and management
-- ============================================================================

function create_weather_emitters()
    -- rain emitter
    weather.emitters.rain = particles.emitter.create(160, -10, {
        rate = 200,
        shape = "rect",
        width = 340,
        height = 0,
        life_min = 2,
        life_max = 3,
        speed_min = 150,
        speed_max = 200,
        direction = math.pi / 2,
        spread = 0.1,
        scale_min = 0.5,
        scale_max = 1.0,
        scale_end_min = 0.5,
        scale_end_max = 1.0,
        color_start = {0.5, 0.5, 1.0, 0.6},
        color_end = {0.5, 0.5, 1.0, 0.6},
        gravity_y = 100,
        group = 1
    })
    weather.emitters.rain.active = false
    
    -- snow emitter
    weather.emitters.snow = particles.emitter.create(160, -10, {
        rate = 100,
        shape = "rect",
        width = 340,
        height = 0,
        life_min = 5,
        life_max = 8,
        speed_min = 20,
        speed_max = 40,
        direction = math.pi / 2,
        spread = 0.3,
        vrot_min = -1,
        vrot_max = 1,
        scale_min = 1.0,
        scale_max = 2.0,
        scale_end_min = 1.0,
        scale_end_max = 2.0,
        color_start = {1.0, 1.0, 1.0, 0.8},
        color_end = {1.0, 1.0, 1.0, 0.8},
        gravity_y = 20,
        group = 2
    })
    weather.emitters.snow.active = false
    
    -- clouds (slow drifting)
    weather.emitters.clouds = particles.emitter.create(160, 30, {
        rate = 5,
        shape = "rect",
        width = 340,
        height = 60,
        life_min = 20,
        life_max = 30,
        speed_min = 5,
        speed_max = 15,
        direction = 0,
        spread = 0.2,
        scale_min = 3.0,
        scale_max = 6.0,
        scale_end_min = 3.0,
        scale_end_max = 6.0,
        color_start = {0.9, 0.9, 0.95, 0.4},
        color_end = {0.8, 0.8, 0.85, 0.4},
        group = 3
    })
    weather.emitters.clouds.active = false
    
    -- fog
    weather.emitters.fog = particles.emitter.create(160, 90, {
        rate = 20,
        shape = "rect",
        width = 340,
        height = 180,
        life_min = 10,
        life_max = 15,
        speed_min = 5,
        speed_max = 10,
        direction = 0,
        spread = 6.28,
        scale_min = 5.0,
        scale_max = 10.0,
        scale_end_min = 5.0,
        scale_end_max = 10.0,
        color_start = {0.8, 0.8, 0.85, 0.3},
        color_end = {0.8, 0.8, 0.85, 0.3},
        group = 4
    })
    weather.emitters.fog.active = false
    
    -- create wind affector for precipitation
    particles.affector.create("turbulence", {
        group_mask = 1, -- rain
        strength = 10,
        frequency = 0.1,
        y = 0
    })
    
    particles.affector.create("turbulence", {
        group_mask = 2, -- snow
        strength = 15,
        frequency = 0.05,
        y = 0
    })
end

function update_weather_emitters(dt)
    -- update rain
    local rain_intensity = weather.intensities.rainy + weather.intensities.stormy * 1.5
    weather.emitters.rain.active = rain_intensity > 0
    if weather.emitters.rain.active then
        weather.emitters.rain.rate = 200 * rain_intensity
        weather.emitters.rain.direction = math.pi / 2 + weather.wind_x * 0.02
    end
    
    -- update snow
    local snow_intensity = weather.intensities.snowy
    weather.emitters.snow.active = snow_intensity > 0
    if weather.emitters.snow.active then
        weather.emitters.snow.rate = 100 * snow_intensity
        weather.emitters.snow.direction = math.pi / 2 + weather.wind_x * 0.01
    end
    
    -- update clouds
    local cloud_intensity = weather.intensities.cloudy + weather.intensities.rainy * 0.8 + weather.intensities.stormy
    weather.emitters.clouds.active = cloud_intensity > 0.3
    if weather.emitters.clouds.active then
        weather.emitters.clouds.rate = 5 * cloud_intensity
        weather.emitters.clouds.speed_min = 5 + math.abs(weather.wind_x) * 0.3
        weather.emitters.clouds.speed_max = 15 + math.abs(weather.wind_x) * 0.5
    end
    
    -- update fog
    local fog_intensity = weather.intensities.foggy
    weather.emitters.fog.active = fog_intensity > 0
    if weather.emitters.fog.active then
        weather.emitters.fog.rate = 20 * fog_intensity
    end
    
    -- update emitters
    for _, em in pairs(weather.emitters) do
        particles.emitter.update(em, dt)
    end
end

-- ============================================================================
-- drawing functions
-- ============================================================================

function create_background_layer()
    renderer.create_static_layer(0, function()
        -- draw sky gradient
        local color = weather.ambient_color
        local lightning_boost = weather.lightning_flash
        
        love.graphics.setColor(
            color[1] + lightning_boost,
            color[2] + lightning_boost,
            color[3] + lightning_boost,
            1
        )
        love.graphics.rectangle("fill", 0, 0, 320, 120)
        
        -- draw ground
        love.graphics.setColor(0.2, 0.3, 0.2, 1)
        love.graphics.rectangle("fill", 0, 120, 320, 60)
        
        -- draw horizon line
        love.graphics.setColor(0.1, 0.2, 0.1, 1)
        love.graphics.rectangle("fill", 0, 115, 320, 10)
        
        love.graphics.setColor(1, 1, 1, 1)
    end)
end

function draw_clouds()
    local pool = particles.pool
    local flags = pool.flags
    local capacity = particles.capacity()
    
    for i = 1, capacity do
        if flags[i] > 0 and pool.group[i] == 3 then
            renderer.draw_circle(
                1,
                "fill",
                pool.x[i],
                pool.y[i],
                pool.scale[i] * 4,
                {pool.r[i], pool.g[i], pool.b[i], pool.a[i]}
            )
        end
    end
end

function draw_precipitation()
    local pool = particles.pool
    local flags = pool.flags
    local capacity = particles.capacity()
    
    for i = 1, capacity do
        if flags[i] > 0 then
            if pool.group[i] == 1 then -- rain
                -- draw rain as lines
                local vx, vy = pool.vx[i], pool.vy[i]
                local length = math.sqrt(vx * vx + vy * vy) * 0.1
                local angle = math.atan2(vy, vx)
                local x2 = pool.x[i] + math.cos(angle) * length
                local y2 = pool.y[i] + math.sin(angle) * length
                
                renderer.draw_line(
                    2,
                    {pool.x[i], pool.y[i], x2, y2},
                    {pool.r[i], pool.g[i], pool.b[i], pool.a[i]}
                )
            elseif pool.group[i] == 2 then -- snow
                renderer.draw_circle(
                    2,
                    "fill",
                    pool.x[i],
                    pool.y[i],
                    pool.scale[i],
                    {pool.r[i], pool.g[i], pool.b[i], pool.a[i]}
                )
            end
        end
    end
end

function draw_fog()
    local pool = particles.pool
    local flags = pool.flags
    local capacity = particles.capacity()
    
    for i = 1, capacity do
        if flags[i] > 0 and pool.group[i] == 4 then
            renderer.draw_circle(
                3,
                "fill",
                pool.x[i],
                pool.y[i],
                pool.scale[i] * 3,
                {pool.r[i], pool.g[i], pool.b[i], pool.a[i]}
            )
        end
    end
end

function draw_ground_effects()
    -- draw puddles during/after rain
    if weather.intensities.rainy > 0.3 or weather.intensities.stormy > 0.3 then
        for i = 1, 10 do
            local x = (i * 30 + weather.cloud_offset * 0.1) % 320
            renderer.draw_circle(
                4,
                "fill",
                x,
                130 + math.sin(love.timer.getTime() * 2 + i) * 2,
                3 + math.sin(love.timer.getTime() * 3 + i) * 0.5,
                {0.3, 0.4, 0.6, 0.3}
            )
        end
    end
    
    -- draw snow accumulation
    if weather.intensities.snowy > 0.5 then
        for i = 1, 320, 5 do
            renderer.draw_rect(
                4,
                "fill",
                i,
                118,
                3,
                2,
                {0.9, 0.95, 1.0, 0.8}
            )
        end
    end
end

function draw_ui()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Markov Weather System Demo", 10, 10)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 30)
    
    love.graphics.print("Current: " .. weather.current, 10, 60)
    love.graphics.print("Time: " .. string.format("%.1f:00", weather.time), 10, 80)
    love.graphics.print("Next transition: " .. string.format("%.1fs", weather.state_duration - weather.state_timer), 10, 100)
    love.graphics.print("Particles: " .. particles.count(), 10, 120)
    love.graphics.print("Transitions: " .. weather.total_transitions, 10, 140)
    
    -- draw weather intensities
    love.graphics.print("Intensities:", 10, 170)
    local y = 190
    for state, intensity in pairs(weather.intensities) do
        if intensity > 0 then
            love.graphics.print(string.format("%s: %.2f", state, intensity), 10, y)
            y = y + 20
        end
    end
    
    -- draw wind indicator
    love.graphics.print("Wind: " .. string.format("%.1f, %.1f", weather.wind_x, weather.wind_y), 10, y + 10)
    
    -- controls
    love.graphics.print("SPACE: Next | 1-6: Set Weather | T: Time | H: History | S: Stats", 10, 690)
end

-- ============================================================================
-- utility functions
-- ============================================================================

function print_weather_history()
    print("\n=== Weather History ===")
    for i, entry in ipairs(weather.history) do
        print(string.format("%d. %s → %s (%.1fs ago)", 
            i, entry.from, entry.to, love.timer.getTime() - entry.time))
    end
    print("====================\n")
end

function print_statistics()
    print("\n=== Weather Statistics ===")
    print("Total transitions: " .. weather.total_transitions)
    
    -- get chain statistics
    local stats = weather.chain:stats()
    print("Chain states: " .. stats.states)
    print("Chain transitions: " .. stats.transitions)
    print("Total observations: " .. stats.total_observations)
    
    -- get probabilities for current state
    local probs = weather.chain:get_probabilities(weather.current)
    if probs then
        print("\nProbabilities from '" .. weather.current .. "':")
        for state, prob in pairs(probs) do
            print(string.format("  %s: %.2f%%", state, prob * 100))
        end
    end
    
    print("========================\n")
end