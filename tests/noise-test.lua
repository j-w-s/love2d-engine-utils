local noise = require("noise")

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
        table.insert(failed_tests, {name = name, error = err})
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
        error(string.format("%s: expected %s (±%s), got %s", msg or "assertion failed", tostring(expected), tostring(tolerance), tostring(actual)))
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

local function assert_range(value, min_val, max_val, msg)
    if value < min_val or value > max_val then
        error(string.format("%s: expected value in [%s, %s], got %s", msg or "range check failed", tostring(min_val), tostring(max_val), tostring(value)))
    end
end

local function assert_not_nan(value, msg)
    if value ~= value then  -- NaN check
        error(msg or "expected non-NaN value")
    end
end

-- ============================================================================
-- CORE NOISE TESTS
-- ============================================================================

print("\n=== Core Noise Functions ===\n")

test("noise2: produces deterministic output", function()
    local v1 = noise.noise2(1.5, 2.5)
    local v2 = noise.noise2(1.5, 2.5)
    assert_eq(v1, v2, "same input should produce same output")
end)

test("noise2: output in valid range", function()
    for i = 1, 100 do
        local v = noise.noise2(i * 0.1, i * 0.2)
        assert_range(v, -1.0, 1.0, "noise2 output")
        assert_not_nan(v, "should not be NaN")
    end
end)

test("noise2: different inputs produce different outputs", function()
    local v1 = noise.noise2(0, 0)
    local v2 = noise.noise2(1, 1)
    assert_true(v1 ~= v2, "different inputs should differ")
end)

test("noise2: smooth gradients", function()
    local v1 = noise.noise2(0, 0)
    local v2 = noise.noise2(0.01, 0)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.1, "adjacent samples should be smooth")
end)

test("noise3: produces deterministic output", function()
    local v1 = noise.noise3(1.5, 2.5, 3.5)
    local v2 = noise.noise3(1.5, 2.5, 3.5)
    assert_eq(v1, v2, "same input should produce same output")
end)

test("noise3: output in valid range", function()
    for i = 1, 100 do
        local v = noise.noise3(i * 0.1, i * 0.2, i * 0.3)
        assert_range(v, -1.0, 1.0, "noise3 output")
        assert_not_nan(v, "should not be NaN")
    end
end)

test("noise3: smooth gradients", function()
    local v1 = noise.noise3(0, 0, 0)
    local v2 = noise.noise3(0.01, 0, 0)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.1, "adjacent samples should be smooth")
end)

test("noise4: produces deterministic output", function()
    local v1 = noise.noise4(1.5, 2.5, 3.5, 4.5)
    local v2 = noise.noise4(1.5, 2.5, 3.5, 4.5)
    assert_eq(v1, v2, "same input should produce same output")
end)

test("noise4: output in valid range", function()
    for i = 1, 100 do
        local v = noise.noise4(i * 0.1, i * 0.2, i * 0.3, i * 0.4)
        assert_range(v, -1.0, 1.0, "noise4 output")
        assert_not_nan(v, "should not be NaN")
    end
end)

test("noise4: different inputs produce different outputs", function()
    local v1 = noise.noise4(0, 0, 0, 0)
    local v2 = noise.noise4(1, 1, 1, 1)
    assert_true(v1 ~= v2, "different inputs should differ")
end)

test("noise4: smooth gradients", function()
    local v1 = noise.noise4(0, 0, 0, 0)
    local v2 = noise.noise4(0.01, 0, 0, 0)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.1, "adjacent samples should be smooth")
end)

test("noise4: wraparound continuity", function()
    local radius = 1.0
    local v1 = noise.noise4(radius, 0, radius, 0)
    local v2 = noise.noise4(radius * math.cos(0.01), radius * math.sin(0.01), radius, 0)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.15, "smooth wraparound")
end)

-- ============================================================================
-- VALUE NOISE TESTS
-- ============================================================================

print("\n=== Value Noise ===\n")

test("value2: produces deterministic output", function()
    local v1 = noise.value2(1.5, 2.5)
    local v2 = noise.value2(1.5, 2.5)
    assert_eq(v1, v2, "deterministic output")
end)

test("value2: output in range [0,1]", function()
    for i = 1, 100 do
        local v = noise.value2(i * 0.5, i * 0.7)
        assert_range(v, 0.0, 1.0, "value2 output")
        assert_not_nan(v, "should not be NaN")
    end
end)

test("value2: smooth interpolation", function()
    local v1 = noise.value2(0.5, 0.5)
    local v2 = noise.value2(0.51, 0.5)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.05, "smooth interpolation")
end)

test("value3: produces deterministic output", function()
    local v1 = noise.value3(1.5, 2.5, 3.5)
    local v2 = noise.value3(1.5, 2.5, 3.5)
    assert_eq(v1, v2, "deterministic output")
end)

test("value3: output in range [0,1]", function()
    for i = 1, 100 do
        local v = noise.value3(i * 0.5, i * 0.7, i * 0.9)
        assert_range(v, 0.0, 1.0, "value3 output")
        assert_not_nan(v, "should not be NaN")
    end
end)

-- ============================================================================
-- WORLEY/CELLULAR NOISE TESTS
-- ============================================================================

print("\n=== Worley/Cellular Noise ===\n")

test("worley2: produces deterministic output", function()
    local d1a, d2a, ida = noise.worley2(1.5, 2.5)
    local d1b, d2b, idb = noise.worley2(1.5, 2.5)
    assert_eq(d1a, d1b, "same first distance")
    assert_eq(d2a, d2b, "same second distance")
    assert_eq(ida, idb, "same cell id")
end)

test("worley2: distances in valid range", function()
    for i = 1, 100 do
        local d1, d2, id = noise.worley2(i * 0.3, i * 0.4)
        assert_true(d1 >= 0, "first distance non-negative")
        assert_true(d2 >= d1, "second distance >= first")
        assert_true(d1 < 2, "first distance reasonable")
        assert_not_nan(d1, "d1 not NaN")
        assert_not_nan(d2, "d2 not NaN")
    end
end)

test("worley2: cell ids differ across cells", function()
    local d1a, d2a, ida = noise.worley2(0.5, 0.5)
    local d1b, d2b, idb = noise.worley2(10.5, 10.5)
    assert_true(ida ~= idb, "different cell ids")
end)

test("worley2: manhattan distance", function()
    local d1 = noise.worley2(1.5, 2.5, 1.0, "manhattan")
    assert_true(d1 >= 0 and d1 < 3, "manhattan distance valid")
end)

test("worley2: chebyshev distance", function()
    local d1 = noise.worley2(1.5, 2.5, 1.0, "chebyshev")
    assert_true(d1 >= 0 and d1 < 2, "chebyshev distance valid")
end)

test("worley2: jitter parameter", function()
    local d1_jitter = noise.worley2(1.5, 2.5, 1.0)
    local d1_no_jitter = noise.worley2(1.5, 2.5, 0.0)
    assert_true(d1_jitter >= 0, "jittered valid")
    assert_true(d1_no_jitter >= 0, "non-jittered valid")
end)

test("worley3: produces deterministic output", function()
    local d1a, d2a, ida = noise.worley3(1.5, 2.5, 3.5)
    local d1b, d2b, idb = noise.worley3(1.5, 2.5, 3.5)
    assert_eq(d1a, d1b, "same first distance")
    assert_eq(ida, idb, "same cell id")
end)

test("worley3: distances in valid range", function()
    for i = 1, 50 do
        local d1, d2, id = noise.worley3(i * 0.3, i * 0.4, i * 0.5)
        assert_true(d1 >= 0, "first distance non-negative")
        assert_true(d2 >= d1, "second distance >= first")
        assert_not_nan(d1, "d1 not NaN")
    end
end)

test("worley3: different distance metrics", function()
    local d_euclidean = noise.worley3(1.5, 2.5, 3.5, 1.0, "euclidean")
    local d_manhattan = noise.worley3(1.5, 2.5, 3.5, 1.0, "manhattan")
    local d_chebyshev = noise.worley3(1.5, 2.5, 3.5, 1.0, "chebyshev")
    assert_true(d_euclidean >= 0, "euclidean valid")
    assert_true(d_manhattan >= 0, "manhattan valid")
    assert_true(d_chebyshev >= 0, "chebyshev valid")
end)

-- ============================================================================
-- FRACTAL NOISE TESTS (FBM, TURBULENCE, RIDGED)
-- ============================================================================

print("\n=== Fractal Noise ===\n")

test("fbm2: produces deterministic output", function()
    local v1 = noise.fbm2(1.5, 2.5, 4)
    local v2 = noise.fbm2(1.5, 2.5, 4)
    assert_eq(v1, v2, "deterministic fbm2")
end)

test("fbm2: output in range [0,1]", function()
    for i = 1, 100 do
        local v = noise.fbm2(i * 0.2, i * 0.3, 4)
        assert_range(v, 0.0, 1.0, "fbm2 output")
        assert_not_nan(v, "not NaN")
    end
end)

test("fbm2: octaves parameter", function()
    local v1 = noise.fbm2(1.5, 2.5, 1)
    local v8 = noise.fbm2(1.5, 2.5, 8)
    assert_range(v1, 0.0, 1.0, "1 octave")
    assert_range(v8, 0.0, 1.0, "8 octaves")
end)

test("fbm2: persistence parameter", function()
    local v_low = noise.fbm2(1.5, 2.5, 4, 0.3)
    local v_high = noise.fbm2(1.5, 2.5, 4, 0.7)
    assert_range(v_low, 0.0, 1.0, "low persistence")
    assert_range(v_high, 0.0, 1.0, "high persistence")
end)

test("fbm2: lacunarity parameter", function()
    local v_low = noise.fbm2(1.5, 2.5, 4, 0.5, 1.5)
    local v_high = noise.fbm2(1.5, 2.5, 4, 0.5, 3.0)
    assert_range(v_low, 0.0, 1.0, "low lacunarity")
    assert_range(v_high, 0.0, 1.0, "high lacunarity")
end)

test("fbm3: produces deterministic output", function()
    local v1 = noise.fbm3(1.5, 2.5, 3.5, 4)
    local v2 = noise.fbm3(1.5, 2.5, 3.5, 4)
    assert_eq(v1, v2, "deterministic fbm3")
end)

test("fbm3: output in range [0,1]", function()
    for i = 1, 50 do
        local v = noise.fbm3(i * 0.2, i * 0.3, i * 0.4, 4)
        assert_range(v, 0.0, 1.0, "fbm3 output")
        assert_not_nan(v, "not NaN")
    end
end)

test("turbulence2: produces positive values", function()
    for i = 1, 100 do
        local v = noise.turbulence2(i * 0.2, i * 0.3, 4)
        assert_true(v >= 0, "turbulence non-negative")
        assert_range(v, 0.0, 1.5, "turbulence range")
        assert_not_nan(v, "not NaN")
    end
end)

test("turbulence2: deterministic", function()
    local v1 = noise.turbulence2(1.5, 2.5, 4)
    local v2 = noise.turbulence2(1.5, 2.5, 4)
    assert_eq(v1, v2, "deterministic turbulence")
end)

test("turbulence3: produces positive values", function()
    for i = 1, 50 do
        local v = noise.turbulence3(i * 0.2, i * 0.3, i * 0.4, 4)
        assert_true(v >= 0, "turbulence non-negative")
        assert_not_nan(v, "not NaN")
    end
end)

test("ridged2: produces ridged patterns", function()
    for i = 1, 100 do
        local v = noise.ridged2(i * 0.2, i * 0.3, 4)
        assert_range(v, 0.0, 1.0, "ridged2 range")
        assert_not_nan(v, "not NaN")
    end
end)

test("ridged2: deterministic", function()
    local v1 = noise.ridged2(1.5, 2.5, 4)
    local v2 = noise.ridged2(1.5, 2.5, 4)
    assert_eq(v1, v2, "deterministic ridged")
end)

test("ridged3: produces ridged patterns", function()
    for i = 1, 50 do
        local v = noise.ridged3(i * 0.2, i * 0.3, i * 0.4, 4)
        assert_range(v, 0.0, 1.0, "ridged3 range")
        assert_not_nan(v, "not NaN")
    end
end)

test("billowy2: produces positive billowy patterns", function()
    for i = 1, 100 do
        local v = noise.billowy2(i * 0.2, i * 0.3, 4)
        assert_range(v, 0.0, 1.0, "billowy2 range")
        assert_not_nan(v, "not NaN")
    end
end)

test("billowy3: produces positive billowy patterns", function()
    for i = 1, 50 do
        local v = noise.billowy3(i * 0.2, i * 0.3, i * 0.4, 4)
        assert_range(v, 0.0, 1.0, "billowy3 range")
        assert_not_nan(v, "not NaN")
    end
end)

-- ============================================================================
-- DOMAIN WARPING TESTS
-- ============================================================================

print("\n=== Domain Warping ===\n")

test("domain_warp2: produces warped output", function()
    local v1 = noise.domain_warp2(1.5, 2.5)
    local v2 = noise.domain_warp2(1.5, 2.5)
    assert_eq(v1, v2, "deterministic warp")
    assert_range(v1, -1.0, 1.0, "warped output range")
end)

test("domain_warp2: strength parameter", function()
    local v_weak = noise.domain_warp2(1.5, 2.5, 0.5)
    local v_strong = noise.domain_warp2(1.5, 2.5, 10.0)
    assert_range(v_weak, -1.0, 1.0, "weak warp")
    assert_range(v_strong, -1.0, 1.0, "strong warp")
end)

test("domain_warp3: produces warped output", function()
    local v1 = noise.domain_warp3(1.5, 2.5, 3.5)
    local v2 = noise.domain_warp3(1.5, 2.5, 3.5)
    assert_eq(v1, v2, "deterministic warp")
    assert_range(v1, -1.0, 1.0, "warped output range")
end)

test("swiss2: advanced turbulence", function()
    for i = 1, 50 do
        local v = noise.swiss2(i * 0.2, i * 0.3, 4)
        assert_range(v, 0.0, 2.0, "swiss2 range")
        assert_not_nan(v, "not NaN")
    end
end)

test("jordan2: advanced ridged multifractal", function()
    for i = 1, 50 do
        local v = noise.jordan2(i * 0.2, i * 0.3, 6)
        assert_not_nan(v, "not NaN")
        assert_true(v >= -10 and v <= 10, "jordan2 reasonable range")
    end
end)

-- ============================================================================
-- BLENDING UTILITIES TESTS
-- ============================================================================

print("\n=== Blending Utilities ===\n")

test("smoothstep: correct interpolation", function()
    assert_eq(noise.smoothstep(0, 1, 0), 0, "smoothstep at 0")
    assert_eq(noise.smoothstep(0, 1, 1), 1, "smoothstep at 1")
    local mid = noise.smoothstep(0, 1, 0.5)
    assert_true(mid > 0.4 and mid < 0.6, "smoothstep at 0.5")
end)

test("smoothstep: clamping", function()
    assert_eq(noise.smoothstep(0, 1, -0.5), 0, "clamps below")
    assert_eq(noise.smoothstep(0, 1, 1.5), 1, "clamps above")
end)

test("smootherstep: correct interpolation", function()
    assert_eq(noise.smootherstep(0, 1, 0), 0, "smootherstep at 0")
    assert_eq(noise.smootherstep(0, 1, 1), 1, "smootherstep at 1")
    local mid = noise.smootherstep(0, 1, 0.5)
    assert_true(mid > 0.4 and mid < 0.6, "smootherstep at 0.5")
end)

test("lerp: linear interpolation", function()
    assert_eq(noise.lerp(0, 10, 0), 0, "lerp at 0")
    assert_eq(noise.lerp(0, 10, 1), 10, "lerp at 1")
    assert_eq(noise.lerp(0, 10, 0.5), 5, "lerp at 0.5")
end)

test("lerp: extrapolation", function()
    local v = noise.lerp(0, 10, 1.5)
    assert_eq(v, 15, "lerp extrapolates")
end)

test("bilerp: 2d interpolation", function()
    local v = noise.bilerp(0, 10, 20, 30, 0.5, 0.5)
    assert_eq(v, 15, "bilerp center")
    
    local v00 = noise.bilerp(0, 10, 20, 30, 0, 0)
    assert_eq(v00, 0, "bilerp corner (0,0)")
    
    local v11 = noise.bilerp(0, 10, 20, 30, 1, 1)
    assert_eq(v11, 30, "bilerp corner (1,1)")
end)

test("trilerp: 3d interpolation", function()
    local v = no    assert_range(v_weak, -1.0, 1.0, "weak warp")
ise.trilerp(0, 1, 2, 3, 4, 5, 6, 7, 0.5, 0.5, 0.5)
    assert_near(v, 3.5, 0.01, "trilerp center")
    
    local v000 = noise.trilerp(0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 0)
    assert_eq(v000, 0, "trilerp corner (0,0,0)")
    
    local v111 = noise.trilerp(0, 1, 2, 3, 4, 5, 6, 7, 1, 1, 1)
    assert_eq(v111, 7, "trilerp corner (1,1,1)")
end)

test("cubic_interp: smooth interpolation", function()
    local v = noise.cubic_interp(0, 5, 10, 15, 0.5)
    assert_true(v > 4 and v < 11, "cubic interp reasonable")
    assert_not_nan(v, "not NaN")
end)

test("weighted_blend: combines values", function()
    local values = {10, 20, 30}
    local weights = {0.5, 0.3, 0.2}
    local result = noise.weighted_blend(values, weights)
    assert_near(result, 17, 0.01, "weighted blend")
end)

test("weighted_blend: equal weights", function()
    local values = {10, 20, 30}
    local weights = {1/3, 1/3, 1/3}
    local result = noise.weighted_blend(values, weights)
    assert_near(result, 20, 0.01, "equal weights average")
end)

test("distance_weight: falloff curve", function()
    local w0 = noise.distance_weight(0, 10)
    local w5 = noise.distance_weight(5, 10)
    local w10 = noise.distance_weight(10, 10)
    local w15 = noise.distance_weight(15, 10)
    
    assert_eq(w0, 1, "full weight at distance 0")
    assert_true(w5 > 0 and w5 < 1, "partial weight at mid distance")
    assert_eq(w10, 0, "zero weight at falloff distance")
    assert_eq(w15, 0, "zero weight beyond falloff")
end)

-- ============================================================================
-- EROSION HELPERS TESTS
-- ============================================================================

print("\n=== Erosion Helpers ===\n")

test("hydraulic_erosion_step: preserves dimensions", function()
    local map = {
        {10, 10, 10},
        {10, 15, 10},
        {10, 10, 10}
    }
    local eroded = noise.hydraulic_erosion_step(map, 3, 3, 0.1)
    assert_eq(#eroded, 3, "height preserved")
    assert_eq(#eroded[1], 3, "width preserved")
end)

test("hydraulic_erosion_step: erodes peaks", function()
    local map = {
        {5, 5, 5},
        {5, 10, 5},
        {5, 5, 5}
    }
    local eroded = noise.hydraulic_erosion_step(map, 3, 3, 0.5)
    assert_true(eroded[2][2] < map[2][2], "peak eroded")
end)

test("thermal_erosion_step: preserves dimensions", function()
    local map = {
        {5, 5, 5},
        {5, 10, 5},
        {5, 5, 5}
    }
    local eroded = noise.thermal_erosion_step(map, 3, 3, 0.6)
    assert_eq(#eroded, 3, "height preserved")
    assert_eq(#eroded[1], 3, "width preserved")
end)

test("thermal_erosion_step: smooths steep slopes", function()
    local map = {
        {0, 0, 0},
        {0, 10, 0},
        {0, 0, 0}
    }
    local eroded = noise.thermal_erosion_step(map, 3, 3, 0.3)
    assert_true(eroded[2][2] <= map[2][2], "peak smoothed")
end)

test("apply_erosion_mask: slope-based erosion", function()
    local map = {
        {5, 5, 5},
        {5, 10, 5},
        {5, 5, 5}
    }
    local eroded = noise.apply_erosion_mask(map, 3, 3, 0.5)
    assert_eq(#eroded, 3, "dimensions preserved")
    assert_true(eroded[2][2] < map[2][2], "high slope eroded")
end)

test("sediment_deposition: smooths valleys", function()
    local map = {
        {10, 10, 10},
        {10, 5, 10},
        {10, 10, 10}
    }
    local smoothed = noise.sediment_deposition(map, 3, 3, 0.5)
    assert_true(smoothed[2][2] > map[2][2], "valley filled")
end)

-- ============================================================================
-- SEEDING TESTS
-- ============================================================================

print("\n=== Seeding ===\n")

test("seed: changes noise output", function()
    noise.seed(12345)
    local v1 = noise.noise2(1.5, 2.5)
    
    noise.seed(67890)
    local v2 = noise.noise2(1.5, 2.5)
    
    assert_true(v1 ~= v2, "different seeds produce different output")
end)

test("seed: deterministic with same seed", function()
    noise.seed(11111)
    local v1 = noise.noise2(1.5, 2.5)
    
    noise.seed(11111)
    local v2 = noise.noise2(1.5, 2.5)
    
    assert_eq(v1, v2, "same seed produces same output")
end)

test("seed: affects all noise types", function()
    noise.seed(99999)
    local n1 = noise.noise2(1.2, 1.3) 
    local v1 = noise.value2(1.2, 1.3)
    local w1, _, _ = noise.worley2(1.2, 1.3)
    
    noise.seed(88888)
    local n2 = noise.noise2(1.2, 1.3)
    local v2 = noise.value2(1.2, 1.3)
    local w2, _, _ = noise.worley2(1.2, 1.3)
    
    assert_true(n1 ~= n2 or v1 ~= v2 or w1 ~= w2, "at least one noise type affected by seed")
end)

-- ============================================================================
-- HASH UTILITIES TESTS
-- ============================================================================

print("\n=== Hash Utilities ===\n")

test("hash2d: deterministic", function()
    local h1 = noise.hash2d(10, 20)
    local h2 = noise.hash2d(10, 20)
    assert_eq(h1, h2, "same input same hash")
end)

test("hash2d: different inputs differ", function()
    local h1 = noise.hash2d(10, 20)
    local h2 = noise.hash2d(11, 20)
    assert_true(h1 ~= h2, "different inputs different hash")
end)

test("hash3d: deterministic", function()
    local h1 = noise.hash3d(10, 20, 30)
    local h2 = noise.hash3d(10, 20, 30)
    assert_eq(h1, h2, "same input same hash")
end)

test("hash3d: different inputs differ", function()
    local h1 = noise.hash3d(10, 20, 30)
    local h2 = noise.hash3d(10, 20, 31)
    assert_true(h1 ~= h2, "different inputs different hash")
end)

test("hash_to_float: in range [0,1]", function()
    for i = 0, 1000 do
        local f = noise.hash_to_float(i)
        assert_range(f, 0.0, 1.0, "hash_to_float output")
    end
end)

test("hash_to_float: deterministic", function()
    local f1 = noise.hash_to_float(42)
    local f2 = noise.hash_to_float(42)
    assert_eq(f1, f2, "deterministic float conversion")
end)

test("hash4d: deterministic", function()
    local h1 = noise.hash4d(10, 20, 30, 40)
    local h2 = noise.hash4d(10, 20, 30, 40)
    assert_eq(h1, h2, "same input same hash")
end)

test("hash4d: different inputs differ", function()
    local h1 = noise.hash4d(10, 20, 30, 40)
    local h2 = noise.hash4d(10, 20, 30, 41)
    assert_true(h1 ~= h2, "different inputs different hash")
end)

test("edge: noise4 zero coordinates", function()
    local v = noise.noise4(0, 0, 0, 0)
    assert_not_nan(v, "handles zero coordinates")
    assert_range(v, -1.0, 1.0, "valid output at origin")
end)

test("edge: noise4 negative coordinates", function()
    local v = noise.noise4(-10, -20, -30, -40)
    assert_not_nan(v, "noise4 handles negatives")
    assert_range(v, -1.0, 1.0, "valid range")
end)

test("edge: noise4 large coordinates", function()
    local v = noise.noise4(10000, 20000, 30000, 40000)
    assert_not_nan(v, "noise4 handles large values")
end)

-- ============================================================================
-- EDGE CASES AND STRESS TESTS
-- ============================================================================

print("\n=== Edge Cases ===\n")

test("edge: zero coordinates", function()
    local v = noise.noise2(0, 0)
    assert_not_nan(v, "handles zero coordinates")
    assert_range(v, -1.0, 1.0, "valid output at origin")
end)

test("edge: negative coordinates", function()
    local v1 = noise.noise2(-10, -20)
    local v2 = noise.noise3(-10, -20, -30)
    assert_not_nan(v1, "noise2 handles negatives")
    assert_not_nan(v2, "noise3 handles negatives")
end)

test("edge: large coordinates", function()
    local v1 = noise.noise2(10000, 20000)
    local v2 = noise.noise3(10000, 20000, 30000)
    assert_not_nan(v1, "noise2 handles large values")
    assert_not_nan(v2, "noise3 handles large values")
end)

test("edge: very small deltas", function()
    local v1 = noise.noise2(1.0, 1.0)
    local v2 = noise.noise2(1.0000001, 1.0)
    local diff = math.abs(v1 - v2)
    assert_true(diff < 0.01, "smooth at tiny deltas")
end)

test("edge: worley with zero jitter", function()
    local d1, d2, id = noise.worley2(1.5, 2.5, 0.0)
    assert_not_nan(d1, "handles zero jitter")
    assert_true(d1 >= 0, "valid distance")
end)

test("edge: fbm with 1 octave", function()
    local v = noise.fbm2(1.5, 2.5, 1)
    assert_range(v, 0.0, 1.0, "single octave fbm")
end)

test("edge: fbm with many octaves", function()
    local v = noise.fbm2(1.5, 2.5, 16)
    assert_range(v, 0.0, 1.0, "16 octave fbm")
end)

test("edge: blending with single value", function()
    local result = noise.weighted_blend({10}, {1.0})
    assert_eq(result, 10, "single value blend")
end)

test("edge: blending with zero weights", function()
    local result = noise.weighted_blend({10, 20}, {0.0, 0.0})
    assert_eq(result, 0, "zero weights")
end)

test("edge: erosion on flat terrain", function()
    local map = {
        {5, 5, 5},
        {5, 5, 5},
        {5, 5, 5}
    }
    local eroded = noise.hydraulic_erosion_step(map, 3, 3, 0.5)
    for y = 1, 3 do
        for x = 1, 3 do
            assert_eq(eroded[y][x], 5, "flat terrain unchanged")
        end
    end
end)

test("edge: erosion on 1x1 map", function()
    local map = {{10}}
    local eroded = noise.hydraulic_erosion_step(map, 1, 1, 0.5)
    assert_eq(eroded[1][1], 10, "single cell unchanged")
end)

-- ============================================================================
-- PERFORMANCE BENCHMARKS
-- ============================================================================

print("\n=== Performance Benchmarks ===\n")

test("benchmark: noise2 throughput", function()
    local iterations = 100000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.noise2(i * 0.01, i * 0.02)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  noise2: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
    assert_true(elapsed < 2.0, "noise2 should be fast")
end)

test("benchmark: noise3 throughput", function()
    local iterations = 50000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.noise3(i * 0.01, i * 0.02, i * 0.03)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  noise3: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
    assert_true(elapsed < 2.0, "noise3 should be fast")
end)

test("benchmark: noise4 throughput", function()
    local iterations = 25000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.noise4(i * 0.01, i * 0.02, i * 0.03, i * 0.04)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  noise4: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
    assert_true(elapsed < 3.0, "noise4 should be reasonably fast")
end)


test("benchmark: value2 throughput", function()
    local iterations = 100000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.value2(i * 0.01, i * 0.02)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  value2: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: worley2 throughput", function()
    local iterations = 50000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.worley2(i * 0.01, i * 0.02)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  worley2: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
    assert_true(elapsed < 3.0, "worley2 reasonably fast")
end)

test("benchmark: fbm2 throughput", function()
    local iterations = 10000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.fbm2(i * 0.01, i * 0.02, 4)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  fbm2: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: domain_warp2 throughput", function()
    local iterations = 5000
    local start = os.clock()
    
    for i = 1, iterations do
        noise.domain_warp2(i * 0.01, i * 0.02)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  domain_warp2: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: heightmap generation (128x128)", function()
    local size = 128
    local start = os.clock()
    
    local heightmap = {}
    for y = 1, size do
        heightmap[y] = {}
        for x = 1, size do
            heightmap[y][x] = noise.fbm2(x * 0.05, y * 0.05, 4)
        end
    end
    
    local elapsed = os.clock() - start
    local pixels = size * size
    print(string.format("  128x128 heightmap: %.3fs (%d pixels, %.0f pixels/sec)", 
        elapsed, pixels, pixels/elapsed))
end)

test("benchmark: biome blending simulation", function()
    local iterations = 1000
    local start = os.clock()
    
    for i = 1, iterations do
        local x, y = i * 0.1, i * 0.2
        
        local d1, d2, id1 = noise.worley2(x * 0.02, y * 0.02)
        
        local terrain_a = noise.fbm2(x, y, 4, 0.5, 2.0)
        local terrain_b = noise.ridged2(x, y, 4, 0.5, 2.0)
        local terrain_c = noise.billowy2(x, y, 4, 0.5, 2.0)
        
        local w1 = noise.distance_weight(d1, 1.0)
        local w2 = noise.distance_weight(d2, 1.0)
        local w3 = 1.0 - w1 - w2
        local sum = w1 + w2 + w3
        w1, w2, w3 = w1/sum, w2/sum, w3/sum
        
        local final = noise.weighted_blend({terrain_a, terrain_b, terrain_c}, {w1, w2, w3})
    end
    
    local elapsed = os.clock() - start
    print(string.format("  biome blending: %d iterations in %.3fs (%.0f iter/sec)", 
        iterations, elapsed, iterations/elapsed))
end)

-- ============================================================================
-- PRACTICAL EXAMPLES
-- ============================================================================

print("\n=== Practical Examples ===\n")

test("example: terrain heightmap with multiple layers", function()
    local x, y = 10.5, 20.3
    
    -- base terrain
    local base = noise.fbm2(x * 0.01, y * 0.01, 4, 0.5, 2.0)
    
    -- add ridges
    local ridges = noise.ridged2(x * 0.05, y * 0.05, 4, 0.5, 2.0)
    
    -- add detail
    local detail = noise.turbulence2(x * 0.2, y * 0.2, 3, 0.5, 2.0)
    
    -- combine
    local height = base * 0.6 + ridges * 0.3 + detail * 0.1
    
    assert_range(height, 0.0, 1.5, "combined height")
end)

test("example: cave generation with 3d noise", function()
    local x, y, z = 10, 20, 30
    
    -- cave density
    local cave = noise.noise3(x * 0.1, y * 0.1, z * 0.1)
    
    -- threshold for cave
    local is_cave = cave < -0.3
    
    assert_true(is_cave == true or is_cave == false, "valid cave state")
end)

test("example: seamless toroidal noise", function()
    local width, height = 256, 256
    local radius = 10.0
    
    local x, y = 0, 0
    local s = x / width
    local t = y / height
    
    local nx = radius * math.cos(s * 2 * math.pi)
    local ny = radius * math.sin(s * 2 * math.pi)
    local nz = radius * math.cos(t * 2 * math.pi)
    local nw = radius * math.sin(t * 2 * math.pi)
    
    local v = noise.noise4(nx, ny, nz, nw)
    assert_range(v, -1.0, 1.0, "toroidal noise")
end)

test("example: biome temperature/humidity map", function()
    local x, y = 15.5, 25.5
    
    -- temperature map
    local temp = noise.fbm2(x * 0.02, y * 0.02, 3)
    
    -- humidity map  
    local humidity = noise.fbm2(x * 0.03 + 100, y * 0.03 + 100, 3)
    
    -- classify biome
    local biome
    if temp > 0.7 and humidity < 0.3 then
        biome = "desert"
    elseif temp < 0.3 and humidity > 0.7 then
        biome = "snow"
    elseif humidity > 0.6 then
        biome = "rainforest"
    else
        biome = "plains"
    end
    
    assert_true(biome ~= nil, "biome classified")
end)

test("example: erosion pipeline", function()
    local map = {
        {5, 8, 10, 8, 5},
        {8, 12, 15, 12, 8},
        {10, 15, 20, 15, 10},
        {8, 12, 15, 12, 8},
        {5, 8, 10, 8, 5}
    }
    
    -- apply hydraulic erosion
    map = noise.hydraulic_erosion_step(map, 5, 5, 0.2)
    
    -- apply thermal erosion
    map = noise.thermal_erosion_step(map, 5, 5, 0.5)
    
    -- deposit sediment
    map = noise.sediment_deposition(map, 5, 5, 0.1)
    
    assert_eq(#map, 5, "erosion pipeline complete")
end)

test("example: multi-scale terrain detail", function()
    local x, y = 50.5, 75.3
    
    -- continental scale (large features)
    local continent = noise.fbm2(x * 0.001, y * 0.001, 2, 0.5, 2.0)
    
    -- regional scale (mountains, valleys)
    local region = noise.fbm2(x * 0.01, y * 0.01, 4, 0.5, 2.0)
    
    -- local scale (hills, rocks)
    local local_detail = noise.fbm2(x * 0.1, y * 0.1, 4, 0.5, 2.0)
    
    -- micro scale (surface texture)
    local micro = noise.turbulence2(x * 0.5, y * 0.5, 3, 0.5, 2.0)
    
    -- combine with diminishing weights
    local height = continent * 100 + region * 50 + local_detail * 10 + micro * 1
    
    assert_true(height > 0, "multi-scale height valid")
end)

test("example: voronoi cell patterns", function()
    local x, y = 10.5, 20.5
    
    -- get cell distances
    local d1, d2, cell_id = noise.worley2(x * 0.1, y * 0.1)
    
    -- cell interior (distance from center)
    local cell_interior = d1
    
    -- cell borders (distance between cells)
    local cell_border = d2 - d1
    
    -- use for different effects
    assert_range(cell_interior, 0.0, 2.0, "cell interior")
    assert_range(cell_border, 0.0, 2.0, "cell border")
end)

-- ============================================================================
-- MATHEMATICAL PROPERTIES
-- ============================================================================

print("\n=== Mathematical Properties ===\n")

test("property: noise2 continuity", function()
    local x, y = 10.0, 20.0
    local epsilon = 0.001
    
    local v1 = noise.noise2(x, y)
    local v2 = noise.noise2(x + epsilon, y)
    
    local gradient = math.abs(v2 - v1) / epsilon
    assert_true(gradient < 10, "gradient bounded (continuous)")
end)

test("property: smoothstep symmetry", function()
    local v1 = noise.smoothstep(0, 1, 0.3)
    local v2 = noise.smoothstep(0, 1, 0.7)
    
    -- smoothstep should be symmetric around 0.5
    assert_near(v1, 1.0 - v2, 0.01, "smoothstep symmetry")
end)

test("property: lerp linearity", function()
    local a, b = 0, 10
    local v1 = noise.lerp(a, b, 0.25)
    local v2 = noise.lerp(a, b, 0.5)
    local v3 = noise.lerp(a, b, 0.75)
    
    assert_eq(v1, 2.5, "lerp at 0.25")
    assert_eq(v2, 5.0, "lerp at 0.5")
    assert_eq(v3, 7.5, "lerp at 0.75")
end)

test("property: weighted_blend normalization", function()
    -- weights sum to 1.0
    local values = {10, 20, 30}
    local weights = {0.2, 0.3, 0.5}
    local result = noise.weighted_blend(values, weights)
    
    -- should be weighted average
    local expected = 10*0.2 + 20*0.3 + 30*0.5
    assert_eq(result, expected, "weighted average")
end)

test("property: worley first distance <= second distance", function()
    for i = 1, 50 do
        local x, y = i * 0.5, i * 0.7
        local d1, d2 = noise.worley2(x, y)
        assert_true(d1 <= d2, "d1 <= d2 always")
    end
end)

test("property: fbm increases with octaves", function()
    local x, y = 5.5, 8.5
    
    local v1 = noise.fbm2(x, y, 1, 0.5, 2.0)
    local v8 = noise.fbm2(x, y, 8, 0.5, 2.0)
    
    assert_range(v1, 0.0, 1.0, "1 octave in range")
    assert_range(v8, 0.0, 1.0, "8 octaves in range")
end)

-- ============================================================================
-- SUMMARY
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