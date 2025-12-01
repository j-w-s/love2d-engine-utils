-- stateful, grid-based physics system with aabb, circle, and polygon support
-- manages a spatial hash grid for fast broadphase collision detection.
-- all colliders are managed internally by id.
-- @module physics

local physics = {}

local bit = require("bit")
local band, lshift = bit.band, bit.lshift

-- ============================================================================
-- module state
-- ============================================================================

-- internal world state
local world = {
    colliders = {}, -- { id = { x, y, w, h, type, shape, mask, active, grid_keys, on_collide, radius, vertices } }
    grid = {},      -- { "x|y" = { id_a = true, id_b = true } }
    active_cells = {}, -- { "x|y" = true }
    cell_size = 64,
}

-- ============================================================================
-- local cache
-- ============================================================================

local lg = love and love.graphics or nil

local floor = math.floor
local min = math.min
local max = math.max
local abs = math.abs
local sqrt = math.sqrt
local huge = math.huge
local sin = math.sin
local cos = math.cos
local EMPTY_TABLE = {}
local temp_neighbors = {}

-- pooled tables for collision results
local hit_pool_x = {}
local hit_pool_y = {}

-- ieee 754 hex constants
local F1 = 0x1.a36e2eb1c432dp-14 -- 0.0001

-- ============================================================================
-- utility functions
-- ============================================================================

---
-- private: clear a table without re-allocating
--- @param t table the table to clear
local function clear_table(t)
    for k in pairs(t) do t[k] = nil end
end

---
-- private: dot product of two 2d vectors
--- @param x1 number
--- @param y1 number
--- @param x2 number
--- @param y2 number
--- @return number dot product
local function dot(x1, y1, x2, y2)
    return x1 * x2 + y1 * y2
end

---
-- private: normalize a 2d vector
--- @param x number
--- @param y number
--- @return number normalized x
--- @return number normalized y
local function normalize(x, y)
    local len = sqrt(x * x + y * y)
    if len < F1 then return 0, 0 end
    return x / len, y / len
end

---
-- private: project polygon onto axis
--- @param vertices table array of {x, y}
--- @param axis_x number
--- @param axis_y number
--- @return number min projection
--- @return number max projection
local function project_polygon(vertices, axis_x, axis_y)
    local min_proj = huge
    local max_proj = -huge
    
    for i = 1, #vertices do
        local proj = dot(vertices[i].x, vertices[i].y, axis_x, axis_y)
        min_proj = min(min_proj, proj)
        max_proj = max(max_proj, proj)
    end
    
    return min_proj, max_proj
end

---
-- private: get perpendicular vector (rotate 90 degrees)
--- @param x number
--- @param y number
--- @return number perpendicular x
--- @return number perpendicular y
local function perpendicular(x, y)
    return -y, x
end

-- ============================================================================
-- grid functions
-- ============================================================================

---
-- private: gets all grid keys for a given collider
--- @param col table the collider
--- @return table a set of "x|y" keys
local function get_grid_keys(col)
    local cs = world.cell_size
    local keys = {}
    
    if col.shape == "circle" then
        local x1 = floor((col.x - col.radius) / cs)
        local y1 = floor((col.y - col.radius) / cs)
        local x2 = floor((col.x + col.radius) / cs)
        local y2 = floor((col.y + col.radius) / cs)
        
        for y = y1, y2 do
            for x = x1, x2 do
                keys[x .. "|" .. y] = true
            end
        end
    elseif col.shape == "polygon" then
        if not col.vertices or #col.vertices == 0 then
            return keys
        end
        
        local min_x, min_y = huge, huge
        local max_x, max_y = -huge, -huge
        
        for i = 1, #col.vertices do
            local v = col.vertices[i]
            min_x = min(min_x, v.x)
            min_y = min(min_y, v.y)
            max_x = max(max_x, v.x)
            max_y = max(max_y, v.y)
        end
        
        local x1 = floor(min_x / cs)
        local y1 = floor(min_y / cs)
        local x2 = floor(max_x / cs)
        local y2 = floor(max_y / cs)
        
        for y = y1, y2 do
            for x = x1, x2 do
                keys[x .. "|" .. y] = true
            end
        end
    else
        -- aabb
        local x1 = floor(col.x / cs)
        local y1 = floor(col.y / cs)
        local x2 = floor((col.x + col.w - 1) / cs)
        local y2 = floor((col.y + col.h - 1) / cs)
        
        for y = y1, y2 do
            for x = x1, x2 do
                keys[x .. "|" .. y] = true
            end
        end
    end
    
    return keys
end

---
-- private: inserts a collider into the grid
--- @param id string|number collider id
--- @param col table the collider
local function grid_insert(id, col)
    local new_keys = get_grid_keys(col)
    col.grid_keys = new_keys
    
    for key in pairs(new_keys) do
        if not world.grid[key] then
            world.grid[key] = {}
            world.active_cells[key] = true
        end
        world.grid[key][id] = true
    end
end

---
-- private: removes a collider from the grid
--- @param id string|number collider id
--- @param col table the collider
local function grid_remove(id, col)
    if not col.grid_keys then return end
    
    for key in pairs(col.grid_keys) do
        local cell = world.grid[key]
        if cell then
            cell[id] = nil
            -- clean up empty cells
            if not next(cell) then
                world.grid[key] = nil
                world.active_cells[key] = nil
            end
        end
    end
    col.grid_keys = {}
end

-- ============================================================================
-- collision detection functions
-- ============================================================================

---
-- private: check if masks collide
--- @param mask1 number
--- @param mask2 number
--- @return boolean
local function masks_collide(mask1, mask2)
    return band(mask1, mask2) ~= 0
end

---
-- private: aabb check with early exit optimization
--- @param c1 table collider
--- @param x number position x
--- @param y number position y
--- @param c2 table collider
--- @return boolean true if overlapping
local function aabb_check(c1, x, y, c2)
    if x >= c2.x + c2.w then return false end
    if x + c1.w <= c2.x then return false end
    if y >= c2.y + c2.h then return false end
    if y + c1.h <= c2.y then return false end
    return true
end

---
-- private: circle vs circle collision check
--- @param c1 table circle collider
--- @param x number circle 1 x
--- @param y number circle 1 y
--- @param c2 table circle collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function circle_circle_check(c1, x, y, c2)
    local dx = c2.x - x
    local dy = c2.y - y
    local dist_sq = dx * dx + dy * dy
    local radius_sum = c1.radius + c2.radius
    
    if dist_sq >= radius_sum * radius_sum then
        return false, 0, 0, 0
    end
    
    local dist = sqrt(dist_sq)
    if dist < F1 then
        return true, radius_sum, 0, -1
    end
    
    local penetration = radius_sum - dist
    local nx = dx / dist
    local ny = dy / dist
    
    return true, penetration, nx, ny
end

---
-- private: circle vs aabb collision check
--- @param circle table circle collider
--- @param cx number circle x
--- @param cy number circle y
--- @param aabb table aabb collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function circle_aabb_check(circle, cx, cy, aabb)
    -- find closest point on aabb to circle center
    local closest_x = max(aabb.x, min(cx, aabb.x + aabb.w))
    local closest_y = max(aabb.y, min(cy, aabb.y + aabb.h))
    
    local dx = cx - closest_x
    local dy = cy - closest_y
    local dist_sq = dx * dx + dy * dy
    
    if dist_sq >= circle.radius * circle.radius then
        return false, 0, 0, 0
    end
    
    local dist = sqrt(dist_sq)
    
    -- circle center inside aabb
    if dist < F1 then
        -- find minimum distance to edge
        local dist_left = cx - aabb.x
        local dist_right = (aabb.x + aabb.w) - cx
        local dist_top = cy - aabb.y
        local dist_bottom = (aabb.y + aabb.h) - cy
        
        local min_dist = min(dist_left, dist_right, dist_top, dist_bottom)
        
        -- Return normal pointing from Circle -> AABB (Moving -> Static)
        if min_dist == dist_left then
            return true, circle.radius + dist_left, 1, 0
        elseif min_dist == dist_right then
            return true, circle.radius + dist_right, -1, 0
        elseif min_dist == dist_top then
            return true, circle.radius + dist_top, 0, 1
        else
            return true, circle.radius + dist_bottom, 0, -1
        end
    end
    
    local penetration = circle.radius - dist
    -- dx is Circle - Closest. So vector points AABB -> Circle.
    -- We need Circle -> AABB. So negate.
    local nx = -dx / dist
    local ny = -dy / dist
    
    return true, penetration, nx, ny
end

---
-- private: sat (separating axis theorem) for polygon vs polygon
--- @param poly1 table polygon collider
--- @param poly2 table polygon collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
---
-- private: sat (separating axis theorem) for polygon vs polygon
--- @param poly1 table polygon collider
--- @param poly2 table polygon collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function polygon_polygon_sat(poly1, poly2)
    local min_overlap = huge
    local smallest_axis_x, smallest_axis_y = 0, 0
    
    -- test axes from both polygons
    for _, poly in ipairs({poly1, poly2}) do
        local vertices = poly.vertices
        
        for i = 1, #vertices do
            local v1 = vertices[i]
            local v2 = vertices[i % #vertices + 1]
            
            -- get edge normal (perpendicular to edge)
            local edge_x = v2.x - v1.x
            local edge_y = v2.y - v1.y
            local axis_x, axis_y = perpendicular(edge_x, edge_y)
            axis_x, axis_y = normalize(axis_x, axis_y)
            
            if not (abs(axis_x) < F1 and abs(axis_y) < F1) then
                -- project both polygons onto axis
                local min1, max1 = project_polygon(poly1.vertices, axis_x, axis_y)
                local min2, max2 = project_polygon(poly2.vertices, axis_x, axis_y)
                
                -- check for separation
                if max1 < min2 or max2 < min1 then
                    return false, 0, 0, 0
                end
                
                -- calculate overlap
                local overlap = min(max1 - min2, max2 - min1)
                
                if overlap < min_overlap then
                    min_overlap = overlap
                    smallest_axis_x = axis_x
                    smallest_axis_y = axis_y
                    
                    -- ensure normal points from poly1 to poly2
                    local center1_x, center1_y = 0, 0
                    local center2_x, center2_y = 0, 0
                    
                    for j = 1, #poly1.vertices do
                        center1_x = center1_x + poly1.vertices[j].x
                        center1_y = center1_y + poly1.vertices[j].y
                    end
                    center1_x = center1_x / #poly1.vertices
                    center1_y = center1_y / #poly1.vertices
                    
                    for j = 1, #poly2.vertices do
                        center2_x = center2_x + poly2.vertices[j].x
                        center2_y = center2_y + poly2.vertices[j].y
                    end
                    center2_x = center2_x / #poly2.vertices
                    center2_y = center2_y / #poly2.vertices
                    
                    local d = dot(center2_x - center1_x, center2_y - center1_y, 
                                 smallest_axis_x, smallest_axis_y)
                    if d < 0 then
                        smallest_axis_x = -smallest_axis_x
                        smallest_axis_y = -smallest_axis_y
                    end
                end
            end
        end
    end
    
    return true, min_overlap, smallest_axis_x, smallest_axis_y
end

---
-- private: polygon vs aabb collision check
--- @param poly table polygon collider
--- @param aabb table aabb collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function polygon_aabb_check(poly, aabb)
    -- convert aabb to polygon
    local aabb_poly = {
        vertices = {
            {x = aabb.x, y = aabb.y},
            {x = aabb.x + aabb.w, y = aabb.y},
            {x = aabb.x + aabb.w, y = aabb.y + aabb.h},
            {x = aabb.x, y = aabb.y + aabb.h}
        }
    }
    
    return polygon_polygon_sat(poly, aabb_poly)
end

---
-- private: circle vs polygon collision check
--- @param circle table circle collider
--- @param cx number circle x
--- @param cy number circle y
--- @param poly table polygon collider
--- @return boolean true if overlapping
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function circle_polygon_check(circle, cx, cy, poly)
    local vertices = poly.vertices
    local min_overlap = huge
    local closest_axis_x, closest_axis_y = 0, 0
    
    -- test polygon edges
    for i = 1, #vertices do
        local v1 = vertices[i]
        local v2 = vertices[i % #vertices + 1]
        
        local edge_x = v2.x - v1.x
        local edge_y = v2.y - v1.y
        local axis_x, axis_y = perpendicular(edge_x, edge_y)
        axis_x, axis_y = normalize(axis_x, axis_y)
        
        -- project polygon
        local min_poly, max_poly = project_polygon(vertices, axis_x, axis_y)
        
        -- project circle
        local circle_proj = dot(cx, cy, axis_x, axis_y)
        local min_circle = circle_proj - circle.radius
        local max_circle = circle_proj + circle.radius
        
        if max_circle < min_poly or max_poly < min_circle then
            return false, 0, 0, 0
        end
        
        local overlap = min(max_circle - min_poly, max_poly - min_circle)
        if overlap < min_overlap then
            min_overlap = overlap
            closest_axis_x = axis_x
            closest_axis_y = axis_y
        end
    end
    
    -- test axis from circle center to closest vertex
    for i = 1, #vertices do
        local v = vertices[i]
        local axis_x = cx - v.x
        local axis_y = cy - v.y
        axis_x, axis_y = normalize(axis_x, axis_y)
        
        local min_poly, max_poly = project_polygon(vertices, axis_x, axis_y)
        
        local circle_proj = dot(cx, cy, axis_x, axis_y)
        local min_circle = circle_proj - circle.radius
        local max_circle = circle_proj + circle.radius
        
        if max_circle < min_poly or max_poly < min_circle then
            return false, 0, 0, 0
        end
        
        local overlap = min(max_circle - min_poly, max_poly - min_circle)
        if overlap < min_overlap then
            min_overlap = overlap
            closest_axis_x = axis_x
            closest_axis_y = axis_y
        end
    end
    
    return true, min_overlap, closest_axis_x, closest_axis_y
end

---
-- private: unified collision check
--- @param c1 table collider 1
--- @param x number position x
--- @param y number position y
--- @param c2 table collider 2
--- @return boolean true if colliding
--- @return number penetration depth
--- @return number normal x
--- @return number normal y
local function collision_check(c1, x, y, c2)
    local shape1 = c1.shape or "aabb"
    local shape2 = c2.shape or "aabb"
    
    if shape1 == "circle" and shape2 == "circle" then
        return circle_circle_check(c1, x, y, c2)
    elseif shape1 == "circle" and shape2 == "aabb" then
        return circle_aabb_check(c1, x, y, c2)
    elseif shape1 == "aabb" and shape2 == "circle" then
        local hit, pen, nx, ny = circle_aabb_check(c2, c2.x, c2.y, {x = x, y = y, w = c1.w, h = c1.h})
        return hit, pen, -nx, -ny
    elseif shape1 == "polygon" and shape2 == "polygon" then
        -- need to transform c1's vertices to test position
        local temp_poly = {vertices = {}}
        local dx = x - c1.x
        local dy = y - c1.y
        for i = 1, #c1.vertices do
            temp_poly.vertices[i] = {
                x = c1.vertices[i].x + dx,
                y = c1.vertices[i].y + dy
            }
        end
        return polygon_polygon_sat(temp_poly, c2)
    elseif shape1 == "polygon" and shape2 == "aabb" then
        local temp_poly = {vertices = {}}
        local dx = x - c1.x
        local dy = y - c1.y
        for i = 1, #c1.vertices do
            temp_poly.vertices[i] = {
                x = c1.vertices[i].x + dx,
                y = c1.vertices[i].y + dy
            }
        end
        return polygon_aabb_check(temp_poly, c2)
    elseif shape1 == "aabb" and shape2 == "polygon" then
        local hit, pen, nx, ny = polygon_aabb_check(c2, {x = x, y = y, w = c1.w, h = c1.h})
        return hit, pen, -nx, -ny
    elseif shape1 == "circle" and shape2 == "polygon" then
        return circle_polygon_check(c1, x, y, c2)
    elseif shape1 == "polygon" and shape2 == "circle" then
        local temp_poly = {vertices = {}}
        local dx = x - c1.x
        local dy = y - c1.y
        for i = 1, #c1.vertices do
            temp_poly.vertices[i] = {
                x = c1.vertices[i].x + dx,
                y = c1.vertices[i].y + dy
            }
        end
        local hit, pen, nx, ny = circle_polygon_check(c2, c2.x, c2.y, temp_poly)
        return hit, pen, -nx, -ny
    else
        -- aabb vs aabb
        if aabb_check(c1, x, y, c2) then
            -- calculate penetration and normal
            local left = (c2.x + c2.w) - x
            local right = (x + c1.w) - c2.x
            local top = (c2.y + c2.h) - y
            local bottom = (y + c1.h) - c2.y
            
            local min_pen = min(left, right, top, bottom)
            
            if min_pen == left then
                return true, left, -1, 0
            elseif min_pen == right then
                return true, right, 1, 0
            elseif min_pen == top then
                return true, top, 0, -1
            else
                return true, bottom, 0, 1
            end
        end
        return false, 0, 0, 0
    end
end

---
-- private: swept aabb collision
--- @param c1 table moving collider
--- @param dx number delta x
--- @param dy number delta y
--- @param c2 table static collider
--- @return number time (0-1, or 1 if no collision)
--- @return number normal_x
--- @return number normal_y
local function swept_aabb(c1, dx, dy, c2)
    local c1x, c1y, c1w, c1h = c1.x, c1.y, c1.w, c1.h
    local c2x, c2y, c2w, c2h = c2.x, c2.y, c2.w, c2.h
    
    local inv_entry_x, inv_exit_x
    local inv_entry_y, inv_exit_y
    
    if dx > 0 then
        inv_entry_x = c2x - (c1x + c1w)
        inv_exit_x = (c2x + c2w) - c1x
    else
        inv_entry_x = (c2x + c2w) - c1x
        inv_exit_x = c2x - (c1x + c1w)
    end
    
    if dy > 0 then
        inv_entry_y = c2y - (c1y + c1h)
        inv_exit_y = (c2y + c2h) - c1y
    else
        inv_entry_y = (c2y + c2h) - c1y
        inv_exit_y = c2y - (c1y + c1h)
    end
    
    local entry_x, exit_x
    local entry_y, exit_y
    
    if dx == 0 then
        entry_x = -huge
        exit_x = huge
    else
        entry_x = inv_entry_x / dx
        exit_x = inv_exit_x / dx
    end
    
    if dy == 0 then
        entry_y = -huge
        exit_y = huge
    else
        entry_y = inv_entry_y / dy
        exit_y = inv_exit_y / dy
    end
    
    local entry_time = max(entry_x, entry_y)
    local exit_time = min(exit_x, exit_y)
    
    if entry_time > exit_time or (entry_x < 0 and entry_y < 0) or entry_x > 1 or entry_y > 1 then
        return 1, 0, 0
    end
    
    local nx, ny = 0, 0
    if entry_x > entry_y then
        nx = inv_entry_x < 0 and 1 or -1
        ny = 0
    else
        nx = 0
        ny = inv_entry_y < 0 and 1 or -1
    end
    
    return entry_time, nx, ny
end

---
-- private: get potential neighbors from the grid
--- @param col table collider to check
--- @param filter_type string (optional) only get this type
--- @param filter_mask number (optional) collision mask filter
--- @param filter_id string|number (optional) id to ignore
--- @return table sparse array of neighbors
local function get_neighbors(col, filter_type, filter_mask, filter_id)
    clear_table(temp_neighbors)
    
    local keys = col.grid_keys or get_grid_keys(col)
    local col_mask = col.mask or 0xFFFFFFFF
    
    for key in pairs(keys) do
        local cell = world.grid[key]
        if cell then
            for id in pairs(cell) do
                if id ~= filter_id then
                    local n_col = world.colliders[id]
                    if n_col and n_col.active then
                        local type_match = not filter_type or n_col.type == filter_type
                        local n_mask = n_col.mask or 0xFFFFFFFF
                        local mask_match = masks_collide(col_mask, n_mask)
                        
                        if filter_mask then
                            mask_match = mask_match and masks_collide(filter_mask, n_mask)
                        end
                        
                        if type_match and mask_match then
                            temp_neighbors[id] = n_col
                        end
                    end
                end
            end
        end
    end
    return temp_neighbors
end

-- ============================================================================
-- public api
-- ============================================================================

--- initialize or re-initialize the physics world
--- @param cell_size number size of the grid cells (e.g., 16 or 32)
function physics.init(cell_size)
    world.cell_size = cell_size or 64
    physics.clear()
end

--- clear all colliders and reset the grid
function physics.clear()
    world.colliders = {}
    world.grid = {}
    world.active_cells = {}
end

--- add or update an aabb collider in the world
--- @param id string|number unique id
--- @param x number
--- @param y number
--- @param w number
--- @param h number
--- @param type string (optional) e.g., 'solid', 'trigger', 'player'
--- @param active boolean (optional) if false, is ignored by queries
--- @param mask number (optional) collision bitmask (default: 0xFFFFFFFF)
--- @param on_collide function (optional) callback(id, other_id, other_col, nx, ny)
function physics.add(id, x, y, w, h, type, active, mask, on_collide)
    local col = world.colliders[id]
    
    if col then
        grid_remove(id, col)
        col.x = x
        col.y = y
        col.w = w
        col.h = h
        col.type = type
        col.shape = "aabb"
        col.active = (active == nil) and true or active
        col.mask = mask or 0xFFFFFFFF
        col.on_collide = on_collide
    else
        col = {
            x = x, y = y, w = w, h = h,
            type = type,
            shape = "aabb",
            active = (active == nil) and true or active,
            mask = mask or 0xFFFFFFFF,
            on_collide = on_collide
        }
        world.colliders[id] = col
    end
    
    grid_insert(id, col)
end

--- add or update a circle collider in the world
--- @param id string|number unique id
--- @param x number center x
--- @param y number center y
--- @param radius number
--- @param type string (optional)
--- @param active boolean (optional)
--- @param mask number (optional)
--- @param on_collide function (optional)
function physics.add_circle(id, x, y, radius, type, active, mask, on_collide)
    local col = world.colliders[id]
    
    if col then
        grid_remove(id, col)
        col.x = x
        col.y = y
        col.radius = radius
        col.type = type
        col.shape = "circle"
        col.active = (active == nil) and true or active
        col.mask = mask or 0xFFFFFFFF
        col.on_collide = on_collide
        col.w = radius * 2
        col.h = radius * 2
    else
        col = {
            x = x, y = y,
            radius = radius,
            w = radius * 2,
            h = radius * 2,
            type = type,
            shape = "circle",
            active = (active == nil) and true or active,
            mask = mask or 0xFFFFFFFF,
            on_collide = on_collide
        }
        world.colliders[id] = col
    end
    
    grid_insert(id, col)
end

--- add or update a polygon collider in the world
-- vertices are specified in world space
--- @param id string|number unique id
--- @param x number reference x position
--- @param y number reference y position
--- @param vertices table array of {x=number, y=number} in world space
--- @param type string (optional)
--- @param active boolean (optional)
--- @param mask number (optional)
--- @param on_collide function (optional)
function physics.add_polygon(id, x, y, vertices, type, active, mask, on_collide)
    local col = world.colliders[id]
    
    if col then
        grid_remove(id, col)
        col.x = x
        col.y = y
        col.vertices = vertices
        col.type = type
        col.shape = "polygon"
        col.active = (active == nil) and true or active
        col.mask = mask or 0xFFFFFFFF
        col.on_collide = on_collide
    else
        col = {
            x = x, y = y,
            vertices = vertices,
            type = type,
            shape = "polygon",
            active = (active == nil) and true or active,
            mask = mask or 0xFFFFFFFF,
            on_collide = on_collide
        }
        world.colliders[id] = col
    end
    
    grid_insert(id, col)
end

--- add or update a collider (just layer, no mask)
--- @param id string|number unique id
--- @param x number
--- @param y number
--- @param w number
--- @param h number
--- @param type string (optional)
--- @param layer number (optional) layer number (0-31), converted to bitmask
--- @param active boolean (optional)
--- @param on_collide function (optional)
function physics.add_layered(id, x, y, w, h, type, layer, active, on_collide)
    local mask = lshift(1, layer or 0)
    physics.add(id, x, y, w, h, type, active, mask, on_collide)
end

--- remove a collider from the world
--- @param id string|number unique id
function physics.remove(id)
    local col = world.colliders[id]
    if col then
        grid_remove(id, col)
        world.colliders[id] = nil
    end
end

--- update a collider's position and re-insert into grid
-- use this for non-physics-driven movement.
-- for physics-driven movement, use 'physics.move()'.
--- @param id string|number unique id
--- @param x number new x
--- @param y number new y
function physics.update(id, x, y)
    local col = world.colliders[id]
    if not col then return end
    
    grid_remove(id, col)
    col.x = x
    col.y = y
    grid_insert(id, col)
end

--- update polygon vertices (use after rotating/scaling a polygon)
--- @param id string|number unique id
--- @param vertices table new vertices in world space
function physics.update_polygon(id, vertices)
    local col = world.colliders[id]
    if not col or col.shape ~= "polygon" then return end
    
    grid_remove(id, col)
    col.vertices = vertices
    grid_insert(id, col)
end

--- check for overlap at a potential position
--- @param id string|number id of the checker
--- @param x number x-position to check at
--- @param y number y-position to check at
--- @param type_filter string (optional) only check against this type
--- @param mask_filter number (optional) collision mask filter
--- @return table a table of colliders this object would hit
function physics.check(id, x, y, type_filter, mask_filter)
    local col = world.colliders[id]
    if not col then return EMPTY_TABLE end
    
    -- create temp collider at new position for neighbor query
    local temp_col = {
        x = x, y = y,
        w = col.w, h = col.h,
        radius = col.radius,
        shape = col.shape,
        mask = col.mask,
        grid_keys = nil -- force recalculation
    }
    
    -- for polygons, shift vertices to new position
    if col.shape == "polygon" then
        temp_col.vertices = {}
        local dx = x - col.x
        local dy = y - col.y
        for i = 1, #col.vertices do
            temp_col.vertices[i] = {
                x = col.vertices[i].x + dx,
                y = col.vertices[i].y + dy
            }
        end
    end
    
    local hits = {}
    local neighbors = get_neighbors(temp_col, type_filter, mask_filter, id)
    
    for n_id, n_col in pairs(neighbors) do
        local hit = collision_check(col, x, y, n_col)
        if hit then
            hits[n_id] = n_col
        end
    end
    
    return hits
end

--- cache neighbors for a collider
--- @param id string|number collider id
function physics.cache_neighbors(id)
    local col = world.colliders[id]
    if not col then return end
    col.cached_neighbors = get_neighbors(col)
end

--- clear cached neighbors for a collider
--- @param id string|number collider id
function physics.clear_cache(id)
    local col = world.colliders[id]
    if col then
        col.cached_neighbors = nil
    end
end

--- move a collider with collision resolution
--- @param id string|number id to move
--- @param dx number
--- @param dy number
--- @param use_swept boolean (optional) use swept aabb for continuous collision
--- @param stop_on_first boolean (optional) stop on first collision (faster)
--- @return number new_x
--- @return number new_y
--- @return table hits { x = {id=col}, y = {id=col} }
function physics.move(id, dx, dy, use_swept, stop_on_first)
    local col = world.colliders[id]
    if not col then return 0, 0, EMPTY_TABLE end
    
    local new_x, new_y = col.x, col.y
    
    clear_table(hit_pool_x)
    clear_table(hit_pool_y)
    local hits = { x = hit_pool_x, y = hit_pool_y }
    
    if use_swept and (dx ~= 0 or dy ~= 0) and col.shape == "aabb" then
        -- swept aabb only works for aabb shapes
        local temp_col = {
            x = min(col.x, col.x + dx),
            y = min(col.y, col.y + dy),
            w = col.w + abs(dx),
            h = col.h + abs(dy),
            shape = "aabb",
            mask = col.mask,
            grid_keys = nil
        }
        
        local neighbors = get_neighbors(temp_col, 'solid', nil, id)
        local min_time = 1
        local closest_id, closest_col
        local final_nx, final_ny = 0, 0
        
        for n_id, n_col in pairs(neighbors) do
            if n_col.shape == "aabb" then
                local time, nx, ny = swept_aabb(col, dx, dy, n_col)
                if time < min_time then
                    min_time = time
                    closest_id = n_id
                    closest_col = n_col
                    final_nx, final_ny = nx, ny
                    
                    if stop_on_first and min_time < 1 then
                        break
                    end
                end
            end
        end
        
        new_x = col.x + dx * min_time
        new_y = col.y + dy * min_time
        
        if closest_id then
            if final_nx ~= 0 then
                hits.x[closest_id] = closest_col
                if col.on_collide then
                    col.on_collide(id, closest_id, closest_col, final_nx, final_ny)
                end
            end
            if final_ny ~= 0 then
                hits.y[closest_id] = closest_col
                if col.on_collide then
                    col.on_collide(id, closest_id, closest_col, final_nx, final_ny)
                end
            end
        end
    else
        -- move and slide with full collision resolution
        if dx ~= 0 then
            new_x = new_x + dx
            local hits_x = physics.check(id, new_x, new_y, 'solid')
            
            for n_id, n_col in pairs(hits_x) do
                local hit, pen, nx, ny = collision_check(col, new_x, new_y, n_col)
                
                if hit then
                    -- ensure normal aligns with velocity
                    if dx * nx < 0 then
                        nx = -nx
                        ny = -ny
                    end

                    hits.x[n_id] = n_col
                    
                    -- resolve collision
                    if col.shape == "aabb" and n_col.shape == "aabb" then
                        new_x = (dx > 0) and (n_col.x - col.w) or (n_col.x + n_col.w)
                    else
                        -- use penetration normal for non-aabb
                        new_x = new_x - nx * pen
                    end
                    
                    if col.on_collide then
                        col.on_collide(id, n_id, n_col, nx, ny)
                    end
                end
            end
        end
        
        if dy ~= 0 then
            new_y = new_y + dy
            local hits_y = physics.check(id, new_x, new_y, 'solid')
            
            for n_id, n_col in pairs(hits_y) do
                local hit, pen, nx, ny = collision_check(col, new_x, new_y, n_col)
                
                if hit then
                    -- ensure normal aligns with velocity
                    if dy * ny < 0 then
                        nx = -nx
                        ny = -ny
                    end

                    hits.y[n_id] = n_col
                    
                    if col.shape == "aabb" and n_col.shape == "aabb" then
                        new_y = (dy > 0) and (n_col.y - col.h) or (n_col.y + n_col.h)
                    else
                        new_y = new_y - ny * pen
                    end
                    
                    if col.on_collide then
                        col.on_collide(id, n_id, n_col, nx, ny)
                    end
                end
            end
        end
    end
    
    physics.update(id, new_x, new_y)
    
    return new_x, new_y, hits
end

--- raycast through the world
--- @param x1 number start x
--- @param y1 number start y
--- @param x2 number end x
--- @param y2 number end y
--- @param type_filter string (optional) only check this type
--- @param mask_filter number (optional) collision mask filter
--- @param callback function (optional) fn(id, col, hit_x, hit_y) -> bool (return true to stop)
--- @return table array of hits: { {id, col, x, y, distance}, ... }
function physics.raycast(x1, y1, x2, y2, type_filter, mask_filter, callback)
    local dx = x2 - x1
    local dy = y2 - y1
    local distance = sqrt(dx * dx + dy * dy)
    
    if distance == 0 then return {} end
    
    local dir_x = dx / distance
    local dir_y = dy / distance
    local hits = {}
    
    local cs = world.cell_size
    local cx = floor(x1 / cs)
    local cy = floor(y1 / cs)
    local end_cx = floor(x2 / cs)
    local end_cy = floor(y2 / cs)
    
    local step_x = dir_x >= 0 and 1 or -1
    local step_y = dir_y >= 0 and 1 or -1
    
    local t_delta_x = (dir_x ~= 0) and (cs / abs(dx)) or huge
    local t_delta_y = (dir_y ~= 0) and (cs / abs(dy)) or huge
    
    local t_max_x = (dir_x ~= 0) and ((cx + (step_x > 0 and 1 or 0)) * cs - x1) / dx or huge
    local t_max_y = (dir_y ~= 0) and ((cy + (step_y > 0 and 1 or 0)) * cs - y1) / dy or huge
    
    local checked = {}
    local max_steps = 1000
    local steps = 0
    
    while steps < max_steps do
        steps = steps + 1
        
        local key = cx .. "|" .. cy
        local cell = world.grid[key]
        
        if cell then
            for id in pairs(cell) do
                if not checked[id] then
                    checked[id] = true
                    local col = world.colliders[id]
                    
                    if col and col.active then
                        local type_match = not type_filter or col.type == type_filter
                        local mask_match = true
                        
                        if mask_filter then
                            mask_match = masks_collide(mask_filter, col.mask)
                        end
                        
                        if type_match and mask_match then
                            local hit_x, hit_y, t
                            
                            if col.shape == "circle" then
                                -- ray-circle intersection
                                local fx = x1 - col.x
                                local fy = y1 - col.y
                                
                                local a = dir_x * dir_x + dir_y * dir_y
                                local b = 2 * (fx * dir_x + fy * dir_y)
                                local c = fx * fx + fy * fy - col.radius * col.radius
                                
                                local discriminant = b * b - 4 * a * c
                                
                                if discriminant >= 0 then
                                    local sqrt_disc = sqrt(discriminant)
                                    local t1 = (-b - sqrt_disc) / (2 * a)
                                    local t2 = (-b + sqrt_disc) / (2 * a)
                                    
                                    if t1 >= 0 and t1 <= distance then
                                        t = t1
                                    elseif t2 >= 0 and t2 <= distance then
                                        t = t2
                                    end
                                    
                                    if t then
                                        hit_x = x1 + dir_x * t
                                        hit_y = y1 + dir_y * t
                                    end
                                end
                            elseif col.shape == "aabb" then
                                -- ray-aabb intersection
                                local colx, coly, colw, colh = col.x, col.y, col.w, col.h
                                
                                local tx1 = (colx - x1) / dx
                                local tx2 = (colx + colw - x1) / dx
                                local ty1 = (coly - y1) / dy
                                local ty2 = (coly + colh - y1) / dy
                                
                                if dx == 0 then tx1, tx2 = -huge, huge end
                                if dy == 0 then ty1, ty2 = -huge, huge end
                                
                                local tmin = max(min(tx1, tx2), min(ty1, ty2))
                                local tmax = min(max(tx1, tx2), max(ty1, ty2))
                                
                                if tmax >= 0 and tmin <= tmax and tmin <= 1 then
                                    t = max(0, tmin) * distance
                                    hit_x = x1 + dx * max(0, tmin)
                                    hit_y = y1 + dy * max(0, tmin)
                                end
                            elseif col.shape == "polygon" then
                                -- ray-polygon intersection
                                local vertices = col.vertices
                                local min_t = huge
                                
                                for i = 1, #vertices do
                                    local v1 = vertices[i]
                                    local v2 = vertices[i % #vertices + 1]
                                    
                                    -- edge segment vector
                                    local s1_x = v2.x - v1.x
                                    local s1_y = v2.y - v1.y
                                    -- ray vector (to max distance)
                                    local s2_x = dx
                                    local s2_y = dy
                                    
                                    local denom = s2_x * s1_y - s2_y * s1_x
                                    
                                    if abs(denom) > F1 then
                                        local s = (s1_y * (v1.x - x1) - s1_x * (v1.y - y1)) / denom
                                        local t_edge = (-s2_x * (v1.y - y1) + s2_y * (v1.x - x1)) / denom
                                        
                                        -- s is along the segment (0..1), t_edge is along the ray (0..1)
                                        if s >= 0 and s <= 1 and t_edge >= 0 and t_edge <= 1 then
                                            local edge_t = t_edge * distance
                                            if edge_t < min_t then
                                                min_t = edge_t
                                            end
                                        end
                                    end
                                end
                                
                                if min_t < huge then
                                    t = min_t
                                    hit_x = x1 + dir_x * t
                                    hit_y = y1 + dir_y * t
                                end
                            end
                            
                            if t then
                                table.insert(hits, {
                                    id = id,
                                    col = col,
                                    x = hit_x,
                                    y = hit_y,
                                    distance = t
                                })
                                
                                if callback and callback(id, col, hit_x, hit_y) then
                                    table.sort(hits, function(a, b) return a.distance < b.distance end)
                                    return hits
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if cx == end_cx and cy == end_cy then break end
        
        if t_max_x < t_max_y then
            t_max_x = t_max_x + t_delta_x
            cx = cx + step_x
        else
            t_max_y = t_max_y + t_delta_y
            cy = cy + step_y
        end
    end
    
    table.sort(hits, function(a, b) return a.distance < b.distance end)
    
    return hits
end

--- get a collider by id
--- @param id string|number
--- @return table collider or nil
function physics.get(id)
    return world.colliders[id]
end

--- check if a collider exists
--- @param id string|number
--- @return boolean
function physics.exists(id)
    return world.colliders[id] ~= nil
end

--- get all colliders in a region
--- @param x number
--- @param y number
--- @param w number
--- @param h number
--- @param type_filter string (optional)
--- @param mask_filter number (optional)
--- @return table array of {id, col}
function physics.query_region(x, y, w, h, type_filter, mask_filter)
    local results = {}
    local temp_col = { x = x, y = y, w = w, h = h, shape = "aabb", mask = mask_filter or 0xFFFFFFFF }
    local neighbors = get_neighbors(temp_col, type_filter, mask_filter, nil)
    
    for n_id, n_col in pairs(neighbors) do
        local hit = collision_check(temp_col, x, y, n_col)
        if hit then
            table.insert(results, { id = n_id, col = n_col })
        end
    end
    
    return results
end

--- get statistics about the physics world
--- @return table { colliders, active_cells, total_cells }
function physics.get_stats()
    local collider_count = 0
    for _ in pairs(world.colliders) do collider_count = collider_count + 1 end
    
    local active_cell_count = 0
    for _ in pairs(world.active_cells) do active_cell_count = active_cell_count + 1 end
    
    local total_cell_count = 0
    for _ in pairs(world.grid) do total_cell_count = total_cell_count + 1 end
    
    return {
        colliders = collider_count,
        active_cells = active_cell_count,
        total_cells = total_cell_count,
        cell_size = world.cell_size
    }
end

--- draw debug information for colliders and grid
--- @param color_map table (optional) { type = {r,g,b,a} }
function physics.debug_draw(color_map)
    if not lg then 
        error("debug_draw requires LÖVE graphics (love.graphics)")
    end
    
    color_map = color_map or {}
    local default_color = {1, 0, 1, 0.5}
    
    for id, col in pairs(world.colliders) do
        local color = color_map[col.type] or default_color
        lg.setColor(color)
        
        if col.shape == "circle" then
            lg.circle("line", col.x, col.y, col.radius)
        elseif col.shape == "polygon" then
            if col.vertices and #col.vertices >= 3 then
                local points = {}
                for i = 1, #col.vertices do
                    table.insert(points, col.vertices[i].x)
                    table.insert(points, col.vertices[i].y)
                end
                lg.polygon("line", points)
            end
        else
            lg.rectangle("line", col.x, col.y, col.w, col.h)
        end
    end
    
    lg.setColor(0, 1, 0, 0.3)
    local cs = world.cell_size
    for key in pairs(world.grid) do
        local parts = {}
        for part in key:gmatch("([^|]+)") do table.insert(parts, part) end
        local x = tonumber(parts[1]) * cs
        local y = tonumber(parts[2]) * cs
        lg.rectangle("line", x, y, cs, cs)
    end
    
    lg.setColor(1, 1, 1, 1)
end

return physics