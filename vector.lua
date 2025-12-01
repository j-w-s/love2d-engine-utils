--- vector math library (vec2, vec3, vec4)
--- optimized for luajit with ffi, allocation sinking, ieee 754 hex floats
--- uses row-major storage for cache efficiency and simd-friendly access patterns
--- @module vector

local ffi = require("ffi")
local sqrt, abs, min, max, sin, cos, atan2, acos = math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.atan2, math.acos
local floor, ceil = math.floor, math.ceil

-- ============================================================================
-- VEC2 - 2D VECTOR
-- ============================================================================

ffi.cdef[[
typedef struct { double x, y; } vec2;
]]

local vec2
local vec2_mt = {
    __index = {
        --- set components
        set = function(self, x, y)
            self.x = x
            self.y = y
            return self
        end,
        
        --- copy from another vec2
        copy = function(self, v)
            self.x = v.x
            self.y = v.y
            return self
        end,
        
        --- clone to new vec2
        clone = function(self)
            return vec2(self.x, self.y)
        end,
        
        --- add vector (in-place)
        add = function(self, v)
            self.x = self.x + v.x
            self.y = self.y + v.y
            return self
        end,
        
        --- subtract vector (in-place)
        sub = function(self, v)
            self.x = self.x - v.x
            self.y = self.y - v.y
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul = function(self, s)
            self.x = self.x * s
            self.y = self.y * s
            return self
        end,
        
        --- divide by scalar (in-place)
        div = function(self, s)
            local inv = 0x1p0 / s
            self.x = self.x * inv
            self.y = self.y * inv
            return self
        end,
        
        --- negate (in-place)
        neg = function(self)
            self.x = -self.x
            self.y = -self.y
            return self
        end,
        
        --- dot product
        dot = function(self, v)
            return self.x * v.x + self.y * v.y
        end,
        
        --- cross product (returns scalar z-component)
        cross = function(self, v)
            return self.x * v.y - self.y * v.x
        end,
        
        --- length squared (avoid sqrt when comparing distances)
        len2 = function(self)
            return self.x * self.x + self.y * self.y
        end,
        
        --- length
        len = function(self)
            return sqrt(self.x * self.x + self.y * self.y)
        end,
        
        --- distance squared to another vector
        dist2 = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            return dx * dx + dy * dy
        end,
        
        --- distance to another vector
        dist = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            return sqrt(dx * dx + dy * dy)
        end,
        
        --- normalize (in-place)
        normalize = function(self)
            local len2 = self.x * self.x + self.y * self.y
            if len2 > 0x0p0 then
                local inv_len = 0x1p0 / sqrt(len2)
                self.x = self.x * inv_len
                self.y = self.y * inv_len
            end
            return self
        end,
        
        --- linear interpolation (in-place)
        lerp = function(self, v, t)
            self.x = self.x + (v.x - self.x) * t
            self.y = self.y + (v.y - self.y) * t
            return self
        end,
        
        --- reflect vector off surface with given normal
        reflect = function(self, n)
            local d = 0x1p1 * (self.x * n.x + self.y * n.y)
            self.x = self.x - d * n.x
            self.y = self.y - d * n.y
            return self
        end,
        
        --- rotate by angle (radians, in-place)
        rotate = function(self, angle)
            local c = cos(angle)
            local s = sin(angle)
            local x = self.x * c - self.y * s
            local y = self.x * s + self.y * c
            self.x = x
            self.y = y
            return self
        end,
        
        --- angle in radians
        angle = function(self)
            return atan2(self.y, self.x)
        end,
        
        --- angle between two vectors
        angle_to = function(self, v)
            local d = (self.x * v.x + self.y * v.y) / sqrt((self.x * self.x + self.y * self.y) * (v.x * v.x + v.y * v.y))
            return acos(max(-0x1p0, min(0x1p0, d)))
        end,
        
        --- perpendicular vector (90 degrees ccw)
        perp = function(self)
            local x = self.x
            self.x = -self.y
            self.y = x
            return self
        end,
        
        --- floor components
        floor = function(self)
            self.x = floor(self.x)
            self.y = floor(self.y)
            return self
        end,
        
        --- ceil components
        ceil = function(self)
            self.x = ceil(self.x)
            self.y = ceil(self.y)
            return self
        end,
        
        --- absolute value of components
        abs = function(self)
            self.x = abs(self.x)
            self.y = abs(self.y)
            return self
        end,
        
        --- component-wise min
        min = function(self, v)
            self.x = min(self.x, v.x)
            self.y = min(self.y, v.y)
            return self
        end,
        
        --- component-wise max
        max = function(self, v)
            self.x = max(self.x, v.x)
            self.y = max(self.y, v.y)
            return self
        end,
        
        --- clamp components
        clamp = function(self, min_val, max_val)
            self.x = max(min_val, min(max_val, self.x))
            self.y = max(min_val, min(max_val, self.y))
            return self
        end,
        
        --- unpack components
        unpack = function(self)
            return self.x, self.y
        end,
    },
    
    __add = function(a, b)
        return vec2(a.x + b.x, a.y + b.y)
    end,
    
    __sub = function(a, b)
        return vec2(a.x - b.x, a.y - b.y)
    end,
    
    __mul = function(a, b)
        if type(a) == "number" then
            return vec2(a * b.x, a * b.y)
        elseif type(b) == "number" then
            return vec2(a.x * b, a.y * b)
        else
            return vec2(a.x * b.x, a.y * b.y)
        end
    end,
    
    __div = function(a, b)
        if type(b) == "number" then
            local inv = 0x1p0 / b
            return vec2(a.x * inv, a.y * inv)
        else
            return vec2(a.x / b.x, a.y / b.y)
        end
    end,
    
    __unm = function(a)
        return vec2(-a.x, -a.y)
    end,
    
    __eq = function(a, b)
        return a.x == b.x and a.y == b.y
    end,
    
    __tostring = function(self)
        return string.format("vec2(%.6f, %.6f)", self.x, self.y)
    end,
}

vec2 = ffi.metatype("vec2", vec2_mt)

-- ============================================================================
-- VEC3 - 3D VECTOR
-- ============================================================================

ffi.cdef[[
typedef struct { double x, y, z; } vec3;
]]

local vec3
local vec3_mt = {
    __index = {
        --- set components
        set = function(self, x, y, z)
            self.x = x
            self.y = y
            self.z = z
            return self
        end,
        
        --- copy from another vec3
        copy = function(self, v)
            self.x = v.x
            self.y = v.y
            self.z = v.z
            return self
        end,
        
        --- clone to new vec3
        clone = function(self)
            return vec3(self.x, self.y, self.z)
        end,
        
        --- add vector (in-place)
        add = function(self, v)
            self.x = self.x + v.x
            self.y = self.y + v.y
            self.z = self.z + v.z
            return self
        end,
        
        --- subtract vector (in-place)
        sub = function(self, v)
            self.x = self.x - v.x
            self.y = self.y - v.y
            self.z = self.z - v.z
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul = function(self, s)
            self.x = self.x * s
            self.y = self.y * s
            self.z = self.z * s
            return self
        end,
        
        --- divide by scalar (in-place)
        div = function(self, s)
            local inv = 0x1p0 / s
            self.x = self.x * inv
            self.y = self.y * inv
            self.z = self.z * inv
            return self
        end,
        
        --- negate (in-place)
        neg = function(self)
            self.x = -self.x
            self.y = -self.y
            self.z = -self.z
            return self
        end,
        
        --- dot product
        dot = function(self, v)
            return self.x * v.x + self.y * v.y + self.z * v.z
        end,
        
        --- cross product (in-place)
        cross = function(self, v)
            local x = self.y * v.z - self.z * v.y
            local y = self.z * v.x - self.x * v.z
            local z = self.x * v.y - self.y * v.x
            self.x = x
            self.y = y
            self.z = z
            return self
        end,
        
        --- length squared
        len2 = function(self)
            return self.x * self.x + self.y * self.y + self.z * self.z
        end,
        
        --- length
        len = function(self)
            return sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
        end,
        
        --- distance squared to another vector
        dist2 = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            local dz = self.z - v.z
            return dx * dx + dy * dy + dz * dz
        end,
        
        --- distance to another vector
        dist = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            local dz = self.z - v.z
            return sqrt(dx * dx + dy * dy + dz * dz)
        end,
        
        --- normalize (in-place)
        normalize = function(self)
            local len2 = self.x * self.x + self.y * self.y + self.z * self.z
            if len2 > 0x0p0 then
                local inv_len = 0x1p0 / sqrt(len2)
                self.x = self.x * inv_len
                self.y = self.y * inv_len
                self.z = self.z * inv_len
            end
            return self
        end,
        
        --- linear interpolation (in-place)
        lerp = function(self, v, t)
            self.x = self.x + (v.x - self.x) * t
            self.y = self.y + (v.y - self.y) * t
            self.z = self.z + (v.z - self.z) * t
            return self
        end,
        
        --- reflect vector off surface with given normal
        reflect = function(self, n)
            local d = 0x1p1 * (self.x * n.x + self.y * n.y + self.z * n.z)
            self.x = self.x - d * n.x
            self.y = self.y - d * n.y
            self.z = self.z - d * n.z
            return self
        end,
        
        --- refract vector through surface with given normal and ratio
        refract = function(self, n, eta)
            local d = self.x * n.x + self.y * n.y + self.z * n.z
            local k = 0x1p0 - eta * eta * (0x1p0 - d * d)
            if k < 0x0p0 then
                self.x = 0x0p0
                self.y = 0x0p0
                self.z = 0x0p0
            else
                local a = eta * d + sqrt(k)
                self.x = eta * self.x - a * n.x
                self.y = eta * self.y - a * n.y
                self.z = eta * self.z - a * n.z
            end
            return self
        end,
        
        --- rotate around axis by angle (radians, in-place)
        rotate_axis = function(self, axis, angle)
            local c = cos(angle)
            local s = sin(angle)
            local t = 0x1p0 - c
            local ax, ay, az = axis.x, axis.y, axis.z
            
            local x = (t * ax * ax + c) * self.x + (t * ax * ay - s * az) * self.y + (t * ax * az + s * ay) * self.z
            local y = (t * ax * ay + s * az) * self.x + (t * ay * ay + c) * self.y + (t * ay * az - s * ax) * self.z
            local z = (t * ax * az - s * ay) * self.x + (t * ay * az + s * ax) * self.y + (t * az * az + c) * self.z
            
            self.x = x
            self.y = y
            self.z = z
            return self
        end,
        
        --- angle between two vectors
        angle_to = function(self, v)
            local d = (self.x * v.x + self.y * v.y + self.z * v.z) / sqrt((self.x * self.x + self.y * self.y + self.z * self.z) * (v.x * v.x + v.y * v.y + v.z * v.z))
            return acos(max(-0x1p0, min(0x1p0, d)))
        end,
        
        --- floor components
        floor = function(self)
            self.x = floor(self.x)
            self.y = floor(self.y)
            self.z = floor(self.z)
            return self
        end,
        
        --- ceil components
        ceil = function(self)
            self.x = ceil(self.x)
            self.y = ceil(self.y)
            self.z = ceil(self.z)
            return self
        end,
        
        --- absolute value of components
        abs = function(self)
            self.x = abs(self.x)
            self.y = abs(self.y)
            self.z = abs(self.z)
            return self
        end,
        
        --- component-wise min
        min = function(self, v)
            self.x = min(self.x, v.x)
            self.y = min(self.y, v.y)
            self.z = min(self.z, v.z)
            return self
        end,
        
        --- component-wise max
        max = function(self, v)
            self.x = max(self.x, v.x)
            self.y = max(self.y, v.y)
            self.z = max(self.z, v.z)
            return self
        end,
        
        --- clamp components
        clamp = function(self, min_val, max_val)
            self.x = max(min_val, min(max_val, self.x))
            self.y = max(min_val, min(max_val, self.y))
            self.z = max(min_val, min(max_val, self.z))
            return self
        end,
        
        --- unpack components
        unpack = function(self)
            return self.x, self.y, self.z
        end,
    },
    
    __add = function(a, b)
        return vec3(a.x + b.x, a.y + b.y, a.z + b.z)
    end,
    
    __sub = function(a, b)
        return vec3(a.x - b.x, a.y - b.y, a.z - b.z)
    end,
    
    __mul = function(a, b)
        if type(a) == "number" then
            return vec3(a * b.x, a * b.y, a * b.z)
        elseif type(b) == "number" then
            return vec3(a.x * b, a.y * b, a.z * b)
        else
            return vec3(a.x * b.x, a.y * b.y, a.z * b.z)
        end
    end,
    
    __div = function(a, b)
        if type(b) == "number" then
            local inv = 0x1p0 / b
            return vec3(a.x * inv, a.y * inv, a.z * inv)
        else
            return vec3(a.x / b.x, a.y / b.y, a.z / b.z)
        end
    end,
    
    __unm = function(a)
        return vec3(-a.x, -a.y, -a.z)
    end,
    
    __eq = function(a, b)
        return a.x == b.x and a.y == b.y and a.z == b.z
    end,
    
    __tostring = function(self)
        return string.format("vec3(%.6f, %.6f, %.6f)", self.x, self.y, self.z)
    end,
}

vec3 = ffi.metatype("vec3", vec3_mt)

-- ============================================================================
-- VEC4 - 4D VECTOR
-- ============================================================================

ffi.cdef[[
typedef struct { double x, y, z, w; } vec4;
]]

local vec4
local vec4_mt = {
    __index = {
        --- set components
        set = function(self, x, y, z, w)
            self.x = x
            self.y = y
            self.z = z
            self.w = w
            return self
        end,
        
        --- copy from another vec4
        copy = function(self, v)
            self.x = v.x
            self.y = v.y
            self.z = v.z
            self.w = v.w
            return self
        end,
        
        --- clone to new vec4
        clone = function(self)
            return vec4(self.x, self.y, self.z, self.w)
        end,
        
        --- add vector (in-place)
        add = function(self, v)
            self.x = self.x + v.x
            self.y = self.y + v.y
            self.z = self.z + v.z
            self.w = self.w + v.w
            return self
        end,
        
        --- subtract vector (in-place)
        sub = function(self, v)
            self.x = self.x - v.x
            self.y = self.y - v.y
            self.z = self.z - v.z
            self.w = self.w - v.w
            return self
        end,
        
        --- multiply by scalar (in-place)
        mul = function(self, s)
            self.x = self.x * s
            self.y = self.y * s
            self.z = self.z * s
            self.w = self.w * s
            return self
        end,
        
        --- divide by scalar (in-place)
        div = function(self, s)
            local inv = 0x1p0 / s
            self.x = self.x * inv
            self.y = self.y * inv
            self.z = self.z * inv
            self.w = self.w * inv
            return self
        end,
        
        --- negate (in-place)
        neg = function(self)
            self.x = -self.x
            self.y = -self.y
            self.z = -self.z
            self.w = -self.w
            return self
        end,
        
        --- dot product
        dot = function(self, v)
            return self.x * v.x + self.y * v.y + self.z * v.z + self.w * v.w
        end,
        
        --- length squared
        len2 = function(self)
            return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w
        end,
        
        --- length
        len = function(self)
            return sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w)
        end,
        
        --- distance squared to another vector
        dist2 = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            local dz = self.z - v.z
            local dw = self.w - v.w
            return dx * dx + dy * dy + dz * dz + dw * dw
        end,
        
        --- distance to another vector
        dist = function(self, v)
            local dx = self.x - v.x
            local dy = self.y - v.y
            local dz = self.z - v.z
            local dw = self.w - v.w
            return sqrt(dx * dx + dy * dy + dz * dz + dw * dw)
        end,
        
        --- normalize (in-place)
        normalize = function(self)
            local len2 = self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w
            if len2 > 0x0p0 then
                local inv_len = 0x1p0 / sqrt(len2)
                self.x = self.x * inv_len
                self.y = self.y * inv_len
                self.z = self.z * inv_len
                self.w = self.w * inv_len
            end
            return self
        end,
        
        --- linear interpolation (in-place)
        lerp = function(self, v, t)
            self.x = self.x + (v.x - self.x) * t
            self.y = self.y + (v.y - self.y) * t
            self.z = self.z + (v.z - self.z) * t
            self.w = self.w + (v.w - self.w) * t
            return self
        end,
        
        --- floor components
        floor = function(self)
            self.x = floor(self.x)
            self.y = floor(self.y)
            self.z = floor(self.z)
            self.w = floor(self.w)
            return self
        end,
        
        --- ceil components
        ceil = function(self)
            self.x = ceil(self.x)
            self.y = ceil(self.y)
            self.z = ceil(self.z)
            self.w = ceil(self.w)
            return self
        end,
        
        --- absolute value of components
        abs = function(self)
            self.x = abs(self.x)
            self.y = abs(self.y)
            self.z = abs(self.z)
            self.w = abs(self.w)
            return self
        end,
        
        --- component-wise min
        min = function(self, v)
            self.x = min(self.x, v.x)
            self.y = min(self.y, v.y)
            self.z = min(self.z, v.z)
            self.w = min(self.w, v.w)
            return self
        end,
        
        --- component-wise max
        max = function(self, v)
            self.x = max(self.x, v.x)
            self.y = max(self.y, v.y)
            self.z = max(self.z, v.z)
            self.w = max(self.w, v.w)
            return self
        end,
        
        --- clamp components
        clamp = function(self, min_val, max_val)
            self.x = max(min_val, min(max_val, self.x))
            self.y = max(min_val, min(max_val, self.y))
            self.z = max(min_val, min(max_val, self.z))
            self.w = max(min_val, min(max_val, self.w))
            return self
        end,
        
        --- unpack components
        unpack = function(self)
            return self.x, self.y, self.z, self.w
        end,
    },
    
    __add = function(a, b)
        return vec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
    end,
    
    __sub = function(a, b)
        return vec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
    end,
    
    __mul = function(a, b)
        if type(a) == "number" then
            return vec4(a * b.x, a * b.y, a * b.z, a * b.w)
        elseif type(b) == "number" then
            return vec4(a.x * b, a.y * b, a.z * b, a.w * b)
        else
            return vec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w)
        end
    end,
    
    __div = function(a, b)
        if type(b) == "number" then
            local inv = 0x1p0 / b
            return vec4(a.x * inv, a.y * inv, a.z * inv, a.w * inv)
        else
            return vec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w)
        end
    end,
    
    __unm = function(a)
        return vec4(-a.x, -a.y, -a.z, -a.w)
    end,
    
    __eq = function(a, b)
        return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
    end,
    
    __tostring = function(self)
        return string.format("vec4(%.6f, %.6f, %.6f, %.6f)", self.x, self.y, self.z, self.w)
    end,
}

vec4 = ffi.metatype("vec4", vec4_mt)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

return {
    vec2 = vec2,
    vec3 = vec3,
    vec4 = vec4,
}