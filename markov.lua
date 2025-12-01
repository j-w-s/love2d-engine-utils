--- markov chain library for luajit/lua 5.3+
-- supports first-order and higher-order chains, text generation, state prediction
-- ideal for weather systems, procedural generation, ai behavior, text synthesis
-- optimized with ieee 754 hex floats, local caching, minimal allocations
-- @module markov

local markov = {}

local math_random = math.random
local math_floor = math.floor
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local string_format = string.format
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local tonumber = tonumber

-- pre-load table.new if available (luajit)
local table_new
local ok, new_mod = pcall(require, "table.new")
if ok then table_new = new_mod end

-- json serialization (optional dependency)
local json_encode, json_decode
local json_ok, json_mod = pcall(require, "json")
if json_ok then
    json_encode = json_mod.encode
    json_decode = json_mod.decode
end

-- ============================================================================
-- constants (ieee 754 hex floats for exact binary representation)
-- ============================================================================

local ZERO = 0x0p0
local ONE = 0x1p0
local EPSILON = 0x1.0c6f7a0b5ed8dp-10  -- 0.001

-- sentinel tokens for sequence boundaries
local START_TOKEN = "<START>"
local END_TOKEN = "<END>"

-- ============================================================================
-- utility functions
-- ============================================================================

--- create a state key from an array of tokens
--- @param tokens table array of tokens
--- @param order number chain order
--- @return string concatenated key
local function make_key(tokens, order)
    if order == 1 then
        return tostring(tokens[1])
    end
    
    -- concatenate with separator for multi-token keys
    local parts = table_new and table_new(order, 0) or {}
    for i = 1, order do
        parts[i] = tostring(tokens[i] or START_TOKEN)
    end
    return table_concat(parts, "\x1f") -- unit separator
end

--- split a key back into tokens
--- @param key string concatenated key
--- @param order number chain order
--- @return table array of tokens
local function split_key(key, order)
    if order == 1 then
        return {key}
    end
    
    local tokens = {}
    for token in key:gmatch("[^\x1f]+") do
        table_insert(tokens, token)
    end
    return tokens
end

--- weighted random selection from a list of choices
--- @param choices table {value, weight} pairs
--- @return any selected value
local function weighted_choice(choices)
    if #choices == 0 then return nil end
    if #choices == 1 then return choices[1][1] end
    
    -- calculate total weight
    local total_weight = ZERO
    for i = 1, #choices do
        total_weight = total_weight + choices[i][2]
    end
    
    if total_weight <= EPSILON then
        -- fallback to uniform random if all weights are zero
        return choices[math_random(1, #choices)][1]
    end
    
    -- select weighted random
    local target = math_random() * total_weight
    local cumulative = ZERO
    
    for i = 1, #choices do
        cumulative = cumulative + choices[i][2]
        if cumulative >= target then
            return choices[i][1]
        end
    end
    
    -- fallback (should never reach here)
    return choices[#choices][1]
end

--- normalize weights in a transition table
--- @param transitions table {state -> weight} map
--- @return table normalized {state -> probability} map
local function normalize_weights(transitions)
    local total = ZERO
    for _, weight in pairs(transitions) do
        total = total + weight
    end
    
    if total <= EPSILON then
        return transitions
    end
    
    local normalized = {}
    for state, weight in pairs(transitions) do
        normalized[state] = weight / total
    end
    
    return normalized
end

-- ============================================================================
-- markov chain class
-- ============================================================================

local Chain = {}
Chain.__index = Chain

--- create a new markov chain
--- @param order number order of the chain (default 1)
--- @param case_sensitive boolean preserve case in tokens (default true)
--- @return table chain instance
function markov.new(order, case_sensitive)
    order = order or 1
    case_sensitive = case_sensitive ~= false
    
    local self = setmetatable({}, Chain)
    
    -- chain configuration
    self.order = order
    self.case_sensitive = case_sensitive
    
    -- transition matrix: { state_key -> { next_state -> count } }
    self.transitions = {}
    
    -- starting states: { state_key -> count }
    self.starts = {}
    
    -- ending states: { state_key -> count }
    self.ends = {}
    
    -- total observations
    self.total_observations = 0
    
    -- cache for normalized probabilities (invalidated on update)
    self.prob_cache = {}
    self.cache_valid = false
    
    return self
end

--- normalize a token (case handling)
--- @param token string token to normalize
--- @return string normalized token
function Chain:normalize(token)
    if not self.case_sensitive and type(token) == "string" then
        return token:lower()
    end
    return token
end

--- add a sequence of observations to the chain
--- @param sequence table array of tokens
function Chain:add_sequence(sequence)
    if not sequence or #sequence == 0 then return end
    
    -- invalidate probability cache
    self.cache_valid = false
    
    local order = self.order
    
    -- create a sliding window buffer with start tokens
    local window = table_new and table_new(order, 0) or {}
    for i = 1, order do
        window[i] = START_TOKEN
    end
    
    -- mark start state
    local start_key = make_key(window, order)
    self.starts[start_key] = (self.starts[start_key] or 0) + 1
    
    -- process sequence
    for i = 1, #sequence do
        local token = self:normalize(sequence[i])
        
        -- get current state key
        local state_key = make_key(window, order)
        
        -- update transition counts
        if not self.transitions[state_key] then
            self.transitions[state_key] = {}
        end
        self.transitions[state_key][token] = (self.transitions[state_key][token] or 0) + 1
        
        -- slide window
        for j = 1, order - 1 do
            window[j] = window[j + 1]
        end
        window[order] = token
        
        self.total_observations = self.total_observations + 1
    end
    
    -- mark end state
    local end_key = make_key(window, order)
    self.ends[end_key] = (self.ends[end_key] or 0) + 1
end

--- add multiple observations of a single transition
--- @param from_state string or table current state
--- @param to_state string next state
--- @param count number number of observations (default 1)
function Chain:add_transition(from_state, to_state, count)
    count = count or 1
    self.cache_valid = false
    
    -- convert from_state to array if needed
    local state_tokens
    if type(from_state) == "table" then
        state_tokens = {}
        for i = 1, #from_state do
            state_tokens[i] = self:normalize(from_state[i])
        end
    else
        state_tokens = {self:normalize(from_state)}
    end
    
    -- ensure state_tokens matches order
    while #state_tokens < self.order do
        table_insert(state_tokens, 1, START_TOKEN)
    end
    
    local state_key = make_key(state_tokens, self.order)
    to_state = self:normalize(to_state)
    
    if not self.transitions[state_key] then
        self.transitions[state_key] = {}
    end
    
    self.transitions[state_key][to_state] = (self.transitions[state_key][to_state] or 0) + count
    self.total_observations = self.total_observations + count
end

--- get normalized transition probabilities for a state
--- @param state string or table current state
--- @return table {next_state -> probability} map, or nil if state unknown
function Chain:get_probabilities(state)
    local state_tokens
    if type(state) == "table" then
        state_tokens = state
    else
        state_tokens = {state}
    end
    
    while #state_tokens < self.order do
        table_insert(state_tokens, 1, START_TOKEN)
    end
    
    local state_key = make_key(state_tokens, self.order)
    
    -- check cache
    if self.cache_valid and self.prob_cache[state_key] then
        return self.prob_cache[state_key]
    end
    
    local transitions = self.transitions[state_key]
    if not transitions then
        return nil
    end
    
    -- normalize and cache
    local probs = normalize_weights(transitions)
    self.prob_cache[state_key] = probs
    
    return probs
end

--- predict the next state given current state
--- @param state string or table current state
--- @param deterministic boolean if true, return most likely state (default false)
--- @return string next state, or nil if no transitions exist
function Chain:predict(state, deterministic)
    local state_tokens
    if type(state) == "table" then
        state_tokens = state
    else
        state_tokens = {state}
    end
    
    while #state_tokens < self.order do
        table_insert(state_tokens, 1, START_TOKEN)
    end
    
    local state_key = make_key(state_tokens, self.order)
    local transitions = self.transitions[state_key]
    
    if not transitions then
        return nil
    end
    
    if deterministic then
        -- return state with highest count
        local max_count = -1
        local max_state = nil
        
        for next_state, count in pairs(transitions) do
            if count > max_count then
                max_count = count
                max_state = next_state
            end
        end
        
        return max_state
    else
        -- weighted random selection
        local choices = table_new and table_new(16, 0) or {}
        for next_state, count in pairs(transitions) do
            table_insert(choices, {next_state, count})
        end
        
        return weighted_choice(choices)
    end
end

--- generate a sequence from the chain
--- @param max_length number maximum sequence length (default 100)
--- @param start_state string or table initial state (default: random start)
--- @param temperature number randomness factor (default 1.0)
--- @return table array of generated tokens
function Chain:generate(max_length, start_state, temperature)
    max_length = max_length or 100
    temperature = temperature or ONE
    
    local sequence = table_new and table_new(max_length, 0) or {}
    local count = 0
    
    -- initialize state
    local state
    if start_state then
        if type(start_state) == "table" then
            state = {}
            for i = 1, #start_state do
                state[i] = start_state[i]
            end
        else
            state = {start_state}
        end
    else
        -- pick random start state
        local start_choices = table_new and table_new(16, 0) or {}
        for start_key, start_count in pairs(self.starts) do
            local tokens = split_key(start_key, self.order)
            table_insert(start_choices, {tokens, start_count})
        end
        
        if #start_choices == 0 then
            return sequence
        end
        
        state = weighted_choice(start_choices)
    end
    
    -- ensure state has correct order
    while #state < self.order do
        table_insert(state, 1, START_TOKEN)
    end
    
    -- remove start tokens from output
    for i = 1, self.order do
        if state[i] ~= START_TOKEN then
            count = count + 1
            sequence[count] = state[i]
        end
    end
    
    -- generate sequence
    for i = 1, max_length do
        local state_key = make_key(state, self.order)
        local transitions = self.transitions[state_key]
        
        if not transitions then
            break
        end
        
        -- check if this is an end state
        if self.ends[state_key] and math_random() < 0x1p-3 then -- 0.125 probability of ending
            break
        end
        
        -- apply temperature to weights
        local choices = table_new and table_new(16, 0) or {}
        for next_token, weight in pairs(transitions) do
            local adjusted_weight = weight ^ (ONE / temperature)
            table_insert(choices, {next_token, adjusted_weight})
        end
        
        local next_token = weighted_choice(choices)
        if not next_token then
            break
        end
        
        count = count + 1
        sequence[count] = next_token
        
        -- slide state window
        for j = 1, self.order - 1 do
            state[j] = state[j + 1]
        end
        state[self.order] = next_token
    end
    
    return sequence
end

--- walk the chain for n steps
--- @param start_state string or table initial state
--- @param steps number number of steps to take
--- @return table array of visited states
function Chain:walk(start_state, steps)
    steps = steps or 10
    
    local path = table_new and table_new(steps, 0) or {}
    local state
    
    if type(start_state) == "table" then
        state = {}
        for i = 1, #start_state do
            state[i] = start_state[i]
        end
    else
        state = {start_state}
    end
    
    while #state < self.order do
        table_insert(state, 1, START_TOKEN)
    end
    
    for i = 1, steps do
        local next_state = self:predict(state)
        if not next_state then
            break
        end
        
        table_insert(path, next_state)
        
        -- update state
        for j = 1, self.order - 1 do
            state[j] = state[j + 1]
        end
        state[self.order] = next_state
    end
    
    return path
end

--- get the stationary distribution (steady-state probabilities)
-- iterative power method (for small chains only)
--- @param max_iterations number maximum iterations (default 1000)
--- @param tolerance number convergence tolerance (default 0.0001)
--- @return table {state -> probability} map
function Chain:stationary_distribution(max_iterations, tolerance)
    max_iterations = max_iterations or 1000
    tolerance = tolerance or 0x1.a36e2eb1c432dp-14 -- 0.0001
    
    -- collect all states
    local states = {}
    local state_count = 0
    for state_key in pairs(self.transitions) do
        state_count = state_count + 1
        states[state_count] = state_key
    end
    
    if state_count == 0 then
        return {}
    end
    
    -- initialize uniform distribution
    local dist = {}
    local uniform_prob = ONE / state_count
    for i = 1, state_count do
        dist[states[i]] = uniform_prob
    end
    
    -- power iteration
    for iter = 1, max_iterations do
        local new_dist = {}
        local max_change = ZERO
        
        for i = 1, state_count do
            local state_key = states[i]
            local prob = ZERO
            
            -- sum incoming probabilities
            for j = 1, state_count do
                local from_key = states[j]
                local from_prob = dist[from_key]
                local trans = self.transitions[from_key]
                
                if trans then
                    local trans_probs = normalize_weights(trans)
                    local tokens = split_key(state_key, self.order)
                    local to_token = tokens[self.order]
                    prob = prob + from_prob * (trans_probs[to_token] or ZERO)
                end
            end
            
            new_dist[state_key] = prob
            
            local change = math.abs(prob - dist[state_key])
            if change > max_change then
                max_change = change
            end
        end
        
        dist = new_dist
        
        -- check convergence
        if max_change < tolerance then
            break
        end
    end
    
    return dist
end

--- merge another chain into this one
--- @param other table another chain instance
--- @param weight number weight for other chain (default 1.0)
function Chain:merge(other, weight)
    if self.order ~= other.order then
        error("cannot merge chains with different orders")
    end
    
    weight = weight or ONE
    self.cache_valid = false
    
    -- merge transitions
    for state_key, transitions in pairs(other.transitions) do
        if not self.transitions[state_key] then
            self.transitions[state_key] = {}
        end
        
        for next_state, count in pairs(transitions) do
            local weighted_count = count * weight
            self.transitions[state_key][next_state] = 
                (self.transitions[state_key][next_state] or 0) + weighted_count
        end
    end
    
    -- merge starts
    for start_key, count in pairs(other.starts) do
        self.starts[start_key] = (self.starts[start_key] or 0) + count * weight
    end
    
    -- merge ends
    for end_key, count in pairs(other.ends) do
        self.ends[end_key] = (self.ends[end_key] or 0) + count * weight
    end
    
    self.total_observations = self.total_observations + other.total_observations * weight
end

--- serialize chain to table (for json/msgpack)
--- @return table serializable representation
function Chain:serialize()
    return {
        order = self.order,
        case_sensitive = self.case_sensitive,
        transitions = self.transitions,
        starts = self.starts,
        ends = self.ends,
        total_observations = self.total_observations,
    }
end

--- deserialize chain from table
--- @param data table serialized representation
--- @return table chain instance
function markov.deserialize(data)
    local chain = markov.new(data.order, data.case_sensitive)
    chain.transitions = data.transitions or {}
    chain.starts = data.starts or {}
    chain.ends = data.ends or {}
    chain.total_observations = data.total_observations or 0
    chain.cache_valid = false
    return chain
end

--- save chain to json string (requires json library)
--- @return string json representation
function Chain:to_json()
    if not json_encode then
        error("json library not available")
    end
    return json_encode(self:serialize())
end

--- load chain from json string (requires json library)
--- @param json_str string json representation
--- @return table chain instance
function markov.from_json(json_str)
    if not json_decode then
        error("json library not available")
    end
    local data = json_decode(json_str)
    return markov.deserialize(data)
end

--- get statistics about the chain
--- @return table {states, transitions, total_observations}
function Chain:stats()
    local state_count = 0
    local transition_count = 0
    
    for state_key, transitions in pairs(self.transitions) do
        state_count = state_count + 1
        for _ in pairs(transitions) do
            transition_count = transition_count + 1
        end
    end
    
    return {
        states = state_count,
        transitions = transition_count,
        total_observations = self.total_observations,
        order = self.order,
    }
end

--- clear all data from the chain
function Chain:clear()
    self.transitions = {}
    self.starts = {}
    self.ends = {}
    self.total_observations = 0
    self.prob_cache = {}
    self.cache_valid = false
end

-- ============================================================================
-- text generation utilities
-- ============================================================================

--- create a chain from text corpus
--- @param text string input text
--- @param order number chain order (default 2)
--- @param word_based boolean use words instead of characters (default true)
--- @return table chain instance
function markov.from_text(text, order, word_based)
    order = order or 2
    word_based = word_based ~= false
    
    local chain = markov.new(order, true)
    
    if word_based then
        -- split into sentences
        for sentence in text:gmatch("[^.!?]+[.!?]?") do
            local words = {}
            for word in sentence:gmatch("%S+") do
                table_insert(words, word)
            end
            
            if #words > 0 then
                chain:add_sequence(words)
            end
        end
    else
        -- character-based
        local chars = {}
        for i = 1, #text do
            chars[i] = text:sub(i, i)
        end
        chain:add_sequence(chars)
    end
    
    return chain
end

--- generate text from a chain
--- @param chain table chain instance
--- @param max_words number maximum words/characters (default 100)
--- @param temperature number randomness (default 1.0)
--- @return string generated text
function markov.generate_text(chain, max_words, temperature)
    local sequence = chain:generate(max_words, nil, temperature)
    return table_concat(sequence, " ")
end

-- ============================================================================
-- state-based utilities (for weather, game states, etc.)
-- ============================================================================

--- create a simple discrete state chain
--- @param states table array of state names
--- @return table chain instance
function markov.discrete(states)
    local chain = markov.new(1, true)
    
    -- initialize with equal probabilities
    for i = 1, #states do
        for j = 1, #states do
            chain:add_transition(states[i], states[j], 1)
        end
    end
    
    return chain
end

--- train a chain on a sequence of discrete states
--- @param sequence table array of states
--- @param order number chain order (default 1)
--- @return table trained chain
function markov.train_discrete(sequence, order)
    order = order or 1
    local chain = markov.new(order, true)
    chain:add_sequence(sequence)
    return chain
end

-- ============================================================================
-- public api
-- ============================================================================

return markov