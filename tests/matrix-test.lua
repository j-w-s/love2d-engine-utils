local matrix = require("matrix")
local mat2, mat3, mat4 = matrix.mat2, matrix.mat3, matrix.mat4

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
    tolerance = tolerance or 0.000001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %s (±%s), got %s (diff: %s)", 
            msg or "assertion failed", tostring(expected), tostring(tolerance), tostring(actual), tostring(math.abs(actual - expected))))
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

local function assert_mat2_eq(m, m00, m01, m10, m11, tolerance, msg)
    tolerance = tolerance or 0.000001
    assert_near(m.m[0], m00, tolerance, (msg or "mat2") .. " [0,0]")
    assert_near(m.m[1], m01, tolerance, (msg or "mat2") .. " [0,1]")
    assert_near(m.m[2], m10, tolerance, (msg or "mat2") .. " [1,0]")
    assert_near(m.m[3], m11, tolerance, (msg or "mat2") .. " [1,1]")
end

local function assert_mat3_eq(m, m00, m01, m02, m10, m11, m12, m20, m21, m22, tolerance, msg)
    tolerance = tolerance or 0.000001
    assert_near(m.m[0], m00, tolerance, (msg or "mat3") .. " [0,0]")
    assert_near(m.m[1], m01, tolerance, (msg or "mat3") .. " [0,1]")
    assert_near(m.m[2], m02, tolerance, (msg or "mat3") .. " [0,2]")
    assert_near(m.m[3], m10, tolerance, (msg or "mat3") .. " [1,0]")
    assert_near(m.m[4], m11, tolerance, (msg or "mat3") .. " [1,1]")
    assert_near(m.m[5], m12, tolerance, (msg or "mat3") .. " [1,2]")
    assert_near(m.m[6], m20, tolerance, (msg or "mat3") .. " [2,0]")
    assert_near(m.m[7], m21, tolerance, (msg or "mat3") .. " [2,1]")
    assert_near(m.m[8], m22, tolerance, (msg or "mat3") .. " [2,2]")
end

local function assert_mat4_near(m, values, tolerance, msg)
    tolerance = tolerance or 0.000001
    for i = 0, 15 do
        assert_near(m.m[i], values[i + 1], tolerance, string.format("%s [%d]", msg or "mat4", i))
    end
end

-- ============================================================================
-- MAT2 TESTS
-- ============================================================================

print("\n=== MAT2: Construction and Basic Operations ===\n")

test("mat2: construction with values", function()
    local m = mat2(1, 2, 3, 4)
    assert_eq(m.m[0], 1, "m[0,0]")
    assert_eq(m.m[1], 2, "m[0,1]")
    assert_eq(m.m[2], 3, "m[1,0]")
    assert_eq(m.m[3], 4, "m[1,1]")
end)

test("mat2: set values", function()
    local m = mat2()
    m:set(5, 6, 7, 8)
    assert_mat2_eq(m, 5, 6, 7, 8)
end)

test("mat2: copy", function()
    local m1 = mat2(1, 2, 3, 4)
    local m2 = mat2()
    m2:copy(m1)
    assert_mat2_eq(m2, 1, 2, 3, 4)
end)

test("mat2: clone", function()
    local m1 = mat2(1, 2, 3, 4)
    local m2 = m1:clone()
    assert_mat2_eq(m2, 1, 2, 3, 4)
    -- ensure they're different objects
    m2:set(9, 9, 9, 9)
    assert_eq(m1.m[0], 1, "original unchanged")
end)

test("mat2: identity", function()
    local m = mat2():identity()
    assert_mat2_eq(m, 1, 0, 0, 1)
end)

test("mat2: zero", function()
    local m = mat2(1, 2, 3, 4):zero()
    assert_mat2_eq(m, 0, 0, 0, 0)
end)

test("mat2: transpose", function()
    local m = mat2(1, 2, 3, 4):transpose()
    assert_mat2_eq(m, 1, 3, 2, 4)
end)

test("mat2: transpose twice returns original", function()
    local m = mat2(1, 2, 3, 4)
    m:transpose():transpose()
    assert_mat2_eq(m, 1, 2, 3, 4)
end)

print("\n=== MAT2: Determinant and Inverse ===\n")

test("mat2: determinant of identity", function()
    local m = mat2():identity()
    assert_eq(m:det(), 1, "det(I) = 1")
end)

test("mat2: determinant calculation", function()
    local m = mat2(1, 2, 3, 4)
    -- det = 1*4 - 2*3 = 4 - 6 = -2
    assert_near(m:det(), -2, 0.000001)
end)

test("mat2: determinant of singular matrix", function()
    local m = mat2(1, 2, 2, 4)
    assert_near(m:det(), 0, 0.000001, "singular matrix has det = 0")
end)

test("mat2: inverse of identity", function()
    local m = mat2():identity():invert()
    assert_mat2_eq(m, 1, 0, 0, 1)
end)

test("mat2: inverse calculation", function()
    local m = mat2(1, 2, 3, 4):invert()
    -- inv = (1/det) * [[4, -2], [-3, 1]] where det = -2
    assert_mat2_eq(m, -2, 1, 1.5, -0.5, 0.000001)
end)

test("mat2: inverse then multiply gives identity", function()
    local m1 = mat2(1, 2, 3, 4)
    local m2 = m1:clone():invert()
    m1:mul(m2)
    assert_mat2_eq(m1, 1, 0, 0, 1, 0.000001, "M * M^-1 = I")
end)

test("mat2: inverse of singular matrix returns identity", function()
    local m = mat2(1, 2, 2, 4):invert()
    assert_mat2_eq(m, 1, 0, 0, 1, 0.000001, "singular matrix inverts to identity")
end)

print("\n=== MAT2: Arithmetic Operations ===\n")

test("mat2: scalar multiplication", function()
    local m = mat2(1, 2, 3, 4):mul_scalar(2)
    assert_mat2_eq(m, 2, 4, 6, 8)
end)

test("mat2: scalar multiplication by zero", function()
    local m = mat2(1, 2, 3, 4):mul_scalar(0)
    assert_mat2_eq(m, 0, 0, 0, 0)
end)

test("mat2: scalar multiplication by negative", function()
    local m = mat2(1, 2, 3, 4):mul_scalar(-1)
    assert_mat2_eq(m, -1, -2, -3, -4)
end)

test("mat2: matrix multiplication", function()
    local m1 = mat2(1, 2, 3, 4)
    local m2 = mat2(5, 6, 7, 8)
    m1:mul(m2)
    -- [[1,2],[3,4]] * [[5,6],[7,8]] = [[19,22],[43,50]]
    assert_mat2_eq(m1, 19, 22, 43, 50)
end)

test("mat2: multiply by identity", function()
    local m = mat2(1, 2, 3, 4)
    local id = mat2():identity()
    m:mul(id)
    assert_mat2_eq(m, 1, 2, 3, 4)
end)

test("mat2: addition", function()
    local m1 = mat2(1, 2, 3, 4)
    local m2 = mat2(5, 6, 7, 8)
    m1:add(m2)
    assert_mat2_eq(m1, 6, 8, 10, 12)
end)

test("mat2: subtraction", function()
    local m1 = mat2(5, 6, 7, 8)
    local m2 = mat2(1, 2, 3, 4)
    m1:sub(m2)
    assert_mat2_eq(m1, 4, 4, 4, 4)
end)

print("\n=== MAT2: Transformations ===\n")

test("mat2: rotation matrix (0 radians)", function()
    local m = mat2():rotation(0)
    assert_mat2_eq(m, 1, 0, 0, 1, 0.000001)
end)

test("mat2: rotation matrix (90 degrees)", function()
    local m = mat2():rotation(math.pi / 2)
    assert_mat2_eq(m, 0, -1, 1, 0, 0.000001)
end)

test("mat2: rotation matrix (180 degrees)", function()
    local m = mat2():rotation(math.pi)
    assert_mat2_eq(m, -1, 0, 0, -1, 0.000001)
end)

test("mat2: rotation matrix (360 degrees)", function()
    local m = mat2():rotation(2 * math.pi)
    assert_mat2_eq(m, 1, 0, 0, 1, 0.000001)
end)

test("mat2: scale matrix (uniform)", function()
    local m = mat2():scale(2)
    assert_mat2_eq(m, 2, 0, 0, 2)
end)

test("mat2: scale matrix (non-uniform)", function()
    local m = mat2():scale(2, 3)
    assert_mat2_eq(m, 2, 0, 0, 3)
end)

test("mat2: scale matrix (zero)", function()
    local m = mat2():scale(0, 0)
    assert_mat2_eq(m, 0, 0, 0, 0)
end)

test("mat2: scale matrix (negative)", function()
    local m = mat2():scale(-1, 2)
    assert_mat2_eq(m, -1, 0, 0, 2)
end)

-- ============================================================================
-- MAT3 TESTS
-- ============================================================================

print("\n=== MAT3: Construction and Basic Operations ===\n")

test("mat3: construction with values", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    for i = 0, 8 do
        assert_eq(m.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat3: set values", function()
    local m = mat3()
    m:set(1, 2, 3, 4, 5, 6, 7, 8, 9)
    for i = 0, 8 do
        assert_eq(m.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat3: copy", function()
    local m1 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    local m2 = mat3()
    m2:copy(m1)
    for i = 0, 8 do
        assert_eq(m2.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat3: clone", function()
    local m1 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    local m2 = m1:clone()
    for i = 0, 8 do
        assert_eq(m2.m[i], i + 1, "m[" .. i .. "]")
    end
    m2:zero()
    assert_eq(m1.m[0], 1, "original unchanged")
end)

test("mat3: identity", function()
    local m = mat3():identity()
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end)

test("mat3: zero", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9):zero()
    for i = 0, 8 do
        assert_eq(m.m[i], 0, "m[" .. i .. "]")
    end
end)

test("mat3: transpose", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9):transpose()
    assert_mat3_eq(m, 1, 4, 7, 2, 5, 8, 3, 6, 9)
end)

test("mat3: transpose twice returns original", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    m:transpose():transpose()
    assert_mat3_eq(m, 1, 2, 3, 4, 5, 6, 7, 8, 9)
end)

print("\n=== MAT3: Determinant and Inverse ===\n")

test("mat3: determinant of identity", function()
    local m = mat3():identity()
    assert_near(m:det(), 1, 0.000001)
end)

test("mat3: determinant calculation", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    -- this matrix is singular (rows are linearly dependent)
    assert_near(m:det(), 0, 0.000001)
end)

test("mat3: determinant of rotation matrix", function()
    local m = mat3():rotation_z(math.pi / 4)
    assert_near(m:det(), 1, 0.000001, "rotation preserves det = 1")
end)

test("mat3: inverse of identity", function()
    local m = mat3():identity():invert()
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end)

test("mat3: inverse of rotation", function()
    local m = mat3():rotation_z(math.pi / 4)
    local det_before = m:det()
    m:invert()
    local det_after = m:det()
    assert_near(det_after, det_before, 0.000001, "inverse preserves determinant magnitude")
end)

test("mat3: inverse then multiply gives identity", function()
    local m1 = mat3(2, 0, 1, 1, 1, 0, 0, 1, 1)
    local m2 = m1:clone():invert()
    m1:mul(m2)
    assert_mat3_eq(m1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001, "M * M^-1 = I")
end)

test("mat3: inverse of singular matrix returns identity", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9):invert()
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001)
end)

print("\n=== MAT3: Arithmetic Operations ===\n")

test("mat3: scalar multiplication", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9):mul_scalar(2)
    assert_mat3_eq(m, 2, 4, 6, 8, 10, 12, 14, 16, 18)
end)

test("mat3: matrix multiplication", function()
    local m1 = mat3():identity()
    local m2 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    m1:mul(m2)
    assert_mat3_eq(m1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0.000001, "I * M = M")
end)

test("mat3: addition", function()
    local m1 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    local m2 = mat3(9, 8, 7, 6, 5, 4, 3, 2, 1)
    m1:add(m2)
    assert_mat3_eq(m1, 10, 10, 10, 10, 10, 10, 10, 10, 10)
end)

test("mat3: subtraction", function()
    local m1 = mat3(10, 10, 10, 10, 10, 10, 10, 10, 10)
    local m2 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    m1:sub(m2)
    assert_mat3_eq(m1, 9, 8, 7, 6, 5, 4, 3, 2, 1)
end)

print("\n=== MAT3: Rotation Matrices ===\n")

test("mat3: rotation_x (0 radians)", function()
    local m = mat3():rotation_x(0)
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001)
end)

test("mat3: rotation_x (90 degrees)", function()
    local m = mat3():rotation_x(math.pi / 2)
    assert_mat3_eq(m, 1, 0, 0, 0, 0, -1, 0, 1, 0, 0.000001)
end)

test("mat3: rotation_y (90 degrees)", function()
    local m = mat3():rotation_y(math.pi / 2)
    assert_mat3_eq(m, 0, 0, 1, 0, 1, 0, -1, 0, 0, 0.000001)
end)

test("mat3: rotation_z (90 degrees)", function()
    local m = mat3():rotation_z(math.pi / 2)
    assert_mat3_eq(m, 0, -1, 0, 1, 0, 0, 0, 0, 1, 0.000001)
end)

test("mat3: rotation_euler (0, 0, 0)", function()
    local m = mat3():rotation_euler(0, 0, 0)
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001)
end)

test("mat3: rotation_euler matches individual rotations", function()
    local angle_x, angle_y, angle_z = 0.1, 0.2, 0.3
    local m_euler = mat3():rotation_euler(angle_x, angle_y, angle_z)
    
    -- compute separately and multiply
    -- order: R = Rz * Ry * Rx
    -- m_combined:mul(my) -> Rz * Ry; then, :mul(mx) -> Rz * Ry * Rx.
    local m_combined = mat3():rotation_z(angle_z)
    local my = mat3():rotation_y(angle_y)
    local mx = mat3():rotation_x(angle_x)
    
    m_combined:mul(my):mul(mx)
    
    for i = 0, 8 do
        assert_near(m_euler.m[i], m_combined.m[i], 0.000001, "euler match at [" .. i .. "]")
    end
end)

print("\n=== MAT3: Scale and Translation ===\n")

test("mat3: scale (uniform)", function()
    local m = mat3():scale(2)
    assert_mat3_eq(m, 2, 0, 0, 0, 2, 0, 0, 0, 2)
end)

test("mat3: scale (non-uniform)", function()
    local m = mat3():scale(2, 3, 4)
    assert_mat3_eq(m, 2, 0, 0, 0, 3, 0, 0, 0, 4)
end)

test("mat3: translation (2D homogeneous)", function()
    local m = mat3():translation(5, 7)
    assert_mat3_eq(m, 1, 0, 5, 0, 1, 7, 0, 0, 1)
end)

test("mat3: translation with zero", function()
    local m = mat3():translation(0, 0)
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end)

-- ============================================================================
-- MAT4 TESTS
-- ============================================================================

print("\n=== MAT4: Construction and Basic Operations ===\n")

test("mat4: construction with values", function()
    local m = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    for i = 0, 15 do
        assert_eq(m.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat4: set values", function()
    local m = mat4()
    m:set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    for i = 0, 15 do
        assert_eq(m.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat4: copy", function()
    local m1 = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    local m2 = mat4()
    m2:copy(m1)
    for i = 0, 15 do
        assert_eq(m2.m[i], i + 1, "m[" .. i .. "]")
    end
end)

test("mat4: clone", function()
    local m1 = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    local m2 = m1:clone()
    for i = 0, 15 do
        assert_eq(m2.m[i], i + 1, "m[" .. i .. "]")
    end
    m2:zero()
    assert_eq(m1.m[0], 1, "original unchanged")
end)

test("mat4: identity", function()
    local m = mat4():identity()
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: zero", function()
    local m = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16):zero()
    for i = 0, 15 do
        assert_eq(m.m[i], 0, "m[" .. i .. "]")
    end
end)

test("mat4: transpose", function()
    local m = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16):transpose()
    local expected = {1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: transpose twice returns original", function()
    local m = mat4(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    m:transpose():transpose()
    local expected = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
    assert_mat4_near(m, expected, 0.000001)
end)

print("\n=== MAT4: Determinant and Inverse ===\n")

test("mat4: determinant of identity", function()
    local m = mat4():identity()
    assert_near(m:det(), 1, 0.000001)
end)

test("mat4: determinant o    for i = 0, 8 do
f zero matrix", function()
    local m = mat4():zero()
    assert_near(m:det(), 0, 0.000001)
end)

test("mat4: inverse of identity", function()
    local m = mat4():identity():invert()
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: inverse then multiply gives identity", function()
    local m1 = mat4():rotation_z(0.5):translation(1, 2, 3):scale(2, 3, 4)
    local m2 = m1:clone():invert()
    m1:mul(m2)
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m1, expected, 0.00001, "M * M^-1 = I")
end)

test("mat4: inverse of singular matrix returns identity", function()
    local m = mat4():zero():invert()
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

print("\n=== MAT4: Arithmetic Operations ===\n")

test("mat4: scalar multiplication", function()
    local m = mat4():identity():mul_scalar(2)
    local expected = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: matrix multiplication with identity", function()
    local m1 = mat4():translation(1, 2, 3)
    local m2 = mat4():identity()
    m1:mul(m2)
    assert_near(m1.m[3], 1, 0.000001, "translation x")
    assert_near(m1.m[7], 2, 0.000001, "translation y")
    assert_near(m1.m[11], 3, 0.000001, "translation z")
end)

test("mat4: addition", function()
    local m1 = mat4():identity()
    local m2 = mat4():identity()
    m1:add(m2)
    local expected = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2}
    assert_mat4_near(m1, expected, 0.000001)
end)

test("mat4: subtraction", function()
    local m1 = mat4():identity():mul_scalar(3)
    local m2 = mat4():identity()
    m1:sub(m2)
    local expected = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2}
    assert_mat4_near(m1, expected, 0.000001)
end)

print("\n=== MAT4: Rotation Matrices ===\n")

test("mat4: rotation_x (0 radians)", function()
    local m = mat4():rotation_x(0)
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_x (90 degrees)", function()
    local m = mat4():rotation_x(math.pi / 2)
    local expected = {1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_y (90 degrees)", function()
    local m = mat4():rotation_y(math.pi / 2)
    local expected = {0, 0, 1, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_z (90 degrees)", function()
    local m = mat4():rotation_z(math.pi / 2)
    local expected = {0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_euler (0, 0, 0)", function()
    local m = mat4():rotation_euler(0, 0, 0)
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_euler determinant is 1", function()
    local m = mat4():rotation_euler(0.5, 0.7, 0.3)
    assert_near(m:det(), 1, 0.000001, "rotation preserves volume")
end)

test("mat4: rotation_axis (z-axis, 90 degrees)", function()
    local axis = {x = 0, y = 0, z = 1}
    local m = mat4():rotation_axis(axis, math.pi / 2)
    local expected = {0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: rotation_axis (arbitrary axis)", function()
    local axis = {x = 1, y = 1, z = 0}  -- not normalized
    local m = mat4():rotation_axis(axis, math.pi / 4)
    -- determinant should be 1
    assert_near(m:det(), 1, 0.000001, "arbitrary axis rotation")
end)

test("mat4: rotation_axis (zero angle)", function()
    local axis = {x = 1, y = 0, z = 0}
    local m = mat4():rotation_axis(axis, 0)
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

print("\n=== MAT4: Scale and Translation ===\n")

test("mat4: scale (uniform)", function()
    local m = mat4():scale(2)
    local expected = {2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: scale (non-uniform)", function()
    local m = mat4():scale(2, 3, 4)
    local expected = {2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: scale (zero)", function()
    local m = mat4():scale(0, 0, 0)
    assert_near(m:det(), 0, 0.000001, "zero scale has det = 0")
end)

test("mat4: scale (negative)", function()
    local m = mat4():scale(-1, 1, 1)
    assert_near(m:det(), -1, 0.000001, "negative scale flips determinant")
end)

test("mat4: translation", function()
    local m = mat4():translation(5, 7, 9)
    assert_near(m.m[3], 5, 0.000001, "translation x")
    assert_near(m.m[7], 7, 0.000001, "translation y")
    assert_near(m.m[11], 9, 0.000001, "translation z")
end)

test("mat4: translation (zero)", function()
    local m = mat4():translation(0, 0, 0)
    local expected = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    assert_mat4_near(m, expected, 0.000001)
end)

test("mat4: translation (2D, z defaults to 0)", function()
    local m = mat4():translation(3, 4)
    assert_near(m.m[3], 3, 0.000001, "translation x")
    assert_near(m.m[7], 4, 0.000001, "translation y")
    assert_near(m.m[11], 0, 0.000001, "translation z defaults to 0")
end)

print("\n=== MAT4: Projection Matrices ===\n")

test("mat4: perspective projection", function()
    local m = mat4():perspective(math.pi / 2, 16 / 9, 0.1, 100)
    assert_not_nan(m.m[0], "m[0] not NaN")
    assert_not_nan(m.m[5], "m[5] not NaN")
    assert_not_nan(m.m[10], "m[10] not NaN")
    assert_near(m.m[14], -1, 0.000001, "perspective w component")
end)

test("mat4: perspective projection (square aspect)", function()
    local m = mat4():perspective(math.pi / 4, 1.0, 1.0, 10.0)
    assert_not_nan(m:det(), "determinant valid")
end)

test("mat4: orthographic projection", function()
    local m = mat4():orthographic(-10, 10, -10, 10, 0.1, 100)
    assert_not_nan(m.m[0], "m[0] not NaN")
    assert_not_nan(m.m[5], "m[5] not NaN")
    assert_not_nan(m.m[10], "m[10] not NaN")
    assert_near(m.m[15], 1, 0.000001, "orthographic w component")
end)

test("mat4: orthographic projection (unit cube)", function()
    local m = mat4():orthographic(-1, 1, -1, 1, -1, 1)
    assert_near(m.m[0], 1, 0.000001, "x scale")
    assert_near(m.m[5], 1, 0.000001, "y scale")
end)

print("\n=== MAT4: Look-At Matrix ===\n")

test("mat4: look_at (looking down -z)", function()
    local eye = {x = 0, y = 0, z = 5}
    local target = {x = 0, y = 0, z = 0}
    local up = {x = 0, y = 1, z = 0}
    local m = mat4():look_at(eye, target, up)
    assert_not_nan(m:det(), "look_at determinant valid")
end)

test("mat4: look_at (looking from different position)", function()
    local eye = {x = 5, y = 5, z = 5}
    local target = {x = 0, y = 0, z = 0}
    local up = {x = 0, y = 1, z = 0}
    local m = mat4():look_at(eye, target, up)
    assert_not_nan(m.m[0], "look_at valid")
end)

test("mat4: look_at (eye equals target)", function()
    local eye = {x = 0, y = 0, z = 0}
    local target = {x = 0, y = 0, z = 0}
    local up = {x = 0, y = 1, z = 0}
    local m = mat4():look_at(eye, target, up)
    assert_true(true, "handles degenerate case")
end)

test("mat4: look_at determinant is 1", function()
    local eye = {x = 10, y = 5, z = 15}
    local target = {x = 0, y = 0, z = 0}
    local up = {x = 0, y = 1, z = 0}
    local m = mat4():look_at(eye, target, up)
    assert_near(m:det(), 1, 0.000001, "look_at is rotation + translation")
end)

print("\n=== MAT4: Vector Transformations ===\n")

test("mat4: transform_point (identity)", function()
    local m = mat4():identity()
    local v = {x = 1, y = 2, z = 3}
    m:transform_point(v)
    assert_near(v.x, 1, 0.000001)
    assert_near(v.y, 2, 0.000001)
    assert_near(v.z, 3, 0.000001)
end)

test("mat4: transform_point (translation)", function()
    local m = mat4():translation(5, 10, 15)
    local v = {x = 1, y = 2, z = 3}
    m:transform_point(v)
    assert_near(v.x, 6, 0.000001, "x translated")
    assert_near(v.y, 12, 0.000001, "y translated")
    assert_near(v.z, 18, 0.000001, "z translated")
end)

test("mat4: transform_point (scale)", function()
    local m = mat4():scale(2, 3, 4)
    local v = {x = 1, y = 2, z = 3}
    m:transform_point(v)
    assert_near(v.x, 2, 0.000001, "x scaled")
    assert_near(v.y, 6, 0.000001, "y scaled")
    assert_near(v.z, 12, 0.000001, "z scaled")
end)

test("mat4: transform_point (rotation 90° around z)", function()
    local m = mat4():rotation_z(math.pi / 2)
    local v = {x = 1, y = 0, z = 0}
    m:transform_point(v)
    assert_near(v.x, 0, 0.000001, "rotated to y-axis")
    assert_near(v.y, 1, 0.000001, "rotated to y-axis")
    assert_near(v.z, 0, 0.000001, "z unchanged")
end)

test("mat4: transform_direction (identity)", function()
    local m = mat4():identity()
    local v = {x = 1, y = 2, z = 3}
    m:transform_direction(v)
    assert_near(v.x, 1, 0.000001)
    assert_near(v.y, 2, 0.000001)
    assert_near(v.z, 3, 0.000001)
end)

test("mat4: transform_direction (translation ignored)", function()
    local m = mat4():translation(100, 200, 300)
    local v = {x = 1, y = 2, z = 3}
    m:transform_direction(v)
    assert_near(v.x, 1, 0.000001, "translation ignored for directions")
    assert_near(v.y, 2, 0.000001)
    assert_near(v.z, 3, 0.000001)
end)

test("mat4: transform_direction (rotation)", function()
    local m = mat4():rotation_z(math.pi / 2)
    local v = {x = 1, y = 0, z = 0}
    m:transform_direction(v)
    assert_near(v.x, 0, 0.000001, "rotated to y-axis")
    assert_near(v.y, 1, 0.000001)
    assert_near(v.z, 0, 0.000001)
end)

test("mat4: transform_direction (scale)", function()
    local m = mat4():scale(2, 3, 4)
    local v = {x = 1, y = 1, z = 1}
    m:transform_direction(v)
    assert_near(v.x, 2, 0.000001, "direction scaled")
    assert_near(v.y, 3, 0.000001)
    assert_near(v.z, 4, 0.000001)
end)

print("\n=== MAT4: Extraction Methods ===\n")

test("mat4: get_position from translation matrix", function()
    local m = mat4():translation(5, 7, 9)
    local x, y, z = m:get_position()
    assert_near(x, 5, 0.000001)
    assert_near(y, 7, 0.000001)
    assert_near(z, 9, 0.000001)
end)

test("mat4: get_position from identity", function()
    local m = mat4():identity()
    local x, y, z = m:get_position()
    assert_near(x, 0, 0.000001)
    assert_near(y, 0, 0.000001)
    assert_near(z, 0, 0.000001)
end)

test("mat4: get_scale from scale matrix", function()
    local m = mat4():scale(2, 3, 4)
    local sx, sy, sz = m:get_scale()
    assert_near(sx, 2, 0.000001)
    assert_near(sy, 3, 0.000001)
    assert_near(sz, 4, 0.000001)
end)

test("mat4: get_scale from identity", function()
    local m = mat4():identity()
    local sx, sy, sz = m:get_scale()
    assert_near(sx, 1, 0.000001)
    assert_near(sy, 1, 0.000001)
    assert_near(sz, 1, 0.000001)
end)

test("mat4: get_scale from rotation (should be 1)", function()
    local m = mat4():rotation_z(math.pi / 4)
    local sx, sy, sz = m:get_scale()
    assert_near(sx, 1, 0.000001, "rotation preserves scale")
    assert_near(sy, 1, 0.000001)
    assert_near(sz, 1, 0.000001)
end)

test("mat4: get_scale from combined transform", function()
    local m = mat4():translation(1, 2, 3):rotation_z(0.5):scale(2, 3, 4)
    local sx, sy, sz = m:get_scale()
    assert_near(sx, 2, 0.000001, "extract scale from combined")
    assert_near(sy, 3, 0.000001)
    assert_near(sz, 4, 0.000001)
end)

-- ============================================================================
-- EDGE CASES AND STRESS TESTS
-- ============================================================================

print("\n=== Edge Cases ===\n")

test("edge: mat2 with very small values", function()
    local m = mat2(1e-10, 2e-10, 3e-10, 4e-10)
    assert_not_nan(m:det(), "handles small values")
end)

test("edge: mat2 with very large values", function()
    local m = mat2(1e10, 2e10, 3e10, 4e10)
    assert_not_nan(m:det(), "handles large values")
end)

test("edge: mat2 determinant near zero", function()
    local m = mat2(1, 2, 2, 4.0000001)
    local det = m:det()
    assert_true(math.abs(det) < 0.001, "nearly singular")
end)

test("edge: mat3 with NaN detection", function()
    local m = mat3():identity()
    for i = 0, 8 do
        assert_not_nan(m.m[i], "no NaN in identity")
    end
end)

test("edge: mat3 rotation around multiple axes", function()
    local m = mat3():rotation_x(1.5):mul(mat3():rotation_y(0.7)):mul(mat3():rotation_z(2.1))
    assert_near(m:det(), 1, 0.000001, "combined rotations preserve det")
end)

test("edge: mat4 with extreme FOV", function()
    local m = mat4():perspective(math.pi * 0.99, 1.0, 0.1, 1000)
    assert_not_nan(m.m[0], "handles extreme FOV")
end)

test("edge: mat4 with near = far (degenerate)", function()
    local m = mat4():perspective(math.pi / 4, 1.0, 10.0, 10.0)
    assert_true(true, "handles near = far")
end)

test("edge: mat4 orthographic with inverted bounds", function()
    local m = mat4():orthographic(10, -10, 10, -10, 1, 100)
    assert_not_nan(m:det(), "handles inverted bounds")
end)

test("edge: mat4 look_at with parallel eye-target-up", function()
    local eye = {x = 0, y = 1, z = 0}
    local target = {x = 0, y = 0, z = 0}
    local up = {x = 0, y = 1, z = 0}  -- parallel to view direction
    local m = mat4():look_at(eye, target, up)
    assert_true(true, "handles degenerate up vector")
end)

test("edge: mat4 transform_point with w = 0", function()
    -- create a projection matrix that might produce w = 0
    local m = mat4():perspective(math.pi / 4, 1.0, 0.1, 100)
    local v = {x = 0, y = 0, z = 0}
    m:transform_point(v)
    assert_not_nan(v.x, "handles w = 0 gracefully")
end)

test("edge: mat2 rotation by 2π", function()
    local m1 = mat2():rotation(0)
    local m2 = mat2():rotation(2 * math.pi)
    for i = 0, 3 do
        assert_near(m1.m[i], m2.m[i], 0.000001, "2π rotation = identity")
    end
end)

test("edge: mat3 scale by zero then invert", function()
    local m = mat3():scale(0, 0, 0):invert()
    -- should return identity (singular matrix)
    assert_mat3_eq(m, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001)
end)

test("edge: mat4 chained operations", function()
    local m = mat4()
        :identity()
        :translation(1, 2, 3)
        :rotation_z(0.5)
        :scale(2, 2, 2)
        :mul(mat4():identity())
    assert_not_nan(m:det(), "chained operations valid")
end)

-- ============================================================================
-- MATHEMATICAL PROPERTIES
-- ============================================================================

print("\n=== Mathematical Properties ===\n")

test("property: mat2 (AB)^T = B^T A^T", function()
    local a = mat2(1, 2, 3, 4)
    local b = mat2(5, 6, 7, 8)
    
    local ab = a:clone():mul(b):transpose()
    local bt_at = b:clone():transpose():mul(a:clone():transpose())
    
    for i = 0, 3 do
        assert_near(ab.m[i], bt_at.m[i], 0.000001, "(AB)^T = B^T A^T")
    end
end)

test("property: mat2 det(AB) = det(A) * det(B)", function()
    local a = mat2(1, 2, 3, 4)
    local b = mat2(5, 6, 7, 8)
    
    local det_a = a:det()
    local det_b = b:det()
    local ab = a:clone():mul(b)
    local det_ab = ab:det()
    
    assert_near(det_ab, det_a * det_b, 0.000001, "det(AB) = det(A)det(B)")
end)

test("property: mat3 rotation matrix orthogonality", function()
    local m = mat3():rotation_z(0.7)
    local mt = m:clone():transpose()
    local mmt = m:clone():mul(mt)
    
    -- M * M^T should be identity for orthogonal matrices
    assert_mat3_eq(mmt, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.000001, "rotation is orthogonal")
end)

test("property: mat3 det(A^T) = det(A)", function()
    local m = mat3(1, 2, 3, 4, 5, 6, 7, 8, 10)
    local det1 = m:det()
    m:transpose()
    local det2 = m:det()
    assert_near(det1, det2, 0.000001, "det(A^T) = det(A)")
end)

test("property: mat4 rotation preserves length", function()
    local m = mat4():rotation_euler(0.3, 0.5, 0.7)
    local v = {x = 3, y = 4, z = 5}
    local len_before = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    
    m:transform_direction(v)
    local len_after = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    
    assert_near(len_before, len_after, 0.000001, "rotation preserves length")
end)

test("property: mat4 translation doesn't affect directions", function()
    local m = mat4():translation(100, 200, 300)
    local v = {x = 1, y = 2, z = 3}
    local len_before = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    
    m:transform_direction(v)
    local len_after = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    
    assert_near(len_before, len_after, 0.000001, "translation doesn't affect direction length")
    assert_near(v.x, 1, 0.000001, "direction unchanged")
end)

test("property: mat4 det(A^-1) = 1/det(A)", function()
    local m = mat4():rotation_z(0.5):translation(1, 2, 3):scale(2, 3, 4)
    local det_m = m:det()
    m:invert()
    local det_inv = m:det()
    
    assert_near(det_inv * det_m, 1, 0.000001, "det(A^-1) = 1/det(A)")
end)

-- ============================================================================
-- PERFORMANCE BENCHMARKS
-- ============================================================================

print("\n=== Performance Benchmarks ===\n")

test("benchmark: mat2 operations", function()
    local iterations = 100000
    local start = os.clock()
    
    local m1 = mat2(1, 2, 3, 4)
    local m2 = mat2(5, 6, 7, 8)
    
    for i = 1, iterations do
        m1:mul(m2)
        m1:transpose()
    end
    
    local elapsed = os.clock() - start
    print(string.format("  mat2: %d ops in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, iterations / elapsed))
end)

test("benchmark: mat3 operations", function()
    local iterations = 50000
    local start = os.clock()
    
    local m1 = mat3(1, 2, 3, 4, 5, 6, 7, 8, 9)
    local m2 = mat3(9, 8, 7, 6, 5, 4, 3, 2, 1)
    
    for i = 1, iterations do
        m1:mul(m2)
        m1:det()
    end
    
    local elapsed = os.clock() - start
    print(string.format("  mat3: %d ops in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, iterations / elapsed))
end)

test("benchmark: mat4 operations", function()
    local iterations = 25000
    local start = os.clock()
    
    local m1 = mat4():identity()
    local m2 = mat4():rotation_z(0.1)
    
    for i = 1, iterations do
        m1:mul(m2)
        m1:transpose()
    end
    
    local elapsed = os.clock() - start
    print(string.format("  mat4: %d ops in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, iterations / elapsed))
end)

test("benchmark: mat4 inverse", function()
    local iterations = 10000
    local start = os.clock()
    
    local m = mat4():rotation_z(0.5):translation(1, 2, 3):scale(2, 3, 4)
    
    for i = 1, iterations do
        m:clone():invert()
    end
    
    local elapsed = os.clock() - start
    print(string.format("  mat4 inverse: %d ops in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, iterations / elapsed))
end)

test("benchmark: mat4 vector transform", function()
    local iterations = 100000
    local start = os.clock()
    
    local m = mat4():rotation_euler(0.1, 0.2, 0.3):translation(1, 2, 3)
    local v = {x = 1, y = 2, z = 3}
    
    for i = 1, iterations do
        v.x, v.y, v.z = 1, 2, 3
        m:transform_point(v)
    end
    
    local elapsed = os.clock() - start
    print(string.format("  vector transform: %d ops in %.3fs (%.0f ops/sec)", 
        iterations, elapsed, iterations / elapsed))
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