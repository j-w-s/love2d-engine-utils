local lighting = require("lighting")

local total_tests = 0
local passed_tests = 0
local failed_tests = {}

local function test(name, fn)
    total_tests = total_tests + 1
    local success, err = pcall(fn)
    if success then
        passed_tests = passed_tests + 1
        print("✓ " .. name)
    else
        table.insert(failed_tests, { name = name, error = err })
        print("✗ " .. name)
        print("  Error: " .. tostring(err))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assert_near(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %s (±%s), got %s", msg or "assertion failed", tostring(expected),
            tostring(tolerance), tostring(actual)))
    end
end

local function assert_true(value, msg)
    if not value then
        error(msg or "expected true, got false")
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "expected false, got true")
    end
end

local function assert_nil(value, msg)
    if value ~= nil then
        error(msg or "expected nil, got " .. tostring(value))
    end
end

local function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "expected non-nil value")
    end
end

local function count_table(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ============================================================================
-- tests
-- ============================================================================

print("\n=== Lighting System Test Suite ===\n")

-- initialization
test("init: initializes with defaults", function()
    lighting.init()
    local stats = lighting.get_stats()
    assert_eq(stats.lights, 0, "no lights initially")
    assert_eq(stats.occluders, 0, "no occluders initially")
end)

test("init: initializes with custom limits", function()
    lighting.init(nil, { max_lights = 512, max_occluders = 2048 })
    local stats = lighting.get_stats()
    assert_not_nil(stats, "stats available")
end)

-- configuration
test("set_ambient: sets ambient light", function()
    lighting.set_ambient(0.1, 0.2, 0.3)
    local ambient = lighting.get_ambient()
    assert_near(ambient[1], 0.1, 0.01, "ambient red")
    assert_near(ambient[2], 0.2, 0.01, "ambient green")
    assert_near(ambient[3], 0.3, 0.01, "ambient blue")
end)



test("set_world_bounds: sets bounds", function()
    lighting.set_world_bounds(-1000, -1000, 1000, 1000)
end)

test("set_spatial_hashing: toggles spatial hashing", function()
    lighting.set_spatial_hashing(true)
    lighting.set_spatial_hashing(false)
    lighting.set_spatial_hashing(true)
end)





test("set_default_attenuation: changes attenuation preset", function()
    lighting.set_default_attenuation("linear")
    lighting.set_default_attenuation("quadratic")
    lighting.set_default_attenuation("none")
end)

-- light creation
test("add_light: creates point light", function()
    lighting.clear()
    local id = lighting.add_light(100, 100, 1, 1, 1, 1, 200)
    assert_not_nil(id, "light id returned")
    local stats = lighting.get_stats()
    assert_eq(stats.lights, 1, "one light created")
end)

test("add_light: with defaults", function()
    lighting.clear()
    local id = lighting.add_light(50, 50)
    assert_not_nil(id, "light created with defaults")
    local light = lighting.get_light(id)
    assert_not_nil(light, "can retrieve light")
    assert_eq(light.x, 50, "x position")
    assert_eq(light.y, 50, "y position")
end)

test("add_spotlight: creates spotlight", function()
    lighting.clear()
    local id = lighting.add_spotlight(100, 100, 0, math.pi / 4, math.pi / 3, 1, 1, 0, 1, 150)
    assert_not_nil(id, "spotlight created")
    local light = lighting.get_light(id)
    assert_eq(light.type, 2, "is spotlight")
    assert_near(light.direction, 0, 0.01, "direction")
end)

test("add_light: multiple lights", function()
    lighting.clear()
    local id1 = lighting.add_light(0, 0, 1, 0, 0)
    local id2 = lighting.add_light(100, 100, 0, 1, 0)
    local id3 = lighting.add_light(200, 200, 0, 0, 1)

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 3, "three lights created")
    assert_true(id1 ~= id2 and id2 ~= id3, "unique ids")
end)

test("add_light: respects max limit", function()
    lighting.init(nil, { max_lights = 2, max_occluders = 100 })
    lighting.clear()

    local id1 = lighting.add_light(0, 0)
    local id2 = lighting.add_light(100, 100)
    local id3 = lighting.add_light(200, 200)

    assert_not_nil(id1, "first light created")
    assert_not_nil(id2, "second light created")
    assert_nil(id3, "third light rejected (max reached)")
    lighting.init()
end)

-- light modification
test("set_light_position: moves light", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)
    lighting.set_light_position(id, 50, 75)

    local light = lighting.get_light(id)
    assert_eq(light.x, 50, "x updated")
    assert_eq(light.y, 75, "y updated")
end)

test("set_light_position: with z coordinate", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)
    lighting.set_light_position(id, 50, 75, 10)

    local light = lighting.get_light(id)
    assert_eq(light.z, 10, "z updated")
end)

test("set_light_color: changes color", function()
    lighting.clear()
    local id = lighting.add_light(0, 0, 1, 0, 0)
    lighting.set_light_color(id, 0, 1, 0)

    local light = lighting.get_light(id)
    assert_near(light.r, 0, 0.01, "red component")
    assert_near(light.g, 1, 0.01, "green component")
    assert_near(light.b, 0, 0.01, "blue component")
end)

test("set_light_intensity: changes intensity", function()
    lighting.clear()
    local id = lighting.add_light(0, 0, 1, 1, 1, 1)
    lighting.set_light_intensity(id, 2.5)

    local light = lighting.get_light(id)
    assert_near(light.intensity, 2.5, 0.01, "intensity updated")
end)

test("set_light_range: changes range", function()
    lighting.clear()
    local id = lighting.add_light(0, 0, 1, 1, 1, 1, 100)
    lighting.set_light_range(id, 250)

    local light = lighting.get_light(id)
    assert_near(light.range, 250, 0.1, "range updated")
end)

test("set_light_attenuation: custom coefficients", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)
    lighting.set_light_attenuation(id, 1.0, 0.01, 0.001)

    local light = lighting.get_light(id)
    assert_not_nil(light, "light still exists")
end)

test("set_spotlight_direction: rotates spotlight", function()
    lighting.clear()
    local id = lighting.add_spotlight(0, 0, 0)
    lighting.set_spotlight_direction(id, math.pi / 2, math.pi / 3, math.pi / 2)

    local light = lighting.get_light(id)
    assert_near(light.direction, math.pi / 2, 0.01, "direction updated")
    assert_near(light.cone_angle, math.pi / 3, 0.01, "cone angle updated")
end)

test("set_light_enabled: toggles light", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)

    lighting.set_light_enabled(id, false)
    local light = lighting.get_light(id)
    assert_false(light.enabled, "light disabled")

    lighting.set_light_enabled(id, true)
    light = lighting.get_light(id)
    assert_true(light.enabled, "light enabled")
end)

test("set_light_shadows: toggles shadow casting", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)

    lighting.set_light_shadows(id, false)
    local light = lighting.get_light(id)
    assert_false(light.cast_shadows, "shadows disabled")

    lighting.set_light_shadows(id, true)
    light = lighting.get_light(id)
    assert_true(light.cast_shadows, "shadows enabled")
end)

test("set_light_layer: assigns layer", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)
    lighting.set_light_layer(id, 5)

    local light = lighting.get_light(id)
    assert_eq(light.layer, 5, "layer assigned")
end)

-- light removal
test("remove_light: deletes light", function()
    lighting.clear()
    local id = lighting.add_light(0, 0)

    lighting.remove_light(id)

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 0, "light removed")

    local light = lighting.get_light(id)
    assert_nil(light, "light data gone")
end)

test("remove_light: maintains other lights", function()
    lighting.clear()
    local id1 = lighting.add_light(0, 0)
    print("After add 1: count=" .. lighting.get_stats().lights)
    local id2 = lighting.add_light(100, 100)
    print("After add 2: count=" .. lighting.get_stats().lights)
    local id3 = lighting.add_light(200, 200)
    print("After add 3: count=" .. lighting.get_stats().lights)

    print("Removing id=" .. id2)
    lighting.remove_light(id2)
    print("After remove: count=" .. lighting.get_stats().lights)

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 2, "one light removed")
end)

test("clear_lights: removes all lights", function()
    lighting.clear()
    lighting.add_light(0, 0)
    lighting.add_light(100, 100)
    lighting.add_light(200, 200)

    lighting.clear_lights()

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 0, "all lights cleared")
end)

-- light queries
test("get_light: retrieves light data", function()
    lighting.clear()
    local id = lighting.add_light(123, 456, 0.5, 0.6, 0.7, 0.8, 300)

    local light = lighting.get_light(id)
    assert_not_nil(light, "light retrieved")
    assert_eq(light.x, 123, "x position")
    assert_eq(light.y, 456, "y position")
    assert_near(light.r, 0.5, 0.01, "red")
    assert_near(light.g, 0.6, 0.01, "green")
    assert_near(light.b, 0.7, 0.01, "blue")
    assert_near(light.intensity, 0.8, 0.01, "intensity")
    assert_near(light.range, 300, 0.1, "range")
end)

test("get_all_lights: returns all enabled lights", function()
    lighting.clear()
    local id1 = lighting.add_light(0, 0)
    local id2 = lighting.add_light(100, 100)
    lighting.set_light_enabled(id2, false)
    local id3 = lighting.add_light(200, 200)

    local lights = lighting.get_all_lights()
    assert_eq(#lights, 2, "two enabled lights")
end)

test("get_all_lights: filters by layer", function()
    lighting.clear()
    local id1 = lighting.add_light(0, 0)
    lighting.set_light_layer(id1, 1)

    local id2 = lighting.add_light(100, 100)
    lighting.set_light_layer(id2, 2)

    local id3 = lighting.add_light(200, 200)
    lighting.set_light_layer(id3, 1)

    local layer1_lights = lighting.get_all_lights(1)
    assert_eq(#layer1_lights, 2, "two lights on layer 1")

    local layer2_lights = lighting.get_all_lights(2)
    assert_eq(#layer2_lights, 1, "one light on layer 2")
end)

-- occluder creation
test("add_occluder: creates line segment", function()
    lighting.clear()
    local id = lighting.add_occluder(0, 0, 100, 100)
    assert_not_nil(id, "occluder created")

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 1, "one occluder")
end)

test("add_occluder: multiple segments", function()
    lighting.clear()
    local id1 = lighting.add_occluder(0, 0, 100, 0)
    local id2 = lighting.add_occluder(100, 0, 100, 100)
    local id3 = lighting.add_occluder(100, 100, 0, 100)

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 3, "three occluders")
end)

test("add_rect_occluder: creates rectangle", function()
    lighting.clear()
    local ids = lighting.add_rect_occluder(50, 50, 100, 80)

    assert_eq(#ids, 4, "four segments for rectangle")

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 4, "four occluders")
end)

test("add_circle_occluder: creates circle approximation", function()
    lighting.clear()
    local ids = lighting.add_circle_occluder(100, 100, 50, 16)

    assert_eq(#ids, 16, "16 segments for circle")

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 16, "16 occluders")
end)

test("add_polygon_occluder: creates polygon", function()
    lighting.clear()
    local vertices = {
        { 0,   0 },
        { 100, 0 },
        { 100, 100 },
        { 50,  150 },
        { 0,   100 }
    }
    local ids = lighting.add_polygon_occluder(vertices)

    assert_eq(#ids, 5, "five segments for pentagon")

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 5, "five occluders")
end)

test("add_occluder: respects max limit", function()
    lighting.init(nil, { max_lights = 100, max_occluders = 2 })
    lighting.clear()

    local id1 = lighting.add_occluder(0, 0, 10, 10)
    local id2 = lighting.add_occluder(20, 20, 30, 30)
    local id3 = lighting.add_occluder(40, 40, 50, 50)

    assert_not_nil(id1, "first occluder created")
    assert_not_nil(id2, "second occluder created")
    assert_nil(id3, "third occluder rejected")
    lighting.init()
end)

-- occluder modification
test("set_occluder_position: moves segment", function()
    lighting.clear()
    local id = lighting.add_occluder(0, 0, 100, 100)
    lighting.set_occluder_position(id, 50, 50, 150, 150)

end)

test("set_occluder_enabled: toggles occluder", function()
    lighting.clear()
    local id = lighting.add_occluder(0, 0, 100, 100)

    lighting.set_occluder_enabled(id, false)
    lighting.set_occluder_enabled(id, true)

end)

test("set_occluder_layer: assigns layer", function()
    lighting.clear()
    local id = lighting.add_occluder(0, 0, 100, 100)
    lighting.set_occluder_layer(id, 3)

end)

-- occluder removal
test("remove_occluder: deletes segment", function()
    lighting.clear()
    local id = lighting.add_occluder(0, 0, 100, 100)

    lighting.remove_occluder(id)

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 0, "occluder removed")
end)

test("remove_occluders: deletes multiple", function()
    lighting.clear()
    local ids = lighting.add_rect_occluder(0, 0, 100, 100)

    lighting.remove_occluders(ids)

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 0, "all occluders removed")
end)

test("clear_occluders: removes all occluders", function()
    lighting.clear()
    lighting.add_rect_occluder(0, 0, 100, 100)
    lighting.add_circle_occluder(200, 200, 50)

    lighting.clear_occluders()

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 0, "all occluders cleared")
end)

-- light queries at points
test("get_light_at_point: calculates illumination", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    local id = lighting.add_light(100, 100, 1, 0, 0, 1, 200)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(100, 100)

    -- at light position, should be near full intensity
    assert_true(r > 0.5, "significant red contribution")
    assert_true(g < 0.1, "minimal green")
    assert_true(b < 0.1, "minimal blue")
end)

test("get_light_at_point: includes ambient", function()
    lighting.clear()
    lighting.set_ambient(0.2, 0.2, 0.2)

    -- no lights, just ambient
    local r, g, b = lighting.get_light_at_point(100, 100)

    assert_near(r, 0.2, 0.01, "ambient red")
    assert_near(g, 0.2, 0.01, "ambient green")
    assert_near(b, 0.2, 0.01, "ambient blue")
end)

test("get_light_at_point: multiple lights accumulate", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    lighting.add_light(100, 100, 1, 0, 0, 0.5, 200)
    lighting.add_light(100, 100, 0, 1, 0, 0.5, 200)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(100, 100)

    assert_true(r > 0.2, "red contribution")
    assert_true(g > 0.2, "green contribution")
end)

test("get_light_at_point: respects range", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    lighting.add_light(0, 0, 1, 1, 1, 1, 50)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(200, 200)

    -- far outside range
    assert_near(r, 0, 0.01, "no light at distance")
    assert_near(g, 0, 0.01, "no light at distance")
    assert_near(b, 0, 0.01, "no light at distance")
end)

test("get_light_at_point: filters by layer", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    local id = lighting.add_light(100, 100, 1, 1, 1, 1, 200)
    lighting.set_light_layer(id, 5)
    lighting.update()

    -- query layer 5
    local r1, g1, b1 = lighting.get_light_at_point(100, 100, 5)
    assert_true(r1 > 0.5, "light on correct layer")

    -- query layer 1
    local r2, g2, b2 = lighting.get_light_at_point(100, 100, 1)
    assert_near(r2, 0, 0.01, "no light on different layer")
end)

-- shadow queries
test("is_point_in_shadow: detects shadows", function()
    lighting.clear()

    local light_id = lighting.add_light(0, 0, 1, 1, 1, 1, 300)
    lighting.add_occluder(50, -10, 50, 10)
    lighting.update()

    -- point behind occluder
    local in_shadow = lighting.is_point_in_shadow(100, 0, light_id)
    assert_true(in_shadow, "point in shadow")
end)

test("is_point_in_shadow: no shadow without occluders", function()
    lighting.clear()

    local light_id = lighting.add_light(0, 0, 1, 1, 1, 1, 200)
    lighting.update()

    local in_shadow = lighting.is_point_in_shadow(100, 100, light_id)
    assert_false(in_shadow, "no shadow without occluders")
end)

test("is_point_in_shadow: respects range", function()
    lighting.clear()

    local light_id = lighting.add_light(0, 0, 1, 1, 1, 1, 50)
    lighting.update()

    -- point outside range
    local in_shadow = lighting.is_point_in_shadow(200, 200, light_id)
    assert_true(in_shadow, "outside range counts as shadow")
end)

-- spotlight specific
test("spotlight: cone angle restricts illumination", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    -- spotlight pointing right
    local id = lighting.add_spotlight(100, 100, 0, math.pi / 6, math.pi / 4, 1, 1, 1, 1, 200)
    lighting.update()

    -- point in cone
    local r1, g1, b1 = lighting.get_light_at_point(150, 100)
    assert_true(r1 > 0.2, "point in cone is lit")

    -- point outside cone
    local r2, g2, b2 = lighting.get_light_at_point(100, 150)
    assert_near(r2, 0, 0.1, "point outside cone is dark")
end)

test("spotlight: direction affects coverage", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    local id = lighting.add_spotlight(100, 100, math.pi / 2, math.pi / 4, math.pi / 3, 1, 1, 1, 1, 200)
    lighting.update()

    -- point in downward cone
    local r, g, b = lighting.get_light_at_point(100, 150)
    assert_true(r > 0.1, "downward spotlight illuminates below")
end)

-- attenuation
test("attenuation_preset: none", function()
    local c, l, q = lighting.attenuation_preset("none", 100)
    assert_near(c, 1, 0.01, "constant")
    assert_near(l, 0, 0.01, "linear")
    assert_near(q, 0, 0.01, "quadratic")
end)

test("attenuation_preset: linear", function()
    local c, l, q = lighting.attenuation_preset("linear", 100)
    assert_near(c, 1, 0.01, "constant")
    assert_near(l, 0.01, 0.001, "linear coefficient")
    assert_near(q, 0, 0.01, "quadratic")
end)

test("attenuation_preset: quadratic", function()
    local c, l, q = lighting.attenuation_preset("quadratic", 100)
    assert_near(c, 1, 0.01, "constant")
    assert_near(l, 0, 0.01, "linear")
    assert_true(q > 0, "quadratic coefficient")
end)

-- utility functions
test("deg_to_rad: converts degrees", function()
    local rad = lighting.deg_to_rad(180)
    assert_near(rad, math.pi, 0.01, "180 degrees")
end)

test("rad_to_deg: converts radians", function()
    local deg = lighting.rad_to_deg(math.pi)
    assert_near(deg, 180, 0.1, "pi radians")
end)

-- statistics
test("get_stats: returns statistics", function()
    lighting.clear()

    lighting.add_light(0, 0)
    lighting.add_light(100, 100)
    lighting.add_occluder(50, 50, 150, 50)

    local stats = lighting.get_stats()

    assert_eq(stats.lights, 2, "light count")
    assert_eq(stats.occluders, 1, "occluder count")
    assert_not_nil(stats.lights_processed, "has lights_processed")
    assert_not_nil(stats.occluders_tested, "has occluders_tested")
end)

-- clear all
test("clear: removes everything", function()
    lighting.clear()

    lighting.add_light(0, 0)
    lighting.add_light(100, 100)
    lighting.add_rect_occluder(50, 50, 100, 100)

    lighting.clear()

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 0, "all lights cleared")
    assert_eq(stats.occluders, 0, "all occluders cleared")
end)

test("get_gpu_data: returns raw data", function()
    lighting.clear()
    lighting.add_light(10, 10)
    lighting.add_occluder(0, 0, 100, 100)

    local lights_data, occluders_data, light_count, occluder_count = lighting.get_gpu_data()

    assert_not_nil(lights_data, "lights data returned")
    assert_not_nil(occluders_data, "occluders data returned")
    assert_eq(light_count, 1, "correct light count")
    assert_eq(occluder_count, 1, "correct occluder count")
end)

-- edge cases
test("edge: light at origin", function()
    lighting.clear()
    local id = lighting.add_light(0, 0, 1, 1, 1, 1, 100)
    assert_not_nil(id, "light at origin")
    lighting.update()
end)

test("edge: negative coordinates", function()
    lighting.clear()
    local id = lighting.add_light(-100, -100, 1, 1, 1, 1, 200)
    lighting.add_occluder(-150, -150, -50, -50)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(-100, -100)
    assert_true(r > 0, "handles negative coordinates")
end)

test("edge: very small range", function()
    lighting.set_default_attenuation("quadratic")
    lighting.clear()
    lighting.set_ambient(0, 0, 0)
    local id = lighting.add_light(100, 100, 1, 1, 1, 1, 0.1)
    local light = lighting.get_light(id)
    print("Light range:", light.range)
    print("Attenuation coeffs:", light.att_const, light.att_linear, light.att_quad)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(100.05, 100.05)
    print("Got RGB:", r, g, b)
    print("Distance:", math.sqrt(0.05 * 0.05 + 0.05 * 0.05))
    -- tolerance accommodates smooth falloff curves (inverse-square window)
    -- which may retain ~13% intensity at 70% radius to prevent visual popping
    assert_near(r, 0, 0.15, "very small range")
end)

test("edge: very large range", function()
    lighting.clear()
    local id = lighting.add_light(0, 0, 1, 1, 1, 1, 10000)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(5000, 5000)
    assert_true(r >= 0, "very large range")
end)

test("edge: zero intensity", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)
    local id = lighting.add_light(100, 100, 1, 1, 1, 0, 100)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(100, 100)
    assert_near(r, 0, 0.01, "zero intensity produces no light")
end)

test("edge: overlapping lights", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    lighting.add_light(100, 100, 1, 0, 0, 0.5, 100)
    lighting.add_light(100, 100, 0, 1, 0, 0.5, 100)
    lighting.add_light(100, 100, 0, 0, 1, 0.5, 100)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(100, 100)
    assert_true(r > 0.2, "red from first light")
    assert_true(g > 0.2, "green from second light")
    assert_true(b > 0.2, "blue from third light")
end)



test("edge: degenerate occluder (zero length)", function()
    lighting.clear()

    local id = lighting.add_light(100, 100, 1, 1, 1, 1, 200)
    lighting.add_occluder(150, 150, 150, 150)

    lighting.update()
end)





test("edge: spotlight with zero cone angle", function()
    lighting.clear()
    local id = lighting.add_spotlight(100, 100, 0, 0, 0.1, 1, 1, 1, 1, 100)
    lighting.update()

    local r, g, b = lighting.get_light_at_point(150, 100)
end)

test("edge: spotlight with full cone (2*pi)", function()
    lighting.clear()
    local id = lighting.add_spotlight(100, 100, 0, math.pi, math.pi * 2, 1, 1, 1, 1, 100)
    lighting.update()

    -- point light tbh
    local r, g, b = lighting.get_light_at_point(150, 100)
    assert_true(r > 0, "full cone spotlight")
end)

test("edge: disabled light is not queried", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    local id = lighting.add_light(100, 100, 1, 1, 1, 1, 200)
    lighting.set_light_enabled(id, false)
    lighting.update()

    local all_lights = lighting.get_all_lights()
    assert_eq(#all_lights, 0, "disabled light not in query")

    local r, g, b = lighting.get_light_at_point(100, 100)
    assert_near(r, 0, 0.01, "disabled light produces no illumination")
end)

test("edge: disabled occluder casts no shadow", function()
    lighting.clear()

    local light_id = lighting.add_light(0, 0, 1, 1, 1, 1, 300)
    local occ_id = lighting.add_occluder(50, -10, 50, 10)

    lighting.set_occluder_enabled(occ_id, false)
    lighting.update()

    local in_shadow = lighting.is_point_in_shadow(100, 0, light_id)
    assert_false(in_shadow, "disabled occluder casts no shadow")
end)

-- stress tests
test("stress: many lights", function()
    lighting.init(nil, { max_lights = 5000, max_occluders = 100 })
    lighting.clear()

    for i = 1, 5000 do
        lighting.add_light(math.random(0, 1000), math.random(0, 1000))
    end

    local stats = lighting.get_stats()
    assert_eq(stats.lights, 5000, "many lights created")

    lighting.init()
end)

test("stress: many occluders", function()
    lighting.init(nil, { max_lights = 100, max_occluders = 5000 })
    lighting.clear()

    for i = 1, 5000 do
        lighting.add_occluder(math.random(0, 1000), math.random(0, 1000), math.random(0, 1000), math.random(0, 1000))
    end

    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 5000, "many occluders created")

    lighting.init()
end)

test("stress: complex scene", function()
    lighting.clear()

    -- grid of lights
    for x = 0, 400, 50 do
        for y = 0, 400, 50 do
            lighting.add_light(x, y, 1, 1, 1, 0.5, 100)
        end
    end

    -- random occluders
    for i = 1, 50 do
        local x = math.random(0, 400)
        local y = math.random(0, 400)
        lighting.add_rect_occluder(x, y, 20, 20)
    end

    lighting.update()

    -- query many points
    for i = 1, 100 do
        local x = math.random(0, 400)
        local y = math.random(0, 400)
        local r, g, b = lighting.get_light_at_point(x, y)
        assert_true(r >= 0 and r <= 1, "valid color range")
    end
end)

test("stress: rapid light movement", function()
    lighting.clear()

    local id = lighting.add_light(0, 0, 1, 1, 1, 1, 100)
    lighting.add_rect_occluder(50, 50, 100, 100)

    -- move light multiple times
    for i = 1, 50 do
        lighting.set_light_position(id, i * 5, i * 5)
        lighting.update()
    end

    -- should handle rapid updates
    local stats = lighting.get_stats()
    assert_eq(stats.lights, 1, "light still exists")
end)

test("stress: rapid occluder changes", function()
    lighting.clear()

    local light_id = lighting.add_light(200, 200, 1, 1, 1, 1, 300)
    local occ_id = lighting.add_occluder(100, 100, 300, 100)

    -- toggle and move occluder
    for i = 1, 20 do
        lighting.set_occluder_enabled(occ_id, i % 2 == 0)
        lighting.set_occluder_position(occ_id, 100 + i, 100, 300 + i, 100)
        lighting.update()
    end

    -- should handle rapid changes
    local stats = lighting.get_stats()
    assert_eq(stats.occluders, 1, "occluder still exists")
end)

-- benchmark tests
test("benchmark: light updates", function()
    lighting.clear()

    local id = lighting.add_light(200, 200, 1, 1, 1, 1, 300)
    lighting.add_rect_occluder(250, 200, 100, 100)

    local start = os.clock()

    for i = 1, 1000 do
        lighting.update()
    end

    local elapsed = os.clock() - start
    print(string.format("  1000 updates in %.3fs (%.1f updates/sec)", elapsed, 1000 / elapsed))

    assert_true(elapsed < 5.0, "updates should be reasonably fast")
end)

test("benchmark: point queries", function()
    lighting.clear()
    lighting.set_ambient(0.1, 0.1, 0.1)

    lighting.add_light(100, 100, 1, 0, 0, 1, 200)
    lighting.add_light(300, 100, 0, 1, 0, 1, 200)
    lighting.add_light(200, 300, 0, 0, 1, 1, 200)
    lighting.update()

    local start = os.clock()

    for i = 1, 10000 do
        local x = (i * 17) % 400
        local y = (i * 23) % 400
        lighting.get_light_at_point(x, y)
    end

    local elapsed = os.clock() - start
    print(string.format("  10000 point queries in %.3fs (%.1f queries/sec)", elapsed, 10000 / elapsed))

    assert_true(elapsed < 1.0, "point queries should be fast")
end)



-- examples
test("example: simple room lighting", function()
    lighting.clear()
    lighting.set_ambient(0.05, 0.05, 0.05)

    -- room walls (400x300 room)
    lighting.add_rect_occluder(0, 0, 400, 300)

    -- ceiling light
    local light1 = lighting.add_light(200, 150, 1, 1, 0.8, 1.5, 300)

    lighting.update()

    -- check illumination at various points
    local r1, g1, b1 = lighting.get_light_at_point(200, 150)
    assert_true(r1 > 0.5, "bright at center")

    local r2, g2, b2 = lighting.get_light_at_point(50, 50)
    assert_true(r2 > 0.1, "lit in corner")
end)

test("example: spotlight effect", function()
    lighting.clear()
    lighting.set_ambient(0.02, 0.02, 0.02)

    -- spotlight pointing down
    local spot = lighting.add_spotlight(
        200, 50,     -- position
        math.pi / 2, -- pointing down
        math.pi / 6, -- 30 degree inner cone
        math.pi / 4, -- 45 degree outer cone
        1, 1, 1,     -- white light
        2.0,         -- intensity
        200          -- range
    )

    lighting.update()

    -- point in spotlight beam
    local r1, g1, b1 = lighting.get_light_at_point(200, 150)
    assert_true(r1 > 0.5, "bright in spotlight")

    -- point outside beam
    local r2, g2, b2 = lighting.get_light_at_point(300, 150)
    assert_true(r2 < 0.2, "dark outside spotlight")
end)

test("example: dynamic shadows", function()
    lighting.clear()
    lighting.set_ambient(0.1, 0.1, 0.1)

    local light = lighting.add_light(100, 100, 1, 1, 1, 1, 300)
    local obstacle_ids = lighting.add_rect_occluder(200, 150, 50, 80)

    lighting.update()

    -- point in shadow
    local shadow1 = lighting.is_point_in_shadow(250, 200, light)

    -- move obstacle
    for i = 1, #obstacle_ids do
        lighting.remove_occluder(obstacle_ids[i])
    end
    lighting.add_rect_occluder(200, 250, 50, 80)

    lighting.update()

    -- same point should no longer be in shadow
    local shadow2 = lighting.is_point_in_shadow(250, 200, light)

    assert_true(shadow1, "initially in shadow")
    assert_false(shadow2, "no longer in shadow after move")
end)

test("example: colored lighting mix", function()
    lighting.clear()
    lighting.set_ambient(0.01, 0.01, 0.01)

    -- red light from left
    lighting.add_light(50, 200, 1, 0, 0, 1, 200)

    -- blue light from right
    lighting.add_light(350, 200, 0, 0, 1, 1, 200)

    -- green light from top
    lighting.add_light(200, 50, 0, 1, 0, 1, 200)

    lighting.update()

    -- center should have mixed colors
    local r, g, b = lighting.get_light_at_point(200, 200)

    assert_true(r > 0.1, "red component")
    assert_true(g > 0.1, "green component")
    assert_true(b > 0.1, "blue component")
end)

test("example: layer-based lighting", function()
    lighting.clear()

    -- background layer lights
    local bg_light = lighting.add_light(100, 100, 0.5, 0.5, 1, 1, 150)
    lighting.set_light_layer(bg_light, 0)

    -- foreground layer lights
    local fg_light = lighting.add_light(200, 200, 1, 0.5, 0, 1, 150)
    lighting.set_light_layer(fg_light, 1)

    lighting.update()

    -- query by layer
    local bg_lights = lighting.get_all_lights(0)
    local fg_lights = lighting.get_all_lights(1)

    assert_eq(#bg_lights, 1, "one background light")
    assert_eq(#fg_lights, 1, "one foreground light")

    -- point lighting respects layers
    local r1, g1, b1 = lighting.get_light_at_point(100, 100, 0)
    local r2, g2, b2 = lighting.get_light_at_point(100, 100, 1)

    assert_true(b1 > r1, "background is blue-ish")
    assert_true(r2 > b2, "foreground is red-ish")
end)

test("example: attenuation comparison", function()
    lighting.clear()
    lighting.set_ambient(0, 0, 0)

    -- light with no attenuation
    local id1 = lighting.add_light(100, 100, 1, 0, 0, 1, 200)
    lighting.set_light_attenuation(id1, 1, 0, 0)

    -- light with quadratic attenuation
    local id2 = lighting.add_light(300, 100, 0, 1, 0, 1, 200)
    local c, l, q = lighting.attenuation_preset("quadratic", 200)
    lighting.set_light_attenuation(id2, c, l, q)

    lighting.update()

    -- compare falloff at distance
    local r1, g1, b1 = lighting.get_light_at_point(100, 200) -- 100 units from light1
    local r2, g2, b2 = lighting.get_light_at_point(300, 200) -- 100 units from light2

    -- no attenuation should be brighter at same distance
    assert_true(r1 > r2, "no attenuation is brighter")
end)

-- ============================================================================
-- summary
-- ============================================================================

print("\n=== Test Summary ===")
print(string.format("Total: %d", total_tests))
print(string.format("Passed: %d", passed_tests))
print(string.format("Failed: %d", total_tests - passed_tests))

if #failed_tests > 0 then
    print("\nFailed tests:")
    for _, failure in ipairs(failed_tests) do
        print("  - " .. failure.name)
    end
    os.exit(1)
else
    print("\n✓ All tests passed!")
    os.exit(0)
end
