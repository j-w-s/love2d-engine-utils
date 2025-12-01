local ecs = require("ecs")

local total_tests = 0
local passed_tests = 0
local failed_tests = {}

local function test(name, fn)
    total_tests = total_tests + 1
    ecs.clear()
    
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

local function assert_true(value, msg)
    if not value then
        error(msg or "expected true, got false/nil")
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "expected false, got true")
    end
end

local function assert_nil(value, msg)
    if value ~= nil then
        error(string.format("%s: expected nil, got %s", msg or "assertion failed", tostring(value)))
    end
end

local function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "expected non-nil value")
    end
end

-- ============================================================================
-- ENTITY TESTS
-- ============================================================================

print("\n=== Entity Management ===\n")

test("entity: creation", function()
    local e = ecs.entity()
    assert_not_nil(e, "entity created")
    assert_not_nil(e.id, "entity has id")
    assert_true(e:valid(), "entity is valid")
end)

test("entity: creation with initial components", function()
    local e = ecs.entity("position", {x = 10, y = 20}, "velocity", {x = 1, y = 2})
    
    local pos = e:get("position")
    assert_not_nil(pos, "has position")
    assert_eq(pos.x, 10, "pos.x correct")
    assert_eq(pos.y, 20, "pos.y correct")
    
    local vel = e:get("velocity")
    assert_not_nil(vel, "has velocity")
    assert_eq(vel.x, 1, "vel.x correct")
    assert_eq(vel.y, 2, "vel.y correct")
end)

test("entity: add component", function()
    local e = ecs.entity()
    e:add("health", 100)
    
    local health = e:get("health")
    assert_eq(health, 100, "health value correct")
end)

test("entity: add multiple components", function()
    local e = ecs.entity()
    e:add("position", {x = 5, y = 10})
    e:add("velocity", {x = 1, y = 0})
    e:add("health", 50)
    
    assert_eq(e:get("position").x, 5, "position correct")
    assert_eq(e:get("velocity").x, 1, "velocity correct")
    assert_eq(e:get("health"), 50, "health correct")
end)

test("entity: update existing component", function()
    local e = ecs.entity("health", 100)
    e:add("health", 50)
    
    assert_eq(e:get("health"), 50, "health updated")
end)

test("entity: remove component", function()
    local e = ecs.entity("position", {x = 10, y = 20}, "velocity", {x = 1, y = 2})
    e:remove("velocity")
    
    assert_not_nil(e:get("position"), "position remains")
    assert_nil(e:get("velocity"), "velocity removed")
end)

test("entity: remove non-existent component", function()
    local e = ecs.entity("health", 100)
    e:remove("velocity") -- should not error
    
    assert_eq(e:get("health"), 100, "health remains")
end)

test("entity: chaining methods", function()
    local e = ecs.entity()
        :add("position", {x = 10, y = 20})
        :add("velocity", {x = 1, y = 2})
        :add("health", 100)
    
    assert_not_nil(e:get("position"), "has position")
    assert_not_nil(e:get("velocity"), "has velocity")
    assert_eq(e:get("health"), 100, "has health")
end)

test("entity: has component check", function()
    local e = ecs.entity("position", {x = 10, y = 20})
    
    assert_true(e:has("position"), "has position")
    assert_false(e:has("velocity"), "does not have velocity")
end)

test("entity: destroy", function()
    local e = ecs.entity("health", 100)
    local id = e.id
    
    e:destroy()
    
    assert_false(e:valid(), "entity no longer valid")
    assert_nil(e:get("health"), "cannot get components")
end)

test("entity: id reuse", function()
    local e1 = ecs.entity()
    local id1 = e1.id
    e1:destroy()
    
    local e2 = ecs.entity()
    local id2 = e2.id
    
    -- when entity is destroyed, id goes into free_ids
    -- next entity() call should reuse it
    assert_eq(id1, id2, "entity id should be reused")
end)

-- ============================================================================
-- QUERY TESTS
-- ============================================================================

print("\n=== Query System ===\n")

test("query: single component iteration", function()
    ecs.entity("position", {x = 10, y = 20})
    ecs.entity("position", {x = 30, y = 40})
    ecs.entity("velocity", {x = 1, y = 2})
    
    local count = 0
    ecs.query():with("position"):each(function(e, pos)
        count = count + 1
        assert_not_nil(pos, "component passed to callback")
    end)
    
    assert_eq(count, 2, "iterated correct number of entities")
end)

test("query: multiple components iteration", function()
    ecs.entity("position", {x = 10, y = 20}, "velocity", {x = 1, y = 2})
    ecs.entity("position", {x = 30, y = 40})
    ecs.entity("velocity", {x = 1, y = 2})
    
    local count = 0
    ecs.query():with("position", "velocity"):each(function(e, pos, vel)
        count = count + 1
        assert_not_nil(pos, "pos passed")
        assert_not_nil(vel, "vel passed")
    end)
    
    assert_eq(count, 1, "found entity with both components")
end)

test("query: without exclusion", function()
    ecs.entity("position", {x = 10, y = 20}, "health", 100)
    ecs.entity("position", {x = 30, y = 40})
    
    local count = 0
    ecs.query():with("position"):without("health"):each(function(e, pos)
        count = count + 1
        assert_eq(pos.x, 30, "found correct entity")
    end)
    
    assert_eq(count, 1, "excluded entity with health")
end)

test("query: count", function()
    ecs.entity("position", {x = 10, y = 20})
    ecs.entity("position", {x = 30, y = 40})
    ecs.entity("velocity", {x = 1, y = 2})
    
    local count = ecs.query():with("position"):count()
    assert_eq(count, 2, "count is correct")
end)

test("query: first", function()
    ecs.entity("position", {x = 10, y = 20})
    
    local e = ecs.query():with("position"):first()
    assert_not_nil(e, "found first entity")
    assert_not_nil(e:get("position"), "entity has required component")
end)

test("query: first with no matches", function()
    local e = ecs.query():with("velocity"):first()
    assert_nil(e, "returns nil when no matches")
end)

test("query: modification during iteration", function()
    local e1 = ecs.entity("health", 100)
    local e2 = ecs.entity("health", 50)
    
    ecs.query():with("health"):each(function(e, health)
        e:add("health", health + 10)
    end)
    
    assert_eq(e1:get("health"), 110, "e1 modified")
    assert_eq(e2:get("health"), 60, "e2 modified")
end)

test("query: caching mechanism", function()
    for i = 1, 50 do
        ecs.entity("position", {x = i, y = i})
    end
    
    local stats_before = ecs.stats()
    local q = ecs.query():with("position")
    q:count() -- triggers cache build
    
    local stats_after_1 = ecs.stats()
    q:count() -- should use cache
    
    -- NOTE/TODO: ecs.lua stats() doesn't explicitly expose cache hit count
    assert_eq(q:count(), 50, "query result correct from cache")
end)

-- ============================================================================
-- SYSTEM TESTS
-- ============================================================================

print("\n=== Systems & Groups ===\n")

test("system: basic execution", function()
    local executed = false
    
    ecs.system(
        ecs.query():with("health"),
        function(e, health, dt)
            executed = true
            assert_eq(dt, 0.016, "dt passed correctly")
        end
    )
    
    ecs.entity("health", 100)
    ecs.update(0.016)
    
    assert_true(executed, "system executed")
end)

test("system: priority", function()
    local log = {}
    
    ecs.system(
        ecs.query():with("val"),
        function() table.insert(log, 2) end,
        10
    )
    
    ecs.system(
        ecs.query():with("val"),
        function() table.insert(log, 1) end,
        5 
    )
    
    ecs.entity("val", 1)
    ecs.update(0.1)
    
    assert_eq(log[1], 1, "priority 5 ran first")
    assert_eq(log[2], 2, "priority 10 ran second")
end)

test("system: enable/disable", function()
    local count = 0
    local sys = ecs.system(
        ecs.query():with("val"),
        function() count = count + 1 end
    )
    
    ecs.entity("val", 1)
    
    ecs.update(0.1)
    assert_eq(count, 1, "ran when enabled")
    
    sys.enabled = false
    ecs.update(0.1)
    assert_eq(count, 1, "did not run when disabled")
end)

test("system: coroutines", function()
    local frame = 0
    local finished = false
    
    local sys = ecs.system(
        ecs.query():with("flag"),
        function() end -- main loop fn
    )

    sys.coroutine = coroutine.create(function(dt)
        frame = 1
        coroutine.yield()
        frame = 2
        coroutine.yield()
        frame = 3
        finished = true
    end)
    
    ecs.entity("flag", true)
    
    ecs.update(0.1)
    assert_eq(frame, 1, "coroutine frame 1")
    
    ecs.update(0.1)
    assert_eq(frame, 2, "coroutine frame 2")
    
    ecs.update(0.1)
    assert_eq(frame, 3, "coroutine frame 3")
    assert_true(finished, "coroutine finished")
end)

test("system: groups", function()
    local physics_run = false
    local render_run = false
    
    ecs.system_group("physics")
    ecs.system_group("render")
    
    ecs.system_in_group("physics", ecs.query():with("p"), function() physics_run = true end)
    ecs.system_in_group("render", ecs.query():with("r"), function() render_run = true end)
    
    ecs.entity("p", 1, "r", 1)
    
    ecs.update_group("physics", 0.1)
    assert_true(physics_run, "physics ran")
    assert_false(render_run, "render did not run")
    
    physics_run = false
    
    ecs.update(0.1)
    assert_true(physics_run, "physics ran")
    assert_true(render_run, "render ran")
end)

-- ============================================================================
-- PREFAB & PATTERN TESTS
-- ============================================================================

print("\n=== Prefabs & Patterns ===\n")

test("prefab: register and spawn", function()
    ecs.prefab("orc", {
        health = 100,
        strength = 15,
        pos = {x=0, y=0}
    })
    
    local e = ecs.spawn("orc")
    assert_eq(e:get("health"), 100, "default health")
    assert_eq(e:get("strength"), 15, "default strength")
end)

test("prefab: spawn with overrides", function()
    ecs.prefab("orc", {
        health = 100,
        faction = "horde"
    })
    
    local e = ecs.spawn("orc", {
        health = 200,
        elite = true
    })
    
    assert_eq(e:get("health"), 200, "overridden health")
    assert_eq(e:get("faction"), "horde", "inherited faction")
    assert_eq(e:get("elite"), true, "new component added")
end)

test("prefab: deep copy", function()
    ecs.prefab("box", {
        dim = {w=10, h=10}
    })
    
    local e1 = ecs.spawn("box")
    local e2 = ecs.spawn("box")
    
    e1:get("dim").w = 20
    
    assert_eq(e2:get("dim").w, 10, "instances do not share tables")
end)

test("pattern: registration and retrieval", function()
    ecs.pattern("renderable", "position", "sprite")
    
    ecs.entity("position", 1, "sprite", 2)
    
    ecs.entity("position", 1) 
    
    ecs.entity("position", 1, "sprite", 2, "health", 100) 
    
    local entities = ecs.get_pattern("renderable")
    assert_eq(#entities, 1, "found correct pattern matches (strict archetype)")
end)

test("pattern: strict vs subset (query)", function()
    ecs.pattern("basic", "A")
    
    ecs.entity("A", 1)          -- archetype {A}
    ecs.entity("A", 1, "B", 2)  -- archetype {A, B}
    
    local pat_entities = ecs.get_pattern("basic")
    assert_eq(#pat_entities, 1, "get_pattern is strict")
    
    local query_count = ecs.query():with("A"):count()
    assert_eq(query_count, 2, "query is subset matching")
end)

-- ============================================================================
-- EVENTS & SERIALIZATION
-- ============================================================================

print("\n=== Events & Serialization ===\n")

test("event: on_add", function()
    local captured_data = nil
    
    ecs.on_add("trigger", function(e, data)
        captured_data = data
    end)
    
    local e = ecs.entity()
    e:add("trigger", "boom")
    
    assert_eq(captured_data, "boom", "on_add fired")
end)

test("event: on_remove", function()
    local removed = false
    
    ecs.on_remove("shield", function(e, data)
        removed = true
    end)
    
    local e = ecs.entity("shield", 100)
    e:remove("shield")
    
    assert_true(removed, "on_remove fired")
end)

test("event: on_remove via destroy", function()
    local removed = false
    
    ecs.on_remove("soul", function()
        removed = true
    end)
    
    local e = ecs.entity("soul", 1)
    e:destroy()
    
    assert_true(removed, "destroy triggers on_remove")
end)

test("serialization: save and load", function()
    ecs.entity("health", 100, "pos", {x=10, y=20})
    ecs.entity("tag", "player")
    
    local saved_data = ecs.serialize()
    
    ecs.clear()
    assert_eq(ecs.stats().entities, 0, "world cleared")
    
    ecs.deserialize(saved_data)
    
    assert_eq(ecs.stats().entities, 2, "entities restored")
    
    local p = ecs.query():with("pos"):first()
    assert_eq(p:get("health"), 100, "component data restored")
    assert_eq(p:get("pos").x, 10, "nested table data restored")
end)

test("serialization: preserves ids", function()
    local e = ecs.entity("id_check", true)
    local original_id = e.id
    
    local data = ecs.serialize()
    ecs.clear()
    ecs.deserialize(data)
    
    local restored = ecs.query():with("id_check"):first()
    assert_eq(restored.id, original_id, "ID preserved")
end)

-- ============================================================================
-- EDGE CASES & ARCHETYPE LOGIC
-- ============================================================================

print("\n=== Edge Cases & Archetypes ===\n")

test("archetype: transition caching", function()
    local entities = {}
    for i = 1, 10 do
        entities[i] = ecs.entity("health", 100)
    end
    
    local stats_before = ecs.stats()
    
    for i = 1, 10 do
        entities[i]:add("position", {x = i, y = i})
    end
    
    local stats_after = ecs.stats()

    for i = 1, 10 do
        local p = entities[i]:get("position")
        assert_eq(p.x, i, "data preserved after transition")
    end
    
    assert_true(stats_after.archetypes < stats_before.archetypes + 5, "Archetypes reused efficiently")
end)

test("edge: empty entity", function()
    local e = ecs.entity()
    assert_nil(e:get("anything"))
    e:destroy()
end)

test("edge: destroy entity twice", function()
    local e = ecs.entity()
    e:destroy()
    
    -- second destroy should be safe/noop
    local success, err = pcall(function() e:destroy() end)
    assert_true(success, "double destroy is safe")
    assert_false(e:valid(), "still invalid")
end)

test("edge: remove component twice", function()
    local e = ecs.entity("a", 1)
    e:remove("a")
    e:remove("a") -- safe
    assert_nil(e:get("a"))
end)

test("edge: query empty world", function()
    local count = ecs.query():with("test"):count()
    assert_eq(count, 0, "empty world query returns 0")
end)

-- ============================================================================
-- PERFORMANCE BENCHMARKS
-- ============================================================================

print("\n=== Performance Benchmarks ===\n")

test("benchmark: entity creation", function()
    local count = 10000
    local start = os.clock()
    
    for i = 1, count do
        ecs.entity("pos", {x=0, y=0}, "vel", {x=1, y=1})
    end
    
    local elapsed = os.clock() - start
    print(string.format("  create %d entities: %.3fs (%.0f/sec)", 
        count, elapsed, count / elapsed))
end)

test("benchmark: query iteration", function()
    local count = 20000
    -- setup
    for i = 1, count do
        ecs.entity("pos", {x=i, y=i}, "vel", {x=1, y=1})
    end
    -- force cache build
    ecs.query():with("pos", "vel"):count()
    
    local start = os.clock()
    local sum_x = 0
    
    ecs.query():with("pos", "vel"):each(function(e, pos, vel)
        sum_x = sum_x + pos.x + vel.x
    end)
    
    local elapsed = os.clock() - start
    print(string.format("  iterate %d entities (2 comps): %.3fs (%.0f/sec)", 
        count, elapsed, count / elapsed))
end)

test("benchmark: archetype transitions (add/remove)", function()
    local count = 10000
    local entities = {}
    for i = 1, count do
        entities[i] = ecs.entity("A", 1)
    end
    
    local start = os.clock()
    
    -- add component B (Transition A -> AB)
    for i = 1, count do
        entities[i]:add("B", 2)
    end
    
    -- remove component A (Transition AB -> B)
    for i = 1, count do
        entities[i]:remove("A")
    end
    
    local elapsed = os.clock() - start
    print(string.format("  %d add/remove cycles: %.3fs (%.0f ops/sec)", 
        count, elapsed, (count * 2) / elapsed))
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
        print("    Error: " .. tostring(failure.error))
    end
    os.exit(1)
else
    print("\n✓ All tests passed!")
    os.exit(0)
end