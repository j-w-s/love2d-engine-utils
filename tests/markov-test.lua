local markov = require("markov")

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
-- tests
-- ============================================================================

print("\n=== Markov Chain Test Suite ===\n")

-- basic chain creation
test("new: creates first-order chain", function()
    local chain = markov.new(1)
    assert_not_nil(chain, "chain should exist")
    assert_eq(chain.order, 1, "order should be 1")
    assert_eq(chain.total_observations, 0, "should have no observations")
end)

test("new: creates higher-order chain", function()
    local chain = markov.new(3)
    assert_eq(chain.order, 3, "order should be 3")
end)

test("new: defaults to first-order", function()
    local chain = markov.new()
    assert_eq(chain.order, 1, "default order should be 1")
end)

test("new: case sensitivity flag", function()
    local chain_sensitive = markov.new(1, true)
    local chain_insensitive = markov.new(1, false)
    assert_true(chain_sensitive.case_sensitive, "should be case sensitive")
    assert_false(chain_insensitive.case_sensitive, "should be case insensitive")
end)

-- sequence addition
test("add_sequence: adds simple sequence", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C"})
    local stats = chain:stats()
    assert_true(stats.states > 0, "should have states")
    assert_true(stats.transitions > 0, "should have transitions")
end)

test("add_sequence: empty sequence handling", function()
    local chain = markov.new(1)
    chain:add_sequence({})
    local stats = chain:stats()
    assert_eq(stats.states, 0, "should have no states")
end)

test("add_sequence: nil sequence handling", function()
    local chain = markov.new(1)
    chain:add_sequence(nil)
    -- should not error
    local stats = chain:stats()
    assert_eq(stats.states, 0, "should have no states")
end)

test("add_sequence: higher-order chain", function()
    local chain = markov.new(2)
    chain:add_sequence({"A", "B", "C", "D"})
    local stats = chain:stats()
    assert_true(stats.states > 0, "should have states")
end)

test("add_sequence: multiple sequences", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B"})
    chain:add_sequence({"B", "C"})
    local stats = chain:stats()
    assert_true(stats.total_observations >= 4, "should have multiple observations")
end)

-- transition addition
test("add_transition: adds single transition", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B")
    local probs = chain:get_probabilities("A")
    assert_not_nil(probs, "should have probabilities")
    assert_not_nil(probs["B"], "should transition to B")
end)

test("add_transition: adds multiple observations", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 5)
    chain:add_transition("A", "C", 3)
    local probs = chain:get_probabilities("A")
    assert_near(probs["B"], 5/8, 0.01, "B probability")
    assert_near(probs["C"], 3/8, 0.01, "C probability")
end)

test("add_transition: higher-order with table state", function()
    local chain = markov.new(2)
    chain:add_transition({"A", "B"}, "C")
    local probs = chain:get_probabilities({"A", "B"})
    assert_not_nil(probs, "should have probabilities")
    assert_not_nil(probs["C"], "should transition to C")
end)

test("add_transition: higher-order with string state", function()
    local chain = markov.new(2)
    chain:add_transition("A", "B")
    -- should automatically pad with start tokens
    local stats = chain:stats()
    assert_true(stats.transitions > 0, "should have transitions")
end)

-- probability queries
test("get_probabilities: returns normalized probabilities", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 3)
    chain:add_transition("A", "C", 1)
    local probs = chain:get_probabilities("A")
    assert_near(probs["B"], 0.75, 0.01, "B probability")
    assert_near(probs["C"], 0.25, 0.01, "C probability")
end)

test("get_probabilities: unknown state returns nil", function()
    local chain = markov.new(1)
    local probs = chain:get_probabilities("unknown")
    assert_nil(probs, "unknown state should return nil")
end)

test("get_probabilities: caches results", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B")
    chain.cache_valid = true
    local probs1 = chain:get_probabilities("A")
    local probs2 = chain:get_probabilities("A")
    -- both calls should work
    assert_not_nil(probs1, "first call")
    assert_not_nil(probs2, "second call")
end)

-- prediction
test("predict: returns next state", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 10)
    local next_state = chain:predict("A")
    assert_eq(next_state, "B", "should predict B")
end)

test("predict: deterministic mode", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 10)
    chain:add_transition("A", "C", 5)
    local next_state = chain:predict("A", true)
    assert_eq(next_state, "B", "should predict most likely state")
end)

test("predict: probabilistic mode", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 1)
    chain:add_transition("A", "C", 1)
    local next_state = chain:predict("A", false)
    assert_true(next_state == "B" or next_state == "C", "should predict B or C")
end)

test("predict: unknown state returns nil", function()
    local chain = markov.new(1)
    local next_state = chain:predict("unknown")
    assert_nil(next_state, "unknown state should return nil")
end)

-- generation
test("generate: produces sequence", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C", "D"})
    local sequence = chain:generate(10)
    assert_not_nil(sequence, "should generate sequence")
    assert_true(#sequence > 0, "sequence should not be empty")
end)

test("generate: respects max length", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C", "D"})
    local sequence = chain:generate(5)
    assert_true(#sequence <= 5, "should respect max length")
end)

test("generate: with start state", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C", "D"})
    local sequence = chain:generate(5, "B")
    assert_not_nil(sequence, "should generate from start state")
end)

test("generate: with temperature", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 10)
    chain:add_transition("A", "C", 1)
    -- high temperature = more random
    local sequence = chain:generate(10, "A", 2.0)
    assert_not_nil(sequence, "should generate with temperature")
end)

test("generate: empty chain returns empty sequence", function()
    local chain = markov.new(1)
    local sequence = chain:generate(10)
    assert_eq(#sequence, 0, "empty chain should return empty sequence")
end)

-- walking
test("walk: walks n steps", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C", "D"})
    local path = chain:walk("A", 3)
    assert_not_nil(path, "should walk chain")
    assert_true(#path > 0, "path should not be empty")
end)

test("walk: stops at dead end", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B")
    -- B has no transitions
    local path = chain:walk("A", 10)
    assert_true(#path < 10, "should stop at dead end")
end)

-- merging
test("merge: combines two chains", function()
    local chain1 = markov.new(1)
    chain1:add_transition("A", "B", 5)
    
    local chain2 = markov.new(1)
    chain2:add_transition("A", "B", 3)
    chain2:add_transition("A", "C", 2)
    
    chain1:merge(chain2)
    
    local probs = chain1:get_probabilities("A")
    assert_near(probs["B"], 8/10, 0.01, "merged B probability")
    assert_near(probs["C"], 2/10, 0.01, "merged C probability")
end)

test("merge: with weight", function()
    local chain1 = markov.new(1)
    chain1:add_transition("A", "B", 5)
    
    local chain2 = markov.new(1)
    chain2:add_transition("A", "C", 10)
    
    chain1:merge(chain2, 0.5)
    
    local probs = chain1:get_probabilities("A")
    assert_near(probs["B"], 5/10, 0.01, "weighted B probability")
    assert_near(probs["C"], 5/10, 0.01, "weighted C probability")
end)

test("merge: mismatched orders error", function()
    local chain1 = markov.new(1)
    local chain2 = markov.new(2)
    
    local success = pcall(function()
        chain1:merge(chain2)
    end)
    
    assert_false(success, "should error on mismatched orders")
end)

-- serialization
test("serialize: produces table", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C"})
    local data = chain:serialize()
    assert_not_nil(data, "should serialize")
    assert_eq(data.order, 1, "order preserved")
    assert_not_nil(data.transitions, "transitions preserved")
end)

test("deserialize: recreates chain", function()
    local chain1 = markov.new(1)
    chain1:add_transition("A", "B", 5)
    
    local data = chain1:serialize()
    local chain2 = markov.deserialize(data)
    
    assert_eq(chain2.order, 1, "order preserved")
    local probs = chain2:get_probabilities("A")
    assert_not_nil(probs["B"], "transitions preserved")
end)

-- statistics
test("stats: returns chain statistics", function()
    local chain = markov.new(2)
    chain:add_sequence({"A", "B", "C", "D"})
    local stats = chain:stats()
    assert_not_nil(stats.states, "has states")
    assert_not_nil(stats.transitions, "has transitions")
    assert_not_nil(stats.total_observations, "has observations")
    assert_eq(stats.order, 2, "order preserved")
end)

test("stats: empty chain", function()
    local chain = markov.new(1)
    local stats = chain:stats()
    assert_eq(stats.states, 0, "no states")
    assert_eq(stats.transitions, 0, "no transitions")
    assert_eq(stats.total_observations, 0, "no observations")
end)

-- clearing
test("clear: removes all data", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C"})
    chain:clear()
    local stats = chain:stats()
    assert_eq(stats.states, 0, "states cleared")
    assert_eq(stats.total_observations, 0, "observations cleared")
end)

-- text generation
test("from_text: creates chain from text", function()
    local text = "The cat sat on the mat. The dog ran in the park."
    local chain = markov.from_text(text, 2, true)
    assert_not_nil(chain, "chain created")
    local stats = chain:stats()
    assert_true(stats.states > 0, "has states")
end)

test("from_text: character-based", function()
    local text = "hello world"
    local chain = markov.from_text(text, 2, false)
    local stats = chain:stats()
    assert_true(stats.states > 0, "has states")
end)

test("generate_text: produces text", function()
    local text = "The cat sat on the mat. The dog ran."
    local chain = markov.from_text(text, 1, true)
    local generated = markov.generate_text(chain, 20)
    assert_not_nil(generated, "text generated")
    assert_true(#generated > 0, "text not empty")
end)

-- discrete state chains
test("discrete: creates uniform chain", function()
    local states = {"sunny", "rainy", "cloudy"}
    local chain = markov.discrete(states)
    local probs = chain:get_probabilities("sunny")
    assert_not_nil(probs, "has probabilities")
    assert_not_nil(probs["sunny"], "can stay sunny")
    assert_not_nil(probs["rainy"], "can become rainy")
    assert_not_nil(probs["cloudy"], "can become cloudy")
end)

test("train_discrete: learns from sequence", function()
    local sequence = {"sunny", "sunny", "rainy", "rainy", "sunny"}
    local chain = markov.train_discrete(sequence, 1)
    local stats = chain:stats()
    assert_true(stats.states > 0, "learned states")
end)

-- weather simulation example
test("weather: simple weather model", function()
    local chain = markov.new(1)
    
    -- sunny -> sunny (90%), rainy (10%)
    chain:add_transition("sunny", "sunny", 9)
    chain:add_transition("sunny", "rainy", 1)
    
    -- rainy -> rainy (50%), sunny (50%)
    chain:add_transition("rainy", "rainy", 5)
    chain:add_transition("rainy", "sunny", 5)
    
    -- simulate 10 days
    local forecast = chain:walk("sunny", 10)
    assert_eq(#forecast, 10, "10 day forecast")
    
    -- verify all states are valid
    for i = 1, #forecast do
        assert_true(forecast[i] == "sunny" or forecast[i] == "rainy", "valid weather state")
    end
end)

-- edge cases
test("edge: single state chain", function()
    local chain = markov.new(1)
    chain:add_transition("A", "A", 10)
    local sequence = chain:generate(5, "A")
    -- should generate all A's
    for i = 1, #sequence do
        assert_eq(sequence[i], "A", "should be A")
    end
end)

test("edge: cyclic chain", function()
    local chain = markov.new(1)
    chain:add_transition("A", "B", 10)
    chain:add_transition("B", "C", 10)
    chain:add_transition("C", "A", 10)
    local sequence = chain:generate(12, "A")
    assert_true(#sequence > 0, "should generate cyclic sequence")
end)

test("edge: long sequence", function()
    local chain = markov.new(1)
    local long_seq = {}
    for i = 1, 1000 do
        long_seq[i] = "token" .. (i % 10)
    end
    chain:add_sequence(long_seq)
    local stats = chain:stats()
    assert_true(stats.total_observations >= 1000, "handles long sequences")
end)

test("edge: very high order", function()
    local chain = markov.new(10)
    chain:add_sequence({"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"})
    local stats = chain:stats()
    assert_true(stats.states > 0, "handles high order")
end)

test("edge: special characters in tokens", function()
    local chain = markov.new(1)
    chain:add_transition("hello world", "foo-bar")
    chain:add_transition("foo-bar", "baz_qux")
    local next_state = chain:predict("hello world")
    assert_eq(next_state, "foo-bar", "handles special characters")
end)

test("edge: numeric tokens", function()
    local chain = markov.new(1)
    chain:add_sequence({1, 2, 3, 4})
    local sequence = chain:generate(5, 1)
    assert_not_nil(sequence, "handles numeric tokens")
end)

test("edge: case sensitivity", function()
    local chain_sensitive = markov.new(1, true)
    chain_sensitive:add_transition("A", "B")
    chain_sensitive:add_transition("a", "C")
    
    local next1 = chain_sensitive:predict("A")
    local next2 = chain_sensitive:predict("a")
    assert_eq(next1, "B", "uppercase A")
    assert_eq(next2, "C", "lowercase a")
    
    local chain_insensitive = markov.new(1, false)
    chain_insensitive:add_transition("A", "B")
    chain_insensitive:add_transition("a", "C")
    
    -- case insensitive chains normalize to lowercase, so we need to query with lowercase
    local probs = chain_insensitive:get_probabilities("a")
    assert_not_nil(probs, "should have probabilities")
    -- both "B" and "C" should be present since "A" and "a" map to same state
    local has_transitions = (probs["b"] or probs["B"] or probs["c"] or probs["C"])
    assert_not_nil(has_transitions, "has transitions")
end)

-- stress tests
test("stress: 1000 states", function()
    local chain = markov.new(1)
    for i = 1, 1000 do
        chain:add_transition("state" .. i, "state" .. ((i % 1000) + 1))
    end
    local stats = chain:stats()
    assert_eq(stats.states, 1000, "handles 1000 states")
end)

test("stress: many sequences", function()
    local chain = markov.new(2)
    for i = 1, 100 do
        local seq = {}
        for j = 1, 10 do
            seq[j] = "token" .. math.random(1, 20)
        end
        chain:add_sequence(seq)
    end
    local stats = chain:stats()
    assert_true(stats.total_observations >= 900, "handles many sequences")
end)

test("stress: generate long sequence", function()
    local chain = markov.new(1)
    chain:add_sequence({"A", "B", "C", "D", "E"})
    local sequence = chain:generate(1000)
    -- should either generate 1000 or stop at end state
    assert_true(#sequence <= 1000, "respects max length")
end)

-- benchmark tests
test("benchmark: sequence addition", function()
    local chain = markov.new(2)
    local start = os.clock()
    
    for i = 1, 1000 do
        local seq = {}
        for j = 1, 10 do
            seq[j] = "token" .. (j % 5)
        end
        chain:add_sequence(seq)
    end
    
    local elapsed = os.clock() - start
    print(string.format("  1000 sequences in %.3fs", elapsed))
    assert_true(elapsed < 5.0, "should be reasonably fast")
end)

test("benchmark: prediction", function()
    local chain = markov.new(1)
    for i = 1, 100 do
        chain:add_transition("state" .. (i % 10), "state" .. ((i + 1) % 10))
    end
    
    local start = os.clock()
    for i = 1, 10000 do
        chain:predict("state" .. (i % 10))
    end
    local elapsed = os.clock() - start
    
    print(string.format("  10000 predictions in %.3fs (%.1f pred/sec)", 
        elapsed, 10000/elapsed))
    assert_true(elapsed < 1.0, "predictions should be fast")
end)

test("benchmark: text generation", function()
    local text = string.rep("The quick brown fox jumps over the lazy dog. ", 100)
    local chain = markov.from_text(text, 2, true)
    
    local start = os.clock()
    for i = 1, 100 do
        markov.generate_text(chain, 50)
    end
    local elapsed = os.clock() - start
    
    print(string.format("  100 text generations in %.3fs (%.1f gen/sec)", 
        elapsed, 100/elapsed))
end)

-- practical examples
test("example: weather forecast", function()
    local chain = markov.new(1)
    
    -- historical weather patterns
    local history = {"sunny", "sunny", "sunny", "cloudy", "rainy", 
                     "rainy", "cloudy", "sunny", "sunny", "sunny",
                     "sunny", "cloudy", "cloudy", "rainy", "sunny"}
    
    chain:add_sequence(history)
    
    -- predict next 7 days starting from sunny
    local forecast = chain:walk("sunny", 7)
    assert_eq(#forecast, 7, "7 day forecast")
end)

test("example: text generation from corpus", function()
    local corpus = [[
        The cat sat on the mat. The dog ran in the park.
        The bird flew over the tree. The cat chased the bird.
        The dog barked at the cat.
    ]]
    
    local chain = markov.from_text(corpus, 2, true)
    local generated = markov.generate_text(chain, 15)
    
    assert_not_nil(generated, "generated text")
    assert_true(#generated > 0, "text not empty")
end)

test("example: state machine transitions", function()
    local chain = markov.new(1)
    
    -- game state transitions
    chain:add_transition("menu", "playing", 10)
    chain:add_transition("playing", "paused", 2)
    chain:add_transition("playing", "game_over", 1)
    chain:add_transition("paused", "playing", 10)
    chain:add_transition("game_over", "menu", 10)
    
    -- simulate game session
    local session = chain:walk("menu", 20)
    assert_true(#session > 0, "simulated session")
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
    end
    os.exit(1)
else
    print("\n✓ All tests passed!")
    os.exit(0)
end