local bit = require("bit")
local physics = require("physics")

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
-- init and clear
-- ============================================================================

print("\n=== Init and Clear ===\n")

test("init: sets default cell size", function()
    physics.init()
    physics.add("test", 0, 0, 16, 16)
    local col = physics.get("test")
    assert_not_nil(col, "collider should exist")
    physics.clear()
end)

test("init: sets custom cell size", function()
    physics.init(32)
    physics.add("test", 0, 0, 16, 16)
    local col = physics.get("test")
    assert_not_nil(col, "collider should exist")
    physics.clear()
end)

test("clear: removes all colliders", function()
    physics.init()
    physics.add("a", 0, 0, 16, 16)
    physics.add("b", 20, 20, 16, 16)
    physics.clear()
    assert_nil(physics.get("a"), "collider 'a' should be removed")
    assert_nil(physics.get("b"), "collider 'b' should be removed")
end)

-- ============================================================================
-- aabb tests
-- ============================================================================

print("\n=== AABB: Add and Get ===\n")

test("aabb: creates new collider", function()
    physics.init()
    physics.add("player", 100, 100, 16, 16, "player", true)
    local col = physics.get("player")
    assert_not_nil(col, "collider should exist")
    assert_eq(col.x, 100, "x position")
    assert_eq(col.y, 100, "y position")
    assert_eq(col.w, 16, "width")
    assert_eq(col.h, 16, "height")
    assert_eq(col.type, "player", "type")
    assert_eq(col.shape, "aabb", "shape")
    assert_true(col.active, "should be active")
    physics.clear()
end)

test("aabb: updates existing collider", function()
    physics.init()
    physics.add("box", 0, 0, 16, 16, "solid")
    physics.add("box", 50, 50, 32, 32, "trigger")
    local col = physics.get("box")
    assert_eq(col.x, 50, "updated x")
    assert_eq(col.y, 50, "updated y")
    assert_eq(col.w, 32, "updated width")
    assert_eq(col.h, 32, "updated height")
    assert_eq(col.type, "trigger", "updated type")
    physics.clear()
end)

test("aabb: defaults active to true", function()
    physics.init()
    physics.add("test", 0, 0, 16, 16)
    local col = physics.get("test")
    assert_true(col.active, "should be active by default")
    physics.clear()
end)

test("aabb: can set inactive", function()
    physics.init()
    physics.add("test", 0, 0, 16, 16, "solid", false)
    local col = physics.get("test")
    assert_false(col.active, "should be inactive")
    physics.clear()
end)

test("aabb: sets collision mask", function()
    physics.init()
    physics.add("test", 0, 0, 16, 16, "solid", true, 0x0002)
    local col = physics.get("test")
    assert_eq(col.mask, 0x0002, "mask should be set")
    physics.clear()
end)

test("aabb: defaults mask to 0xFFFFFFFF", function()
    physics.init()
    physics.add("test", 0, 0, 16, 16)
    local col = physics.get("test")
    assert_eq(col.mask, 0xFFFFFFFF, "default mask")
    physics.clear()
end)

print("\n=== AABB: Check and Move ===\n")

test("aabb: detects overlap", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player")
    physics.add("wall", 10, 10, 16, 16, "solid")
    local hits = physics.check("player", 8, 8)
    assert_eq(count_table(hits), 1, "should detect one collision")
    assert_not_nil(hits["wall"], "should hit wall")
    physics.clear()
end)

test("aabb: no overlap when separated", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player")
    physics.add("wall", 100, 100, 16, 16, "solid")
    local hits = physics.check("player", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collisions")
    physics.clear()
end)

test("aabb: moves without collision", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player")
    local x, y, hits = physics.move("player", 10, 5)
    assert_eq(x, 10, "x moved")
    assert_eq(y, 5, "y moved")
    assert_eq(count_table(hits.x), 0, "no x collisions")
    assert_eq(count_table(hits.y), 0, "no y collisions")
    physics.clear()
end)

test("aabb: stops at solid (x axis)", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player")
    physics.add("wall", 30, 0, 16, 16, "solid")
    local x, y, hits = physics.move("player", 20, 0)
    assert_eq(x, 14, "stopped at wall")
    assert_eq(y, 0, "y unchanged")
    assert_not_nil(hits.x["wall"], "hit wall on x")
    physics.clear()
end)

test("aabb: stops at solid (y axis)", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player")
    physics.add("wall", 0, 30, 16, 16, "solid")
    local x, y, hits = physics.move("player", 0, 20)
    assert_eq(x, 0, "x unchanged")
    assert_eq(y, 14, "stopped at wall")
    assert_not_nil(hits.y["wall"], "hit wall on y")
    physics.clear()
end)

test("aabb: stops at solid (negative x)", function()
    physics.init()
    physics.add("player", 50, 0, 16, 16, "player")
    physics.add("wall", 20, 0, 16, 16, "solid")
    local x, y, hits = physics.move("player", -20, 0)
    assert_eq(x, 36, "stopped at wall")
    assert_eq(y, 0, "y unchanged")
    assert_not_nil(hits.x["wall"], "hit wall on x")
    physics.clear()
end)

test("aabb: stops at solid (negative y)", function()
    physics.init()
    physics.add("player", 0, 50, 16, 16, "player")
    physics.add("wall", 0, 20, 16, 16, "solid")
    local x, y, hits = physics.move("player", 0, -20)
    assert_eq(x, 0, "x unchanged")
    assert_eq(y, 36, "stopped at wall")
    assert_not_nil(hits.y["wall"], "hit wall on y")
    physics.clear()
end)

test("aabb: swept prevents tunneling", function()
    physics.init(16)
    physics.add("bullet", 0, 8, 4, 4, "player")
    physics.add("wall", 50, 0, 16, 16, "solid")
    local x, y, hits = physics.move("bullet", 100, 0, true)
    assert_true(x <= 50, "stopped at or before wall")
    assert_true(count_table(hits.x) > 0, "detected x collision")
    physics.clear()
end)

-- ============================================================================
-- circle tests
-- ============================================================================

print("\n=== Circle: Add and Get ===\n")

test("circle: creates new collider", function()
    physics.init()
    physics.add_circle("ball", 50, 50, 10, "player", true)
    local col = physics.get("ball")
    assert_not_nil(col, "collider should exist")
    assert_eq(col.x, 50, "x position")
    assert_eq(col.y, 50, "y position")
    assert_eq(col.radius, 10, "radius")
    assert_eq(col.shape, "circle", "shape")
    assert_eq(col.type, "player", "type")
    physics.clear()
end)

test("circle: updates existing collider", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 5, "solid")
    physics.add_circle("ball", 20, 30, 15, "trigger")
    local col = physics.get("ball")
    assert_eq(col.x, 20, "updated x")
    assert_eq(col.y, 30, "updated y")
    assert_eq(col.radius, 15, "updated radius")
    assert_eq(col.type, "trigger", "updated type")
    physics.clear()
end)

print("\n=== Circle: Collision Detection ===\n")

test("circle vs circle: detects overlap", function()
    physics.init()
    physics.add_circle("a", 0, 0, 10, "player")
    physics.add_circle("b", 15, 0, 10, "solid")
    local hits = physics.check("a", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    assert_not_nil(hits["b"], "should hit circle b")
    physics.clear()
end)

test("circle vs circle: no overlap when separated", function()
    physics.init()
    physics.add_circle("a", 0, 0, 10, "player")
    physics.add_circle("b", 50, 0, 10, "solid")
    local hits = physics.check("a", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collision")
    physics.clear()
end)

test("circle vs circle: exact touch", function()
    physics.init()
    physics.add_circle("a", 0, 0, 10, "player")
    physics.add_circle("b", 20, 0, 10, "solid")
    local hits = physics.check("a", 0, 0)
    assert_eq(count_table(hits), 0, "exact touch should not overlap")
    physics.clear()
end)

test("circle vs aabb: detects overlap", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 10, "player")
    physics.add("wall", 8, -5, 10, 10, "solid")
    local hits = physics.check("ball", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("circle vs aabb: no overlap when separated", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 10, "player")
    physics.add("wall", 50, 50, 10, 10, "solid")
    local hits = physics.check("ball", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collision")
    physics.clear()
end)

test("circle vs aabb: circle center inside aabb", function()
    physics.init()
    physics.add_circle("ball", 5, 5, 3, "player")
    physics.add("wall", 0, 0, 20, 20, "solid")
    local hits = physics.check("ball", 5, 5)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("aabb vs circle: detects overlap", function()
    physics.init()
    physics.add("box", 0, 0, 10, 10, "player")
    physics.add_circle("ball", 15, 5, 8, "solid")
    local hits = physics.check("box", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

print("\n=== Circle: Movement ===\n")

test("circle: moves without collision", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 5, "player")
    local x, y, hits = physics.move("ball", 10, 10)
    assert_eq(x, 10, "x moved")
    assert_eq(y, 10, "y moved")
    assert_eq(count_table(hits.x), 0, "no collisions")
    physics.clear()
end)

test("circle: stops at solid circle", function()
    physics.init()
    physics.add_circle("a", 0, 0, 10, "player")
    physics.add_circle("b", 30, 0, 10, "solid")
    local x, y, hits = physics.move("a", 15, 0)
    assert_true(x < 15, "stopped before destination")
    assert_eq(count_table(hits.x), 1, "detected collision")
    physics.clear()
end)

test("circle: stops at solid aabb", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 5, "player")
    physics.add("wall", 20, -5, 10, 10, "solid")
    local x, y, hits = physics.move("ball", 20, 0)
    assert_true(x < 20, "stopped before wall")
    physics.clear()
end)

test("circle: slides along aabb", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 5, "player")
    physics.add("wall", 20, 0, 10, 30, "solid")
    local x, y, hits = physics.move("ball", 20, 10)
    assert_true(x < 20, "x blocked by wall")
    assert_eq(y, 10, "y movement allowed")
    physics.clear()
end)

-- ============================================================================
-- polygon tests
-- ============================================================================

print("\n=== Polygon: Add and Get ===\n")

test("polygon: creates triangle", function()
    physics.init()
    local verts = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 10, y = 20}
    }
    physics.add_polygon("tri", 0, 0, verts, "solid", true)
    local col = physics.get("tri")
    assert_not_nil(col, "collider should exist")
    assert_eq(col.shape, "polygon", "shape")
    assert_eq(#col.vertices, 3, "has 3 vertices")
    physics.clear()
end)

test("polygon: creates rectangle", function()
    physics.init()
    local verts = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 20, y = 10},
        {x = 0, y = 10}
    }
    physics.add_polygon("rect", 0, 0, verts, "solid", true)
    local col = physics.get("rect")
    assert_eq(#col.vertices, 4, "has 4 vertices")
    physics.clear()
end)

test("polygon: creates slope", function()
    physics.init()
    local verts = {
        {x = 0, y = 20},
        {x = 40, y = 0},
        {x = 40, y = 20}
    }
    physics.add_polygon("slope", 0, 0, verts, "solid", true)
    local col = physics.get("slope")
    assert_eq(#col.vertices, 3, "slope has 3 vertices")
    physics.clear()
end)

test("polygon: updates vertices", function()
    physics.init()
    local verts1 = {
        {x = 0, y = 0},
        {x = 10, y = 0},
        {x = 5, y = 10}
    }
    physics.add_polygon("tri", 0, 0, verts1, "solid")
    
    local verts2 = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 20, y = 20},
        {x = 0, y = 20}
    }
    physics.update_polygon("tri", verts2)
    
    local col = physics.get("tri")
    assert_eq(#col.vertices, 4, "updated to 4 vertices")
    physics.clear()
end)

print("\n=== Polygon: Collision Detection ===\n")

test("polygon vs polygon: detects overlap", function()
    physics.init()
    local verts1 = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 20, y = 20},
        {x = 0, y = 20}
    }
    local verts2 = {
        {x = 15, y = 15},
        {x = 35, y = 15},
        {x = 35, y = 35},
        {x = 15, y = 35}
    }
    physics.add_polygon("a", 0, 0, verts1, "player")
    physics.add_polygon("b", 0, 0, verts2, "solid")
    local hits = physics.check("a", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("polygon vs polygon: no overlap when separated", function()
    physics.init()
    local verts1 = {
        {x = 0, y = 0},
        {x = 10, y = 0},
        {x = 10, y = 10},
        {x = 0, y = 10}
    }
    local verts2 = {
        {x = 50, y = 50},
        {x = 60, y = 50},
        {x = 60, y = 60},
        {x = 50, y = 60}
    }
    physics.add_polygon("a", 0, 0, verts1, "player")
    physics.add_polygon("b", 0, 0, verts2, "solid")
    local hits = physics.check("a", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collision")
    physics.clear()
end)

test("polygon vs aabb: detects overlap", function()
    physics.init()
    local verts = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 10, y = 20}
    }
    physics.add_polygon("tri", 0, 0, verts, "player")
    physics.add("box", 15, 5, 10, 10, "solid")
    local hits = physics.check("tri", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("polygon vs aabb: no overlap when separated", function()
    physics.init()
    local verts = {
        {x = 0, y = 0},
        {x = 10, y = 0},
        {x = 5, y = 10}
    }
    physics.add_polygon("tri", 0, 0, verts, "player")
    physics.add("box", 50, 50, 10, 10, "solid")
    local hits = physics.check("tri", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collision")
    physics.clear()
end)

test("aabb vs polygon: detects overlap", function()
    physics.init()
    physics.add("box", 0, 0, 20, 20, "player")
    local verts = {
        {x = 15, y = 15},
        {x = 35, y = 15},
        {x = 25, y = 35}
    }
    physics.add_polygon("tri", 0, 0, verts, "solid")
    local hits = physics.check("box", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("circle vs polygon: detects overlap", function()
    physics.init()
    physics.add_circle("ball", 10, 10, 5, "player")
    local verts = {
        {x = 5, y = 5},
        {x = 25, y = 5},
        {x = 25, y = 25},
        {x = 5, y = 25}
    }
    physics.add_polygon("rect", 0, 0, verts, "solid")
    local hits = physics.check("ball", 10, 10)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

test("circle vs polygon: no overlap when separated", function()
    physics.init()
    physics.add_circle("ball", 0, 0, 5, "player")
    local verts = {
        {x = 50, y = 50},
        {x = 60, y = 50},
        {x = 60, y = 60},
        {x = 50, y = 60}
    }
    physics.add_polygon("rect", 0, 0, verts, "solid")
    local hits = physics.check("ball", 0, 0)
    assert_eq(count_table(hits), 0, "should detect no collision")
    physics.clear()
end)

test("polygon vs circle: detects overlap", function()
    physics.init()
    local verts = {
        {x = 0, y = 0},
        {x = 20, y = 0},
        {x = 10, y = 20}
    }
    physics.add_polygon("tri", 0, 0, verts, "player")
    physics.add_circle("ball", 10, 10, 5, "solid")
    local hits = physics.check("tri", 0, 0)
    assert_eq(count_table(hits), 1, "should detect collision")
    physics.clear()
end)

print("\n=== Polygon: Slope Movement ===\n")

test("polygon: slope collision from above", function()
    physics.init()
    local slope_verts = {
        {x = 0, y = 20},
        {x = 40, y = 0},
        {x = 40, y = 20}
    }
    physics.add_polygon("slope", 0, 0, slope_verts, "solid")
    physics.add("player", 15, -10, 10, 10, "player")
    
    local x, y, hits = physics.move("player", 0, 20)
    assert_true(y < 10, "should stop on slope surface")
    assert_true(count_table(hits.y) > 0, "should detect collision")
    physics.clear()
end)

test("polygon: slope allows sliding", function()
    physics.init()
    local slope_verts = {
        {x = 0, y = 20},
        {x = 40, y = 0},
        {x = 40, y = 20}
    }
    physics.add_polygon("slope", 0, 0, slope_verts, "solid")
    physics.add_circle("ball", 5, 5, 5, "player")
    
    -- ball should be able to move along slope
    local x1, y1 = physics.move("ball", 10, 0)
    assert_true(x1 > 5, "x movement allowed")
    physics.clear()
end)

-- ============================================================================
-- raycast tests
-- ============================================================================

print("\n=== Raycast ===\n")

test("raycast: hits aabb", function()
    physics.init()
    physics.add("wall", 50, 50, 16, 16, "solid")
    local hits = physics.raycast(0, 58, 100, 58)
    assert_true(#hits > 0, "should hit wall")
    assert_eq(hits[1].id, "wall", "hit correct collider")
    physics.clear()
end)

test("raycast: hits circle", function()
    physics.init()
    physics.add_circle("ball", 50, 50, 10, "solid")
    local hits = physics.raycast(0, 50, 100, 50)
    assert_true(#hits > 0, "should hit circle")
    assert_eq(hits[1].id, "ball", "hit correct collider")
    physics.clear()
end)

test("raycast: hits polygon", function()
    physics.init()
    local verts = {
        {x = 45, y = 45},
        {x = 55, y = 45},
        {x = 55, y = 55},
        {x = 45, y = 55}
    }
    physics.add_polygon("poly", 0, 0, verts, "solid")
    local hits = physics.raycast(0, 50, 100, 50)
    assert_true(#hits > 0, "should hit polygon")
    assert_eq(hits[1].id, "poly", "hit correct collider")
    physics.clear()
end)

test("raycast: misses when not intersecting", function()
    physics.init()
    physics.add("wall", 50, 50, 16, 16, "solid")
    local hits = physics.raycast(0, 0, 10, 10)
    assert_eq(#hits, 0, "should not hit wall")
    physics.clear()
end)

test("raycast: returns sorted by distance", function()
    physics.init()
    physics.add("far", 80, 50, 16, 16, "solid")
    physics.add("near", 40, 50, 16, 16, "solid")
    local hits = physics.raycast(0, 58, 100, 58)
    assert_eq(#hits, 2, "hit both walls")
    assert_true(hits[1].distance < hits[2].distance, "sorted by distance")
    assert_eq(hits[1].id, "near", "nearest is first")
    physics.clear()
end)

test("raycast: callback stops early", function()
    physics.init()
    physics.add("wall1", 50, 50, 16, 16, "solid")
    physics.add("wall2", 70, 50, 16, 16, "solid")
    local count = 0
    local hits = physics.raycast(0, 58, 100, 58, nil, nil, function()
        count = count + 1
        return true
    end)
    assert_eq(count, 1, "callback called once")
    assert_eq(#hits, 1, "only one hit returned")
    physics.clear()
end)

-- ============================================================================
-- layer and mask tests
-- ============================================================================

print("\n=== Layers and Masks ===\n")

test("layer: add_layered creates correct mask", function()
    physics.init()
    physics.add_layered("test", 0, 0, 16, 16, "solid", 2)
    local col = physics.get("test")
    assert_eq(col.mask, 0x0004, "layer 2 should be bitmask 0x0004")
    physics.clear()
end)

test("layer: defaults to layer 0", function()
    physics.init()
    physics.add_layered("test", 0, 0, 16, 16, "solid")
    local col = physics.get("test")
    assert_eq(col.mask, 0x0001, "layer 0 should be bitmask 0x0001")
    physics.clear()
end)

test("mask: filters collisions", function()
    physics.init()
    physics.add("player", 0, 0, 16, 16, "player", true, 0x0001)
    physics.add("wall1", 0, 0, 16, 16, "solid", true, 0x0001)
    physics.add("wall2", 0, 0, 16, 16, "solid", true, 0x0002)
    local hits = physics.check("player", 0, 0)
    assert_not_nil(hits["wall1"], "hit matching mask")
    assert_nil(hits["wall2"], "ignored non-matching mask")
    physics.clear()
end)

-- ============================================================================
-- General/Utility Tests
-- ============================================================================

print("\n=== Utility Methods ===\n")

test("remove: deletes collider and clears grid", function()
    physics.init()
    physics.add("temp", 0, 0, 16, 16)
    assert_true(physics.exists("temp"), "exists before remove")
    
    physics.remove("temp")
    assert_false(physics.exists("temp"), "does not exist after remove")
    
    physics.add("check", 0, 0, 16, 16)
    local hits = physics.check("check", 0, 0)
    assert_nil(hits["temp"], "should not be hit")
    physics.clear()
end)

test("update: manually moves collider", function()
    physics.init()
    physics.add("moveable", 0, 0, 16, 16)
    physics.update("moveable", 100, 100)
    
    local col = physics.get("moveable")
    assert_eq(col.x, 100, "x updated")
    assert_eq(col.y, 100, "y updated")
    
    physics.add("wall", 100, 100, 16, 16)
    local hits = physics.check("moveable", 100, 100)
    assert_not_nil(hits["wall"], "grid updated correctly")
    physics.clear()
end)

test("query_region: returns colliders in area", function()
    physics.init()
    physics.add("a", 10, 10, 10, 10)
    physics.add("b", 100, 100, 10, 10)
    
    local results = physics.query_region(0, 0, 50, 50)
    assert_eq(#results, 1, "found 1 collider")
    assert_eq(results[1].id, "a", "found correct collider")
    physics.clear()
end)

test("cache_neighbors: optimization", function()
    physics.init()
    physics.add("cached", 0, 0, 16, 16)
    physics.add("neighbor", 10, 0, 16, 16)
    
    physics.cache_neighbors("cached")
    local col = physics.get("cached")
    assert_not_nil(col.cached_neighbors, "neighbors cached")
    
    physics.clear_cache("cached")
    assert_nil(col.cached_neighbors, "cache cleared")
    physics.clear()
end)

test("callbacks: on_collide triggered", function()
    physics.init()
    local hit_count = 0
    local last_other
    
    local function on_hit(id, other, col, nx, ny)
        hit_count = hit_count + 1
        last_other = other
    end
    
    physics.add("mover", 0, 0, 16, 16, "player", true, nil, on_hit)
    physics.add("obstacle", 20, 0, 16, 16, "solid")
    
    physics.move("mover", 20, 0)
    
    assert_true(hit_count > 0, "callback fired")
    assert_eq(last_other, "obstacle", "correct other id")
    physics.clear()
end)

test("stats: returns correct counts", function()
    physics.init()
    physics.add("a", 0, 0, 10, 10)
    physics.add("b", 100, 100, 10, 10)
    
    local stats = physics.get_stats()
    assert_eq(stats.colliders, 2, "collider count")
    assert_true(stats.active_cells > 0, "active cells count")
    physics.clear()
end)

-- ============================================================================
-- performance benchmarks
-- ============================================================================

print("\n=== Performance Benchmarks ===\n")

test("benchmark: add many static colliders", function()
    physics.init()
    local count = 5000
    local start = os.clock()
    
    for i = 1, count do
        physics.add(i, i * 2, i * 2, 16, 16, "solid")
    end
    
    local elapsed = os.clock() - start
    print(string.format("  add %d colliders: %.3fs (%.0f/sec)", 
        count, elapsed, count / elapsed))
    physics.clear()
end)

test("benchmark: move with collision checks", function()
    physics.init()
    local grid_w, grid_h = 50, 50
    for x = 0, grid_w do
        for y = 0, grid_h do
            physics.add("wall_"..x.."_"..y, x * 32, y * 32, 16, 16, "solid")
        end
    end
    
    physics.add("mover", 0, 0, 16, 16, "player")
    
    local moves = 1000
    local start = os.clock()
    
    for i = 1, moves do
        physics.move("mover", 5, 5)
        physics.move("mover", 5, -2)
    end
    
    local elapsed = os.clock() - start
    print(string.format("  %d moves vs %d statics: %.3fs (%.0f moves/sec)", 
        moves, (grid_w+1)*(grid_h+1), elapsed, moves / elapsed))
    physics.clear()
end)

test("benchmark: raycasts", function()
    physics.init()
    for i = 1, 1000 do
        physics.add(i, math.random(0, 1000), math.random(0, 1000), 16, 16, "solid")
    end
    
    local casts = 5000
    local start = os.clock()
    
    for i = 1, casts do
        physics.raycast(0, 0, 1000, 1000)
    end
    
    local elapsed = os.clock() - start
    print(string.format("  %d raycasts vs 1000 objs: %.3fs (%.0f casts/sec)", 
        casts, elapsed, casts / elapsed))
    physics.clear()
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
        print("    Error: " .. tostring(failure.error))
    end
    os.exit(1)
else
    print("\n✓ All tests passed!")
    os.exit(0)
end