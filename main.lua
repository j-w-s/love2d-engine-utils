local renderer = require("renderer")
local input = require("input")
local particles = require("particles")
local lighting = require("lighting")
local camera = require("camera")

local test_state = {
    -- textures
    player_tex = nil,
    tileset_tex = nil,
    particle_tex = nil,
    enemy_tex = nil,

    -- atlases
    tileset_atlas = nil,

    -- animations
    walk_anim = nil,
    spin_anim = nil,

    -- shaders
    wave_shader = nil,
    glow_shader = nil,
    invert_shader = nil,
    blur_shader = nil,
    vignette_shader = nil,
    chromatic_shader = nil,

    -- test state
    player_x = 160,
    player_y = 90,
    player_vel_x = 0,
    player_vel_y = 0,

    particle_emitter = nil,
    enemies = {},

    -- test modes
    current_test = 1,
    test_names = {
        "1: Static Layer + Batching",
        "2: Blend Modes (Additive)",
        "3: Wave Shader Effect",
        "4: Texture Atlas",
        "5: Sprite Animation",
        "6: Camera Shake",
        "7: Camera Lerp",
        "8: Quaternion Rotation",
        "9: All Primitives",
        "A: Multi-Layer Stress",
        "B: Layer Visibility/Opacity",
        "C: Camera Bounds",
        "D: Camera Deadzone",
        "E: Viewport/Scissor",
        "F: Frustum Culling",
        "G: Z-Index Sorting",
        "H: Static Layer Dirty",
        "I: Non-Loop Animation",
        "J: Coordinate Conversion",
        "K: Post-Process: Blur",
        "L: Post-Process: Vignette",
        "M: Post-Process: Multi-Pass",
        "N: Shader Uniform Update",
        "O: Lighting Demo"
    },

    time = 0,
    shake_cooldown = 0,

    -- test-specific state
    layer_flash_timer = 0,
    tilemap_colors = {},
    show_stats = true,

    -- coordinate test
    test_points = {},

    -- post-process state
    blur_amount = 0x1.0p0,         -- 1.0
    vignette_intensity = 0x1.4p-1, -- 0.7
    chromatic_offset = 0x1.0p-2,   -- 0.25

    -- camera instance
    camera = nil,
}

function love.load()
    love.window.setTitle("Enhanced Renderer Test Suite (with Input & Particles)")
    love.window.setMode(1280, 720, { vsync = false })

    -- initialize renderer: 320x180 internal, 4x scale
    renderer.init(320, 180, 4)
    renderer.set_clear_color(0x1.99999ap-5, 0x1.99999ap-5, 0x1.99999ap-4) -- 0.05, 0.05, 0.1

    -- initialize other systems
    -- init camera
    test_state.camera = camera.new(0, 0, 1, 0)
    renderer.set_active_camera(test_state.camera)

    -- init particles
    input.refresh()
    particles.init(1000)
    lighting.init(nil, {
        max_lights = 100,
        max_occluders = 100,
        ambient_color = { 0.1, 0.1, 0.2 }
    })

    -- create test textures
    test_state.player_tex = create_player_texture()
    test_state.tileset_tex = create_tileset_texture()
    test_state.particle_tex = create_particle_texture()
    test_state.enemy_tex = create_enemy_texture()

    -- create texture atlas
    test_state.tileset_atlas = renderer.create_atlas(
        "tileset",
        test_state.tileset_tex,
        16, 16
    )

    -- create animations
    test_state.walk_anim = renderer.create_animation(
        {
            { "tileset", 0 },
            { "tileset", 1 },
            { "tileset", 2 },
            { "tileset", 3 }
        },
        0x1.333334p-3, -- 0.15
        true
    )

    test_state.spin_anim = renderer.create_animation(
        {
            { "tileset", 4 },
            { "tileset", 5 },
            { "tileset", 6 },
            { "tileset", 7 }
        },
        0x1.99999ap-3, -- 0.2
        false
    )

    -- create shaders
    test_state.wave_shader = create_wave_shader()
    test_state.glow_shader = create_glow_shader()
    test_state.invert_shader = create_invert_shader()
    test_state.blur_shader = create_blur_shader()
    test_state.vignette_shader = create_vignette_shader()
    test_state.chromatic_shader = create_chromatic_shader()

    -- create static layer (tilemap background)
    create_tilemap_layer()

    -- create particle emitter
    test_state.particle_emitter = particles.emitter.create(
        test_state.player_x,
        test_state.player_y,
        {
            rate = 50,
            shape = "rect",
            width = 40,
            height = 40,
            life_min = 1,
            life_max = 3,
            speed_min = 10,
            speed_max = 30,
            direction = 0,
            spread = 0x1.921fb6p1, -- two_pi
            scale_min = 0x1.0p-1,
            scale_max = 0x1.0p0,
            color_start = { 0x1.0p-1, 0x1.333334p-2, 0x1.99999ap-1, 1 },
            color_end = { 0x1.0p0, 0x1.333334p-1, 0x1.0p0, 0 },
            gravity_y = 0
        }
    )

    -- spawn enemies for z-index test
    for i = 1, 10 do
        spawn_enemy()
    end

    -- set batch sizes
    renderer.set_batch_size(test_state.particle_tex, 200)
    renderer.set_default_batch_size(1000)

    -- initialize test points for coordinate conversion
    for i = 1, 5 do
        table.insert(test_state.test_points, {
            x = math.random(50, 270),
            y = math.random(30, 150)
        })
    end

    print("=== Enhanced Renderer Test Suite ===")
    print("Press 1-9, A-N to switch test modes")
    print("Arrow keys/WASD/Gamepad: move player")
    print("Space: trigger camera shake")
    print("Q/E: camera zoom")
    print("W/S: layer 1 opacity (in test B)")
    print("R: reset camera")
    print("T: regenerate tilemap")
    print("V: toggle layer 1 visibility")
    print("Tab: toggle stats display")
    print("P: pause/play non-loop animation")
    print("+/-: adjust post-process intensity")
    print("O: Lighting Demo")
    print("===========================")
end

function love.update(dt)
    test_state.time = test_state.time + dt
    test_state.shake_cooldown = math.max(0, test_state.shake_cooldown - dt)
    test_state.layer_flash_timer = test_state.layer_flash_timer + dt

    -- update systems
    input.update(dt)
    particles.update(dt)
    renderer.update(dt)
    renderer.update_animations(dt)
    lighting.update() -- no-op but good practice

    -- update lighting demo
    if test_state.current_test == 24 then
        update_lighting_demo(dt)
    end

    -- update player movement (using input.lua)
    local move_speed = 120
    local move_x, move_y = input.axis()

    if move_x ~= 0 or move_y ~= 0 then
        test_state.player_vel_x = move_x * move_speed
        test_state.player_vel_y = move_y * move_speed
    else
        -- friction
        test_state.player_vel_x = test_state.player_vel_x * 0x1.b33334p-1 -- 0.85
        test_state.player_vel_y = test_state.player_vel_y * 0x1.b33334p-1
    end

    test_state.player_x = test_state.player_x + test_state.player_vel_x * dt
    test_state.player_y = test_state.player_y + test_state.player_vel_y * dt

    -- wrap around (unless camera bounds test)
    if test_state.current_test ~= 12 then
        if test_state.player_x < 0 then test_state.player_x = 320 end
        if test_state.player_x > 320 then test_state.player_x = 0 end
        if test_state.player_y < 0 then test_state.player_y = 180 end
        if test_state.player_y > 180 then test_state.player_y = 0 end
    end

    -- update camera based on test mode
    if test_state.current_test == 7 then
        test_state.camera:set_target(test_state.player_x, test_state.player_y)
    elseif test_state.current_test == 13 then
        test_state.camera:set_target(test_state.player_x, test_state.player_y)
    else
        test_state.camera:set_position(test_state.player_x, test_state.player_y)
    end

    -- update camera
    if test_state.camera then
        test_state.camera:update(dt)
    end

    -- update particle emitter position
    test_state.particle_emitter.x = test_state.player_x
    test_state.particle_emitter.y = test_state.player_y

    -- update enemies (circular motion)
    for _, e in ipairs(test_state.enemies) do
        e.angle = e.angle + e.speed * dt
        e.x = test_state.player_x + math.cos(e.angle) * e.dist
        e.y = test_state.player_y + math.sin(e.angle) * e.dist
    end

    -- quaternion rotation test
    if test_state.current_test == 8 then
        -- renderer.camera_rotate_quat(0, 0, 1, dt * 0x1.0p-1) -- Deprecated
        test_state.camera:set_rotation(test_state.camera:get_rotation() + dt * 0x1.0p-1)
    end

    -- update shader time uniforms
    if test_state.wave_shader then
        test_state.wave_shader:send("time", test_state.time)
    end

    -- update post-process uniforms dynamically for test N
    if test_state.current_test == 23 then
        local pulse = (math.sin(test_state.time * 2) + 1) * 0x1.0p-1
        renderer.update_post_process_uniforms(1, {
            offset = test_state.chromatic_offset * pulse
        })
    end
end

function love.draw()
    -- configure test mode
    configure_test_mode()

    -- LAYER 0: background static tilemap (already cached)

    -- LAYER 1: particles
    local pool = particles.pool
    local flags = pool.flags
    local capacity = particles.capacity()

    for i = 1, capacity do
        if flags[i] > 0 then
            renderer.draw_sprite(
                1,
                test_state.particle_tex,
                pool.x[i],
                pool.y[i],
                nil,
                {
                    r = pool.rot[i],
                    sx = pool.scale[i],
                    sy = pool.scale[i],
                    ox = 4,
                    oy = 4,
                    color = { pool.r[i], pool.g[i], pool.b[i], pool.a[i] },
                    z = pool.life[i]
                }
            )
        end
    end

    -- LAYER 2: player
    if test_state.current_test == 4 then
        renderer.draw_atlas_sprite(
            2,
            "tileset",
            math.floor(test_state.time * 4) % 16,
            test_state.player_x,
            test_state.player_y,
            { ox = 8, oy = 8 }
        )
    elseif test_state.current_test == 5 then
        renderer.draw_animated_sprite(
            2,
            test_state.walk_anim,
            test_state.player_x,
            test_state.player_y,
            { ox = 8, oy = 8 }
        )
    elseif test_state.current_test == 18 then
        renderer.draw_animated_sprite(
            2,
            test_state.spin_anim,
            test_state.player_x,
            test_state.player_y,
            { ox = 8, oy = 8 }
        )
    else
        renderer.draw_sprite(
            2,
            test_state.player_tex,
            test_state.player_x,
            test_state.player_y,
            nil,
            { ox = 8, oy = 8 }
        )
    end

    -- LAYER 3: primitives test
    if test_state.current_test == 9 then
        draw_primitives_test()
    end

    -- LAYER 3: enemies (z-index test)
    if test_state.current_test == 16 then
        for _, e in ipairs(test_state.enemies) do
            renderer.draw_sprite(
                3,
                test_state.enemy_tex,
                e.x, e.y,
                nil,
                {
                    ox = 8,
                    oy = 8,
                    color = { e.r, e.g, e.b, 0x1.99999ap-1 },
                    z = e.z
                }
            )
        end
    end

    -- LAYER 4-9: stress test
    if test_state.current_test == 10 then
        draw_stress_test()
    end

    -- coordinate conversion test
    if test_state.current_test == 19 then
        draw_coordinate_test()
    end

    -- submit lighting data
    if test_state.current_test == 24 then
        local l, o, lc, oc = lighting.get_gpu_data()
        local ambient = lighting.get_ambient()
        renderer.submit_lighting(l, lc, o, oc, ambient)
    end

    -- present all layers
    renderer.present()

    -- draw UI (not rendered through renderer)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Test: " .. test_state.test_names[test_state.current_test], 10, 10)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 30)

    if test_state.show_stats then
        local stats = renderer.get_stats()
        love.graphics.print("Draw Calls: " .. stats.draw_calls, 10, 50)
        love.graphics.print("Sprites: " .. stats.sprites_drawn, 10, 70)
        love.graphics.print("Primitives: " .. stats.primitives_drawn, 10, 90)
        love.graphics.print("Batches: " .. stats.batches_used, 10, 110)
        love.graphics.print("Triangles: " .. stats.triangles, 10, 130)
    end

    love.graphics.print("Particles: " .. particles.count(), 10, 150)
    love.graphics.print("Player: " .. math.floor(test_state.player_x) .. ", " .. math.floor(test_state.player_y), 10, 170)
    local cam_x, cam_y = test_state.camera:get_position()
    love.graphics.print("Camera: " .. math.floor(cam_x) .. ", " .. math.floor(cam_y), 10, 190)
    love.graphics.print("Zoom: " .. string.format("%.2f", test_state.camera:get_zoom()), 10, 210)

    -- layer info for visibility/opacity test
    if test_state.current_test == 11 then
        local opacity = renderer.get_layer_opacity(1)
        local visible = renderer.get_layer_visible(1)
        love.graphics.print("Layer 1 Opacity: " .. string.format("%.2f", opacity), 10, 230)
        love.graphics.print("Layer 1 Visible: " .. tostring(visible), 10, 250)
    end

    -- post-process info
    if test_state.current_test >= 20 and test_state.current_test <= 23 then
        love.graphics.print("Post-Process Active", 10, 230)
        if test_state.current_test == 20 then
            love.graphics.print("Blur Amount: " .. string.format("%.2f", test_state.blur_amount), 10, 250)
        elseif test_state.current_test == 21 then
            love.graphics.print("Vignette: " .. string.format("%.2f", test_state.vignette_intensity), 10, 250)
        elseif test_state.current_test == 22 then
            love.graphics.print("Multi-Pass: Blur + Vignette", 10, 250)
        elseif test_state.current_test == 23 then
            love.graphics.print("Chromatic Aberration (pulsing)", 10, 250)
            love.graphics.print("Offset: " .. string.format("%.3f", test_state.chromatic_offset), 10, 270)
        end
        love.graphics.print("+/- to adjust intensity", 10, 290)
    end
end

function love.keypressed(key)
    input.keypressed(key)

    -- test mode switching
    if key == "1" then test_state.current_test = 1 end
    if key == "2" then test_state.current_test = 2 end
    if key == "3" then test_state.current_test = 3 end
    if key == "4" then test_state.current_test = 4 end
    if key == "5" then test_state.current_test = 5 end
    if key == "6" then test_state.current_test = 6 end
    if key == "7" then
        test_state.current_test = 7
        test_state.camera:set_lerp_speed(3)
    end
    if key == "8" then
        test_state.current_test = 8
    end
    if key == "9" then test_state.current_test = 9 end
    if key == "a" then test_state.current_test = 10 end
    if key == "b" then test_state.current_test = 11 end
    if key == "c" then
        test_state.current_test = 12
        test_state.camera:set_bounds(0, 0, 320, 180)
    end
    if key == "d" then
        test_state.current_test = 13
        test_state.camera:set_deadzone(80, 45, 160, 90)
        test_state.camera:set_lerp_speed(5)
    end
    if key == "e" then
        test_state.current_test = 14
        renderer.set_viewport(40, 20, 240, 140)
    end
    if key == "f" then test_state.current_test = 15 end
    if key == "g" then test_state.current_test = 16 end
    if key == "h" then
        if test_state.current_test == 17 then
            test_state.show_stats = not test_state.show_stats
        else
            test_state.current_test = 17
        end
    end
    if key == "i" then
        test_state.current_test = 18
        renderer.reset_animation(test_state.spin_anim)
        renderer.play_animation(test_state.spin_anim)
    end
    if key == "j" then test_state.current_test = 19 end

    -- post-process tests
    if key == "k" then test_state.current_test = 20 end
    if key == "l" then test_state.current_test = 21 end
    if key == "m" then test_state.current_test = 22 end
    if key == "n" then test_state.current_test = 23 end
    if key == "o" then
        test_state.current_test = 24
        setup_lighting_demo()
    end

    -- camera shake
    if key == "space" and test_state.shake_cooldown <= 0 then
        test_state.camera:shake(8, 0x1.333334p-2) -- 0.3
        test_state.shake_cooldown = 0x1.0p-1      -- 0.5
    end

    -- layer opacity (test B only)
    if test_state.current_test == 11 then
        if key == "w" then
            local opacity = renderer.get_layer_opacity(1)
            renderer.set_layer_opacity(1, math.min(0x1.0p0, opacity + 0x1.99999ap-4))
        end
        if key == "s" then
            local opacity = renderer.get_layer_opacity(1)
            renderer.set_layer_opacity(1, math.max(0, opacity - 0x1.99999ap-4))
        end
    end

    -- toggle layer visibility
    if key == "v" then
        local visible = renderer.get_layer_visible(1)
        renderer.set_layer_visible(1, not visible)
    end

    -- toggle stats
    if key == "tab" then
        test_state.show_stats = not test_state.show_stats
    end

    -- animation control
    if key == "p" then
        if test_state.current_test == 18 then
            renderer.reset_animation(test_state.spin_anim)
            renderer.play_animation(test_state.spin_anim)
        end
    end

    -- post-process intensity adjustment
    if key == "=" or key == "kp+" then
        if test_state.current_test == 20 then
            test_state.blur_amount = math.min(5, test_state.blur_amount + 0x1.0p-1)
        elseif test_state.current_test == 21 then
            test_state.vignette_intensity = math.min(2, test_state.vignette_intensity + 0x1.99999ap-4)
        elseif test_state.current_test == 23 then
            test_state.chromatic_offset = math.min(2, test_state.chromatic_offset + 0x1.47ae14p-4) -- 0.08
        end
    end
    if key == "-" or key == "kp-" then
        if test_state.current_test == 20 then
            test_state.blur_amount = math.max(0, test_state.blur_amount - 0x1.0p-1)
        elseif test_state.current_test == 21 then
            test_state.vignette_intensity = math.max(0, test_state.vignette_intensity - 0x1.99999ap-4)
        elseif test_state.current_test == 23 then
            test_state.chromatic_offset = math.max(0, test_state.chromatic_offset - 0x1.47ae14p-4)
        end
    end

    -- camera controls
    local cam = test_state.camera
    local cam_speed = 100 * love.timer.getDelta()
    if love.keyboard.isDown("left") then cam:move(-cam_speed, 0) end
    if love.keyboard.isDown("right") then cam:move(cam_speed, 0) end
    if love.keyboard.isDown("up") then cam:move(0, -cam_speed) end
    if love.keyboard.isDown("down") then cam:move(0, cam_speed) end

    -- zoom controls
    if love.keyboard.isDown("q") then cam:set_zoom(cam:get_zoom() * (1 - love.timer.getDelta())) end
    if love.keyboard.isDown("e") then cam:set_zoom(cam:get_zoom() * (1 + love.timer.getDelta())) end

    -- rotation controls
    if love.keyboard.isDown("z") then cam:set_rotation(cam:get_rotation() - love.timer.getDelta()) end
    if love.keyboard.isDown("x") then cam:set_rotation(cam:get_rotation() + love.timer.getDelta()) end

    -- reset camera
    if key == "r" then
        cam:set_position(test_state.player_x, test_state.player_y)
        cam:set_zoom(1)
        cam:set_rotation(0)
        cam:set_lerp_speed(0)
        cam:clear_bounds()
        cam:clear_deadzone()
        renderer.clear_viewport()
        renderer.set_layer_visible(1, true)
        renderer.set_layer_opacity(1, 1)
        renderer.clear_post_process()
    end

    -- regenerate tilemap (dirty flag)
    if key == "t" then
        create_tilemap_layer()
        renderer.mark_static_layer_dirty(0)
    end
end

-- ============================================================================
-- input.lua callbacks
-- ============================================================================
function love.mousepressed(x, y, button, istouch, presses)
    input.mousepressed(x, y, button, istouch, presses)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    input.touchpressed(id, x, y, dx, dy, pressure)
end

function love.gamepadpressed(joystick, button)
    input.gamepadpressed(joystick, button)
end

function love.joystickadded(joystick)
    input.joystickadded(joystick)
end

function love.joystickremoved(joystick)
    input.joystickremoved(joystick)
end

-- ============================================================================
-- helper functions
-- ============================================================================

function configure_test_mode()
    -- reset all effects
    renderer.clear_layer_blend_mode(0)
    renderer.clear_layer_blend_mode(1)
    renderer.clear_layer_blend_mode(2)
    renderer.clear_layer_shader(0)
    renderer.clear_viewport()
    renderer.set_frustum_culling(true)
    renderer.clear_post_process()

    -- reset camera settings
    if test_state.camera then
        test_state.camera:set_lerp_speed(0)
        test_state.camera:set_bounds(nil)
    end

    -- apply test-specific settings
    if test_state.current_test == 2 then
        renderer.set_layer_blend_mode(1, "add")
    elseif test_state.current_test == 3 then
        renderer.set_layer_shader(0, test_state.wave_shader)
    elseif test_state.current_test == 8 then
        -- quaternion mode deprecated, use standard rotation
        -- renderer.set_camera_quaternion_mode(true)
    elseif test_state.current_test == 11 then
        local flash = math.sin(test_state.layer_flash_timer * 3)
        renderer.set_layer_opacity(1, (flash + 1) * 0x1.0p-1)
    elseif test_state.current_test == 14 then
        renderer.set_viewport(40, 20, 240, 140)
    elseif test_state.current_test == 15 then
        renderer.set_frustum_culling(false)
    elseif test_state.current_test == 20 then
        -- blur post-process
        if test_state.blur_shader then
            renderer.add_post_process(test_state.blur_shader, {
                blur_size = test_state.blur_amount,
                resolution = { 320, 180 }
            })
        end
    elseif test_state.current_test == 21 then
        -- vignette post-process
        if test_state.vignette_shader then
            renderer.add_post_process(test_state.vignette_shader, {
                intensity = test_state.vignette_intensity,
                smoothness = 0x1.0p-1
            })
        end
    elseif test_state.current_test == 22 then
        -- multi-pass: blur then vignette
        if test_state.blur_shader then
            renderer.add_post_process(test_state.blur_shader, {
                blur_size = 0x1.0p0,
                resolution = { 320, 180 }
            })
        end
        if test_state.vignette_shader then
            renderer.add_post_process(test_state.vignette_shader, {
                intensity = 0x1.0p-1,
                smoothness = 0x1.0p-1
            })
        end
    elseif test_state.current_test == 23 then
        -- chromatic aberration with dynamic uniform updates
        if test_state.chromatic_shader then
            renderer.add_post_process(test_state.chromatic_shader, {
                offset = test_state.chromatic_offset
            })
        end
    end
end

function create_tilemap_layer()
    test_state.tilemap_colors = {}
    for i = 1, 240 do
        test_state.tilemap_colors[i] = {
            math.random() * 0x1.333334p-2 + 0x1.99999ap-3, -- 0.3, 0.2
            math.random() * 0x1.99999ap-3 + 0x1.99999ap-4, -- 0.2, 0.1
            math.random() * 0x1.99999ap-3 + 0x1.333334p-2  -- 0.2, 0.3
        }
    end

    renderer.create_static_layer(0, function()
        local idx = 1
        for y = 0, 11 do
            for x = 0, 19 do
                local tile_x = x * 16
                local tile_y = y * 16
                local color = test_state.tilemap_colors[idx]

                love.graphics.setColor(color[1], color[2], color[3], 1)
                love.graphics.rectangle("fill", tile_x, tile_y, 16, 16)

                love.graphics.setColor(0x1.99999ap-4, 0x1.99999ap-4, 0x1.333334p-3, 1)
                love.graphics.rectangle("line", tile_x, tile_y, 16, 16)

                idx = idx + 1
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end)
end

function spawn_enemy()
    table.insert(test_state.enemies, {
        x = 0,
        y = 0,
        angle = math.random() * math.pi * 2,
        speed = 0x1.0p-1 + math.random(), -- 0.5
        dist = 30 + math.random() * 50,
        r = math.random(),
        g = math.random(),
        b = math.random(),
        z = math.random() * 100
    })
end

function draw_primitives_test()
    renderer.draw_rect(3, "fill", 50, 50, 30, 20, { 1, 0, 0, 0x1.99999ap-1 })
    renderer.draw_rect(3, "line", 50, 80, 30, 20, { 1, 1, 0, 1 })

    renderer.draw_circle(3, "fill", 150, 60, 15, { 0, 1, 0, 0x1.99999ap-1 }, 16)
    renderer.draw_circle(3, "line", 150, 100, 15, { 0, 1, 1, 1 }, 32)

    renderer.draw_line(3, { 200, 50, 250, 70, 230, 100, 270, 110 }, { 1, 0, 1, 1 })

    renderer.draw_polygon(3, "fill", { 100, 120, 110, 140, 90, 140 }, { 1, 0x1.0p-1, 0, 0x1.666666p-1 })
    renderer.draw_polygon(3, "line", { 120, 120, 135, 135, 120, 145, 105, 135 }, { 0, 1, 0x1.0p-1, 1 })

    renderer.draw_arc(3, "fill", 200, 140, 20, 0, math.pi, { 0x1.0p-1, 0x1.0p-1, 1, 0x1.99999ap-1 }, 16)
    renderer.draw_arc(3, "line", 250, 140, 20, math.pi, math.pi * 2, { 1, 1, 0x1.0p-1, 1 }, 24)

    local t = test_state.time
    local x = 160 + math.cos(t * 2) * 40
    local y = 90 + math.sin(t * 2) * 30
    renderer.draw_circle(3, "fill", x, y, 10, { 1, 1, 0, 0x1.333334p-1 })
end

function draw_stress_test()
    for layer = 4, 9 do
        for i = 1, 30 do
            local angle = (i / 30) * math.pi * 2 + test_state.time * 0x1.0p-1
            local dist = 40 + layer * 12
            local x = test_state.player_x + math.cos(angle) * dist
            local y = test_state.player_y + math.sin(angle) * dist

            renderer.draw_sprite(
                layer,
                test_state.particle_tex,
                x, y,
                nil,
                {
                    r = angle,
                    sx = 0x1.0p-1 + layer * 0x1.99999ap-4,
                    sy = 0x1.0p-1 + layer * 0x1.99999ap-4,
                    ox = 4,
                    oy = 4,
                    color = {
                        (layer % 3) / 3,
                        ((layer + 1) % 3) / 3,
                        ((layer + 2) % 3) / 3,
                        0x1.333334p-1
                    }
                }
            )
        end
    end
end

function draw_coordinate_test()
    for i, pt in ipairs(test_state.test_points) do
        renderer.draw_circle(3, "fill", pt.x, pt.y, 3, { 1, 1, 0, 1 })

        local sx, sy = renderer.world_to_screen(pt.x, pt.y)
        local wx, wy = renderer.screen_to_world(sx, sy)

        renderer.draw_line(3, { pt.x, pt.y, wx, wy }, { 0, 1, 0, 0x1.0p-1 })
        renderer.draw_rect(3, "line", wx - 2, wy - 2, 4, 4, { 1, 0, 0, 1 })
    end
end

-- ============================================================================
-- texture generation
-- ============================================================================

function create_player_texture()
    local canvas = love.graphics.newCanvas(16, 16)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    love.graphics.setColor(0x1.99999ap-3, 0x1.333334p-1, 1, 1)
    love.graphics.circle("fill", 8, 8, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 6, 6, 2)
    love.graphics.circle("fill", 10, 6, 2)
    love.graphics.setColor(1, 0x1.0p-1, 0x1.0p-1, 1)
    love.graphics.arc("fill", 8, 8, 4, 0, math.pi)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

-- ============================================================================
-- lighting demo
-- ============================================================================

local demo_light_id = nil

function setup_lighting_demo()
    lighting.clear()
    lighting.set_ambient(0.1, 0.1, 0.2)

    -- add player light
    demo_light_id = lighting.add_light(test_state.player_x, test_state.player_y, 1, 0.8, 0.6, 1.0, 150)

    -- add some static lights
    lighting.add_light(50, 50, 1, 0, 0, 1, 100)
    lighting.add_light(270, 50, 0, 1, 0, 1, 100)
    lighting.add_light(50, 130, 0, 0, 1, 1, 100)
    lighting.add_light(270, 130, 1, 1, 0, 1, 100)
end

function update_lighting_demo(dt)
    if demo_light_id then
        lighting.set_light_position(demo_light_id, test_state.player_x, test_state.player_y)
    end
end

function create_tileset_texture()
    local canvas = love.graphics.newCanvas(64, 64)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    for y = 0, 3 do
        for x = 0, 3 do
            local tile_x = x * 16
            local tile_y = y * 16
            local hue = (x + y * 4) / 16

            love.graphics.setColor(hue, 1 - hue, 0x1.0p-1, 1)
            love.graphics.rectangle("fill", tile_x + 2, tile_y + 2, 12, 12)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("line", tile_x + 2, tile_y + 2, 12, 12)
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

function create_particle_texture()
    local canvas = love.graphics.newCanvas(8, 8)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    for r = 4, 0, -1 do
        local alpha = r * 0x1.0p-2
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.circle("fill", 4, 4, r)
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

function create_enemy_texture()
    local canvas = love.graphics.newCanvas(16, 16)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    love.graphics.setColor(1, 0x1.333334p-2, 0x1.333334p-2, 1)
    love.graphics.polygon("fill", 8, 2, 14, 14, 2, 14)
    love.graphics.setColor(0x1.99999ap-1, 0x1.99999ap-1, 0x1.99999ap-1, 1)
    love.graphics.circle("fill", 8, 9, 3)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

-- ============================================================================
-- shader generation
-- ============================================================================

function create_wave_shader()
    local shader_code = [[
uniform float time;
vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec2 offset = vec2(
        sin(tc.y * 10.0 + time * 2.0) * 0.01,
        cos(tc.x * 10.0 + time * 2.0) * 0.01
    );
    vec4 pixel = Texel(texture, tc + offset);
    return pixel * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create wave shader:", result)
        return nil
    end
end

function create_glow_shader()
    local shader_code = [[
vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(texture, tc);
    float brightness = (pixel.r + pixel.g + pixel.b) / 3.0;
    vec3 glow = pixel.rgb * brightness * 1.5;
    return vec4(glow, pixel.a) * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create glow shader:", result)
        return nil
    end
end

function create_invert_shader()
    local shader_code = [[
vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(texture, tc);
    return vec4(1.0 - pixel.rgb, pixel.a) * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create invert shader:", result)
        return nil
    end
end

function create_blur_shader()
    local shader_code = [[
uniform float blur_size;
uniform vec2 resolution;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec4 sum = vec4(0.0);
    vec2 blur = vec2(blur_size) / resolution;

    sum += Texel(texture, tc + vec2(-blur.x, -blur.y)) * 0.0625;
    sum += Texel(texture, tc + vec2(0.0, -blur.y)) * 0.125;
    sum += Texel(texture, tc + vec2(blur.x, -blur.y)) * 0.0625;
    sum += Texel(texture, tc + vec2(-blur.x, 0.0)) * 0.125;
    sum += Texel(texture, tc) * 0.25;
    sum += Texel(texture, tc + vec2(blur.x, 0.0)) * 0.125;
    sum += Texel(texture, tc + vec2(-blur.x, blur.y)) * 0.0625;
    sum += Texel(texture, tc + vec2(0.0, blur.y)) * 0.125;
    sum += Texel(texture, tc + vec2(blur.x, blur.y)) * 0.0625;

    return sum * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create blur shader:", result)
        return nil
    end
end

function create_vignette_shader()
    local shader_code = [[
uniform float intensity;
uniform float smoothness;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(texture, tc);
    vec2 uv = tc - 0.5;
    float dist = length(uv);
    float vignette = smoothstep(0.5, 0.5 - smoothness, dist * intensity);
    return vec4(pixel.rgb * vignette, pixel.a) * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create vignette shader:", result)
        return nil
    end
end

function create_chromatic_shader()
    local shader_code = [[
uniform float offset;

vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    vec2 dir = tc - 0.5;
    float r = Texel(texture, tc + dir * offset * 0.01).r;
    float g = Texel(texture, tc).g;
    float b = Texel(texture, tc - dir * offset * 0.01).b;
    float a = Texel(texture, tc).a;
    return vec4(r, g, b, a) * color;
}
    ]]

    local success, result = pcall(love.graphics.newShader, shader_code)
    if success then
        return result
    else
        print("failed to create chromatic shader:", result)
        return nil
    end
end
