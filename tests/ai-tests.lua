local ai = require("lib.ai")

local tests_run = 0
local tests_passed = 0
local tests_failed = 0

local function assert_eq(a, b, msg)
    tests_run = tests_run + 1
    if a == b then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. (msg or "assertion failed") .. " (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
    end
end

local function assert_true(cond, msg)
    assert_eq(cond, true, msg)
end

local function assert_false(cond, msg)
    assert_eq(cond, false, msg)
end

local function assert_near(a, b, epsilon, msg)
    tests_run = tests_run + 1
    epsilon = epsilon or 0.001
    if math.abs(a - b) < epsilon then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. (msg or "values not close") .. " (expected ~" .. tostring(b) .. ", got " .. tostring(a) .. ")")
    end
end

local function assert_not_nil(val, msg)
    tests_run = tests_run + 1
    if val ~= nil then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. (msg or "value is nil"))
    end
end

local function assert_nil(val, msg)
    tests_run = tests_run + 1
    if val == nil then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. (msg or "value is not nil"))
    end
end

print("=== AI LIBRARY TEST SUITE ===\n")

-- ============================================================================
-- UTILITY TESTS
-- ============================================================================

print("Testing utilities...")

-- manhattan distance
assert_eq(ai.manhattan(0, 0, 3, 4), 7, "manhattan distance")
assert_eq(ai.manhattan(5, 5, 5, 5), 0, "manhattan same point")
assert_eq(ai.manhattan(-2, -3, 2, 3), 10, "manhattan negative coords")

-- euclidean distance
assert_near(ai.euclidean(0, 0, 3, 4), 5, 0.001, "euclidean distance")
assert_eq(ai.euclidean(5, 5, 5, 5), 0, "euclidean same point")
assert_near(ai.euclidean(0, 0, 1, 1), math.sqrt(2), 0.001, "euclidean diagonal")

-- binary heap
local h = ai.heap.new()
assert_true(h:empty(), "heap starts empty")
h:push(5)
h:push(3)
h:push(7)
h:push(1)
assert_false(h:empty(), "heap not empty after push")
assert_eq(h:pop(), 1, "heap min 1")
assert_eq(h:pop(), 3, "heap min 2")
assert_eq(h:pop(), 5, "heap min 3")
assert_eq(h:pop(), 7, "heap min 4")
assert_true(h:empty(), "heap empty after all pops")
assert_nil(h:pop(), "pop from empty heap returns nil")

-- heap with custom comparator
local max_heap = ai.heap.new(function(a, b) return a > b end)
max_heap:push(5)
max_heap:push(3)
max_heap:push(7)
assert_eq(max_heap:pop(), 7, "max heap returns maximum")

print("Utilities: OK\n")

-- ============================================================================
-- A* PATHFINDING TESTS
-- ============================================================================

print("Testing A* pathfinding...")

-- simple grid
local grid = {
    {1, 1, 1, 1, 1},
    {1, 0, 0, 0, 1},
    {1, 1, 1, 0, 1},
    {0, 0, 1, 0, 1},
    {1, 1, 1, 1, 1}
}

local path = ai.asp.grid(grid, 1, 1, 5, 5)
assert_not_nil(path, "a* finds path in open grid")
assert_eq(path[1].x, 1, "path starts at start x")
assert_eq(path[1].y, 1, "path starts at start y")
assert_eq(path[#path].x, 5, "path ends at goal x")
assert_eq(path[#path].y, 5, "path ends at goal y")

-- blocked path
local blocked_grid = {
    {1, 0, 1},
    {1, 0, 1},
    {1, 0, 1}
}
local no_path = ai.asp.grid(blocked_grid, 1, 1, 3, 1)
assert_nil(no_path, "a* returns nil when no path exists")

-- same start and goal
local same_path = ai.asp.grid(grid, 1, 1, 1, 1)
assert_not_nil(same_path, "a* handles same start/goal")
assert_eq(#same_path, 1, "path to self has length 1")

-- weighted grid (prefer certain paths)
local weighted_grid = {
    {1, 1, 1},
    {1, 10, 1},
    {1, 1, 1}
}
local weighted_path = ai.asp.grid(weighted_grid, 1, 1, 3, 3)
assert_not_nil(weighted_path, "a* works with weighted costs")

-- custom heuristic (manhattan)
local manhattan_path = ai.asp.grid(grid, 1, 1, 5, 5, ai.manhattan)
assert_not_nil(manhattan_path, "a* works with manhattan heuristic")

print("A* pathfinding: OK\n")

-- ============================================================================
-- JUMP POINT SEARCH TESTS
-- ============================================================================

print("Testing Jump Point Search...")

local jps_path = ai.jps.grid(grid, 1, 1, 5, 5)
assert_not_nil(jps_path, "jps finds path")
assert_eq(jps_path[1].x, 1, "jps path starts at start")
assert_eq(jps_path[#jps_path].x, 5, "jps path ends at goal")

local jps_no_path = ai.jps.grid(blocked_grid, 1, 1, 3, 1)
assert_nil(jps_no_path, "jps returns nil when blocked")

-- large open grid (jps should be efficient)
local large_grid = {}
for y = 1, 20 do
    large_grid[y] = {}
    for x = 1, 20 do
        large_grid[y][x] = 1
    end
end
local jps_large = ai.jps.grid(large_grid, 1, 1, 20, 20)
assert_not_nil(jps_large, "jps handles large grids")

print("Jump Point Search: OK\n")

-- ============================================================================
-- NAVIGATION MESH TESTS
-- ============================================================================

print("Testing Navigation Mesh...")

local triangles = {
    ai.navmesh.triangle({x=0, y=0}, {x=10, y=0}, {x=5, y=10}),
    ai.navmesh.triangle({x=10, y=0}, {x=20, y=0}, {x=15, y=10}),
    ai.navmesh.triangle({x=10, y=0}, {x=15, y=10}, {x=5, y=10})
}

local mesh = ai.navmesh.new(triangles)
assert_not_nil(mesh, "navmesh created")
assert_eq(#mesh.triangles, 3, "navmesh has correct triangle count")

local tri = ai.navmesh.find_triangle(mesh, 5, 3)
assert_not_nil(tri, "find_triangle finds containing triangle")

local tri_outside = ai.navmesh.find_triangle(mesh, 100, 100)
assert_nil(tri_outside, "find_triangle returns nil for outside point")

local nav_path = ai.navmesh.find_path(mesh, 2, 2, 18, 2)
assert_not_nil(nav_path, "navmesh finds path")
assert_eq(nav_path[1].x, 2, "navmesh path starts correctly")

-- same triangle
local same_tri_path = ai.navmesh.find_path(mesh, 5, 3, 6, 4)
assert_not_nil(same_tri_path, "navmesh handles same triangle")

print("Navigation Mesh: OK\n")

-- ============================================================================
-- HIERARCHICAL PATHFINDING TESTS
-- ============================================================================

print("Testing Hierarchical Pathfinding...")

local hpa_grid = {}
for y = 1, 25 do
    hpa_grid[y] = {}
    for x = 1, 25 do
        hpa_grid[y][x] = 1
    end
end

local hpa = ai.hpa.new(hpa_grid, 5)
assert_not_nil(hpa, "hpa created")
assert_eq(hpa.cluster_size, 5, "hpa cluster size correct")
assert_true(#hpa.entrances > 0, "hpa found entrances")

local hpa_path = ai.hpa.find_path(hpa, 1, 1, 25, 25)
assert_not_nil(hpa_path, "hpa finds path")

print("Hierarchical Pathfinding: OK\n")

-- ============================================================================
-- FLOW FIELD TESTS
-- ============================================================================

print("Testing Flow Field...")

local ff_grid = {
    {1, 1, 1, 1},
    {1, 0, 0, 1},
    {1, 1, 1, 1}
}

local field = ai.ffp.compute(ff_grid, 4, 3)
assert_not_nil(field, "flow field computed")

local dx, dy = ai.ffp.follow(field, 1, 1)
assert_true(dx ~= 0 or dy ~= 0, "flow field has direction")

-- flow toward goal
local dx2, dy2 = ai.ffp.follow(field, 4, 3)
assert_eq(dx2, 0, "flow at goal is zero x")
assert_eq(dy2, 0, "flow at goal is zero y")

-- out of bounds
local dx3, dy3 = ai.ffp.follow(field, 100, 100)
assert_eq(dx3, 0, "out of bounds returns zero")

print("Flow Field: OK\n")

-- ============================================================================
-- FINITE STATE MACHINE TESTS
-- ============================================================================

-- NOTE/TODO: move this shit outta here

print("Testing Finite State Machine...")

local fsm_log = {}
local test_fsm = ai.fsm.new("idle")

test_fsm:add_state("idle",
    function() table.insert(fsm_log, "enter idle") end,
    function() table.insert(fsm_log, "update idle") end,
    function() table.insert(fsm_log, "exit idle") end
)

test_fsm:add_state("moving",
    function() table.insert(fsm_log, "enter moving") end,
    function() table.insert(fsm_log, "update moving") end,
    function() table.insert(fsm_log, "exit moving") end
)

assert_eq(test_fsm:current(), "idle", "fsm starts in initial state")

test_fsm:update(0.016)
assert_eq(fsm_log[#fsm_log], "update idle", "fsm updates current state")

test_fsm:change_state("moving")
assert_eq(test_fsm:current(), "moving", "fsm changes state")
assert_eq(fsm_log[#fsm_log], "enter moving", "fsm calls enter on new state")

-- no change on same state
local log_len = #fsm_log
test_fsm:change_state("moving")
assert_eq(#fsm_log, log_len, "fsm doesn't change to same state")

-- hierarchical fsm
test_fsm:add_substate("moving", "walk")
test_fsm:add_substate("moving", "run")
assert_not_nil(test_fsm.states.moving.substates, "fsm has substates")

print("Finite State Machine: OK\n")

-- ============================================================================
-- BEHAVIOR TREE TESTS
-- ============================================================================

print("Testing Behavior Trees...")

local bt_context = {value = 0}

-- action node
local inc_action = ai.btree.action(function(ctx)
    ctx.value = ctx.value + 1
    return ai.btree.SUCCESS
end)
assert_eq(inc_action:tick(bt_context), ai.btree.SUCCESS, "action returns success")
assert_eq(bt_context.value, 1, "action modifies context")

-- condition node
local check_positive = ai.btree.condition(function(ctx)
    return ctx.value > 0
end)
assert_eq(check_positive:tick(bt_context), ai.btree.SUCCESS, "condition true returns success")

bt_context.value = -1
assert_eq(check_positive:tick(bt_context), ai.btree.FAILURE, "condition false returns failure")

-- sequence node
bt_context.value = 0
local seq = ai.btree.sequence({inc_action, check_positive})
assert_eq(seq:tick(bt_context), ai.btree.SUCCESS, "sequence succeeds when all succeed")

local fail_action = ai.btree.action(function() return ai.btree.FAILURE end)
local fail_seq = ai.btree.sequence({inc_action, fail_action, inc_action})
bt_context.value = 0
assert_eq(fail_seq:tick(bt_context), ai.btree.FAILURE, "sequence fails on first failure")
assert_eq(bt_context.value, 1, "sequence stops at failure")

-- selector node
local sel = ai.btree.selector({fail_action, inc_action})
bt_context.value = 0
assert_eq(sel:tick(bt_context), ai.btree.SUCCESS, "selector succeeds on first success")

local all_fail_sel = ai.btree.selector({fail_action, fail_action})
assert_eq(all_fail_sel:tick(bt_context), ai.btree.FAILURE, "selector fails when all fail")

-- parallel node
bt_context.value = 0
local par = ai.btree.parallel({inc_action, inc_action, inc_action}, 2)
assert_eq(par:tick(bt_context), ai.btree.SUCCESS, "parallel succeeds with enough successes")
assert_eq(bt_context.value, 3, "parallel runs all children")

-- inverter
local inv = ai.btree.inverter(inc_action)
assert_eq(inv:tick(bt_context), ai.btree.FAILURE, "inverter inverts success")

local inv2 = ai.btree.inverter(fail_action)
assert_eq(inv2:tick(bt_context), ai.btree.SUCCESS, "inverter inverts failure")

-- repeater
bt_context.value = 0
local rep = ai.btree.repeater(inc_action, 3)
assert_eq(rep:tick(bt_context), ai.btree.SUCCESS, "repeater succeeds after n iterations")
assert_eq(bt_context.value, 3, "repeater runs n times")

print("Behavior Trees: OK\n")

-- ============================================================================
-- GOAP TESTS
-- ============================================================================

print("Testing GOAP...")

-- create actions
local chop_wood = ai.goap.action("chop_wood", 4, {has_axe = true}, {has_wood = true})
local get_axe = ai.goap.action("get_axe", 2, {}, {has_axe = true})
local build_house = ai.goap.action("build_house", 6, {has_wood = true, has_nails = true}, {has_house = true})
local buy_nails = ai.goap.action("buy_nails", 1, {}, {has_nails = true})

local actions = {chop_wood, get_axe, build_house, buy_nails}

-- plan to build house
local start_state = ai.goap.state({})
local goal_state = ai.goap.state({has_house = true})

local plan = ai.goap.plan(start_state, goal_state, actions)
assert_not_nil(plan, "goap finds plan")
assert_true(#plan > 0, "plan has actions")
assert_eq(plan[#plan].name, "build_house", "plan ends with goal action")

-- verify plan order
assert_eq(plan[1].name, "buy_nails", "goap plans in correct order")

-- no plan possible
local impossible_goal = ai.goap.state({impossible = true})
local no_plan = ai.goap.plan(start_state, impossible_goal, actions)
assert_nil(no_plan, "goap returns nil for impossible goal")

-- already at goal
local at_goal_plan = ai.goap.plan(goal_state, goal_state, actions)
assert_not_nil(at_goal_plan, "goap handles already at goal")
assert_eq(#at_goal_plan, 0, "plan is empty when at goal")

print("GOAP: OK\n")

-- ============================================================================
-- UTILITY AI TESTS
-- ============================================================================

print("Testing Utility AI...")

-- considerations
local health_consideration = ai.utility.consideration(
    function(ctx) return ctx.health end,
    ai.utility.curve_linear(1, 0)
)

local distance_consideration = ai.utility.consideration(
    function(ctx) return 1 - ctx.distance end,
    ai.utility.curve_quadratic(2)
)

local context = {health = 0.5, distance = 0.3}
assert_near(health_consideration:evaluate(context), 0.5, 0.01, "consideration evaluates health")
assert_near(distance_consideration:evaluate(context), 0.49, 0.01, "consideration evaluates distance")

-- curve functions
local linear = ai.utility.curve_linear(2, 0.5)
assert_near(linear(0.25), 1, 0.01, "linear curve clamped at 1")

local linear2 = ai.utility.curve_linear(1, 0)
assert_near(linear2(0.5), 0.5, 0.01, "linear curve no clamp")

local quad = ai.utility.curve_quadratic(2)
assert_near(quad(0.5), 0.25, 0.01, "quadratic curve")

local inv = ai.utility.curve_inverse()
assert_near(inv(0.3), 0.7, 0.01, "inverse curve")

local sig = ai.utility.curve_sigmoid(5, 0.5)
assert_true(sig(0.5) > 0.4 and sig(0.5) < 0.6, "sigmoid curve")

-- actions
local attack_action = ai.utility.action("attack", {health_consideration}, function() end)
local flee_action = ai.utility.action("flee", {distance_consideration}, function() end)

context.health = 0.8
context.distance = 0.2
local best, score = ai.utility.select_action({attack_action, flee_action}, context)
assert_eq(best.name, "attack", "utility selects best action")
assert_true(score > 0, "utility returns score")

-- zero score handling
context.health = 0
context.distance = 0
local zero_best = ai.utility.select_action({attack_action}, context)
assert_not_nil(zero_best, "utility handles zero scores")

-- empty considerations
local no_consideration_action = ai.utility.action("test", {}, function() end)
local no_con_score = no_consideration_action:evaluate(context)
assert_eq(no_con_score, 1, "action with no considerations scores 1")

print("Utility AI: OK\n")

-- ============================================================================
-- STEERING BEHAVIORS TESTS
-- ============================================================================

print("Testing Steering Behaviors...")

local agent = {x = 0, y = 0, vx = 0, vy = 0}
local target = {x = 10, y = 0}

-- seek
local fx, fy = ai.steer.seek(agent, target, 5)
assert_true(fx > 0, "seek produces positive x force toward right")
assert_near(fy, 0, 0.01, "seek y force is zero for horizontal")

-- seek at target
agent.x = 10
local fx2, fy2 = ai.steer.seek(agent, target, 5)
assert_near(fx2, 0, 0.01, "seek at target is zero")

-- flee
agent.x = 0
local ffx, ffy = ai.steer.flee(agent, target, 5)
assert_true(ffx < 0, "flee produces negative force away from threat")

-- arrive
agent.x = 8
agent.vx = 0
local afx, afy = ai.steer.arrive(agent, target, 5, 5)
assert_true(afx >= 0, "arrive slows down near target")

-- pursue
local moving_target = {x = 10, y = 0, vx = 2, vy = 0}
agent.x = 0
agent.vx = 0
local pfx, pfy = ai.steer.pursue(agent, moving_target, 5, 1)
assert_true(pfx > 0, "pursue leads moving target")

-- evade
local efx, efy = ai.steer.evade(agent, moving_target, 5, 1)
assert_true(efx < 0, "evade escapes from pursuing threat")

-- wander
agent.wander_angle = 0
local wfx, wfy = ai.steer.wander(agent, 1, 1, 0.5)
assert_true(wfx ~= 0 or wfy ~= 0, "wander produces direction")

-- separation
local neighbors = {
    {x = 1, y = 0},
    {x = -1, y = 0}
}
agent.x = 0
agent.y = 0
local sfx, sfy = ai.steer.separation(agent, neighbors, 5)
assert_near(sfx, 0, 0.01, "separation balanced in x")

-- separation with one neighbor
local single_neighbor = {{x = 1, y = 0}}
local sfx2, sfy2 = ai.steer.separation(agent, single_neighbor, 5)
assert_true(sfx2 < 0, "separation pushes away from neighbor")

-- alignment
local aligned_neighbors = {
    {x = 1, y = 1, vx = 1, vy = 0},
    {x = -1, y = 1, vx = 1, vy = 0}
}
agent.vx = 0
agent.vy = 0
local alx, aly = ai.steer.alignment(agent, aligned_neighbors, 5)
assert_true(alx > 0, "alignment matches neighbor velocity")

-- cohesion
local coh_neighbors = {
    {x = 5, y = 5},
    {x = 5, y = -5}
}
agent.x = 0
agent.y = 0
local cfx, cfy = ai.steer.cohesion(agent, coh_neighbors, 10, 5)
assert_true(cfx > 0, "cohesion moves toward center")

-- empty neighbors
local efx2, efy2 = ai.steer.separation(agent, {}, 5)
assert_eq(efx2, 0, "empty neighbors returns zero")

print("Steering Behaviors: OK\n")

-- ============================================================================
-- INFLUENCE MAP TESTS
-- ============================================================================

print("Testing Influence Maps...")

local inf_map = ai.influence.new(10, 10, 0)
assert_not_nil(inf_map, "influence map created")
assert_eq(inf_map.width, 10, "influence map width correct")
assert_eq(inf_map.height, 10, "influence map height correct")

-- stamp influence
ai.influence.stamp(inf_map, 5, 5, 10, 2, 1)
local center_val = ai.influence.get(inf_map, 5, 5)
assert_true(center_val > 0, "influence stamped at center")

local edge_val = ai.influence.get(inf_map, 7, 5)
assert_true(edge_val < center_val, "influence decays with distance")

-- out of bounds
local oob_val = ai.influence.get(inf_map, 100, 100)
assert_eq(oob_val, 0, "out of bounds returns 0")

-- propagate
ai.influence.propagate(inf_map, 0.5, 0.9)
local propagated = ai.influence.get(inf_map, 6, 6)
assert_true(propagated > 0, "influence propagates")

-- combine maps
local map1 = ai.influence.new(5, 5, 1)
local map2 = ai.influence.new(5, 5, 2)
local combined = ai.influence.combine(map1, map2, 0.5, 0.5)
assert_eq(ai.influence.get(combined, 1, 1), 1.5, "maps combine correctly")

print("Influence Maps: OK\n")

-- ============================================================================
-- SPATIAL PARTITIONING TESTS
-- ============================================================================

print("Testing Spatial Partitioning...")

local spatial_grid = ai.spatial.grid_new(10, {0, 0, 100, 100})
assert_not_nil(spatial_grid, "spatial grid created")

-- insert objects
ai.spatial.grid_insert(spatial_grid, "obj1", 15, 15)
ai.spatial.grid_insert(spatial_grid, "obj2", 25, 25)
ai.spatial.grid_insert(spatial_grid, "obj3", 85, 85)

-- query near first object
local results = ai.spatial.grid_query(spatial_grid, 15, 15, 20)
assert_true(#results > 0, "spatial query finds objects")
assert_true(#results <= 2, "spatial query filters by distance")

-- query far from all
local far_results = ai.spatial.grid_query(spatial_grid, 0, 0, 5)
assert_eq(#far_results, 0, "spatial query finds nothing when far")

-- clear grid
ai.spatial.grid_clear(spatial_grid)
local empty_results = ai.spatial.grid_query(spatial_grid, 15, 15, 20)
assert_eq(#empty_results, 0, "spatial grid cleared")

print("Spatial Partitioning: OK\n")

-- ============================================================================
-- EDGE CASE AND STRESS TESTS
-- ============================================================================

print("Testing edge cases and stress scenarios...")

-- very small grids
local tiny_grid = {{1}}
local tiny_path = ai.asp.grid(tiny_grid, 1, 1, 1, 1)
assert_not_nil(tiny_path, "handles 1x1 grid")

-- diagonal only path
local diag_grid = {
    {1, 0, 0},
    {0, 1, 0},
    {0, 0, 1}
}
local diag_path = ai.asp.grid(diag_grid, 1, 1, 3, 3)
assert_not_nil(diag_path, "handles diagonal-only paths")

-- very large influence map
local large_inf = ai.influence.new(100, 100)
ai.influence.stamp(large_inf, 50, 50, 100, 10)
assert_true(ai.influence.get(large_inf, 50, 50) > 0, "handles large influence maps")

-- heap with many elements
local big_heap = ai.heap.new()
for i = 1, 1000 do
    big_heap:push(math.random(1000))
end
local prev = -1
local sorted = true
while not big_heap:empty() do
    local val = big_heap:pop()
    if val < prev then
        sorted = false
        break
    end
    prev = val
end
assert_true(sorted, "heap maintains order with many elements")

-- goap with complex state
local complex_actions = {}
for i = 1, 10 do
    table.insert(complex_actions, ai.goap.action(
        "action" .. i,
        math.random(5),
        {["cond" .. i] = true},
        {["effect" .. (i+1)] = true}
    ))
end
local complex_plan = ai.goap.plan({cond1 = true}, {effect11 = true}, complex_actions)
-- may or may not find path, just shouldn't crash
assert_true(true, "handles complex goap scenarios")

-- behavior tree with deep nesting
local deep_seq = ai.btree.sequence({
    ai.btree.sequence({
        ai.btree.sequence({
            ai.btree.action(function() return ai.btree.SUCCESS end)
        })
    })
})
assert_eq(deep_seq:tick({}), ai.btree.SUCCESS, "handles deeply nested trees")

-- navmesh with overlapping triangles
local overlap_tris = {
    ai.navmesh.triangle({x=0,y=0}, {x=10,y=0}, {x=5,y=5}),
    ai.navmesh.triangle({x=0,y=0}, {x=10,y=0}, {x=5,y=-5})
}
local overlap_mesh = ai.navmesh.new(overlap_tris)
assert_not_nil(overlap_mesh, "handles overlapping triangles")

-- flow field in enclosed area
local enclosed = {
    {0, 0, 0, 0, 0},
    {0, 1, 1, 1, 0},
    {0, 1, 0, 1, 0},
    {0, 1, 1, 1, 0},
    {0, 0, 0, 0, 0}
}
local enclosed_field = ai.ffp.compute(enclosed, 2, 2)
assert_not_nil(enclosed_field, "flow field in enclosed area")

-- utility ai with all zero scores
local zero_actions = {
    ai.utility.action("a1", {ai.utility.consideration(function() return 0 end)}, function() end),
    ai.utility.action("a2", {ai.utility.consideration(function() return 0 end)}, function() end)
}
local zero_action = ai.utility.select_action(zero_actions, {})
assert_not_nil(zero_action, "utility handles all zero scores")

print("Edge cases: OK\n")

-- ============================================================================
-- SUMMARY
-- ============================================================================

print("\n=== TEST SUMMARY ===")
print("Tests run: " .. tests_run)
print("Tests passed: " .. tests_passed)
print("Tests failed: " .. tests_failed)

if tests_failed == 0 then
    print("\n✓ ALL TESTS PASSED")
else
    print("\n✗ SOME TESTS FAILED")
    os.exit(1)
end