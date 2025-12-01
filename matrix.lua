--- matrix math library (mat2, mat3, mat4)
--- optimized for luajit with ffi, allocation sinking, ieee 754 hex floats
--- uses row-major storage for cache efficiency and simd-friendly sequential access
--- matrices stored as contiguous arrays of rows for optimal memory locality
--- @module matrix

local ffi = require("ffi")
local sqrt, abs, min, max, sin, cos, tan = math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.tan

-- ============================================================================
-- MAT2 - 2X2 MATRIX
-- ============================================================================

ffi.cdef[[
typedef struct { double m[4]; } mat2;
]]

local mat2
local mat2_mt = {
    __new = function(ct, m00, m01, m10, m11)
        if m00 then
            return ffi.new(ct, {{m00, m01, m10, m11}})
        else
            local m = ffi.new(ct)
            m.m[0] = 0x1p0; m.m[3] = 0x1p0
            return m
        end
    end,

    __index = {
        --- set from values (row-major order)
        set = function(self, m00, m01, m10, m11)
            local m = self.m
            m[0] = m00; m[1] = m01
            m[2] = m10; m[3] = m11
            return self
        end,
        
        --- copy from another mat2
        copy = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = n[0]; m[1] = n[1]
            m[2] = n[2]; m[3] = n[3]
            return self
        end,
        
        --- clone to new mat2
        clone = function(self)
            return mat2(self.m[0], self.m[1], self.m[2], self.m[3])
        end,
        
        --- set to identity
        identity = function(self)
            local m = self.m
            m[0] = 0x1p0; m[1] = 0x0p0
            m[2] = 0x0p0; m[3] = 0x1p0
            return self
        end,
        
        --- set to zero matrix
        zero = function(self)
            local m = self.m
            m[0] = 0x0p0; m[1] = 0x0p0
            m[2] = 0x0p0; m[3] = 0x0p0
            return self
        end,
        
        --- transpose (in-place)
        transpose = function(self)
            local m = self.m
            local t = m[1]
            m[1] = m[2]
            m[2] = t
            return self
        end,
        
        --- determinant
        det = function(self)
            local m = self.m
            return m[0] * m[3] - m[1] * m[2]
        end,
        
        --- inverse (in-place)
        invert = function(self)
            local m = self.m
            local det = m[0] * m[3] - m[1] * m[2]
            
            if abs(det) < 0x1p-52 then
                return self:identity()
            end
            
            local inv_det = 0x1p0 / det
            local m00 = m[0]
            
            m[0] = m[3] * inv_det
            m[1] = -m[1] * inv_det
            m[2] = -m[2] * inv_det
            m[3] = m00 * inv_det
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul_scalar = function(self, s)
            local m = self.m
            m[0] = m[0] * s; m[1] = m[1] * s
            m[2] = m[2] * s; m[3] = m[3] * s
            return self
        end,
        
        --- multiply by another mat2 (in-place: self = self * mat)
        mul = function(self, mat)
            local a = self.m
            local b = mat.m
            local a00, a01 = a[0], a[1]
            local a10, a11 = a[2], a[3]
            a[0] = a00 * b[0] + a01 * b[2]
            a[1] = a00 * b[1] + a01 * b[3]
            a[2] = a10 * b[0] + a11 * b[2]
            a[3] = a10 * b[1] + a11 * b[3]
            return self
        end,
        
        --- add another mat2 (in-place)
        add = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] + n[0]; m[1] = m[1] + n[1]
            m[2] = m[2] + n[2]; m[3] = m[3] + n[3]
            return self
        end,
        
        --- subtract another mat2 (in-place)
        sub = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] - n[0]; m[1] = m[1] - n[1]
            m[2] = m[2] - n[2]; m[3] = m[3] - n[3]
            return self
        end,
        
        --- rotation matrix (radians) - OVERWRITES
        rotation = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            m[0] = c;  m[1] = -s
            m[2] = s;  m[3] = c
            return self
        end,
        
        --- scale matrix - OVERWRITES
        scale = function(self, sx, sy)
            local m = self.m
            m[0] = sx; m[1] = 0x0p0
            m[2] = 0x0p0; m[3] = sy or sx
            return self
        end,
    },
    
    __tostring = function(self)
        local m = self.m
        return string.format("mat2(\n  %.6f, %.6f\n  %.6f, %.6f\n)", m[0], m[1], m[2], m[3])
    end,
}

mat2 = ffi.metatype("mat2", mat2_mt)

-- ============================================================================
-- MAT3 - 3X3 MATRIX
-- ============================================================================

ffi.cdef[[
typedef struct { double m[9]; } mat3;
]]

local mat3
local mat3_mt = {
    __new = function(ct, m00, m01, m02, m10, m11, m12, m20, m21, m22)
        if m00 then
            return ffi.new(ct, {{m00, m01, m02, m10, m11, m12, m20, m21, m22}})
        else
            local m = ffi.new(ct)
            m.m[0] = 0x1p0; m.m[4] = 0x1p0; m.m[8] = 0x1p0
            return m
        end
    end,

    __index = {
        --- set from values (row-major order)
        set = function(self, m00, m01, m02, m10, m11, m12, m20, m21, m22)
            local m = self.m
            m[0] = m00; m[1] = m01; m[2] = m02
            m[3] = m10; m[4] = m11; m[5] = m12
            m[6] = m20; m[7] = m21; m[8] = m22
            return self
        end,
        
        --- copy from another mat3
        copy = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = n[0]; m[1] = n[1]; m[2] = n[2]
            m[3] = n[3]; m[4] = n[4]; m[5] = n[5]
            m[6] = n[6]; m[7] = n[7]; m[8] = n[8]
            return self
        end,
        
        --- clone to new mat3
        clone = function(self)
            local m = self.m
            return mat3(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        end,
        
        --- set to identity
        identity = function(self)
            local m = self.m
            m[0] = 0x1p0; m[1] = 0x0p0; m[2] = 0x0p0
            m[3] = 0x0p0; m[4] = 0x1p0; m[5] = 0x0p0
            m[6] = 0x0p0; m[7] = 0x0p0; m[8] = 0x1p0
            return self
        end,
        
        --- set to zero matrix
        zero = function(self)
            local m = self.m
            m[0] = 0x0p0; m[1] = 0x0p0; m[2] = 0x0p0
            m[3] = 0x0p0; m[4] = 0x0p0; m[5] = 0x0p0
            m[6] = 0x0p0; m[7] = 0x0p0; m[8] = 0x0p0
            return self
        end,
        
        --- transpose (in-place)
        transpose = function(self)
            local m = self.m
            local t
            t = m[1]; m[1] = m[3]; m[3] = t
            t = m[2]; m[2] = m[6]; m[6] = t
            t = m[5]; m[5] = m[7]; m[7] = t
            return self
        end,
        
        --- determinant
        det = function(self)
            local m = self.m
            return m[0] * (m[4] * m[8] - m[5] * m[7]) - 
                   m[1] * (m[3] * m[8] - m[5] * m[6]) + 
                   m[2] * (m[3] * m[7] - m[4] * m[6])
        end,
        
        --- inverse (in-place)
        invert = function(self)
            local m = self.m
            local m00, m01, m02 = m[0], m[1], m[2]
            local m10, m11, m12 = m[3], m[4], m[5]
            local m20, m21, m22 = m[6], m[7], m[8]
            
            local c00 = m11 * m22 - m12 * m21
            local c01 = m12 * m20 - m10 * m22
            local c02 = m10 * m21 - m11 * m20
            
            local det = m00 * c00 + m01 * c01 + m02 * c02
            if abs(det) < 0x1p-52 then
                return self:identity()
            end
            
            local inv_det = 0x1p0 / det
            m[0] = c00 * inv_det
            m[1] = (m02 * m21 - m01 * m22) * inv_det
            m[2] = (m01 * m12 - m02 * m11) * inv_det
            m[3] = c01 * inv_det
            m[4] = (m00 * m22 - m02 * m20) * inv_det
            m[5] = (m02 * m10 - m00 * m12) * inv_det
            m[6] = c02 * inv_det
            m[7] = (m01 * m20 - m00 * m21) * inv_det
            m[8] = (m00 * m11 - m01 * m10) * inv_det
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul_scalar = function(self, s)
            local m = self.m
            m[0] = m[0] * s; m[1] = m[1] * s; m[2] = m[2] * s
            m[3] = m[3] * s; m[4] = m[4] * s; m[5] = m[5] * s
            m[6] = m[6] * s; m[7] = m[7] * s; m[8] = m[8] * s
            return self
        end,
        
        --- multiply by another mat3 (in-place: self = self * mat)
        mul = function(self, mat)
            local a = self.m
            local b = mat.m
            local a00, a01, a02 = a[0], a[1], a[2]
            local a10, a11, a12 = a[3], a[4], a[5]
            local a20, a21, a22 = a[6], a[7], a[8]
            
            a[0] = a00 * b[0] + a01 * b[3] + a02 * b[6]
            a[1] = a00 * b[1] + a01 * b[4] + a02 * b[7]
            a[2] = a00 * b[2] + a01 * b[5] + a02 * b[8]
            
            a[3] = a10 * b[0] + a11 * b[3] + a12 * b[6]
            a[4] = a10 * b[1] + a11 * b[4] + a12 * b[7]
            a[5] = a10 * b[2] + a11 * b[5] + a12 * b[8]
            
            a[6] = a20 * b[0] + a21 * b[3] + a22 * b[6]
            a[7] = a20 * b[1] + a21 * b[4] + a22 * b[7]
            a[8] = a20 * b[2] + a21 * b[5] + a22 * b[8]
            return self
        end,
        
        --- add another mat3 (in-place)
        add = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] + n[0]; m[1] = m[1] + n[1]; m[2] = m[2] + n[2]
            m[3] = m[3] + n[3]; m[4] = m[4] + n[4]; m[5] = m[5] + n[5]
            m[6] = m[6] + n[6]; m[7] = m[7] + n[7]; m[8] = m[8] + n[8]
            return self
        end,
        
        --- subtract another mat3 (in-place)
        sub = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] - n[0]; m[1] = m[1] - n[1]; m[2] = m[2] - n[2]
            m[3] = m[3] - n[3]; m[4] = m[4] - n[4]; m[5] = m[5] - n[5]
            m[6] = m[6] - n[6]; m[7] = m[7] - n[7]; m[8] = m[8] - n[8]
            return self
        end,
        
        --- rotation matrix around x-axis (radians) - OVERWRITES
        rotation_x = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            m[0] = 0x1p0; m[1] = 0x0p0; m[2] = 0x0p0
            m[3] = 0x0p0; m[4] = c;     m[5] = -s
            m[6] = 0x0p0; m[7] = s;     m[8] = c
            return self
        end,
        
        --- rotation matrix around y-axis (radians) - OVERWRITES
        rotation_y = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            m[0] = c;     m[1] = 0x0p0; m[2] = s
            m[3] = 0x0p0; m[4] = 0x1p0; m[5] = 0x0p0
            m[6] = -s;    m[7] = 0x0p0; m[8] = c
            return self
        end,
        
        --- rotation matrix around z-axis (radians) - OVERWRITES
        rotation_z = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            m[0] = c;     m[1] = -s;    m[2] = 0x0p0
            m[3] = s;     m[4] = c;     m[5] = 0x0p0
            m[6] = 0x0p0; m[7] = 0x0p0; m[8] = 0x1p0
            return self
        end,
        
        --- rotation matrix from euler angles (radians, xyz order) - OVERWRITES
        rotation_euler = function(self, x, y, z)
            local cx, sx = cos(x), sin(x)
            local cy, sy = cos(y), sin(y)
            local cz, sz = cos(z), sin(z)
            local m = self.m
            
            local czsy = cz * sy
            local szsy = sz * sy
            
            -- R = Rz * Ry * Rx (intr. ZYX / extr.. XYZ)
            -- row 0
            m[0] = cz * cy
            m[1] = czsy * sx - sz * cx
            m[2] = czsy * cx + sz * sx
            
            -- row 1
            m[3] = sz * cy
            m[4] = szsy * sx + cz * cx
            m[5] = szsy * cx - cz * sx
            
            -- 
            m[6] = -sy
            m[7] = cy * sx
            m[8] = cy * cx
            return self
        end,
        
        --- scale matrix - OVERWRITES
        scale = function(self, sx, sy, sz)
            local m = self.m
            m[0] = sx;    m[1] = 0x0p0; m[2] = 0x0p0
            m[3] = 0x0p0; m[4] = sy or sx; m[5] = 0x0p0
            m[6] = 0x0p0; m[7] = 0x0p0; m[8] = sz or sy or sx
            return self
        end,
        
        --- translation matrix (2d in 3x3 homogeneous coords) - OVERWRITES
        translation = function(self, x, y)
            local m = self.m
            m[0] = 0x1p0; m[1] = 0x0p0; m[2] = x
            m[3] = 0x0p0; m[4] = 0x1p0; m[5] = y
            m[6] = 0x0p0; m[7] = 0x0p0; m[8] = 0x1p0
            return self
        end,

        --- unpack for shader uniform
        unpack = function(self)
            local m = self.m
            return m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]
        end,
    },
    
    __tostring = function(self)
        local m = self.m
        return string.format("mat3(\n  %.6f, %.6f, %.6f\n  %.6f, %.6f, %.6f\n  %.6f, %.6f, %.6f\n)", 
            m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
    end,
}

mat3 = ffi.metatype("mat3", mat3_mt)

-- ============================================================================
-- MAT4 - 4X4 MATRIX
-- ============================================================================

ffi.cdef[[
typedef struct { double m[16]; } mat4;
]]

local mat4
local mat4_mt = {
    __new = function(ct, m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33)
        if m00 then
            return ffi.new(ct, {{
                m00, m01, m02, m03,
                m10, m11, m12, m13,
                m20, m21, m22, m23,
                m30, m31, m32, m33
            }})
        else
            local m = ffi.new(ct)
            m.m[0] = 0x1p0; m.m[5] = 0x1p0; m.m[10] = 0x1p0; m.m[15] = 0x1p0
            return m
        end
    end,

    __index = {
        --- set from values (row-major order)
        set = function(self, m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33)
            local m = self.m
            m[0] = m00;  m[1] = m01;  m[2] = m02;  m[3] = m03
            m[4] = m10;  m[5] = m11;  m[6] = m12;  m[7] = m13
            m[8] = m20;  m[9] = m21;  m[10] = m22; m[11] = m23
            m[12] = m30; m[13] = m31; m[14] = m32; m[15] = m33
            return self
        end,
        
        --- copy from another mat4
        copy = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = n[0];   m[1] = n[1];   m[2] = n[2];   m[3] = n[3]
            m[4] = n[4];   m[5] = n[5];   m[6] = n[6];   m[7] = n[7]
            m[8] = n[8];   m[9] = n[9];   m[10] = n[10]; m[11] = n[11]
            m[12] = n[12]; m[13] = n[13]; m[14] = n[14]; m[15] = n[15]
            return self
        end,
        
        --- clone to new mat4
        clone = function(self)
            local m = self.m
            return mat4(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], 
                       m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15])
        end,
        
        --- set to identity
        identity = function(self)
            local m = self.m
            m[0] = 0x1p0; m[1] = 0x0p0; m[2] = 0x0p0;  m[3] = 0x0p0
            m[4] = 0x0p0; m[5] = 0x1p0; m[6] = 0x0p0;  m[7] = 0x0p0
            m[8] = 0x0p0; m[9] = 0x0p0; m[10] = 0x1p0; m[11] = 0x0p0
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = 0x0p0; m[15] = 0x1p0
            return self
        end,
        
        --- set to zero matrix
        zero = function(self)
            local m = self.m
            m[0] = 0x0p0; m[1] = 0x0p0; m[2] = 0x0p0;  m[3] = 0x0p0
            m[4] = 0x0p0; m[5] = 0x0p0; m[6] = 0x0p0;  m[7] = 0x0p0
            m[8] = 0x0p0; m[9] = 0x0p0; m[10] = 0x0p0; m[11] = 0x0p0
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = 0x0p0; m[15] = 0x0p0
            return self
        end,
        
        --- transpose (in-place)
        transpose = function(self)
            local m = self.m
            local t
            t = m[1];  m[1] = m[4];   m[4] = t
            t = m[2];  m[2] = m[8];   m[8] = t
            t = m[3];  m[3] = m[12];  m[12] = t
            t = m[6];  m[6] = m[9];   m[9] = t
            t = m[7];  m[7] = m[13];  m[13] = t
            t = m[11]; m[11] = m[14]; m[14] = t
            return self
        end,
        
        --- determinant
        det = function(self)
            local m = self.m
            local m00, m01, m02, m03 = m[0], m[1], m[2], m[3]
            local m10, m11, m12, m13 = m[4], m[5], m[6], m[7]
            local m20, m21, m22, m23 = m[8], m[9], m[10], m[11]
            local m30, m31, m32, m33 = m[12], m[13], m[14], m[15]
            
            local s0 = m00 * m11 - m01 * m10
            local s1 = m00 * m12 - m02 * m10
            local s2 = m00 * m13 - m03 * m10
            local s3 = m01 * m12 - m02 * m11
            local s4 = m01 * m13 - m03 * m11
            local s5 = m02 * m13 - m03 * m12
            
            local c5 = m22 * m33 - m23 * m32
            local c4 = m21 * m33 - m23 * m31
            local c3 = m21 * m32 - m22 * m31
            local c2 = m20 * m33 - m23 * m30
            local c1 = m20 * m32 - m22 * m30
            local c0 = m20 * m31 - m21 * m30
            
            return s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
        end,
        
        --- inverse (in-place)
        invert = function(self)
            local m = self.m
            local m00, m01, m02, m03 = m[0], m[1], m[2], m[3]
            local m10, m11, m12, m13 = m[4], m[5], m[6], m[7]
            local m20, m21, m22, m23 = m[8], m[9], m[10], m[11]
            local m30, m31, m32, m33 = m[12], m[13], m[14], m[15]
            
            local s0 = m00 * m11 - m01 * m10
            local s1 = m00 * m12 - m02 * m10
            local s2 = m00 * m13 - m03 * m10
            local s3 = m01 * m12 - m02 * m11
            local s4 = m01 * m13 - m03 * m11
            local s5 = m02 * m13 - m03 * m12
            
            local c5 = m22 * m33 - m23 * m32
            local c4 = m21 * m33 - m23 * m31
            local c3 = m21 * m32 - m22 * m31
            local c2 = m20 * m33 - m23 * m30
            local c1 = m20 * m32 - m22 * m30
            local c0 = m20 * m31 - m21 * m30
            
            local det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
            
            if abs(det) < 0x1p-52 then
                return self:identity()
            end
            
            local inv_det = 0x1p0 / det
            
            m[0] = (m11 * c5 - m12 * c4 + m13 * c3) * inv_det
            m[1] = (-m01 * c5 + m02 * c4 - m03 * c3) * inv_det
            m[2] = (m31 * s5 - m32 * s4 + m33 * s3) * inv_det
            m[3] = (-m21 * s5 + m22 * s4 - m23 * s3) * inv_det
            
            m[4] = (-m10 * c5 + m12 * c2 - m13 * c1) * inv_det
            m[5] = (m00 * c5 - m02 * c2 + m03 * c1) * inv_det
            m[6] = (-m30 * s5 + m32 * s2 - m33 * s1) * inv_det
            m[7] = (m20 * s5 - m22 * s2 + m23 * s1) * inv_det
            
            m[8] = (m10 * c4 - m11 * c2 + m13 * c0) * inv_det
            m[9] = (-m00 * c4 + m01 * c2 - m03 * c0) * inv_det
            m[10] = (m30 * s4 - m31 * s2 + m33 * s0) * inv_det
            m[11] = (-m20 * s4 + m21 * s2 - m23 * s0) * inv_det
            
            m[12] = (-m10 * c3 + m11 * c1 - m12 * c0) * inv_det
            m[13] = (m00 * c3 - m01 * c1 + m02 * c0) * inv_det
            m[14] = (-m30 * s3 + m31 * s1 - m32 * s0) * inv_det
            m[15] = (m20 * s3 - m21 * s1 + m22 * s0) * inv_det
            
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul_scalar = function(self, s)
            local m = self.m
            m[0] = m[0] * s;   m[1] = m[1] * s;   m[2] = m[2] * s;   m[3] = m[3] * s
            m[4] = m[4] * s;   m[5] = m[5] * s;   m[6] = m[6] * s;   m[7] = m[7] * s
            m[8] = m[8] * s;   m[9] = m[9] * s;   m[10] = m[10] * s; m[11] = m[11] * s
            m[12] = m[12] * s; m[13] = m[13] * s; m[14] = m[14] * s; m[15] = m[15] * s
            return self
        end,
        
        --- multiply by another mat4 (in-place: self = self * mat)
        mul = function(self, mat)
            local a = self.m
            local b = mat.m
            local a00, a01, a02, a03 = a[0], a[1], a[2], a[3]
            local a10, a11, a12, a13 = a[4], a[5], a[6], a[7]
            local a20, a21, a22, a23 = a[8], a[9], a[10], a[11]
            local a30, a31, a32, a33 = a[12], a[13], a[14], a[15]
            
            -- row 0
            a[0] = a00 * b[0] + a01 * b[4] + a02 * b[8] + a03 * b[12]
            a[1] = a00 * b[1] + a01 * b[5] + a02 * b[9] + a03 * b[13]
            a[2] = a00 * b[2] + a01 * b[6] + a02 * b[10] + a03 * b[14]
            a[3] = a00 * b[3] + a01 * b[7] + a02 * b[11] + a03 * b[15]
            
            -- row 1
            a[4] = a10 * b[0] + a11 * b[4] + a12 * b[8] + a13 * b[12]
            a[5] = a10 * b[1] + a11 * b[5] + a12 * b[9] + a13 * b[13]
            a[6] = a10 * b[2] + a11 * b[6] + a12 * b[10] + a13 * b[14]
            a[7] = a10 * b[3] + a11 * b[7] + a12 * b[11] + a13 * b[15]
            
            -- row 2
            a[8] = a20 * b[0] + a21 * b[4] + a22 * b[8] + a23 * b[12]
            a[9] = a20 * b[1] + a21 * b[5] + a22 * b[9] + a23 * b[13]
            a[10] = a20 * b[2] + a21 * b[6] + a22 * b[10] + a23 * b[14]
            a[11] = a20 * b[3] + a21 * b[7] + a22 * b[11] + a23 * b[15]
            
            -- row 3
            a[12] = a30 * b[0] + a31 * b[4] + a32 * b[8] + a33 * b[12]
            a[13] = a30 * b[1] + a31 * b[5] + a32 * b[9] + a33 * b[13]
            a[14] = a30 * b[2] + a31 * b[6] + a32 * b[10] + a33 * b[14]
            a[15] = a30 * b[3] + a31 * b[7] + a32 * b[11] + a33 * b[15]
            return self
        end,
        
        --- add another mat4 (in-place)
        add = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] + n[0];   m[1] = m[1] + n[1];   m[2] = m[2] + n[2];   m[3] = m[3] + n[3]
            m[4] = m[4] + n[4];   m[5] = m[5] + n[5];   m[6] = m[6] + n[6];   m[7] = m[7] + n[7]
            m[8] = m[8] + n[8];   m[9] = m[9] + n[9];   m[10] = m[10] + n[10]; m[11] = m[11] + n[11]
            m[12] = m[12] + n[12]; m[13] = m[13] + n[13]; m[14] = m[14] + n[14]; m[15] = m[15] + n[15]
            return self
        end,
        
        --- subtract another mat4 (in-place)
        sub = function(self, mat)
            local m = self.m
            local n = mat.m
            m[0] = m[0] - n[0];   m[1] = m[1] - n[1];   m[2] = m[2] - n[2];   m[3] = m[3] - n[3]
            m[4] = m[4] - n[4];   m[5] = m[5] - n[5];   m[6] = m[6] - n[6];   m[7] = m[7] - n[7]
            m[8] = m[8] - n[8];   m[9] = m[9] - n[9];   m[10] = m[10] - n[10]; m[11] = m[11] - n[11]
            m[12] = m[12] - n[12]; m[13] = m[13] - n[13]; m[14] = m[14] - n[14]; m[15] = m[15] - n[15]
            return self
        end,
        
        --- apply rotation around x-axis (radians) to self
        rotation_x = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            local m01, m02 = m[1], m[2]
            local m05, m06 = m[5], m[6]
            local m09, m10 = m[9], m[10]
            local m13, m14 = m[13], m[14]
            
            m[1] = m01 * c + m02 * s
            m[2] = m02 * c - m01 * s
            m[5] = m05 * c + m06 * s
            m[6] = m06 * c - m05 * s
            m[9] = m09 * c + m10 * s
            m[10] = m10 * c - m09 * s
            m[13] = m13 * c + m14 * s
            m[14] = m14 * c - m13 * s
            return self
        end,
        
        --- apply rotation around y-axis (radians) to self
        rotation_y = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            local m00, m02 = m[0], m[2]
            local m04, m06 = m[4], m[6]
            local m08, m10 = m[8], m[10]
            local m12, m14 = m[12], m[14]
            
            m[0] = m00 * c - m02 * s
            m[2] = m02 * c + m00 * s
            m[4] = m04 * c - m06 * s
            m[6] = m06 * c + m04 * s
            m[8] = m08 * c - m10 * s
            m[10] = m10 * c + m08 * s
            m[12] = m12 * c - m14 * s
            m[14] = m14 * c + m12 * s
            return self
        end,
        
        --- apply rotation around z-axis (radians) to self
        rotation_z = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local m = self.m
            local m00, m01 = m[0], m[1]
            local m04, m05 = m[4], m[5]
            local m08, m09 = m[8], m[9]
            local m12, m13 = m[12], m[13]
            
            m[0] = m00 * c + m01 * s
            m[1] = m01 * c - m00 * s
            m[4] = m04 * c + m05 * s
            m[5] = m05 * c - m04 * s
            m[8] = m08 * c + m09 * s
            m[9] = m09 * c - m08 * s
            m[12] = m12 * c + m13 * s
            m[13] = m13 * c - m12 * s
            return self
        end,
        
        --- apply rotation from euler angles (radians, xyz order) to self
        rotation_euler = function(self, x, y, z)
            local cx, sx = cos(x), sin(x)
            local cy, sy = cos(y), sin(y)
            local cz, sz = cos(z), sin(z)
            local m = self.m
            
            local czsy = cz * sy
            local szsy = sz * sy
            
            -- R = Rz * Ry * Rx
            -- row 0
            m[0] = cz * cy
            m[1] = czsy * sx - sz * cx
            m[2] = czsy * cx + sz * sx
            m[3] = 0x0p0
            
            -- row 1
            m[4] = sz * cy
            m[5] = szsy * sx + cz * cx
            m[6] = szsy * cx - cz * sx
            m[7] = 0x0p0
            
            -- row 2
            m[8] = -sy
            m[9] = cy * sx
            m[10] = cy * cx
            m[11] = 0x0p0
            
            -- row 3
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = 0x0p0; m[15] = 0x1p0
            return self
        end,
        
        --- apply rotation from axis and angle (radians) to self
        rotation_axis = function(self, axis, angle)
            local c = cos(angle)
            local s = sin(angle)
            local t = 0x1p0 - c
            
            -- normalize axis
            local len = sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z)
            local x, y, z
            if len > 0x1p-32 then
                local inv_len = 0x1p0 / len
                x = axis.x * inv_len
                y = axis.y * inv_len
                z = axis.z * inv_len
            else
                return self
            end
            
            local r00 = t * x * x + c
            local r01 = t * x * y - s * z
            local r02 = t * x * z + s * y
            
            local r10 = t * x * y + s * z
            local r11 = t * y * y + c
            local r12 = t * y * z - s * x
            
            local r20 = t * x * z - s * y
            local r21 = t * y * z + s * x
            local r22 = t * z * z + c
            
            local m = self.m
            local a00, a01, a02, a03 = m[0], m[1], m[2], m[3]
            local a10, a11, a12, a13 = m[4], m[5], m[6], m[7]
            local a20, a21, a22, a23 = m[8], m[9], m[10], m[11]
            local a30, a31, a32, a33 = m[12], m[13], m[14], m[15]
            
            m[0] = a00 * r00 + a01 * r10 + a02 * r20
            m[1] = a00 * r01 + a01 * r11 + a02 * r21
            m[2] = a00 * r02 + a01 * r12 + a02 * r22
            
            m[4] = a10 * r00 + a11 * r10 + a12 * r20
            m[5] = a10 * r01 + a11 * r11 + a12 * r21
            m[6] = a10 * r02 + a11 * r12 + a12 * r22
            
            m[8] = a20 * r00 + a21 * r10 + a22 * r20
            m[9] = a20 * r01 + a21 * r11 + a22 * r21
            m[10] = a20 * r02 + a21 * r12 + a22 * r22
            
            m[12] = a30 * r00 + a31 * r10 + a32 * r20
            m[13] = a30 * r01 + a31 * r11 + a32 * r21
            m[14] = a30 * r02 + a31 * r12 + a32 * r22
            return self
        end,
        
        --- apply scale to self
        scale = function(self, sx, sy, sz)
            local m = self.m
            local y = sy or sx
            local z = sz or sy or sx
            
            m[0] = m[0] * sx;  m[1] = m[1] * y;  m[2] = m[2] * z
            m[4] = m[4] * sx;  m[5] = m[5] * y;  m[6] = m[6] * z
            m[8] = m[8] * sx;  m[9] = m[9] * y;  m[10] = m[10] * z
            m[12] = m[12] * sx; m[13] = m[13] * y; m[14] = m[14] * z
            return self
        end,
        
        --- apply translation to self
        translation = function(self, x, y, z)
            local m = self.m
            local z_val = z or 0x0p0
            
            m[3] = m[0] * x + m[1] * y + m[2] * z_val + m[3]
            m[7] = m[4] * x + m[5] * y + m[6] * z_val + m[7]
            m[11] = m[8] * x + m[9] * y + m[10] * z_val + m[11]
            m[15] = m[12] * x + m[13] * y + m[14] * z_val + m[15]
            return self
        end,
        
        --- perspective projection matrix (right-handed) - OVERWRITES
        perspective = function(self, fov, aspect, near, far)
            local f = 0x1p0 / tan(fov * 0x1p-1)
            local nf = 0x1p0 / (near - far)
            local m = self.m
            
            m[0] = f / aspect; m[1] = 0x0p0; m[2] = 0x0p0; m[3] = 0x0p0
            m[4] = 0x0p0; m[5] = f; m[6] = 0x0p0; m[7] = 0x0p0
            m[8] = 0x0p0; m[9] = 0x0p0; m[10] = (far + near) * nf; m[11] = 0x1p1 * far * near * nf
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = -0x1p0; m[15] = 0x0p0
            return self
        end,
        
        --- orthographic projection matrix (right-handed) - OVERWRITES
        orthographic = function(self, left, right, bottom, top, near, far)
            local rl = 0x1p0 / (right - left)
            local tb = 0x1p0 / (top - bottom)
            local fn = 0x1p0 / (far - near)
            local m = self.m
            
            m[0] = 0x1p1 * rl; m[1] = 0x0p0; m[2] = 0x0p0; m[3] = -(right + left) * rl
            m[4] = 0x0p0; m[5] = 0x1p1 * tb; m[6] = 0x0p0; m[7] = -(top + bottom) * tb
            m[8] = 0x0p0; m[9] = 0x0p0; m[10] = -0x1p1 * fn; m[11] = -(far + near) * fn
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = 0x0p0; m[15] = 0x1p0
            return self
        end,
        
        --- look-at view matrix (right-handed) - OVERWRITES
        look_at = function(self, eye, target, up)
            local zx = eye.x - target.x
            local zy = eye.y - target.y
            local zz = eye.z - target.z
            local len = zx*zx + zy*zy + zz*zz
            if len > 0x1p-32 then
                len = 0x1p0 / sqrt(len)
                zx = zx * len
                zy = zy * len
                zz = zz * len
            end
            
            local xx = up.y * zz - up.z * zy
            local xy = up.z * zx - up.x * zz
            local xz = up.x * zy - up.y * zx
            len = xx*xx + xy*xy + xz*xz
            if len > 0x1p-32 then
                len = 0x1p0 / sqrt(len)
                xx = xx * len
                xy = xy * len
                xz = xz * len
            end
            
            local yx = zy * xz - zz * xy
            local yy = zz * xx - zx * xz
            local yz = zx * xy - zy * xx
            
            local m = self.m
            
            -- rotation (rows = basis vectors for view matrix)
            m[0] = xx; m[1] = xy; m[2] = xz
            m[4] = yx; m[5] = yy; m[6] = yz
            m[8] = zx; m[9] = zy; m[10] = zz
            
            -- translation (dot product of basis and negative eye)
            m[3] = -(xx * eye.x + xy * eye.y + xz * eye.z)
            m[7] = -(yx * eye.x + yy * eye.y + yz * eye.z)
            m[11] = -(zx * eye.x + zy * eye.y + zz * eye.z)
            
            m[12] = 0x0p0; m[13] = 0x0p0; m[14] = 0x0p0; m[15] = 0x1p0
            return self
        end,
        
        --- transform vec3 by matrix (w = 1, point transformation)
        transform_point = function(self, v)
            local m = self.m
            local x = v.x
            local y = v.y
            local z = v.z
            local w = m[12] * x + m[13] * y + m[14] * z + m[15]
            w = w ~= 0x0p0 and (0x1p0 / w) or 0x1p0
            v.x = (m[0] * x + m[1] * y + m[2] * z + m[3]) * w
            v.y = (m[4] * x + m[5] * y + m[6] * z + m[7]) * w
            v.z = (m[8] * x + m[9] * y + m[10] * z + m[11]) * w
            return v
        end,
        
        --- transform vec3 by matrix (w = 0, direction transformation)
        transform_direction = function(self, v)
            local m = self.m
            local x = v.x
            local y = v.y
            local z = v.z
            v.x = m[0] * x + m[1] * y + m[2] * z
            v.y = m[4] * x + m[5] * y + m[6] * z
            v.z = m[8] * x + m[9] * y + m[10] * z
            return v
        end,
        
        --- extract position from transformation matrix
        get_position = function(self)
            local m = self.m
            return m[3], m[7], m[11]
        end,
        
        --- extract scale from transformation matrix
        get_scale = function(self)
            local m = self.m
            local sx = sqrt(m[0] * m[0] + m[4] * m[4] + m[8] * m[8])
            local sy = sqrt(m[1] * m[1] + m[5] * m[5] + m[9] * m[9])
            local sz = sqrt(m[2] * m[2] + m[6] * m[6] + m[10] * m[10])
            return sx, sy, sz
        end,
    },
    
    __tostring = function(self)
        local m = self.m
        return string.format("mat4(\n  %.6f, %.6f, %.6f, %.6f\n  %.6f, %.6f, %.6f, %.6f\n  %.6f, %.6f, %.6f, %.6f\n  %.6f, %.6f, %.6f, %.6f\n)", 
            m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12], m[13], m[14], m[15])
    end,
}

mat4 = ffi.metatype("mat4", mat4_mt)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

return {
    mat2 = mat2,
    mat3 = mat3,
    mat4 = mat4,
}