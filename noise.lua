--- noise implementation with worley/cellular, value noise,
--- domain warping, blending utilities, and erosion helpers
--- optimized for luajit/lua 5.3+ with ieee 754 hex floats
--- @module noise

local bit = require("bit")
local band, bor, bxor, rshift, lshift, floor = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift, math.floor
local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max

local F2 = 0x1.76cf5d0b09954p-2   -- (sqrt(3) - 1) / 2
local G2 = 0x1.b0cb174df99c8p-3   -- (3 - sqrt(3)) / 6
local F3 = 0x1.5555555555555p-2   -- 1/3
local G3 = 0x1.5555555555555p-3   -- 1/6
local G2_2 = 0x1.b0cb174df99c8p-2 -- 2.0 * G2
local G3_2 = 0x1.5555555555555p-2 -- 2.0 * G3
local G3_3 = 0x1p0                -- 3.0 * G3 = 1.0
local F4 = 0x1.965fea53d6e3dp-2   -- (sqrt(5) - 1) / 4
local G4 = 0x1.4f8b588e368f1p-3   -- (5 - sqrt(5)) / 20
local G4_2 = 0x1.4f8b588e368f1p-2 -- 2.0 * G4
local G4_3 = 0x1.f6a0baf5a1796p-2 -- 3.0 * G4
local G4_4 = 0x1.3d70a3d70a3d7p-1 -- 4.0 * G4 - 1.0

-- gradient vectors for 2d/3d
local grad2 = {
    { 0x1p0, 0x1p0 }, { -0x1p0, 0x1p0 }, { 0x1p0, -0x1p0 }, { -0x1p0, -0x1p0 },
    { 0x1p0, 0x0p0 }, { -0x1p0, 0x0p0 }, { 0x1p0, 0x0p0 }, { -0x1p0, 0x0p0 },
    { 0x0p0, 0x1p0 }, { 0x0p0, -0x1p0 }, { 0x0p0, 0x1p0 }, { 0x0p0, -0x1p0 }
}

local grad3 = {
    { 0x1p0, 0x1p0, 0x0p0 }, { -0x1p0, 0x1p0, 0x0p0 }, { 0x1p0, -0x1p0, 0x0p0 }, { -0x1p0, -0x1p0, 0x0p0 },
    { 0x1p0, 0x0p0, 0x1p0 }, { -0x1p0, 0x0p0, 0x1p0 }, { 0x1p0, 0x0p0, -0x1p0 }, { -0x1p0, 0x0p0, -0x1p0 },
    { 0x0p0, 0x1p0, 0x1p0 }, { 0x0p0, -0x1p0, 0x1p0 }, { 0x0p0, 0x1p0, -0x1p0 }, { 0x0p0, -0x1p0, -0x1p0 },
    { 0x1p0, 0x0p0, -0x1p0 }, { -0x1p0, 0x0p0, -0x1p0 }, { 0x0p0, -0x1p0, 0x1p0 }, { 0x0p0, 0x1p0, 0x1p0 }
}

local grad4 = {
    { 0x0p0, 0x1p0, 0x1p0,  0x1p0 }, { 0x0p0, 0x1p0, 0x1p0, -0x1p0 },
    { 0x0p0, 0x1p0, -0x1p0, 0x1p0 }, { 0x0p0, 0x1p0, -0x1p0, -0x1p0 },
    { 0x0p0, -0x1p0, 0x1p0,  0x1p0 }, { 0x0p0, -0x1p0, 0x1p0, -0x1p0 },
    { 0x0p0, -0x1p0, -0x1p0, 0x1p0 }, { 0x0p0, -0x1p0, -0x1p0, -0x1p0 },
    { 0x1p0, 0x0p0, 0x1p0,  0x1p0 }, { 0x1p0, 0x0p0, 0x1p0, -0x1p0 },
    { 0x1p0, 0x0p0, -0x1p0, 0x1p0 }, { 0x1p0, 0x0p0, -0x1p0, -0x1p0 },
    { -0x1p0, 0x0p0, 0x1p0,  0x1p0 }, { -0x1p0, 0x0p0, 0x1p0, -0x1p0 },
    { -0x1p0, 0x0p0, -0x1p0, 0x1p0 }, { -0x1p0, 0x0p0, -0x1p0, -0x1p0 },
    { 0x1p0, 0x1p0,  0x0p0, 0x1p0 }, { 0x1p0, 0x1p0, 0x0p0, -0x1p0 },
    { 0x1p0, -0x1p0, 0x0p0, 0x1p0 }, { 0x1p0, -0x1p0, 0x0p0, -0x1p0 },
    { -0x1p0, 0x1p0,  0x0p0, 0x1p0 }, { -0x1p0, 0x1p0, 0x0p0, -0x1p0 },
    { -0x1p0, -0x1p0, 0x0p0, 0x1p0 }, { -0x1p0, -0x1p0, 0x0p0, -0x1p0 },
    { 0x1p0, 0x1p0,  0x1p0, 0x0p0 }, { 0x1p0, 0x1p0, -0x1p0, 0x0p0 },
    { 0x1p0, -0x1p0, 0x1p0, 0x0p0 }, { 0x1p0, -0x1p0, -0x1p0, 0x0p0 },
    { -0x1p0, 0x1p0,  0x1p0, 0x0p0 }, { -0x1p0, 0x1p0, -0x1p0, 0x0p0 },
    { -0x1p0, -0x1p0, 0x1p0, 0x0p0 }, { -0x1p0, -0x1p0, -0x1p0, 0x0p0 }
}

-- default permutation table (256 values repeated twice)
local perm = {
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
    140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
    247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
    57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
    74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
    60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
    65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
    200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
    52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
    207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
    119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
    129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
    218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
    81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
    184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
    222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180
}

-- duplicate for overflow handling
for i = 1, 256 do
    perm[256 + i] = perm[i]
end

--- seed the permutation table with fisher-yates shuffle
--- @param s seed value
local function seed(s)
    math.randomseed(s)

    for i = 0, 255 do
        perm[i + 1] = i
    end

    for i = 255, 1, -1 do
        local j = math.random(0, i)
        perm[i + 1], perm[j + 1] = perm[j + 1], perm[i + 1]
    end

    for i = 1, 256 do
        perm[256 + i] = perm[i]
    end
end

--- @param x integer x coordinate
--- @param y integer y coordinate
--- @return integer hash value
local function hash2d(x, y)
    local ix = band(x, 255) + 1
    local iy = band(y, 255) + 1
    return bxor(perm[ix], perm[iy + 256])
end

--- @param x integer x coordinate
--- @param y integer y coordinate
--- @param z integer z coordinate
--- @return integer hash value
local function hash3d(x, y, z)
    local ix = band(x, 255) + 1
    local iy = band(y, 255) + 1
    local iz = band(z, 255) + 1
    return bxor(bxor(perm[ix], perm[iy + 256]), perm[iz])
end

--- @param x integer x coordinate
--- @param y integer y coordinate
--- @param z integer z coordinate
--- @param w integer w coordinate
--- @return integer hash value
local function hash4d(x, y, z, w)
    local ix = band(x, 255) + 1
    local iy = band(y, 255) + 1
    local iz = band(z, 255) + 1
    local iw = band(w, 255) + 1
    return bxor(bxor(bxor(perm[ix], perm[iy + 256]), perm[iz]), perm[iw + 256])
end

--- 2d simplex noise
--- @param x coordinate x
--- @param y coordinate y
--- @return number noise value in range [-1, 1]
local function noise2(x, y)
    local s = (x + y) * F2
    local i = floor(x + s)
    local j = floor(y + s)

    local t = (i + j) * G2
    local x0 = x - i + t
    local y0 = y - j + t

    local i1 = rshift(floor(y0 - x0), 31)
    local j1 = 1 - i1

    local x1 = x0 - i1 + G2
    local y1 = y0 - j1 + G2
    local x2 = x0 - 0x1p0 + G2_2
    local y2 = y0 - 0x1p0 + G2_2

    local ii = band(i, 255) + 1
    local jj = band(j, 255) + 1

    local gi0 = band(perm[ii + perm[jj]], 11) + 1
    local gi1 = band(perm[ii + i1 + perm[jj + j1]], 11) + 1
    local gi2 = band(perm[ii + 1 + perm[jj + 1]], 11) + 1

    local n0, n1, n2 = 0x0p0, 0x0p0, 0x0p0

    local t0 = 0x1p-1 - x0 * x0 - y0 * y0
    if t0 > 0x0p0 then
        t0 = t0 * t0
        local g = grad2[gi0]
        n0 = t0 * t0 * (g[1] * x0 + g[2] * y0)
    end

    local t1 = 0x1p-1 - x1 * x1 - y1 * y1
    if t1 > 0x0p0 then
        t1 = t1 * t1
        local g = grad2[gi1]
        n1 = t1 * t1 * (g[1] * x1 + g[2] * y1)
    end

    local t2 = 0x1p-1 - x2 * x2 - y2 * y2
    if t2 > 0x0p0 then
        t2 = t2 * t2
        local g = grad2[gi2]
        n2 = t2 * t2 * (g[1] * x2 + g[2] * y2)
    end

    return 0x1.18p6 * (n0 + n1 + n2)
end

--- 3d simplex noise
--- @param x coordinate x
--- @param y coordinate y
--- @param z coordinate z
--- @return number noise value in range [-1, 1]
local function noise3(x, y, z)
    local s = (x + y + z) * F3
    local i = floor(x + s)
    local j = floor(y + s)
    local k = floor(z + s)

    local t = (i + j + k) * G3
    local x0 = x - i + t
    local y0 = y - j + t
    local z0 = z - k + t

    local i1, j1, k1, i2, j2, k2

    if x0 >= y0 then
        if y0 >= z0 then
            i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
        elseif x0 >= z0 then
            i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
        else
            i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1
        end
    else
        if y0 < z0 then
            i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
        elseif x0 < z0 then
            i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
        else
            i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0
        end
    end

    local x1 = x0 - i1 + G3
    local y1 = y0 - j1 + G3
    local z1 = z0 - k1 + G3
    local x2 = x0 - i2 + G3_2
    local y2 = y0 - j2 + G3_2
    local z2 = z0 - k2 + G3_2
    local x3 = x0 - G3_3
    local y3 = y0 - G3_3
    local z3 = z0 - G3_3

    local ii = band(i, 255) + 1
    local jj = band(j, 255) + 1
    local kk = band(k, 255) + 1

    local gi0 = band(perm[ii + perm[jj + perm[kk]]], 15) + 1
    local gi1 = band(perm[ii + i1 + perm[jj + j1 + perm[kk + k1]]], 15) + 1
    local gi2 = band(perm[ii + i2 + perm[jj + j2 + perm[kk + k2]]], 15) + 1
    local gi3 = band(perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]], 15) + 1

    local n0, n1, n2, n3 = 0x0p0, 0x0p0, 0x0p0, 0x0p0

    local t0 = 0x1.3333333333333p-1 - x0 * x0 - y0 * y0 - z0 * z0
    if t0 > 0x0p0 then
        t0 = t0 * t0
        local g = grad3[gi0]
        n0 = t0 * t0 * (g[1] * x0 + g[2] * y0 + g[3] * z0)
    end

    local t1 = 0x1.3333333333333p-1 - x1 * x1 - y1 * y1 - z1 * z1
    if t1 > 0x0p0 then
        t1 = t1 * t1
        local g = grad3[gi1]
        n1 = t1 * t1 * (g[1] * x1 + g[2] * y1 + g[3] * z1)
    end

    local t2 = 0x1.3333333333333p-1 - x2 * x2 - y2 * y2 - z2 * z2
    if t2 > 0x0p0 then
        t2 = t2 * t2
        local g = grad3[gi2]
        n2 = t2 * t2 * (g[1] * x2 + g[2] * y2 + g[3] * z2)
    end

    local t3 = 0x1.3333333333333p-1 - x3 * x3 - y3 * y3 - z3 * z3
    if t3 > 0x0p0 then
        t3 = t3 * t3
        local g = grad3[gi3]
        n3 = t3 * t3 * (g[1] * x3 + g[2] * y3 + g[3] * z3)
    end

    return 0x1p5 * (n0 + n1 + n2 + n3)
end

--- 4d simplex noise
--- @param x coordinate x
--- @param y coordinate y
--- @param z coordinate z
--- @param w coordinate w
--- @return number noise value in range [-1, 1]
local function noise4(x, y, z, w)
    -- skew the (x,y,z,w) space to determine which cell of 24 simplices we're in
    local s = (x + y + z + w) * F4
    local i = floor(x + s)
    local j = floor(y + s)
    local k = floor(z + s)
    local l = floor(w + s)

    -- unskew the cell origin back to (x,y,z,w) space
    local t = (i + j + k + l) * G4
    local x0 = x - i + t
    local y0 = y - j + t
    local z0 = z - k + t
    local w0 = w - l + t

    -- for the 4D case, your head explodes and gushy brainy matter ends up all over the place.
    -- to find out which of the 24 possible simplices we're in, we need to
    -- determine the magnitude ordering of x0, y0, z0 and w0.
    -- six pair-wise comparisons are performed between each possible pair
    -- of the four coordinates, and the results are used to rank the numbers.
    local rankx = 0x0p0
    local ranky = 0x0p0
    local rankz = 0x0p0
    local rankw = 0x0p0

    if x0 > y0 then rankx = rankx + 1 else ranky = ranky + 1 end
    if x0 > z0 then rankx = rankx + 1 else rankz = rankz + 1 end
    if x0 > w0 then rankx = rankx + 1 else rankw = rankw + 1 end
    if y0 > z0 then ranky = ranky + 1 else rankz = rankz + 1 end
    if y0 > w0 then ranky = ranky + 1 else rankw = rankw + 1 end
    if z0 > w0 then rankz = rankz + 1 else rankw = rankw + 1 end

    -- integer offsets for the simplex corners
    local i1 = rankx >= 3 and 1 or 0
    local j1 = ranky >= 3 and 1 or 0
    local k1 = rankz >= 3 and 1 or 0
    local l1 = rankw >= 3 and 1 or 0

    local i2 = rankx >= 2 and 1 or 0
    local j2 = ranky >= 2 and 1 or 0
    local k2 = rankz >= 2 and 1 or 0
    local l2 = rankw >= 2 and 1 or 0

    local i3 = rankx >= 1 and 1 or 0
    local j3 = ranky >= 1 and 1 or 0
    local k3 = rankz >= 1 and 1 or 0
    local l3 = rankw >= 1 and 1 or 0

    -- offsets for simplex corners in (x,y,z,w) coords
    local x1 = x0 - i1 + G4
    local y1 = y0 - j1 + G4
    local z1 = z0 - k1 + G4
    local w1 = w0 - l1 + G4

    local x2 = x0 - i2 + G4_2
    local y2 = y0 - j2 + G4_2
    local z2 = z0 - k2 + G4_2
    local w2 = w0 - l2 + G4_2

    local x3 = x0 - i3 + G4_3
    local y3 = y0 - j3 + G4_3
    local z3 = z0 - k3 + G4_3
    local w3 = w0 - l3 + G4_3

    local x4 = x0 - 0x1p0 + G4_4
    local y4 = y0 - 0x1p0 + G4_4
    local z4 = z0 - 0x1p0 + G4_4
    local w4 = w0 - 0x1p0 + G4_4

    -- work out the hashed gradient indices of the five simplex corners
    local ii = band(i, 255) + 1
    local jj = band(j, 255) + 1
    local kk = band(k, 255) + 1
    local ll = band(l, 255) + 1

    local gi0 = band(perm[ii + perm[jj + perm[kk + perm[ll]]]], 31) + 1
    local gi1 = band(perm[ii + i1 + perm[jj + j1 + perm[kk + k1 + perm[ll + l1]]]], 31) + 1
    local gi2 = band(perm[ii + i2 + perm[jj + j2 + perm[kk + k2 + perm[ll + l2]]]], 31) + 1
    local gi3 = band(perm[ii + i3 + perm[jj + j3 + perm[kk + k3 + perm[ll + l3]]]], 31) + 1
    local gi4 = band(perm[ii + 1 + perm[jj + 1 + perm[kk + 1 + perm[ll + 1]]]], 31) + 1

    -- calculate the contribution from the five corners
    local n0, n1, n2, n3, n4 = 0x0p0, 0x0p0, 0x0p0, 0x0p0, 0x0p0

    local t0 = 0x1.3333333333333p-1 - x0 * x0 - y0 * y0 - z0 * z0 - w0 * w0
    if t0 > 0x0p0 then
        t0 = t0 * t0
        local g = grad4[gi0]
        n0 = t0 * t0 * (g[1] * x0 + g[2] * y0 + g[3] * z0 + g[4] * w0)
    end

    local t1 = 0x1.3333333333333p-1 - x1 * x1 - y1 * y1 - z1 * z1 - w1 * w1
    if t1 > 0x0p0 then
        t1 = t1 * t1
        local g = grad4[gi1]
        n1 = t1 * t1 * (g[1] * x1 + g[2] * y1 + g[3] * z1 + g[4] * w1)
    end

    local t2 = 0x1.3333333333333p-1 - x2 * x2 - y2 * y2 - z2 * z2 - w2 * w2
    if t2 > 0x0p0 then
        t2 = t2 * t2
        local g = grad4[gi2]
        n2 = t2 * t2 * (g[1] * x2 + g[2] * y2 + g[3] * z2 + g[4] * w2)
    end

    local t3 = 0x1.3333333333333p-1 - x3 * x3 - y3 * y3 - z3 * z3 - w3 * w3
    if t3 > 0x0p0 then
        t3 = t3 * t3
        local g = grad4[gi3]
        n3 = t3 * t3 * (g[1] * x3 + g[2] * y3 + g[3] * z3 + g[4] * w3)
    end

    local t4 = 0x1.3333333333333p-1 - x4 * x4 - y4 * y4 - z4 * z4 - w4 * w4
    if t4 > 0x0p0 then
        t4 = t4 * t4
        local g = grad4[gi4]
        n4 = t4 * t4 * (g[1] * x4 + g[2] * y4 + g[3] * z4 + g[4] * w4)
    end

    -- sum and scale the result to cover the range [-1, 1]
    return 0x1.bp4 * (n0 + n1 + n2 + n3 + n4) -- 27.0 * sum
end

-- ============================================================================
-- VALUE NOISE
-- ============================================================================

--- random value from hash (deterministic pseudo-random)
--- @param n integer hash input
--- @return number value in range [0, 1]
local function hash_to_float(n)
    n = bxor(n, rshift(n, 16))
    n = (n * 0x85ebca6b) % 0x100000000
    n = bxor(n, rshift(n, 13))
    n = (n * 0xc2b2ae35) % 0x100000000
    n = bxor(n, rshift(n, 16))
    return (n % 0x1000000) / 0x1000000
end

--- 2d value noise (interpolated random values)
--- @param x coordinate x
--- @param y coordinate y
--- @return number noise value in range [0, 1]
local function value2(x, y)
    local ix = floor(x)
    local iy = floor(y)
    local fx = x - ix
    local fy = y - iy

    -- quintic interpolation curve (smoother than cubic)
    local ux = fx * fx * fx * (fx * (fx * 0x1.ep0 - 0x1.ep1) + 0x1.4p1)
    local uy = fy * fy * fy * (fy * (fy * 0x1.ep0 - 0x1.ep1) + 0x1.4p1)

    -- hash corner values
    local h00 = hash2d(ix, iy)
    local h10 = hash2d(ix + 1, iy)
    local h01 = hash2d(ix, iy + 1)
    local h11 = hash2d(ix + 1, iy + 1)

    -- convert to float [0,1]
    local v00 = hash_to_float(h00)
    local v10 = hash_to_float(h10)
    local v01 = hash_to_float(h01)
    local v11 = hash_to_float(h11)

    -- bilinear interpolation
    local a = v00 + (v10 - v00) * ux
    local b = v01 + (v11 - v01) * ux
    return a + (b - a) * uy
end

--- 3d value noise (interpolated random values)
--- @param x coordinate x
--- @param y coordinate y
--- @param z coordinate z
--- @return number noise value in range [0, 1]
local function value3(x, y, z)
    local ix = floor(x)
    local iy = floor(y)
    local iz = floor(z)
    local fx = x - ix
    local fy = y - iy
    local fz = z - iz

    -- quintic interpolation
    local ux = fx * fx * fx * (fx * (fx * 0x1.ep0 - 0x1.ep1) + 0x1.4p1)
    local uy = fy * fy * fy * (fy * (fy * 0x1.ep0 - 0x1.ep1) + 0x1.4p1)
    local uz = fz * fz * fz * (fz * (fz * 0x1.ep0 - 0x1.ep1) + 0x1.4p1)

    -- hash 8 corners
    local h000 = hash3d(ix, iy, iz)
    local h100 = hash3d(ix + 1, iy, iz)
    local h010 = hash3d(ix, iy + 1, iz)
    local h110 = hash3d(ix + 1, iy + 1, iz)
    local h001 = hash3d(ix, iy, iz + 1)
    local h101 = hash3d(ix + 1, iy, iz + 1)
    local h011 = hash3d(ix, iy + 1, iz + 1)
    local h111 = hash3d(ix + 1, iy + 1, iz + 1)

    -- convert to float
    local v000 = hash_to_float(h000)
    local v100 = hash_to_float(h100)
    local v010 = hash_to_float(h010)
    local v110 = hash_to_float(h110)
    local v001 = hash_to_float(h001)
    local v101 = hash_to_float(h101)
    local v011 = hash_to_float(h011)
    local v111 = hash_to_float(h111)

    -- trilinear interpolation
    local a = v000 + (v100 - v000) * ux
    local b = v010 + (v110 - v010) * ux
    local c = v001 + (v101 - v001) * ux
    local d = v011 + (v111 - v011) * ux
    local e = a + (b - a) * uy
    local f = c + (d - c) * uy
    return e + (f - e) * uz
end

-- ============================================================================
-- WORLEY/CELLULAR NOISE
-- ============================================================================

--- 2d worley/cellular noise (distance to nearest feature point)
--- @param x coordinate x
--- @param y coordinate y
--- @param jitter randomization amount [0,1], default 1.0
--- @param distance_func optional distance function: "euclidean", "manhattan", "chebyshev"
--- @return number distance to nearest point (normalized ~[0,1])
--- @return number distance to second nearest (for advanced patterns)
--- @return integer cell id of nearest point (for voronoi coloring)
local function worley2(x, y, jitter, distance_func)
    jitter = jitter or 0x1p0
    distance_func = distance_func or "euclidean"

    local xi = floor(x)
    local yi = floor(y)
    local xf = x - xi
    local yf = y - yi

    local min_dist1 = 0x1p10 -- large number
    local min_dist2 = 0x1p10
    local min_cell_id = 0

    -- check 3x3 neighborhood
    for j = -1, 1 do
        for i = -1, 1 do
            local cell_x = xi + i
            local cell_y = yi + j

            -- generate feature point in this cell
            local h = hash2d(cell_x, cell_y)
            local px = i + hash_to_float(h) * jitter
            local py = j + hash_to_float(h * 31337) * jitter

            -- distance to feature point
            local dx = xf - px
            local dy = yf - py
            local dist

            if distance_func == "euclidean" then
                dist = sqrt(dx * dx + dy * dy)
            elseif distance_func == "manhattan" then
                dist = abs(dx) + abs(dy)
            elseif distance_func == "chebyshev" then
                dist = max(abs(dx), abs(dy))
            else
                dist = sqrt(dx * dx + dy * dy)
            end

            -- track two nearest distances
            if dist < min_dist1 then
                min_dist2 = min_dist1
                min_dist1 = dist
                min_cell_id = h
            elseif dist < min_dist2 then
                min_dist2 = dist
            end
        end
    end

    return min_dist1, min_dist2, min_cell_id
end

--- 3d worley/cellular noise (distance to nearest feature point)
--- @param x coordinate x
--- @param y coordinate y
--- @param z coordinate z
--- @param jitter randomization amount [0,1], default 1.0
--- @param distance_func optional distance function
--- @return number distance to nearest point (normalized ~[0,1])
--- @return number distance to second nearest
--- @return integer cell id of nearest point
local function worley3(x, y, z, jitter, distance_func)
    jitter = jitter or 0x1p0
    distance_func = distance_func or "euclidean"

    local xi = floor(x)
    local yi = floor(y)
    local zi = floor(z)
    local xf = x - xi
    local yf = y - yi
    local zf = z - zi

    local min_dist1 = 0x1p10
    local min_dist2 = 0x1p10
    local min_cell_id = 0

    -- check 3x3x3 neighborhood
    for k = -1, 1 do
        for j = -1, 1 do
            for i = -1, 1 do
                local cell_x = xi + i
                local cell_y = yi + j
                local cell_z = zi + k

                local h = hash3d(cell_x, cell_y, cell_z)
                local px = i + hash_to_float(h) * jitter
                local py = j + hash_to_float(h * 31337) * jitter
                local pz = k + hash_to_float(h * 97531) * jitter

                local dx = xf - px
                local dy = yf - py
                local dz = zf - pz
                local dist

                if distance_func == "euclidean" then
                    dist = sqrt(dx * dx + dy * dy + dz * dz)
                elseif distance_func == "manhattan" then
                    dist = abs(dx) + abs(dy) + abs(dz)
                elseif distance_func == "chebyshev" then
                    dist = max(max(abs(dx), abs(dy)), abs(dz))
                else
                    dist = sqrt(dx * dx + dy * dy + dz * dz)
                end

                if dist < min_dist1 then
                    min_dist2 = min_dist1
                    min_dist1 = dist
                    min_cell_id = h
                elseif dist < min_dist2 then
                    min_dist2 = dist
                end
            end
        end
    end

    return min_dist1, min_dist2, min_cell_id
end

-- ============================================================================
-- FBM (FRACTAL BROWNIAN MOTION)
-- ============================================================================

local function fbm2(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        total = total + noise2(x * frequency, y * frequency) * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return (total / max_value + 0x1p0) * 0x1p-1
end

local function fbm3(x, y, z, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        total = total + noise3(x * frequency, y * frequency, z * frequency) * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return (total / max_value + 0x1p0) * 0x1p-1
end

-- ============================================================================
-- DOMAIN WARPING 
-- ============================================================================

--- 2d domain warping (offset input by fbm noise)
--- @param x coordinate x
--- @param y coordinate y
--- @param strength warping strength (amplitude)
--- @param scale warping frequency scale
--- @param octaves number of fbm octaves for warp
--- @return number warped noise value
local function domain_warp2(x, y, strength, scale, octaves)
    strength = strength or 0x1p2 -- default 4.0
    scale = scale or 0x1p0       -- default 1.0
    octaves = octaves or 3

    -- compute warp offsets using fbm
    local qx = fbm2(x * scale, y * scale, octaves)
    local qy = fbm2((x + 0x1.4cccccccccccdp2) * scale, (y + 0x1.4p0) * scale, octaves)

    -- apply warped noise
    return noise2(x + strength * qx, y + strength * qy)
end

--- 3d domain warping (offset input by fbm noise)
--- @param x coordinate x
--- @param y coordinate y
--- @param z coordinate z
--- @param strength warping strength
--- @param scale warping frequency scale
--- @param octaves number of fbm octaves
--- @return number warped noise value
local function domain_warp3(x, y, z, strength, scale, octaves)
    strength = strength or 0x1p2
    scale = scale or 0x1p0
    octaves = octaves or 3

    local qx = fbm3(x * scale, y * scale, z * scale, octaves)
    local qy = fbm3((x + 0x1.4cccccccccccdp2) * scale, (y + 0x1.4p0) * scale, (z + 0x1.9p0) * scale, octaves)
    local qz = fbm3((x + 0x1.ap0) * scale, (y + 0x1.2p1) * scale, (z + 0x1.6p1) * scale, octaves)

    return noise3(x + strength * qx, y + strength * qy, z + strength * qz)
end

-- ============================================================================
-- TURBULENCE
-- ============================================================================

local function turbulence2(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        total = total + abs(noise2(x * frequency, y * frequency)) * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

local function turbulence3(x, y, z, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        total = total + abs(noise3(x * frequency, y * frequency, z * frequency)) * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

-- ============================================================================
-- RIDGED MULTIFRACTAL
-- ============================================================================

local function ridged2(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        local signal = 0x1p0 - abs(noise2(x * frequency, y * frequency))
        signal = signal * signal
        total = total + signal * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

local function ridged3(x, y, z, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        local signal = 0x1p0 - abs(noise3(x * frequency, y * frequency, z * frequency))
        signal = signal * signal
        total = total + signal * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

-- ============================================================================
-- BLENDING UTILITIES
-- ============================================================================

--- smoothstep interpolation (3rd order hermite)
--- @param edge0 lower edge
--- @param edge1 upper edge
--- @param x value to interpolate
--- @return number smoothly interpolated value [0,1]
local function smoothstep(edge0, edge1, x)
    local t = max(0x0p0, min(0x1p0, (x - edge0) / (edge1 - edge0)))
    -- 3t^2 - 2t^3 = t^2(3 - 2t)
    return t * t * (3 - 2 * t)
end

--- smootherstep interpolation (5th order hermite)
--- @param edge0 lower edge
--- @param edge1 upper edge
--- @param x value to interpolate
--- @return number smoothly interpolated value [0,1]
local function smootherstep(edge0, edge1, x)
    local t = max(0x0p0, min(0x1p0, (x - edge0) / (edge1 - edge0)))
    -- 6t^5 - 15t^4 + 10t^3 = t^3(6t^2 - 15t + 10)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

--- linear interpolation
--- @param a first value
--- @param b second value
--- @param t interpolation factor [0,1]
--- @return number interpolated value
local function lerp(a, b, t)
    return a + (b - a) * t
end

--- bilinear interpolation (2d)
--- @param v00 value at (0,0)
--- @param v10 value at (1,0)
--- @param v01 value at (0,1)
--- @param v11 value at (1,1)
--- @param tx interpolation factor x [0,1]
--- @param ty interpolation factor y [0,1]
--- @return number interpolated value
local function bilerp(v00, v10, v01, v11, tx, ty)
    local a = lerp(v00, v10, tx)
    local b = lerp(v01, v11, tx)
    return lerp(a, b, ty)
end

--- trilinear interpolation (3d)
--- @param v000 value at (0,0,0)
--- @param v100 value at (1,0,0)
--- @param v010 value at (0,1,0)
--- @param v110 value at (1,1,0)
--- @param v001 value at (0,0,1)
--- @param v101 value at (1,0,1)
--- @param v011 value at (0,1,1)
--- @param v111 value at (1,1,1)
--- @param tx interpolation factor x [0,1]
--- @param ty interpolation factor y [0,1]
--- @param tz interpolation factor z [0,1]
--- @return number interpolated value
local function trilerp(v000, v100, v010, v110, v001, v101, v011, v111, tx, ty, tz)
    local a = bilerp(v000, v100, v010, v110, tx, ty)
    local b = bilerp(v001, v101, v011, v111, tx, ty)
    return lerp(a, b, tz)
end

--- cubic interpolation (catmull-rom spline)
--- @param p0 point before
--- @param p1 start point
--- @param p2 end point
--- @param p3 point after
--- @param t interpolation factor [0,1]
--- @return number interpolated value
local function cubic_interp(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0x1p-1 * (
        (0x1p1 * p1) +
        (-p0 + p2) * t +
        (0x1p1 * p0 - 0x1.4p0 * p1 + p2 - 0x1p-1 * p3) * t2 +
        (-p0 + 0x1.8p0 * p1 - 0x1.8p0 * p2 + p3) * t3
    )
end

--- weighted blend of multiple values (blending)
--- @param values array of values to blend
--- @param weights array of blend weights (must sum to 1.0)
--- @return number blended value
local function weighted_blend(values, weights)
    local result = 0x0p0
    for i = 1, #values do
        result = result + values[i] * weights[i]
    end
    return result
end

--- distance-based blend weight (inverse distance)
--- @param distance distance from biome center
--- @param falloff falloff distance
--- @return number blend weight [0,1]
local function distance_weight(distance, falloff)
    if distance >= falloff then return 0x0p0 end
    local t = distance / falloff
    return 0x1p0 - smootherstep(0x0p0, 0x1p0, t)
end

-- ============================================================================
-- EROSION/WEATHERING HELPERS
-- ============================================================================

--- hydraulic erosion simulation (simple single-step)
--- @param height_map 2d array of heights
--- @param width map width
--- @param height map height
--- @param erosion_rate how much material to erode per step
--- @return table eroded height map
local function hydraulic_erosion_step(height_map, width, height, erosion_rate)
    erosion_rate = erosion_rate or 0x1p-3 -- 0.125
    local new_map = {}

    for y = 1, height do
        new_map[y] = {}
        for x = 1, width do
            local h = height_map[y][x]
            local min_neighbor = h
            local count = 0

            -- find lowest neighbor
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local nx = x + dx
                        local ny = y + dy
                        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                            min_neighbor = min(min_neighbor, height_map[ny][nx])
                            count = count + 1
                        end
                    end
                end
            end

            -- erode if higher than neighbors
            if h > min_neighbor then
                local delta = (h - min_neighbor) * erosion_rate
                new_map[y][x] = h - delta
            else
                new_map[y][x] = h
            end
        end
    end

    return new_map
end

--- thermal erosion (simulate talus slope)
--- @param height_map 2d array of heights
--- @param width map width
--- @param height map height
--- @param talus_angle maximum stable slope angle (default 0.6)
--- @return table eroded height map
local function thermal_erosion_step(height_map, width, height, talus_angle)
    talus_angle = talus_angle or 0x1.3333333333333p-1 -- 0.6
    local new_map = {}

    for y = 1, height do
        new_map[y] = {}
        for x = 1, width do
            new_map[y][x] = height_map[y][x]
        end
    end

    for y = 1, height do
        for x = 1, width do
            local h = height_map[y][x]

            -- check all neighbors
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local nx = x + dx
                        local ny = y + dy
                        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                            local neighbor_h = height_map[ny][nx]
                            local delta = h - neighbor_h

                            -- if slope exceeds talus angle, move material
                            if delta > talus_angle then
                                local amount = 0x1p-2 * (delta - talus_angle) -- 0.25
                                new_map[y][x] = new_map[y][x] - amount
                                new_map[ny][nx] = new_map[ny][nx] + amount
                            end
                        end
                    end
                end
            end
        end
    end

    return new_map
end

--- apply erosion mask (selective erosion based on slope/height)
--- @param height_map 2d array of heights
--- @param width map width
--- @param height map height
--- @param erosion_strength erosion multiplier
--- @return table eroded height map
local function apply_erosion_mask(height_map, width, height, erosion_strength)
    erosion_strength = erosion_strength or 0x1p-2 -- 0.25
    local result = {}

    for y = 1, height do
        result[y] = {}
        for x = 1, width do
            local h = height_map[y][x]
            local slope = 0x0p0
            local count = 0

            -- calculate average slope
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local nx = x + dx
                        local ny = y + dy
                        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                            slope = slope + abs(h - height_map[ny][nx])
                            count = count + 1
                        end
                    end
                end
            end

            if count > 0 then
                slope = slope / count
            end

            -- erode more on steep slopes
            local erosion = slope * erosion_strength
            result[y][x] = h * (0x1p0 - erosion)
        end
    end

    return result
end

--- sediment deposition (smooth low areas)
--- @param height_map 2d array of heights
--- @param width map width
--- @param height map height
--- @param deposition_rate amount to smooth
--- @return table smoothed height map
local function sediment_deposition(height_map, width, height, deposition_rate)
    deposition_rate = deposition_rate or 0x1p-3 -- 0.125
    local result = {}

    for y = 1, height do
        result[y] = {}
        for x = 1, width do
            local sum = 0x0p0
            local count = 0

            -- average with neighbors
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local nx = x + dx
                    local ny = y + dy
                    if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                        sum = sum + height_map[ny][nx]
                        count = count + 1
                    end
                end
            end

            local avg = sum / count
            local h = height_map[y][x]

            -- deposit in low areas (below average)
            if h < avg then
                result[y][x] = lerp(h, avg, deposition_rate)
            else
                result[y][x] = h
            end
        end
    end

    return result
end

-- ============================================================================
-- MISCELLANEOUS
-- ============================================================================

--- billowy noise (absolute fbm, always positive)
--- @param x coordinate x
--- @param y coordinate y
--- @param octaves number of octaves
--- @param persistence amplitude decay
--- @param lacunarity frequency multiplier
--- @return number billowy noise in range [0,1]
local function billowy2(x, y, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        local n = abs(noise2(x * frequency, y * frequency))
        total = total + n * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

--- billowy noise 3d
local function billowy3(x, y, z, octaves, persistence, lacunarity)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0

    for i = 1, octaves do
        local n = abs(noise3(x * frequency, y * frequency, z * frequency))
        total = total + n * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

--- swiss turbulence (ridged with domain warping)
--- @param x coordinate x
--- @param y coordinate y
--- @param octaves number of octaves
--- @param persistence amplitude decay
--- @param lacunarity frequency multiplier
--- @param warp warp strength
--- @return number swiss noise value
local function swiss2(x, y, octaves, persistence, lacunarity, warp)
    octaves = octaves or 4
    persistence = persistence or 0x1p-1
    lacunarity = lacunarity or 0x1p1
    warp = warp or 0x1p-1

    local total = 0x0p0
    local amplitude = 0x1p0
    local frequency = 0x1p0
    local max_value = 0x0p0
    local dx = 0x0p0
    local dy = 0x0p0

    for i = 1, octaves do
        local n = ridged2((x + warp * dx) * frequency, (y + warp * dy) * frequency, 1)
        total = total + n * amplitude

        -- accumulate derivatives for warping
        dx = dx + noise2(x * frequency, y * frequency)
        dy = dy + noise2(x * frequency + 0x1.b333333333333p1, y * frequency + 0x1.4p0)

        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * lacunarity
    end

    return total / max_value
end

--- jordan turbulence (advanced ridged multifractal)
--- @param x coordinate x
--- @param y coordinate y
--- @param octaves number of octaves
--- @param gain0 initial gain
--- @param gain gain per octave
--- @param warp0 initial warp
--- @param warp warp per octave
--- @param damp dampening per octave
--- @param lacunarity frequency multiplier
--- @return number jordan noise value
local function jordan2(x, y, octaves, gain0, gain, warp0, warp, damp, lacunarity)
    octaves = octaves or 6
    gain0 = gain0 or 0x1.199999999999ap0  -- 1.1
    gain = gain or 0x1p-1
    warp0 = warp0 or 0x1.999999999999ap-2 -- 0.4
    warp = warp or 0x1.999999999999ap-1   -- 0.8
    damp = damp or 0x1p0
    lacunarity = lacunarity or 0x1p1

    local total = 0x0p0
    local amplitude = gain0
    local frequency = 0x1p0
    local dx = 0x0p0
    local dy = 0x0p0
    local damp_scale = 0x1p0

    for i = 1, octaves do
        local n = noise2((x + warp0 * dx) * frequency, (y + warp0 * dy) * frequency)
        n = 0x1p0 - abs(n)
        n = n * n * amplitude * damp_scale

        total = total + n

        -- update warping offsets
        dx = dx + noise2(x * frequency, y * frequency)
        dy = dy + noise2(x * frequency + 0x1.9p0, y * frequency + 0x1.3p0)

        damp_scale = damp_scale * damp
        amplitude = amplitude * gain
        frequency = frequency * lacunarity
        warp0 = warp0 * warp
    end

    return total
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

return {
    -- seeding
    seed = seed,

    -- core noise functions
    noise2 = noise2,
    noise3 = noise3,
    noise4 = noise4,
    value2 = value2,
    value3 = value3,
    worley2 = worley2,
    worley3 = worley3,

    -- fractal noise
    fbm2 = fbm2,
    fbm3 = fbm3,
    turbulence2 = turbulence2,
    turbulence3 = turbulence3,
    ridged2 = ridged2,
    ridged3 = ridged3,
    billowy2 = billowy2,
    billowy3 = billowy3,

    -- advanced noise
    domain_warp2 = domain_warp2,
    domain_warp3 = domain_warp3,
    swiss2 = swiss2,
    jordan2 = jordan2,

    -- blending utilities
    smoothstep = smoothstep,
    smootherstep = smootherstep,
    lerp = lerp,
    bilerp = bilerp,
    trilerp = trilerp,
    cubic_interp = cubic_interp,
    weighted_blend = weighted_blend,
    distance_weight = distance_weight,

    -- erosion helpers
    hydraulic_erosion_step = hydraulic_erosion_step,
    thermal_erosion_step = thermal_erosion_step,
    apply_erosion_mask = apply_erosion_mask,
    sediment_deposition = sediment_deposition,

    -- hash utilities
    hash2d = hash2d,
    hash3d = hash3d,
    hash4d = hash4d,
    hash_to_float = hash_to_float
}
