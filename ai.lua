--- pathfinding, planning, behavior systems
-- optimized for luajit/lua 5.3+ with ieee 754 hex floats
-- @module ai

local bit = require("bit")
local band, bor = bit.band, bit.bor
local floor, abs, sqrt = math.floor, math.abs, math.sqrt
local min, max = math.min, math.max
local insert, remove = table.insert, table.remove
local cos, sin, atan2 = math.cos, math.sin, math.atan

-- ============================================================================
-- UTILITIES
-- ============================================================================

--- manhattan distance between two points
--- @param x1 first x coordinate
--- @param y1 first y coordinate
--- @param x2 second x coordinate
--- @param y2 second y coordinate
--- @return number manhattan distance
local function manhattan(x1, y1, x2, y2)
    return abs(x1 - x2) + abs(y1 - y2)
end

--- euclidean distance between two points
--- @param x1 first x coordinate
--- @param y1 first y coordinate
--- @param x2 second x coordinate
--- @param y2 second y coordinate
--- @return number euclidean distance
local function euclidean(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

-- binary heap (min-heap for pathfinding)
local heap = {}
heap.__index = heap

--- create new binary heap
--- @param compare comparison function (optional)
--- @return table heap instance
function heap.new(compare)
    return setmetatable({
        items = {},
        compare = compare or function(a, b) return a < b end
    }, heap)
end

--- push item onto heap
--- @param item item to push
function heap:push(item)
    local items = self.items
    insert(items, item)
    local i = #items
    local parent = floor(i * 0x1p-1) -- i / 2

    while i > 1 and self.compare(items[i], items[parent]) do
        items[i], items[parent] = items[parent], items[i]
        i = parent
        parent = floor(i * 0x1p-1)
    end
end

--- pop minimum item from heap
--- @return any minimum item or nil if empty
function heap:pop()
    local items = self.items
    if #items == 0 then return nil end

    local top = items[1]
    items[1] = items[#items]
    items[#items] = nil

    local i = 1
    local n = #items

    while true do
        local smallest = i
        local left = i * 2
        local right = i * 2 + 1

        if left <= n and self.compare(items[left], items[smallest]) then
            smallest = left
        end
        if right <= n and self.compare(items[right], items[smallest]) then
            smallest = right
        end

        if smallest == i then break end

        items[i], items[smallest] = items[smallest], items[i]
        i = smallest
    end

    return top
end

--- check if heap is empty
--- @return boolean true if empty
function heap:empty()
    return #self.items == 0
end

-- ============================================================================
-- A* PATHFINDING (asp)
-- ============================================================================

local asp = {}

-- grid navigation (8-directional)
local SQRT2 = 0x1.6a09e667f3bcdp0 -- sqrt(2)
local neighbors_8 = {
    { -1, -1, SQRT2 }, { 0, -1, 0x1p0 }, { 1, -1, SQRT2 },
    { -1, 0,  0x1p0 }, { 1, 0, 0x1p0 },
    { -1, 1, SQRT2 }, { 0, 1, 0x1p0 }, { 1, 1, SQRT2 }
}

--- find path on grid using a* algorithm
--- @param grid 2d array of costs (0 = blocked, >0 = traversable)
--- @param sx start x coordinate
--- @param sy start y coordinate
--- @param gx goal x coordinate
--- @param gy goal y coordinate
--- @param heuristic heuristic function (optional, defaults to euclidean)
--- @return table path as array of {x, y} or nil if no path
function asp.grid(grid, sx, sy, gx, gy, heuristic)
    local w, h = #grid[1], #grid
    heuristic = heuristic or euclidean

    local open = heap.new(function(a, b) return a.f < b.f end)
    local closed = {}
    local key = function(x, y) return y * w + x end

    local start = { x = sx, y = sy, g = 0x0p0, h = heuristic(sx, sy, gx, gy), parent = nil }
    start.f = start.g + start.h
    open:push(start)

    local nodes = { [key(sx, sy)] = start }

    while not open:empty() do
        local current = open:pop()
        local ck = key(current.x, current.y)

        if current.x == gx and current.y == gy then
            -- reconstruct path
            local path = {}
            while current do
                insert(path, 1, { x = current.x, y = current.y })
                current = current.parent
            end
            return path
        end

        closed[ck] = true

        for _, dir in ipairs(neighbors_8) do
            local nx, ny, cost = current.x + dir[1], current.y + dir[2], dir[3]

            if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[ny][nx] > 0x0p0 then
                local nk = key(nx, ny)

                if not closed[nk] then
                    local g = current.g + cost * grid[ny][nx]
                    local node = nodes[nk]

                    if not node then
                        node = {
                            x = nx,
                            y = ny,
                            g = g,
                            h = heuristic(nx, ny, gx, gy),
                            parent = current
                        }
                        node.f = node.g + node.h
                        nodes[nk] = node
                        open:push(node)
                    elseif g < node.g then
                        node.g = g
                        node.f = g + node.h
                        node.parent = current
                    end
                end
            end
        end
    end

    return nil 
end

-- ============================================================================
-- JUMP POINT SEARCH (jps)
-- ============================================================================

local jps = {}

-- check if node is walkable
local function is_walkable(grid, x, y)
    local w, h = #grid[1], #grid
    return x >= 1 and x <= w and y >= 1 and y <= h and grid[y][x] > 0x0p0
end

-- check if node is forced neighbor
local function has_forced_neighbor(grid, x, y, dx, dy)
    if dx ~= 0 and dy ~= 0 then
        -- diagonal: check perpendicular forced neighbors
        if (not is_walkable(grid, x - dx, y) and is_walkable(grid, x - dx, y + dy)) or
            (not is_walkable(grid, x, y - dy) and is_walkable(grid, x + dx, y - dy)) then
            return true
        end
    elseif dx ~= 0 then
        -- horizontal: check above/below
        if (not is_walkable(grid, x, y + 1) and is_walkable(grid, x + dx, y + 1)) or
            (not is_walkable(grid, x, y - 1) and is_walkable(grid, x + dx, y - 1)) then
            return true
        end
    else
        -- vertical: check left/right
        if (not is_walkable(grid, x + 1, y) and is_walkable(grid, x + 1, y + dy)) or
            (not is_walkable(grid, x - 1, y) and is_walkable(grid, x - 1, y + dy)) then
            return true
        end
    end
    return false
end

-- jump horizontally or vertically
local function jump_straight(grid, x, y, dx, dy, gx, gy)
    local nx, ny = x + dx, y + dy

    if not is_walkable(grid, nx, ny) then return nil end
    if nx == gx and ny == gy then return nx, ny end
    if has_forced_neighbor(grid, nx, ny, dx, dy) then return nx, ny end

    return jump_straight(grid, nx, ny, dx, dy, gx, gy)
end

-- jump diagonally
local function jump_diagonal(grid, x, y, dx, dy, gx, gy)
    local nx, ny = x + dx, y + dy

    if not is_walkable(grid, nx, ny) then return nil end
    if nx == gx and ny == gy then return nx, ny end

    -- check if diagonal move is blocked
    if not is_walkable(grid, x + dx, y) and not is_walkable(grid, x, y + dy) then
        return nil
    end

    if has_forced_neighbor(grid, nx, ny, dx, dy) then return nx, ny end

    -- check horizontal and vertical directions
    if jump_straight(grid, nx, ny, dx, 0, gx, gy) or
        jump_straight(grid, nx, ny, 0, dy, gx, gy) then
        return nx, ny
    end

    return jump_diagonal(grid, nx, ny, dx, dy, gx, gy)
end

-- identify successors (jump points)
local function identify_successors(grid, node, gx, gy, open, closed, nodes, w)
    local successors = {}
    local x, y = node.x, node.y

    -- get pruned neighbors based on parent direction
    local neighbors = {}
    if node.parent then
        local dx = x - node.parent.x
        local dy = y - node.parent.y
        dx = dx ~= 0 and dx / abs(dx) or 0
        dy = dy ~= 0 and dy / abs(dy) or 0

        if dx ~= 0 and dy ~= 0 then
            -- diagonal movement
            if is_walkable(grid, x, y + dy) then insert(neighbors, { 0, dy }) end
            if is_walkable(grid, x + dx, y) then insert(neighbors, { dx, 0 }) end
            if is_walkable(grid, x + dx, y + dy) then insert(neighbors, { dx, dy }) end
        elseif dx ~= 0 then
            -- horizontal movement
            if is_walkable(grid, x + dx, y) then insert(neighbors, { dx, 0 }) end
            if not is_walkable(grid, x, y + 1) and is_walkable(grid, x + dx, y + 1) then
                insert(neighbors, { dx, 1 })
            end
            if not is_walkable(grid, x, y - 1) and is_walkable(grid, x + dx, y - 1) then
                insert(neighbors, { dx, -1 })
            end
        else
            -- vertical movement
            if is_walkable(grid, x, y + dy) then insert(neighbors, { 0, dy }) end
            if not is_walkable(grid, x + 1, y) and is_walkable(grid, x + 1, y + dy) then
                insert(neighbors, { 1, dy })
            end
            if not is_walkable(grid, x - 1, y) and is_walkable(grid, x - 1, y + dy) then
                insert(neighbors, { -1, dy })
            end
        end
    else
        -- no parent, check all directions
        for _, dir in ipairs(neighbors_8) do
            insert(neighbors, { dir[1], dir[2] })
        end
    end

    -- jump in each direction
    for _, dir in ipairs(neighbors) do
        local dx, dy = dir[1], dir[2]
        local jx, jy

        if dx ~= 0 and dy ~= 0 then
            jx, jy = jump_diagonal(grid, x, y, dx, dy, gx, gy)
        else
            jx, jy = jump_straight(grid, x, y, dx, dy, gx, gy)
        end

        if jx then
            insert(successors, { x = jx, y = jy })
        end
    end

    return successors
end

--- find path using jump point search optimization
--- @param grid 2d array of costs (0 = blocked, >0 = traversable)
--- @param sx start x coordinate
--- @param sy start y coordinate
--- @param gx goal x coordinate
--- @param gy goal y coordinate
--- @return table path as array of {x, y} or nil if no path
function jps.grid(grid, sx, sy, gx, gy)
    local w, h = #grid[1], #grid

    local open = heap.new(function(a, b) return a.f < b.f end)
    local closed = {}
    local key = function(x, y) return y * w + x end

    local start = { x = sx, y = sy, g = 0x0p0, h = euclidean(sx, sy, gx, gy), parent = nil }
    start.f = start.g + start.h
    open:push(start)

    local nodes = { [key(sx, sy)] = start }

    while not open:empty() do
        local current = open:pop()
        local ck = key(current.x, current.y)

        if current.x == gx and current.y == gy then
            -- reconstruct path
            local path = {}
            while current do
                insert(path, 1, { x = current.x, y = current.y })
                current = current.parent
            end
            return path
        end

        closed[ck] = true

        local successors = identify_successors(grid, current, gx, gy, open, closed, nodes, w)

        for _, succ in ipairs(successors) do
            local nk = key(succ.x, succ.y)

            if not closed[nk] then
                local dist = euclidean(current.x, current.y, succ.x, succ.y)
                local g = current.g + dist * grid[succ.y][succ.x]
                local node = nodes[nk]

                if not node then
                    node = {
                        x = succ.x,
                        y = succ.y,
                        g = g,
                        h = euclidean(succ.x, succ.y, gx, gy),
                        parent = current
                    }
                    node.f = node.g + node.h
                    nodes[nk] = node
                    open:push(node)
                elseif g < node.g then
                    node.g = g
                    node.f = g + node.h
                    node.parent = current
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- NAVIGATION MESH (navmesh)
-- ============================================================================

local navmesh = {}

--- create triangle
--- @param v1 vertex 1 {x, y}
--- @param v2 vertex 2 {x, y}
--- @param v3 vertex 3 {x, y}
--- @return table triangle
function navmesh.triangle(v1, v2, v3)
    -- compute center
    local cx = (v1.x + v2.x + v3.x) * 0x1.5555555555555p-2 -- 1/3
    local cy = (v1.y + v2.y + v3.y) * 0x1.5555555555555p-2 -- 1/3

    return {
        v1 = v1,
        v2 = v2,
        v3 = v3,
        cx = cx,
        cy = cy,
        neighbors = {}
    }
end

--- check if point is inside triangle
--- @param tri triangle
--- @param x point x
--- @param y point y
--- @return boolean true if inside
local function point_in_triangle(tri, x, y)
    local v1, v2, v3 = tri.v1, tri.v2, tri.v3

    local function sign(px, py, ax, ay, bx, by)
        return (px - bx) * (ay - by) - (ax - bx) * (py - by)
    end

    local d1 = sign(x, y, v1.x, v1.y, v2.x, v2.y)
    local d2 = sign(x, y, v2.x, v2.y, v3.x, v3.y)
    local d3 = sign(x, y, v3.x, v3.y, v1.x, v1.y)

    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)

    return not (has_neg and has_pos)
end

--- create navigation mesh from triangles
--- @param triangles array of triangles
--- @return table navmesh instance
function navmesh.new(triangles)
    local mesh = {
        triangles = triangles,
        portals = {}
    }

    -- find shared edges (portals)
    for i = 1, #triangles do
        for j = i + 1, #triangles do
            local t1, t2 = triangles[i], triangles[j]
            local shared = 0
            local portal = {}

            -- check for shared vertices
            local verts1 = { t1.v1, t1.v2, t1.v3 }
            local verts2 = { t2.v1, t2.v2, t2.v3 }

            for _, v1 in ipairs(verts1) do
                for _, v2 in ipairs(verts2) do
                    if v1.x == v2.x and v1.y == v2.y then
                        insert(portal, v1)
                        shared = shared + 1
                    end
                end
            end

            if shared == 2 then
                insert(t1.neighbors, { tri = t2, portal = portal })
                insert(t2.neighbors, { tri = t1, portal = portal })
            end
        end
    end

    return mesh
end

--- find triangle containing point
--- @param mesh navmesh
--- @param x point x
--- @param y point y
--- @return table triangle or nil
function navmesh.find_triangle(mesh, x, y)
    for _, tri in ipairs(mesh.triangles) do
        if point_in_triangle(tri, x, y) then
            return tri
        end
    end
    return nil
end

--- find path through navmesh using a*
--- @param mesh navmesh
--- @param sx start x
--- @param sy start y
--- @param gx goal x
--- @param gy goal y
--- @return table path as array of {x, y} or nil
function navmesh.find_path(mesh, sx, sy, gx, gy)
    local start_tri = navmesh.find_triangle(mesh, sx, sy)
    local goal_tri = navmesh.find_triangle(mesh, gx, gy)

    if not start_tri or not goal_tri then return nil end
    if start_tri == goal_tri then
        return { { x = sx, y = sy }, { x = gx, y = gy } }
    end

    -- a* on triangle graph
    local open = heap.new(function(a, b) return a.f < b.f end)
    local closed = {}

    local start_node = {
        tri = start_tri,
        g = 0x0p0,
        h = euclidean(start_tri.cx, start_tri.cy, goal_tri.cx, goal_tri.cy),
        parent = nil
    }
    start_node.f = start_node.g + start_node.h
    open:push(start_node)

    local nodes = { [start_tri] = start_node }

    while not open:empty() do
        local current = open:pop()

        if current.tri == goal_tri then
            -- reconstruct path through portals
            local path = { { x = gx, y = gy } }

            while current.parent do
                -- find portal between current and parent
                for _, neighbor in ipairs(current.parent.tri.neighbors) do
                    if neighbor.tri == current.tri then
                        local portal = neighbor.portal
                        if #portal == 2 then
                            local px = (portal[1].x + portal[2].x) * 0x1p-1
                            local py = (portal[1].y + portal[2].y) * 0x1p-1
                            insert(path, 1, { x = px, y = py })
                        end
                        break
                    end
                end
                current = current.parent
            end

            insert(path, 1, { x = sx, y = sy })
            return path
        end

        closed[current.tri] = true

        for _, neighbor in ipairs(current.tri.neighbors) do
            local ntri = neighbor.tri

            if not closed[ntri] then
                local g = current.g + euclidean(current.tri.cx, current.tri.cy, ntri.cx, ntri.cy)
                local node = nodes[ntri]

                if not node then
                    node = {
                        tri = ntri,
                        g = g,
                        h = euclidean(ntri.cx, ntri.cy, goal_tri.cx, goal_tri.cy),
                        parent = current
                    }
                    node.f = node.g + node.h
                    nodes[ntri] = node
                    open:push(node)
                elseif g < node.g then
                    node.g = g
                    node.f = g + node.h
                    node.parent = current
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- BEHAVIOR TREE (btree)
-- ============================================================================

local btree = {}

-- node states
btree.SUCCESS = "success"
btree.FAILURE = "failure"
btree.RUNNING = "running"

--- create action node
--- @param func action function (context) -> state
--- @return table action node
function btree.action(func)
    return {
        type = "action",
        tick = function(self, context)
            return func(context)
        end
    }
end

--- create condition node
--- @param func condition function (context) -> boolean
--- @return table condition node
function btree.condition(func)
    return {
        type = "condition",
        tick = function(self, context)
            return func(context) and btree.SUCCESS or btree.FAILURE
        end
    }
end

--- create sequence node (all children must succeed)
--- @param children array of child nodes
--- @return table sequence node
function btree.sequence(children)
    return {
        type = "sequence",
        children = children,
        current = 1,
        tick = function(self, context)
            while self.current <= #self.children do
                local state = self.children[self.current]:tick(context)

                if state == btree.FAILURE then
                    self.current = 1
                    return btree.FAILURE
                elseif state == btree.RUNNING then
                    return btree.RUNNING
                end

                self.current = self.current + 1
            end

            self.current = 1
            return btree.SUCCESS
        end
    }
end

--- create selector node (first child to succeed wins)
--- @param children array of child nodes
--- @return table selector node
function btree.selector(children)
    return {
        type = "selector",
        children = children,
        current = 1,
        tick = function(self, context)
            while self.current <= #self.children do
                local state = self.children[self.current]:tick(context)

                if state == btree.SUCCESS then
                    self.current = 1
                    return btree.SUCCESS
                elseif state == btree.RUNNING then
                    return btree.RUNNING
                end

                self.current = self.current + 1
            end

            self.current = 1
            return btree.FAILURE
        end
    }
end

--- create parallel node (all children execute)
--- @param children array of child nodes
--- @param success_count minimum successes needed
--- @return table parallel node
function btree.parallel(children, success_count)
    success_count = success_count or #children

    return {
        type = "parallel",
        children = children,
        tick = function(self, context)
            local successes = 0
            local failures = 0
            local running = 0

            for _, child in ipairs(self.children) do
                local state = child:tick(context)

                if state == btree.SUCCESS then
                    successes = successes + 1
                elseif state == btree.FAILURE then
                    failures = failures + 1
                elseif state == btree.RUNNING then
                    running = running + 1
                end
            end

            if successes >= success_count then
                return btree.SUCCESS
            elseif failures > #self.children - success_count then
                return btree.FAILURE
            else
                return btree.RUNNING
            end
        end
    }
end

--- create decorator node (modifies child result)
--- @param child child node
--- @param decorator_func function(state) -> new_state
--- @return table decorator node
function btree.decorator(child, decorator_func)
    return {
        type = "decorator",
        child = child,
        tick = function(self, context)
            local state = self.child:tick(context)
            return decorator_func(state)
        end
    }
end

--- create inverter node (inverts success/failure)
--- @param child child node
--- @return table inverter node
function btree.inverter(child)
    return btree.decorator(child, function(state)
        if state == btree.SUCCESS then
            return btree.FAILURE
        elseif state == btree.FAILURE then
            return btree.SUCCESS
        else
            return state
        end
    end)
end

--- create repeater node (repeats child n times)
--- @param child child node
--- @param count repeat count
--- @return table repeater node
function btree.repeater(child, count)
    return {
        type = "repeater",
        child = child,
        count = count,
        current = 0,
        tick = function(self, context)
            while self.current < self.count do
                local state = self.child:tick(context)

                if state == btree.RUNNING then
                    return btree.RUNNING
                elseif state == btree.FAILURE then
                    self.current = 0
                    return btree.FAILURE
                end

                self.current = self.current + 1
            end

            self.current = 0
            return btree.SUCCESS
        end
    }
end

-- ============================================================================
-- UTILITY AI (utility)
-- ============================================================================

local utility = {}

--- create consideration (input -> score curve)
--- @param input_func function to get input value
--- @param curve curve function (x) -> y
--- @return table consideration
function utility.consideration(input_func, curve)
    curve = curve or function(x) return x end

    return {
        input = input_func,
        curve = curve,
        evaluate = function(self, context)
            local input = self.input(context)
            return self.curve(input)
        end
    }
end

--- linear curve
--- @param slope slope of line
--- @param intercept y-intercept
--- @return function curve function
function utility.curve_linear(slope, intercept)
    slope = slope or 0x1p0
    intercept = intercept or 0x0p0
    return function(x)
        return max(0x0p0, min(0x1p0, slope * x + intercept))
    end
end

--- quadratic curve
--- @param exponent exponent (default 2)
--- @return function curve function
function utility.curve_quadratic(exponent)
    exponent = exponent or 0x1p1
    return function(x)
        return x ^ exponent
    end
end

--- inverse curve (1 - x)
--- @return function curve function
function utility.curve_inverse()
    return function(x)
        return 0x1p0 - x
    end
end

--- sigmoid curve
--- @param steepness steepness factor
--- @param shift horizontal shift
--- @return function curve function
function utility.curve_sigmoid(steepness, shift)
    steepness = steepness or 0x1.4p3 -- 10.0
    shift = shift or 0x1p-1          -- 0.5
    return function(x)
        return 0x1p0 / (0x1p0 + math.exp(-steepness * (x - shift)))
    end
end

--- create action with considerations
--- @param name action name
--- @param considerations array of considerations
--- @param execute execution function
--- @return table action
function utility.action(name, considerations, execute)
    return {
        name = name,
        considerations = considerations,
        execute = execute,
        evaluate = function(self, context)
            if #self.considerations == 0 then return 0x1p0 end

            local score = 0x1p0
            for _, consideration in ipairs(self.considerations) do
                score = score * consideration:evaluate(context)
                if score == 0x0p0 then break end
            end

            return score
        end
    }
end

--- select best action from available actions
--- @param actions array of actions
--- @param context evaluation context
--- @return table selected action or nil
function utility.select_action(actions, context)
    local best_action = nil
    local best_score = -math.huge

    for _, action in ipairs(actions) do
        local score = action:evaluate(context)
        if score > best_score then
            best_score = score
            best_action = action
        end
    end

    return best_action, best_score
end

-- ============================================================================
-- HIERARCHICAL PATHFINDING (hpa)
-- ============================================================================

local hpa = {}

--- create new hierarchical pathfinding structure
--- @param grid 2d grid array
--- @param cluster_size size of clusters (default 10)
--- @return table hpa instance
function hpa.new(grid, cluster_size)
    cluster_size = cluster_size or 10

    local w, h = #grid[1], #grid
    local cw = floor(w / cluster_size)
    local ch = floor(h / cluster_size)

    -- build abstract graph
    local entrances = {}
    local abstract_graph = {}

    -- find cluster entrances (transitions between clusters)
    for cy = 0, ch - 1 do
        for cx = 0, cw - 1 do
            local x1, y1 = cx * cluster_size + 1, cy * cluster_size + 1
            local x2, y2 = min(x1 + cluster_size - 1, w), min(y1 + cluster_size - 1, h)

            -- check right edge
            if cx < cw - 1 then
                for y = y1, y2 do
                    if grid[y][x2] > 0x0p0 and grid[y][x2 + 1] > 0x0p0 then
                        local ent = { cx1 = cx, cy1 = cy, cx2 = cx + 1, cy2 = cy, x = x2, y = y }
                        insert(entrances, ent)
                    end
                end
            end

            -- check bottom edge
            if cy < ch - 1 then
                for x = x1, x2 do
                    if grid[y2][x] > 0x0p0 and grid[y2 + 1][x] > 0x0p0 then
                        local ent = { cx1 = cx, cy1 = cy, cx2 = cx, cy2 = cy + 1, x = x, y = y2 }
                        insert(entrances, ent)
                    end
                end
            end
        end
    end

    return {
        grid = grid,
        cluster_size = cluster_size,
        cw = cw,
        ch = ch,
        entrances = entrances,
        abstract_graph = abstract_graph
    }
end

--- find path using hierarchical pathfinding
--- @param hpa hpa instance
--- @param sx start x
--- @param sy start y
--- @param gx goal x
--- @param gy goal y
--- @return table path array
function hpa.find_path(hpa, sx, sy, gx, gy)
    -- simplified: just use regular a* for now
    -- full implementation would find cluster path then refine
    return asp.grid(hpa.grid, sx, sy, gx, gy)
end

-- ============================================================================
-- FLOW FIELD PATHFINDING (ffp)
-- ============================================================================

local ffp = {}

--- compute flow field for grid
--- @param grid 2d grid array
--- @param gx goal x coordinate
--- @param gy goal y coordinate
--- @return table flow field
function ffp.compute(grid, gx, gy)
    local w, h = #grid[1], #grid
    local cost = {}
    local field = {}

    -- initialize costs
    for y = 1, h do
        cost[y] = {}
        field[y] = {}
        for x = 1, w do
            cost[y][x] = math.huge
            field[y][x] = { dx = 0x0p0, dy = 0x0p0 }
        end
    end

    -- dijkstra from goal backwards
    local open = heap.new(function(a, b) return a.cost < b.cost end)
    cost[gy][gx] = 0x0p0
    open:push({ x = gx, y = gy, cost = 0x0p0 })

    while not open:empty() do
        local current = open:pop()
        local cx, cy = current.x, current.y

        if current.cost > cost[cy][cx] then
            goto continue
        end

        for _, dir in ipairs(neighbors_8) do
            local nx, ny = cx + dir[1], cy + dir[2]
            local edge_cost = dir[3]

            if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[ny][nx] > 0x0p0 then
                local new_cost = cost[cy][cx] + edge_cost * grid[ny][nx]

                if new_cost < cost[ny][nx] then
                    cost[ny][nx] = new_cost
                    open:push({ x = nx, y = ny, cost = new_cost })
                end
            end
        end

        ::continue::
    end

    -- compute flow field from cost gradient
    for y = 1, h do
        for x = 1, w do
            if cost[y][x] < math.huge then
                local best_cost = cost[y][x]
                local best_dx, best_dy = 0x0p0, 0x0p0

                for _, dir in ipairs(neighbors_8) do
                    local nx, ny = x + dir[1], y + dir[2]
                    if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
                        if cost[ny][nx] < best_cost then
                            best_cost = cost[ny][nx]
                            best_dx, best_dy = dir[1], dir[2]
                        end
                    end
                end

                field[y][x] = { dx = best_dx, dy = best_dy }
            end
        end
    end

    return field
end

--- follow flow field at position
--- @param field flow field from ffp.compute
--- @param x current x position
--- @param y current y position
--- @return number dx, number dy direction vector
function ffp.follow(field, x, y)
    local cell = field[floor(y + 0x1p-1)]
    if cell then
        cell = cell[floor(x + 0x1p-1)]
        if cell then
            return cell.dx, cell.dy
        end
    end
    return 0x0p0, 0x0p0
end

-- ============================================================================
-- HIERARCHICAL FSM (fsm)
-- ============================================================================

local fsm = {}
fsm.__index = fsm

--- create new finite state machine
--- @param initial_state name of initial state
--- @return table fsm instance
function fsm.new(initial_state)
    return setmetatable({
        state = initial_state,
        states = {},
        history = {}
    }, fsm)
end

--- add state to machine
--- @param name state name
--- @param enter enter callback (optional)
--- @param update update callback (optional)
--- @param exit exit callback (optional)
function fsm:add_state(name, enter, update, exit)
    self.states[name] = {
        enter = enter or function() end,
        update = update or function() end,
        exit = exit or function() end,
        substates = nil -- can be another fsm
    }
end

--- add substate to parent state
--- @param parent parent state name
--- @param name substate name
--- @param enter enter callback (optional)
--- @param update update callback (optional)
--- @param exit exit callback (optional)
function fsm:add_substate(parent, name, enter, update, exit)
    if not self.states[parent].substates then
        self.states[parent].substates = fsm.new(name)
    end
    self.states[parent].substates:add_state(name, enter, update, exit)
end

--- change to new state
--- @param new_state name of state to change to
function fsm:change_state(new_state)
    if self.state == new_state then return end

    local old = self.states[self.state]
    if old then old.exit(self) end

    insert(self.history, self.state)
    self.state = new_state

    local new = self.states[new_state]
    if new then new.enter(self) end
end

--- update state machine
--- @param dt delta time
function fsm:update(dt)
    local state = self.states[self.state]
    if not state then return end

    state.update(self, dt)

    if state.substates then
        state.substates:update(dt)
    end
end

--- get current state name
--- @return string current state name
function fsm:current()
    return self.state
end

-- ============================================================================
-- GOAL-ORIENTED ACTION PLANNING (goap)
-- ============================================================================

local goap = {}

--- create action definition
--- @param name action name
--- @param cost action cost
--- @param preconditions table of required world state
--- @param effects table of state changes
--- @param perform perform callback (optional)
--- @return table action
function goap.action(name, cost, preconditions, effects, perform)
    return {
        name = name,
        cost = cost,
        preconditions = preconditions or {},
        effects = effects or {},
        perform = perform or function() end
    }
end

--- create world state
--- @param initial initial state table (optional)
--- @return table state
function goap.state(initial)
    return initial or {}
end

-- check if state satisfies conditions
local function satisfies(state, conditions)
    for k, v in pairs(conditions) do
        if state[k] ~= v then return false end
    end
    return true
end

-- apply effects to state (creates copy)
local function apply_effects(state, effects)
    local new_state = {}
    for k, v in pairs(state) do new_state[k] = v end
    for k, v in pairs(effects) do new_state[k] = v end
    return new_state
end

-- heuristic: count mismatched goal conditions
local function heuristic(state, goal)
    local diff = 0
    for k, v in pairs(goal) do
        if state[k] ~= v then diff = diff + 1 end
    end
    return diff
end

--- plan actions to reach goal using a* search
--- @param current_state current world state
--- @param goal_state desired world state
--- @param available_actions array of available actions
--- @return table plan as array of actions, or nil if no plan
function goap.plan(current_state, goal_state, available_actions)
    local open = heap.new(function(a, b) return a.f < b.f end)
    local closed = {}

    -- state to string key
    local function state_key(s)
        local parts = {}
        for k, v in pairs(s) do
            insert(parts, k .. "=" .. tostring(v))
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end

    local start_node = {
        state = current_state,
        g = 0x0p0,
        h = heuristic(current_state, goal_state),
        plan = {},
        parent = nil
    }
    start_node.f = start_node.g + start_node.h

    open:push(start_node)
    local visited = { [state_key(current_state)] = start_node }

    while not open:empty() do
        local current = open:pop()
        local sk = state_key(current.state)

        if satisfies(current.state, goal_state) then
            return current.plan -- found solution
        end

        closed[sk] = true

        for _, action in ipairs(available_actions) do
            if satisfies(current.state, action.preconditions) then
                local new_state = apply_effects(current.state, action.effects)
                local nk = state_key(new_state)

                if not closed[nk] then
                    local g = current.g + action.cost
                    local existing = visited[nk]

                    if not existing or g < existing.g then
                        local new_plan = {}
                        for i, a in ipairs(current.plan) do new_plan[i] = a end
                        insert(new_plan, action)

                        local node = {
                            state = new_state,
                            g = g,
                            h = heuristic(new_state, goal_state),
                            plan = new_plan,
                            parent = current
                        }
                        node.f = node.g + node.h

                        visited[nk] = node
                        open:push(node)
                    end
                end
            end
        end
    end

    return nil -- no plan found
end

-- ============================================================================
-- STEERING BEHAVIORS (steer)
-- ============================================================================

local steer = {}

local EPSILON = 0x1.0c6f7a0b5ed8dp-10 -- 0.001

--- seek behavior - move toward target
--- @param agent agent with x, y, vx, vy
--- @param target target with x, y
--- @param max_speed maximum speed
--- @return number fx, number fy steering force
function steer.seek(agent, target, max_speed)
    local dx, dy = target.x - agent.x, target.y - agent.y
    local dist = sqrt(dx * dx + dy * dy)
    if dist < EPSILON then return 0x0p0, 0x0p0 end

    local desired_vx = (dx / dist) * max_speed
    local desired_vy = (dy / dist) * max_speed

    return desired_vx - agent.vx, desired_vy - agent.vy
end

--- flee behavior - move away from threat
--- @param agent agent with x, y, vx, vy
--- @param threat threat with x, y
--- @param max_speed maximum speed
--- @return number fx, number fy steering force
function steer.flee(agent, threat, max_speed)
    local sx, sy = steer.seek(agent, threat, max_speed)
    return -sx, -sy
end

--- arrive behavior - slow down when approaching target
--- @param agent agent with x, y, vx, vy
--- @param target target with x, y
--- @param max_speed maximum speed
--- @param slow_radius radius to start slowing
--- @return number fx, number fy steering force
function steer.arrive(agent, target, max_speed, slow_radius)
    local dx, dy = target.x - agent.x, target.y - agent.y
    local dist = sqrt(dx * dx + dy * dy)
    if dist < EPSILON then return 0x0p0, 0x0p0 end

    local speed = max_speed
    if dist < slow_radius then
        speed = max_speed * (dist / slow_radius)
    end

    local desired_vx = (dx / dist) * speed
    local desired_vy = (dy / dist) * speed

    return desired_vx - agent.vx, desired_vy - agent.vy
end

--- pursue behavior - intercept moving target
--- @param agent agent with x, y, vx, vy
--- @param target target with x, y, vx, vy
--- @param max_speed maximum speed
--- @param predict_time prediction time (default 1.0)
--- @return number fx, number fy steering force
function steer.pursue(agent, target, max_speed, predict_time)
    local T = predict_time or 0x1p0
    local future = {
        x = target.x + target.vx * T,
        y = target.y + target.vy * T
    }
    return steer.seek(agent, future, max_speed)
end

--- evade behavior - escape moving threat
--- @param agent agent with x, y, vx, vy
--- @param threat threat with x, y, vx, vy
--- @param max_speed maximum speed
--- @param predict_time prediction time (default 1.0)
--- @return number fx, number fy steering force
function steer.evade(agent, threat, max_speed, predict_time)
    local px, py = steer.pursue(agent, threat, max_speed, predict_time)
    return -px, -py
end

--- wander behavior - random wandering
--- @param agent agent with x, y, vx, vy, wander_angle
--- @param circle_dist circle distance ahead
--- @param circle_radius circle radius
--- @param angle_change maximum angle change
--- @return number fx, number fy steering force
function steer.wander(agent, circle_dist, circle_radius, angle_change)
    agent.wander_angle = (agent.wander_angle or 0x0p0) + (math.random() - 0x1p-1) * angle_change

    local circle_x = agent.x + agent.vx * circle_dist
    local circle_y = agent.y + agent.vy * circle_dist

    local target_x = circle_x + cos(agent.wander_angle) * circle_radius
    local target_y = circle_y + sin(agent.wander_angle) * circle_radius

    local dx, dy = target_x - agent.x, target_y - agent.y
    local dist = sqrt(dx * dx + dy * dy)
    if dist < EPSILON then return 0x0p0, 0x0p0 end

    return dx / dist, dy / dist
end

--- separation behavior - avoid crowding neighbors
--- @param agent agent with x, y
--- @param neighbors array of neighbor agents
--- @param radius separation radius
--- @return number fx, number fy steering force
function steer.separation(agent, neighbors, radius)
    local fx, fy = 0x0p0, 0x0p0
    local count = 0

    for _, neighbor in ipairs(neighbors) do
        local dx = agent.x - neighbor.x
        local dy = agent.y - neighbor.y
        local dist = sqrt(dx * dx + dy * dy)

        if dist > 0x0p0 and dist < radius then
            fx = fx + (dx / dist) / dist
            fy = fy + (dy / dist) / dist
            count = count + 1
        end
    end

    if count > 0 then
        fx = fx / count
        fy = fy / count
    end

    return fx, fy
end

--- alignment behavior - steer toward average heading
--- @param agent agent with x, y, vx, vy
--- @param neighbors array of neighbor agents
--- @param radius alignment radius
--- @return number fx, number fy steering force
function steer.alignment(agent, neighbors, radius)
    local avg_vx, avg_vy = 0x0p0, 0x0p0
    local count = 0

    for _, neighbor in ipairs(neighbors) do
        local dx = agent.x - neighbor.x
        local dy = agent.y - neighbor.y
        local dist = sqrt(dx * dx + dy * dy)

        if dist < radius then
            avg_vx = avg_vx + neighbor.vx
            avg_vy = avg_vy + neighbor.vy
            count = count + 1
        end
    end

    if count > 0 then
        avg_vx = avg_vx / count
        avg_vy = avg_vy / count
        return avg_vx - agent.vx, avg_vy - agent.vy
    end

    return 0x0p0, 0x0p0
end

--- cohesion behavior - steer toward average position
--- @param agent agent with x, y, vx, vy
--- @param neighbors array of neighbor agents
--- @param radius cohesion radius
--- @param max_speed maximum speed
--- @return number fx, number fy steering force
function steer.cohesion(agent, neighbors, radius, max_speed)
    local avg_x, avg_y = 0x0p0, 0x0p0
    local count = 0

    for _, neighbor in ipairs(neighbors) do
        local dx = agent.x - neighbor.x
        local dy = agent.y - neighbor.y
        local dist = sqrt(dx * dx + dy * dy)

        if dist < radius then
            avg_x = avg_x + neighbor.x
            avg_y = avg_y + neighbor.y
            count = count + 1
        end
    end

    if count > 0 then
        avg_x = avg_x / count
        avg_y = avg_y / count
        return steer.seek(agent, { x = avg_x, y = avg_y }, max_speed)
    end

    return 0x0p0, 0x0p0
end

-- ============================================================================
-- INFLUENCE MAPS (influence)
-- ============================================================================

local influence = {}

--- create new influence map
--- @param width map width
--- @param height map height
--- @param default_value default cell value (default 0)
--- @return table influence map
function influence.new(width, height, default_value)
    local map = {
        width = width,
        height = height,
        cells = {}
    }

    default_value = default_value or 0x0p0

    for y = 1, height do
        map.cells[y] = {}
        for x = 1, width do
            map.cells[y][x] = default_value
        end
    end

    return map
end

--- stamp influence at position
--- @param map influence map
--- @param x x coordinate
--- @param y y coordinate
--- @param value influence value
--- @param radius influence radius
--- @param decay decay rate (default 1.0)
function influence.stamp(map, x, y, value, radius, decay)
    decay = decay or 0x1p0
    x, y = floor(x + 0x1p-1), floor(y + 0x1p-1)

    for cy = max(1, y - radius), min(map.height, y + radius) do
        for cx = max(1, x - radius), min(map.width, x + radius) do
            local dist = euclidean(x, y, cx, cy)
            if dist <= radius then
                local influence_value = value * max(0x0p0, 0x1p0 - (dist / radius) * decay)
                map.cells[cy][cx] = map.cells[cy][cx] + influence_value
            end
        end
    end
end

--- propagate influence across map
--- @param map influence map
--- @param momentum momentum factor (0-1)
--- @param decay_rate decay rate (0-1)
function influence.propagate(map, momentum, decay_rate)
    local new_cells = {}

    for y = 1, map.height do
        new_cells[y] = {}
        for x = 1, map.width do
            local current = map.cells[y][x]
            local sum, count = 0x0p0, 0

            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local nx, ny = x + dx, y + dy
                        if nx >= 1 and nx <= map.width and ny >= 1 and ny <= map.height then
                            sum = sum + map.cells[ny][nx]
                            count = count + 1
                        end
                    end
                end
            end

            local avg = count > 0 and sum / count or 0x0p0
            new_cells[y][x] = current * momentum + avg * (0x1p0 - momentum) * decay_rate
        end
    end

    map.cells = new_cells
end

--- get influence at position
--- @param map influence map
--- @param x x coordinate
--- @param y y coordinate
--- @return number influence value
function influence.get(map, x, y)
    x, y = floor(x + 0x1p-1), floor(y + 0x1p-1)
    if x >= 1 and x <= map.width and y >= 1 and y <= map.height then
        return map.cells[y][x]
    end
    return 0x0p0
end

--- combine two influence maps
--- @param map1 first influence map
--- @param map2 second influence map
--- @param weight1 weight for first map
--- @param weight2 weight for second map
--- @return table combined influence map
function influence.combine(map1, map2, weight1, weight2)
    local result = influence.new(map1.width, map1.height)

    for y = 1, map1.height do
        for x = 1, map1.width do
            result.cells[y][x] = map1.cells[y][x] * weight1 + map2.cells[y][x] * weight2
        end
    end

    return result
end

-- ============================================================================
-- SPATIAL PARTITIONING (spatial)
-- ============================================================================

local spatial = {}

--- create new spatial grid
--- @param cell_size size of each cell
--- @param bounds bounds as {x1, y1, x2, y2}
--- @return table spatial grid
function spatial.grid_new(cell_size, bounds)
    return {
        cell_size = cell_size,
        bounds = bounds,
        cells = {}
    }
end

--- insert object into spatial grid
--- @param grid spatial grid
--- @param obj object to insert
--- @param x x position
--- @param y y position
function spatial.grid_insert(grid, obj, x, y)
    local cx = floor(x / grid.cell_size)
    local cy = floor(y / grid.cell_size)
    local key = cy * 10000 + cx

    if not grid.cells[key] then
        grid.cells[key] = {}
    end

    insert(grid.cells[key], { obj = obj, x = x, y = y })
end

--- query spatial grid for nearby objects
--- @param grid spatial grid
--- @param x query x position
--- @param y query y position
--- @param radius query radius
--- @return table array of {obj, dist}
function spatial.grid_query(grid, x, y, radius)
    local results = {}
    local cell_radius = floor(radius / grid.cell_size) + 1
    local cx = floor(x / grid.cell_size)
    local cy = floor(y / grid.cell_size)

    for dy = -cell_radius, cell_radius do
        for dx = -cell_radius, cell_radius do
            local key = (cy + dy) * 10000 + (cx + dx)
            local cell = grid.cells[key]

            if cell then
                for _, entry in ipairs(cell) do
                    local dist = euclidean(x, y, entry.x, entry.y)
                    if dist <= radius then
                        insert(results, { obj = entry.obj, dist = dist })
                    end
                end
            end
        end
    end

    return results
end

--- clear all objects from spatial grid
--- @param grid spatial grid
function spatial.grid_clear(grid)
    grid.cells = {}
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return {
    asp = asp,
    jps = jps,
    hpa = hpa,
    ffp = ffp,
    fsm = fsm,
    goap = goap,
    steer = steer,
    influence = influence,
    spatial = spatial,
    navmesh = navmesh,
    btree = btree,
    utility = utility,

    -- utilities
    manhattan = manhattan,
    euclidean = euclidean,
    heap = heap
}
