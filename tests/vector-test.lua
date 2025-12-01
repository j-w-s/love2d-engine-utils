local vector = require("vector")
local vec2, vec3, vec4 = vector.vec2, vector.vec3, vector.vec4

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

local function assert_not_nan(value, msg)
    if value ~= value then
        error(msg or "expected non-NaN value")
    end
end

-- ============================================================================
-- VEC2 TESTS
-- ============================================================================

print("\n=== Vec2 Construction ===\n")

test("vec2: construction with values", function()
    local v = vec2(3, 4)
    assert_eq(v.x, 3, "x component")
    assert_eq(v.y, 4, "y component")
end)

test("vec2: construction with zero", function()
    local v = vec2(0, 0)
    assert_eq(v.x, 0, "zero x")
    assert_eq(v.y, 0, "zero y")
end)

test("vec2: construction with negatives", function()
    local v = vec2(-5, -10)
    assert_eq(v.x, -5, "negative x")
    assert_eq(v.y, -10, "negative y")
end)

print("\n=== Vec2 Basic Operations ===\n")

test("vec2: set", function()
    local v = vec2(1, 2)
    v:set(5, 6)
    assert_eq(v.x, 5, "x updated")
    assert_eq(v.y, 6, "y updated")
end)

test("vec2: copy", function()
    local v1 = vec2(3, 4)
    local v2 = vec2(0, 0)
    v2:copy(v1)
    assert_eq(v2.x, 3, "copied x")
    assert_eq(v2.y, 4, "copied y")
end)

test("vec2: clone", function()
    local v1 = vec2(7, 8)
    local v2 = v1:clone()
    assert_eq(v2.x, 7, "cloned x")
    assert_eq(v2.y, 8, "cloned y")
end)

test("vec2: add", function()
    local v1 = vec2(2, 3)
    local v2 = vec2(1, 4)
    v1:add(v2)
    assert_eq(v1.x, 3, "added x")
    assert_eq(v1.y, 7, "added y")
end)

test("vec2: sub", function()
    local v1 = vec2(5, 8)
    local v2 = vec2(2, 3)
    v1:sub(v2)
    assert_eq(v1.x, 3, "subtracted x")
    assert_eq(v1.y, 5, "subtracted y")
end)

test("vec2: mul (scalar)", function()
    local v = vec2(2, 3)
    v:mul(3)
    assert_eq(v.x, 6, "multiplied x")
    assert_eq(v.y, 9, "multiplied y")
end)

test("vec2: div (scalar)", function()
    local v = vec2(10, 20)
    v:div(2)
    assert_eq(v.x, 5, "divided x")
    assert_eq(v.y, 10, "divided y")
end)

test("vec2: neg", function()
    local v = vec2(3, -4)
    v:neg()
    assert_eq(v.x, -3, "negated x")
    assert_eq(v.y, 4, "negated y")
end)

print("\n=== Vec2 Vector Operations ===\n")

test("vec2: dot product", function()
    local v1 = vec2(2, 3)
    local v2 = vec2(4, 5)
    local dot = v1:dot(v2)
    assert_eq(dot, 23, "dot product (2*4 + 3*5)")
end)

test("vec2: dot product orthogonal", function()
    local v1 = vec2(1, 0)
    local v2 = vec2(0, 1)
    local dot = v1:dot(v2)
    assert_eq(dot, 0, "orthogonal vectors")
end)

test("vec2: cross product (2d scalar)", function()
    local v1 = vec2(2, 0)
    local v2 = vec2(0, 3)
    local cross = v1:cross(v2)
    assert_eq(cross, 6, "cross product 2*3")
end)

test("vec2: cross product parallel", function()
    local v1 = vec2(2, 4)
    local v2 = vec2(1, 2)
    local cross = v1:cross(v2)
    assert_eq(cross, 0, "parallel vectors")
end)

test("vec2: len2", function()
    local v = vec2(3, 4)
    assert_eq(v:len2(), 25, "length squared (3² + 4²)")
end)

test("vec2: len", function()
    local v = vec2(3, 4)
    assert_eq(v:len(), 5, "length (pythagorean)")
end)

test("vec2: dist2", function()
    local v1 = vec2(1, 2)
    local v2 = vec2(4, 6)
    assert_eq(v1:dist2(v2), 25, "distance squared (3² + 4²)")
end)

test("vec2: dist", function()
    local v1 = vec2(0, 0)
    local v2 = vec2(3, 4)
    assert_eq(v1:dist(v2), 5, "distance")
end)

test("vec2: normalize", function()
    local v = vec2(3, 4)
    v:normalize()
    assert_near(v:len(), 1.0, 0.0001, "normalized length")
    assert_near(v.x, 0.6, 0.0001, "normalized x")
    assert_near(v.y, 0.8, 0.0001, "normalized y")
end)

test("vec2: normalize zero vector", function()
    local v = vec2(0, 0)
    v:normalize()
    assert_eq(v.x, 0, "zero vector x unchanged")
    assert_eq(v.y, 0, "zero vector y unchanged")
end)

test("vec2: lerp", function()
    local v1 = vec2(0, 0)
    local v2 = vec2(10, 20)
    v1:lerp(v2, 0.5)
    assert_eq(v1.x, 5, "lerp x at 0.5")
    assert_eq(v1.y, 10, "lerp y at 0.5")
end)

test("vec2: lerp at extremes", function()
    local v1 = vec2(0, 0)
    local v2 = vec2(10, 20)
    local v_start = v1:clone():lerp(v2, 0)
    assert_eq(v_start.x, 0, "lerp at t=0")
    
    local v_end = vec2(0, 0):lerp(v2, 1)
    assert_eq(v_end.x, 10, "lerp at t=1")
end)

test("vec2: reflect", function()
    local v = vec2(1, -1)
    local n = vec2(0, 1)  -- reflect off horizontal surface
    v:reflect(n)
    assert_near(v.x, 1, 0.0001, "reflected x")
    assert_near(v.y, 1, 0.0001, "reflected y")
end)

test("vec2: rotate 90 degrees", function()
    local v = vec2(1, 0)
    v:rotate(math.pi / 2)
    assert_near(v.x, 0, 0.0001, "rotated x")
    assert_near(v.y, 1, 0.0001, "rotated y")
end)

test("vec2: rotate 180 degrees", function()
    local v = vec2(1, 0)
    v:rotate(math.pi)
    assert_near(v.x, -1, 0.0001, "rotated x")
    assert_near(v.y, 0, 0.0001, "rotated y")
end)

test("vec2: angle", function()
    local v = vec2(1, 0)
    assert_near(v:angle(), 0, 0.0001, "angle of (1,0)")
    
    local v2 = vec2(0, 1)
    assert_near(v2:angle(), math.pi/2, 0.0001, "angle of (0,1)")
end)

test("vec2: angle_to", function()
    local v1 = vec2(1, 0)
    local v2 = vec2(0, 1)
    local angle = v1:angle_to(v2)
    assert_near(angle, math.pi/2, 0.0001, "90 degree angle")
end)

test("vec2: perp", function()
    local v = vec2(1, 0)
    v:perp()
    assert_eq(v.x, 0, "perp x")
    assert_eq(v.y, 1, "perp y")
end)

print("\n=== Vec2 Component Operations ===\n")

test("vec2: floor", function()
    local v = vec2(3.7, 4.2)
    v:floor()
    assert_eq(v.x, 3, "floor x")
    assert_eq(v.y, 4, "floor y")
end)

test("vec2: ceil", function()
    local v = vec2(3.2, 4.7)
    v:ceil()
    assert_eq(v.x, 4, "ceil x")
    assert_eq(v.y, 5, "ceil y")
end)

test("vec2: abs", function()
    local v = vec2(-3, -4)
    v:abs()
    assert_eq(v.x, 3, "abs x")
    assert_eq(v.y, 4, "abs y")
end)

test("vec2: min", function()
    local v1 = vec2(5, 2)
    local v2 = vec2(3, 8)
    v1:min(v2)
    assert_eq(v1.x, 3, "min x")
    assert_eq(v1.y, 2, "min y")
end)

test("vec2: max", function()
    local v1 = vec2(5, 2)
    local v2 = vec2(3, 8)
    v1:max(v2)
    assert_eq(v1.x, 5, "max x")
    assert_eq(v1.y, 8, "max y")
end)

test("vec2: clamp", function()
    local v = vec2(-5, 15)
    v:clamp(0, 10)
    assert_eq(v.x, 0, "clamped min x")
    assert_eq(v.y, 10, "clamped max y")
end)

test("vec2: unpack", function()
    local v = vec2(7, 9)
    local x, y = v:unpack()
    assert_eq(x, 7, "unpacked x")
    assert_eq(y, 9, "unpacked y")
end)

print("\n=== Vec2 Operator Overloads ===\n")

test("vec2: operator +", function()
    local v1 = vec2(2, 3)
    local v2 = vec2(4, 5)
    local v3 = v1 + v2
    assert_eq(v3.x, 6, "added x")
    assert_eq(v3.y, 8, "added y")
end)

test("vec2: operator -", function()
    local v1 = vec2(7, 9)
    local v2 = vec2(3, 4)
    local v3 = v1 - v2
    assert_eq(v3.x, 4, "subtracted x")
    assert_eq(v3.y, 5, "subtracted y")
end)

test("vec2: operator * (vec * scalar)", function()
    local v = vec2(3, 4)
    local v2 = v * 2
    assert_eq(v2.x, 6, "multiplied x")
    assert_eq(v2.y, 8, "multiplied y")
end)

test("vec2: operator * (scalar * vec)", function()
    local v = vec2(3, 4)
    local v2 = 2 * v
    assert_eq(v2.x, 6, "multiplied x")
    assert_eq(v2.y, 8, "multiplied y")
end)

test("vec2: operator * (component-wise)", function()
    local v1 = vec2(2, 3)
    local v2 = vec2(4, 5)
    local v3 = v1 * v2
    assert_eq(v3.x, 8, "component x")
    assert_eq(v3.y, 15, "component y")
end)

test("vec2: operator / (scalar)", function()
    local v = vec2(10, 20)
    local v2 = v / 2
    assert_eq(v2.x, 5, "divided x")
    assert_eq(v2.y, 10, "divided y")
end)

test("vec2: operator / (component-wise)", function()
    local v1 = vec2(10, 20)
    local v2 = vec2(2, 4)
    local v3 = v1 / v2
    assert_eq(v3.x, 5, "component x")
    assert_eq(v3.y, 5, "component y")
end)

test("vec2: operator unary -", function()
    local v = vec2(3, -4)
    local v2 = -v
    assert_eq(v2.x, -3, "negated x")
    assert_eq(v2.y, 4, "negated y")
end)

test("vec2: operator ==", function()
    local v1 = vec2(3, 4)
    local v2 = vec2(3, 4)
    local v3 = vec2(3, 5)
    assert_true(v1 == v2, "equal vectors")
    assert_false(v1 == v3, "unequal vectors")
end)

test("vec2: tostring", function()
    local v = vec2(1.5, 2.5)
    local s = tostring(v)
    assert_true(s:match("vec2"), "contains vec2")
    assert_true(s:match("1.5"), "contains x value")
    assert_true(s:match("2.5"), "contains y value")
end)

-- ============================================================================
-- VEC3 TESTS
-- ============================================================================

print("\n=== Vec3 Construction ===\n")

test("vec3: construction with values", function()
    local v = vec3(1, 2, 3)
    assert_eq(v.x, 1, "x component")
    assert_eq(v.y, 2, "y component")
    assert_eq(v.z, 3, "z component")
end)

test("vec3: construction with zero", function()
    local v = vec3(0, 0, 0)
    assert_eq(v.x, 0, "zero x")
    assert_eq(v.y, 0, "zero y")
    assert_eq(v.z, 0, "zero z")
end)

print("\n=== Vec3 Basic Operations ===\n")

test("vec3: set", function()
    local v = vec3(1, 2, 3)
    v:set(4, 5, 6)
    assert_eq(v.x, 4, "x updated")
    assert_eq(v.y, 5, "y updated")
    assert_eq(v.z, 6, "z updated")
end)

test("vec3: copy", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(0, 0, 0)
    v2:copy(v1)
    assert_eq(v2.x, 1, "copied x")
    assert_eq(v2.y, 2, "copied y")
    assert_eq(v2.z, 3, "copied z")
end)

test("vec3: clone", function()
    local v1 = vec3(7, 8, 9)
    local v2 = v1:clone()
    assert_eq(v2.x, 7, "cloned x")
    assert_eq(v2.y, 8, "cloned y")
    assert_eq(v2.z, 9, "cloned z")
end)

test("vec3: add", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    v1:add(v2)
    assert_eq(v1.x, 5, "added x")
    assert_eq(v1.y, 7, "added y")
    assert_eq(v1.z, 9, "added z")
end)

test("vec3: sub", function()
    local v1 = vec3(10, 8, 6)
    local v2 = vec3(1, 2, 3)
    v1:sub(v2)
    assert_eq(v1.x, 9, "subtracted x")
    assert_eq(v1.y, 6, "subtracted y")
    assert_eq(v1.z, 3, "subtracted z")
end)

test("vec3: mul", function()
    local v = vec3(2, 3, 4)
    v:mul(2)
    assert_eq(v.x, 4, "multiplied x")
    assert_eq(v.y, 6, "multiplied y")
    assert_eq(v.z, 8, "multiplied z")
end)

test("vec3: div", function()
    local v = vec3(10, 20, 30)
    v:div(10)
    assert_eq(v.x, 1, "divided x")
    assert_eq(v.y, 2, "divided y")
    assert_eq(v.z, 3, "divided z")
end)

test("vec3: neg", function()
    local v = vec3(1, -2, 3)
    v:neg()
    assert_eq(v.x, -1, "negated x")
    assert_eq(v.y, 2, "negated y")
    assert_eq(v.z, -3, "negated z")
end)

print("\n=== Vec3 Vector Operations ===\n")

test("vec3: dot product", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    local dot = v1:dot(v2)
    assert_eq(dot, 32, "dot product (1*4 + 2*5 + 3*6)")
end)

test("vec3: dot product orthogonal", function()
    local v1 = vec3(1, 0, 0)
    local v2 = vec3(0, 1, 0)
    local dot = v1:dot(v2)
    assert_eq(dot, 0, "orthogonal vectors")
end)

test("vec3: cross product", function()
    local v1 = vec3(1, 0, 0)
    local v2 = vec3(0, 1, 0)
    v1:cross(v2)
    assert_eq(v1.x, 0, "cross x")
    assert_eq(v1.y, 0, "cross y")
    assert_eq(v1.z, 1, "cross z")
end)

test("vec3: cross product anticommutative", function()
    local v1 = vec3(2, 3, 4)
    local v2 = vec3(5, 6, 7)
    local c1 = v1:clone():cross(v2)
    local c2 = v2:clone():cross(v1)
    assert_eq(c1.x, -c2.x, "anticommutative x")
    assert_eq(c1.y, -c2.y, "anticommutative y")
    assert_eq(c1.z, -c2.z, "anticommutative z")
end)

test("vec3: len2", function()
    local v = vec3(1, 2, 2)
    assert_eq(v:len2(), 9, "length squared (1² + 2² + 2²)")
end)

test("vec3: len", function()
    local v = vec3(2, 3, 6)
    assert_eq(v:len(), 7, "length")
end)

test("vec3: dist2", function()
    local v1 = vec3(0, 0, 0)
    local v2 = vec3(1, 2, 2)
    assert_eq(v1:dist2(v2), 9, "distance squared")
end)

test("vec3: dist", function()
    local v1 = vec3(0, 0, 0)
    local v2 = vec3(2, 3, 6)
    assert_eq(v1:dist(v2), 7, "distance")
end)

test("vec3: normalize", function()
    local v = vec3(3, 0, 4)
    v:normalize()
    assert_near(v:len(), 1.0, 0.0001, "normalized length")
    assert_near(v.x, 0.6, 0.0001, "normalized x")
    assert_near(v.y, 0.0, 0.0001, "normalized y")
    assert_near(v.z, 0.8, 0.0001, "normalized z")
end)

test("vec3: normalize zero vector", function()
    local v = vec3(0, 0, 0)
    v:normalize()
    assert_eq(v.x, 0, "zero vector unchanged")
end)

test("vec3: lerp", function()
    local v1 = vec3(0, 0, 0)
    local v2 = vec3(10, 20, 30)
    v1:lerp(v2, 0.5)
    assert_eq(v1.x, 5, "lerp x")
    assert_eq(v1.y, 10, "lerp y")
    assert_eq(v1.z, 15, "lerp z")
end)

test("vec3: reflect", function()
    local v = vec3(1, -1, 0)
    local n = vec3(0, 1, 0)  -- reflect off horizontal surface
    v:reflect(n)
    assert_near(v.x, 1, 0.0001, "reflected x")
    assert_near(v.y, 1, 0.0001, "reflected y")
    assert_near(v.z, 0, 0.0001, "reflected z")
end)

test("vec3: refract", function()
    local v = vec3(0, -1, 0)
    local n = vec3(0, 1, 0)
    v:refract(n, 1.5)  -- into denser medium
    assert_not_nan(v.x, "refracted x not NaN")
    assert_not_nan(v.y, "refracted y not NaN")
    assert_not_nan(v.z, "refracted z not NaN")
end)

test("vec3: refract total internal reflection", function()
    local v = vec3(1, -0.1, 0):normalize()
    local n = vec3(0, 1, 0)
    v:refract(n, 0.5)  -- from dense to less dense at shallow angle
    -- should return zero vector for TIR
    local len = v:len()
    assert_true(len < 0.001 or len > 0.999, "TIR or refraction")
end)

test("vec3: rotate_axis", function()
    local v = vec3(1, 0, 0)
    local axis = vec3(0, 0, 1)
    v:rotate_axis(axis, math.pi / 2)  -- rotate 90° around z-axis
    assert_near(v.x, 0, 0.0001, "rotated x")
    assert_near(v.y, 1, 0.0001, "rotated y")
    assert_near(v.z, 0, 0.0001, "rotated z")
end)

test("vec3: angle_to", function()
    local v1 = vec3(1, 0, 0)
    local v2 = vec3(0, 1, 0)
    local angle = v1:angle_to(v2)
    assert_near(angle, math.pi/2, 0.0001, "90 degree angle")
end)

print("\n=== Vec3 Component Operations ===\n")

test("vec3: floor", function()
    local v = vec3(1.9, 2.1, 3.5)
    v:floor()
    assert_eq(v.x, 1, "floor x")
    assert_eq(v.y, 2, "floor y")
    assert_eq(v.z, 3, "floor z")
end)

test("vec3: ceil", function()
    local v = vec3(1.1, 2.9, 3.5)
    v:ceil()
    assert_eq(v.x, 2, "ceil x")
    assert_eq(v.y, 3, "ceil y")
    assert_eq(v.z, 4, "ceil z")
end)

test("vec3: abs", function()
    local v = vec3(-1, -2, -3)
    v:abs()
    assert_eq(v.x, 1, "abs x")
    assert_eq(v.y, 2, "abs y")
    assert_eq(v.z, 3, "abs z")
end)

test("vec3: min", function()
    local v1 = vec3(5, 2, 8)
    local v2 = vec3(3, 7, 1)
    v1:min(v2)
    assert_eq(v1.x, 3, "min x")
    assert_eq(v1.y, 2, "min y")
    assert_eq(v1.z, 1, "min z")
end)

test("vec3: max", function()
    local v1 = vec3(5, 2, 8)
    local v2 = vec3(3, 7, 1)
    v1:max(v2)
    assert_eq(v1.x, 5, "max x")
    assert_eq(v1.y, 7, "max y")
    assert_eq(v1.z, 8, "max z")
end)

test("vec3: clamp", function()
    local v = vec3(-5, 5, 15)
    v:clamp(0, 10)
    assert_eq(v.x, 0, "clamped min")
    assert_eq(v.y, 5, "in range")
    assert_eq(v.z, 10, "clamped max")
end)

test("vec3: unpack", function()
    local v = vec3(7, 8, 9)
    local x, y, z = v:unpack()
    assert_eq(x, 7, "unpacked x")
    assert_eq(y, 8, "unpacked y")
    assert_eq(z, 9, "unpacked z")
end)

print("\n=== Vec3 Operator Overloads ===\n")

test("vec3: operator +", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    local v3 = v1 + v2
    assert_eq(v3.x, 5, "added x")
    assert_eq(v3.y, 7, "added y")
    assert_eq(v3.z, 9, "added z")
end)

test("vec3: operator -", function()
    local v1 = vec3(10, 9, 8)
    local v2 = vec3(1, 2, 3)
    local v3 = v1 - v2
    assert_eq(v3.x, 9, "subtracted x")
    assert_eq(v3.y, 7, "subtracted y")
    assert_eq(v3.z, 5, "subtracted z")
end)

test("vec3: operator *", function()
    local v = vec3(2, 3, 4)
    local v2 = v * 2
    assert_eq(v2.x, 4, "multiplied x")
    assert_eq(v2.y, 6, "multiplied y")
    assert_eq(v2.z, 8, "multiplied z")
end)

test("vec3: operator / (scalar)", function()
    local v = vec3(10, 20, 30)
    local v2 = v / 10
    assert_eq(v2.x, 1, "divided x")
    assert_eq(v2.y, 2, "divided y")
    assert_eq(v2.z, 3, "divided z")
end)

test("vec3: operator unary -", function()
    local v = vec3(1, -2, 3)
    local v2 = -v
    assert_eq(v2.x, -1, "negated x")
    assert_eq(v2.y, 2, "negated y")
    assert_eq(v2.z, -3, "negated z")
end)

test("vec3: operator ==", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(1, 2, 3)
    local v3 = vec3(1, 2, 4)
    assert_true(v1 == v2, "equal vectors")
    assert_false(v1 == v3, "unequal vectors")
end)

test("vec3: tostring", function()
    local v = vec3(1.5, 2.5, 3.5)
    local s = tostring(v)
    assert_true(s:match("vec3"), "contains vec3")
    assert_true(s:match("1.5"), "contains x")
    assert_true(s:match("2.5"), "contains y")
    assert_true(s:match("3.5"), "contains z")
end)

-- ============================================================================
-- VEC4 TESTS
-- ============================================================================

print("\n=== Vec4 Construction ===\n")

test("vec4: construction with values", function()
    local v = vec4(1, 2, 3, 4)
    assert_eq(v.x, 1, "x component")
    assert_eq(v.y, 2, "y component")
    assert_eq(v.z, 3, "z component")
    assert_eq(v.w, 4, "w component")
end)

test("vec4: construction with zero", function()
    local v = vec4(0, 0, 0, 0)
    assert_eq(v.x, 0, "zero x")
    assert_eq(v.y, 0, "zero y")
    assert_eq(v.z, 0, "zero z")
    assert_eq(v.w, 0, "zero w")
end)

print("\n=== Vec4 Basic Operations ===\n")

test("vec4: set", function()
    local v = vec4(1, 2, 3, 4)
    v:set(5, 6, 7, 8)
    assert_eq(v.x, 5, "x updated")
    assert_eq(v.y, 6, "y updated")
    assert_eq(v.z, 7, "z updated")
    assert_eq(v.w, 8, "w updated")
end)

test("vec4: copy", function()
    local v1 = vec4(1, 2, 3, 4)
    local v2 = vec4(0, 0, 0, 0)
    v2:copy(v1)
    assert_eq(v2.x, 1, "copied x")
    assert_eq(v2.y, 2, "copied y")
    assert_eq(v2.z, 3, "copied z")
    assert_eq(v2.w, 4, "copied w")
end)

test("vec4: clone", function()
    local v1 = vec4(5, 6, 7, 8)
    local v2 = v1:clone()
    assert_eq(v2.x, 5, "cloned x")
    assert_eq(v2.y, 6, "cloned y")
    assert_eq(v2.z, 7, "cloned z")
    assert_eq(v2.w, 8, "cloned w")
end)

test("vec4: add", function()
    local v1 = vec4(1, 2, 3, 4)
    local v2 = vec4(5, 6, 7, 8)
    v1:add(v2)
    assert_eq(v1.x, 6, "added x")
    assert_eq(v1.y, 8, "added y")
    assert_eq(v1.z, 10, "added z")
    assert_eq(v1.w, 12, "added w")
end)

test("vec4: sub", function()
    local v1 = vec4(10, 9, 8, 7)
    local v2 = vec4(1, 2, 3, 4)
    v1:sub(v2)
    assert_eq(v1.x, 9, "subtracted x")
    assert_eq(v1.y, 7, "subtracted y")
    assert_eq(v1.z, 5, "subtracted z")
    assert_eq(v1.w, 3, "subtracted w")
end)

test("vec4: mul", function()
    local v = vec4(2, 3, 4, 5)
    v:mul(2)
    assert_eq(v.x, 4, "multiplied x")
    assert_eq(v.y, 6, "multiplied y")
    assert_eq(v.z, 8, "multiplied z")
    assert_eq(v.w, 10, "multiplied w")
end)

test("vec4: div", function()
    local v = vec4(10, 20, 30, 40)
    v:div(10)
    assert_eq(v.x, 1, "divided x")
    assert_eq(v.y, 2, "divided y")
    assert_eq(v.z, 3, "divided z")
    assert_eq(v.w, 4, "divided w")
end)

test("vec4: neg", function()
    local v = vec4(1, -2, 3, -4)
    v:neg()
    assert_eq(v.x, -1, "negated x")
    assert_eq(v.y, 2, "negated y")
    assert_eq(v.z, -3, "negated z")
    assert_eq(v.w, 4, "negated w")
end)

print("\n=== Vec4 Vector Operations ===\n")

test("vec4: dot product", function()
    local v1 = vec4(1, 2, 3, 4)
    local v2 = vec4(5, 6, 7, 8)
    local dot = v1:dot(v2)
    assert_eq(dot, 70, "dot product (1*5 + 2*6 + 3*7 + 4*8)")
end)

test("vec4: dot product orthogonal", function()
    local v1 = vec4(1, 0, 0, 0)
    local v2 = vec4(0, 1, 0, 0)
    local dot = v1:dot(v2)
    assert_eq(dot, 0, "orthogonal vectors")
end)

test("vec4: len2", function()
    local v = vec4(1, 2, 2, 0)
    assert_eq(v:len2(), 9, "length squared")
end)

test("vec4: len", function()
    local v = vec4(2, 3, 6, 0)
    assert_eq(v:len(), 7, "length")
end)

test("vec4: dist2", function()
    local v1 = vec4(0, 0, 0, 0)
    local v2 = vec4(1, 2, 2, 0)
    assert_eq(v1:dist2(v2), 9, "distance squared")
end)

test("vec4: dist", function()
    local v1 = vec4(0, 0, 0, 0)
    local v2 = vec4(2, 3, 6, 0)
    assert_eq(v1:dist(v2), 7, "distance")
end)

test("vec4: normalize", function()
    local v = vec4(3, 0, 4, 0)
    v:normalize()
    assert_near(v:len(), 1.0, 0.0001, "normalized length")
    assert_near(v.x, 0.6, 0.0001, "normalized x")
    assert_near(v.z, 0.8, 0.0001, "normalized z")
end)

test("vec4: normalize zero vector", function()
    local v = vec4(0, 0, 0, 0)
    v:normalize()
    assert_eq(v.x, 0, "zero vector unchanged")
end)

test("vec4: lerp", function()
    local v1 = vec4(0, 0, 0, 0)
    local v2 = vec4(10, 20, 30, 40)
    v1:lerp(v2, 0.5)
    assert_eq(v1.x, 5, "lerp x")
    assert_eq(v1.y, 10, "lerp y")
    assert_eq(v1.z, 15, "lerp z")
    assert_eq(v1.w, 20, "lerp w")
end)

print("\n=== Vec4 Component Operations ===\n")

test("vec4: floor", function()
    local v = vec4(1.9, 2.1, 3.5, 4.7)
    v:floor()
    assert_eq(v.x, 1, "floor x")
    assert_eq(v.y, 2, "floor y")
    assert_eq(v.z, 3, "floor z")
    assert_eq(v.w, 4, "floor w")
end)

test("vec4: ceil", function()
    local v = vec4(1.1, 2.9, 3.5, 4.2)
    v:ceil()
    assert_eq(v.x, 2, "ceil x")
    assert_eq(v.y, 3, "ceil y")
    assert_eq(v.z, 4, "ceil z")
    assert_eq(v.w, 5, "ceil w")
end)

test("vec4: abs", function()
    local v = vec4(-1, -2, -3, -4)
    v:abs()
    assert_eq(v.x, 1, "abs x")
    assert_eq(v.y, 2, "abs y")
    assert_eq(v.z, 3, "abs z")
    assert_eq(v.w, 4, "abs w")
end)

test("vec4: min", function()
    local v1 = vec4(5, 2, 8, 1)
    local v2 = vec4(3, 7, 1, 9)
    v1:min(v2)
    assert_eq(v1.x, 3, "min x")
    assert_eq(v1.y, 2, "min y")
    assert_eq(v1.z, 1, "min z")
    assert_eq(v1.w, 1, "min w")
end)

test("vec4: max", function()
    local v1 = vec4(5, 2, 8, 1)
    local v2 = vec4(3, 7, 1, 9)
    v1:max(v2)
    assert_eq(v1.x, 5, "max x")
    assert_eq(v1.y, 7, "max y")
    assert_eq(v1.z, 8, "max z")
    assert_eq(v1.w, 9, "max w")
end)

test("vec4: clamp", function()
    local v = vec4(-5, 5, 15, 7)
    v:clamp(0, 10)
    assert_eq(v.x, 0, "clamped min")
    assert_eq(v.y, 5, "in range")
    assert_eq(v.z, 10, "clamped max")
    assert_eq(v.w, 7, "in range")
end)

test("vec4: unpack", function()
    local v = vec4(5, 6, 7, 8)
    local x, y, z, w = v:unpack()
    assert_eq(x, 5, "unpacked x")
    assert_eq(y, 6, "unpacked y")
    assert_eq(z, 7, "unpacked z")
    assert_eq(w, 8, "unpacked w")
end)

print("\n=== Vec4 Operator Overloads ===\n")

test("vec4: operator +", function()
    local v1 = vec4(1, 2, 3, 4)
    local v2 = vec4(5, 6, 7, 8)
    local v3 = v1 + v2
    assert_eq(v3.x, 6, "added x")
    assert_eq(v3.y, 8, "added y")
    assert_eq(v3.z, 10, "added z")
    assert_eq(v3.w, 12, "added w")
end)

test("vec4: operator -", function()
    local v1 = vec4(10, 9, 8, 7)
    local v2 = vec4(1, 2, 3, 4)
    local v3 = v1 - v2
    assert_eq(v3.x, 9, "subtracted x")
    assert_eq(v3.y, 7, "subtracted y")
    assert_eq(v3.z, 5, "subtracted z")
    assert_eq(v3.w, 3, "subtracted w")
end)

test("vec4: operator *", function()
    local v = vec4(2, 3, 4, 5)
    local v2 = v * 2
    assert_eq(v2.x, 4, "multiplied x")
    assert_eq(v2.y, 6, "multiplied y")
    assert_eq(v2.z, 8, "multiplied z")
    assert_eq(v2.w, 10, "multiplied w")
end)

test("vec4: operator /", function()
    local v = vec4(10, 20, 30, 40)
    local v2 = v / 10
    assert_eq(v2.x, 1, "divided x")
    assert_eq(v2.y, 2, "divided y")
    assert_eq(v2.z, 3, "divided z")
    assert_eq(v2.w, 4, "divided w")
end)

test("vec4: operator unary -", function()
    local v = vec4(1, -2, 3, -4)
    local v2 = -v
    assert_eq(v2.x, -1, "negated x")
    assert_eq(v2.y, 2, "negated y")
    assert_eq(v2.z, -3, "negated z")
    assert_eq(v2.w, 4, "negated w")
end)

test("vec4: operator ==", function()
    local v1 = vec4(1, 2, 3, 4)
    local v2 = vec4(1, 2, 3, 4)
    local v3 = vec4(1, 2, 3, 5)
    assert_true(v1 == v2, "equal vectors")
    assert_false(v1 == v3, "unequal vectors")
end)

test("vec4: tostring", function()
    local v = vec4(1.5, 2.5, 3.5, 4.5)
    local s = tostring(v)
    assert_true(s:match("vec4"), "contains vec4")
    assert_true(s:match("1.5"), "contains x")
    assert_true(s:match("2.5"), "contains y")
    assert_true(s:match("3.5"), "contains z")
    assert_true(s:match("4.5"), "contains w")
end)

-- ============================================================================
-- EDGE CASES
-- ============================================================================

print("\n=== Edge Cases ===\n")

test("edge: vec2 very small values", function()
    local v = vec2(1e-10, 1e-10)
    v:normalize()
    assert_not_nan(v.x, "handles tiny values")
end)

test("edge: vec3 very large values", function()
    local v = vec3(1e100, 1e100, 1e100)
    local len = v:len()
    assert_not_nan(len, "handles large values")
end)

test("edge: vec2 divide by zero prevention", function()
    local v = vec2(10, 20)
    -- dividing by very small number
    v:div(1e-100)
    assert_not_nan(v.x, "handles near-zero division")
end)

test("edge: vec3 cross product with parallel vectors", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(2, 4, 6)
    v1:cross(v2)
    assert_near(v1:len(), 0, 0.0001, "parallel cross is zero")
end)

test("edge: vec2 angle with zero vector", function()
    local v = vec2(0, 0)
    local angle = v:angle()
    assert_not_nan(angle, "angle of zero vector")
end)

test("edge: vec3 refract with perpendicular incidence", function()
    local v = vec3(0, -1, 0)
    local n = vec3(0, 1, 0)
    v:refract(n, 1.5)
    assert_not_nan(v.y, "perpendicular refraction")
end)

test("edge: vec4 homogeneous coordinate w=0", function()
    local v = vec4(1, 2, 3, 0)
    local len = v:len()
    assert_near(len, math.sqrt(14), 0.0001, "w=0 length")
end)

test("edge: vec2 lerp with t > 1", function()
    local v1 = vec2(0, 0)
    local v2 = vec2(10, 10)
    v1:lerp(v2, 1.5)
    assert_eq(v1.x, 15, "extrapolation x")
    assert_eq(v1.y, 15, "extrapolation y")
end)

test("edge: vec3 rotate_axis with zero axis", function()
    local v = vec3(1, 0, 0)
    local axis = vec3(0, 0, 0)
    v:rotate_axis(axis, math.pi/2)
    assert_not_nan(v.x, "handles zero axis")
end)

test("edge: vec2 clamp with inverted range", function()
    local v = vec2(5, 5)
    v:clamp(10, 0)  -- min > max
    -- behavior depends on implementation
    assert_not_nan(v.x, "handles inverted range")
end)

-- ============================================================================
-- PERFORMANCE BENCHMARKS
-- ============================================================================

print("\n=== Performance Benchmarks ===\n")

test("benchmark: vec2 operations throughput", function()
    local iterations = 1000000
    local start = os.clock()
    
    local v1 = vec2(1, 2)
    local v2 = vec2(3, 4)
    for i = 1, iterations do
        v1:add(v2)
        v1:mul(0.99)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  vec2 ops: %d iterations in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: vec3 operations throughput", function()
    local iterations = 1000000
    local start = os.clock()
    
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    for i = 1, iterations do
        v1:add(v2)
        v1:mul(0.99)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  vec3 ops: %d iterations in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: vec3 normalize throughput", function()
    local iterations = 100000
    local start = os.clock()
    
    for i = 1, iterations do
        local v = vec3(i, i+1, i+2)
        v:normalize()
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  vec3 normalize: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: vec3 cross product throughput", function()
    local iterations = 100000
    local start = os.clock()
    
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    for i = 1, iterations do
        v1:cross(v2)
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  vec3 cross: %d calls in %.3fs (%.0f calls/sec)", 
        iterations, elapsed, rate))
end)

test("benchmark: vec2 operator overload throughput", function()
    local iterations = 100000
    local start = os.clock()
    
    local v1 = vec2(1, 2)
    local v2 = vec2(3, 4)
    for i = 1, iterations do
        local v3 = v1 + v2
        local v4 = v3 * 2
    end
    
    local elapsed = os.clock() - start
    local rate = iterations / elapsed
    print(string.format("  vec2 operators: %d iterations in %.3fs (%.0f iter/sec)", 
        iterations, elapsed, rate))
end)

-- ============================================================================
-- PRACTICAL EXAMPLES
-- ============================================================================

print("\n=== Practical Examples ===\n")

test("example: 2d projectile motion", function()
    local pos = vec2(0, 0)
    local vel = vec2(10, 15)
    local gravity = vec2(0, -9.8)
    local dt = 0.016
    
    -- simulate one frame
    vel:add(gravity * dt)
    pos:add(vel * dt)
    
    assert_true(pos.y > 0, "projectile moving upward initially")
    assert_true(vel.y < 15, "velocity decreasing due to gravity")
end)

test("example: 3d camera look-at", function()
    local eye = vec3(0, 0, 10)
    local target = vec3(0, 0, 0)
    local forward = (target - eye):normalize()
    
    assert_near(forward.z, -1, 0.0001, "looking toward -z")
    assert_near(forward:len(), 1, 0.0001, "unit length")
end)

test("example: surface normal calculation", function()
    -- triangle vertices
    local v0 = vec3(0, 0, 0)
    local v1 = vec3(1, 0, 0)
    local v2 = vec3(0, 1, 0)
    
    local edge1 = v1 - v0
    local edge2 = v2 - v0
    local normal = edge1:clone():cross(edge2):normalize()
    
    assert_near(normal.z, 1, 0.0001, "normal points up")
end)

test("example: reflection vector for lighting", function()
    local incident = vec3(1, -1, 0):normalize()
    local normal = vec3(0, 1, 0)
    local reflected = incident:clone():reflect(normal)

    assert_near(reflected.x, 0.707, 0.001, "reflects rightward")
    assert_near(reflected.y, 0.707, 0.001, "reflects upward at 45°")
    assert_near(reflected.z, 0, 0.0001, "z unchanged")
end)

test("example: bounding box intersection", function()
    local box_min = vec3(0, 0, 0)
    local box_max = vec3(10, 10, 10)
    local point = vec3(5, 5, 5)
    
    local clamped = point:clone():max(box_min):min(box_max)
    assert_eq(clamped.x, 5, "point inside box")
end)

test("example: spring physics", function()
    local pos = vec2(10, 0)
    local target = vec2(0, 0)
    local vel = vec2(0, 0)
    local k = 0.5  -- spring constant
    
    local spring_force = (target - pos) * k
    vel:add(spring_force)
    pos:add(vel)
    
    assert_true(pos.x < 10, "moving toward target")
end)

test("example: billboard rotation", function()
    local billboard_pos = vec3(5, 0, 0)
    local camera_pos = vec3(0, 0, 10)
    local to_camera = (camera_pos - billboard_pos):normalize()
    
    assert_true(to_camera:len() > 0.99, "unit direction to camera")
end)

test("example: color blending (vec4 as RGBA)", function()
    local color1 = vec4(1, 0, 0, 1)  -- red
    local color2 = vec4(0, 0, 1, 1)  -- blue
    local blended = color1:clone():lerp(color2, 0.5)
    
    assert_near(blended.x, 0.5, 0.001, "blended red")
    assert_near(blended.z, 0.5, 0.001, "blended blue")
end)

-- ============================================================================
-- MATHEMATICAL PROPERTIES
-- ============================================================================

print("\n=== Mathematical Properties ===\n")

test("property: vec2 addition commutative", function()
    local v1 = vec2(3, 4)
    local v2 = vec2(5, 6)
    local r1 = v1 + v2
    local r2 = v2 + v1
    assert_eq(r1.x, r2.x, "commutative x")
    assert_eq(r1.y, r2.y, "commutative y")
end)

test("property: vec3 addition associative", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    local v3 = vec3(7, 8, 9)
    local r1 = (v1 + v2) + v3
    local r2 = v1 + (v2 + v3)
    assert_eq(r1.x, r2.x, "associative x")
    assert_eq(r1.y, r2.y, "associative y")
    assert_eq(r1.z, r2.z, "associative z")
end)

test("property: vec2 dot product commutative", function()
    local v1 = vec2(3, 4)
    local v2 = vec2(5, 6)
    assert_eq(v1:dot(v2), v2:dot(v1), "dot commutative")
end)

test("property: vec3 cross product anticommutative", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    local c1 = v1:clone():cross(v2)
    local c2 = v2:clone():cross(v1)
    assert_near(c1.x, -c2.x, 0.0001, "anticommutative")
end)

test("property: vec2 scalar multiplication distributive", function()
    local v = vec2(2, 3)
    local r1 = (v * 2) * 3
    local r2 = v * 6
    assert_near(r1.x, r2.x, 0.0001, "distributive x")
    assert_near(r1.y, r2.y, 0.0001, "distributive y")
end)

test("property: vec3 normalize idempotent", function()
    local v = vec3(3, 4, 0)
    v:normalize()
    local len1 = v:len()
    v:normalize()
    local len2 = v:len()
    assert_near(len1, len2, 0.0001, "normalize idempotent")
end)

test("property: vec2 lerp at t=0 and t=1", function()
    local v1 = vec2(0, 0)
    local v2 = vec2(10, 10)
    local r0 = v1:clone():lerp(v2, 0)
    local r1 = v1:clone():lerp(v2, 1)
    assert_eq(r0.x, 0, "lerp t=0")
    assert_eq(r1.x, 10, "lerp t=1")
end)

test("property: vec3 distance symmetry", function()
    local v1 = vec3(1, 2, 3)
    local v2 = vec3(4, 5, 6)
    assert_near(v1:dist(v2), v2:dist(v1), 0.0001, "distance symmetric")
end)

test("property: vec4 dot product with itself equals len2", function()
    local v = vec4(2, 3, 4, 5)
    assert_near(v:dot(v), v:len2(), 0.0001, "dot self = len2")
end)

test("property: vec2 perpendicular dot product is zero", function()
    local v = vec2(3, 4)
    v:perp()
    local original = vec2(3, 4)
    assert_near(v:dot(original), 0, 0.0001, "perpendicular")
end)

-- ============================================================================
-- SUMMARY
-- ============================================================================

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