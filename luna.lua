--- query library.
-- a high-performance, lazy iterator library inspired by linq and rust.
-- **attempted** lua-native zero-cost abstractions with fusion optimization and early termination.
-- @module luna

local setmetatable = setmetatable
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local next = next
local table_sort = table.sort
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local tostring = tostring
local unpack = unpack or table.unpack
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local t_move = table.move
local coroutine_create = coroutine.create
local coroutine_resume = coroutine.resume
local coroutine_yield = coroutine.yield
local coroutine_status = coroutine.status

-- pre-load table.new if available
local table_new
local ok, new_mod = pcall(require, "table.new")
if ok then table_new = new_mod end

-- nil sentinel for distinct operations (nil cannot be table key)
local NIL_SENTINEL = {}

-- ============================================================================
-- operation type codes
-- ============================================================================
local OP_WHERE, OP_SELECT, OP_TAKE, OP_SKIP = 1, 2, 3, 4
local OP_DISTINCT, OP_SCAN, OP_ZIP, OP_LAG = 5, 6, 7, 8
local OP_FIND, OP_BETWEEN, OP_UNION, OP_INTERSECTION = 9, 10, 11, 12
local OP_COMPLEMENT, OP_INTERSPERSE, OP_EFFECT, OP_REVERSE = 13, 14, 15, 16
local OP_ORDER, OP_GROUP, OP_JOIN, OP_LJOIN = 17, 18, 19, 20
local OP_RJOIN, OP_CROSS, OP_WINDOW, OP_FLATTEN = 21, 22, 23, 24
local OP_UNZIP, OP_MEMOIZE, OP_PARALLEL_MAP, OP_CHUNK = 25, 26, 27, 28

-- source type codes for monomorphic dispatch
local SRC_TABLE, SRC_RANGE, SRC_REPEAT, SRC_UNFOLD, SRC_STRING = 1, 2, 3, 4, 5

-- operations requiring materialization
local NEEDS_MATERIALIZE = {
    [OP_REVERSE] = true,
    [OP_ORDER] = true,
    [OP_GROUP] = true,
    [OP_JOIN] = true,
    [OP_LJOIN] = true,
    [OP_RJOIN] = true,
    [OP_CROSS] = true,
    [OP_WINDOW] = true,
    [OP_FLATTEN] = true,
    [OP_UNZIP] = true,
    [OP_CHUNK] = true,
    [OP_PARALLEL_MAP] = true
}

-- ============================================================================
-- memoization cache
-- ============================================================================
local memo_cache = {}
setmetatable(memo_cache, { __mode = "k" }) -- weak keys for gc

--- create memoized predicate
--- @param predicate function predicate to memoize
--- @return function memoized predicate
local function memoize_predicate(predicate)
    local cache = {}
    setmetatable(cache, { __mode = "kv" }) -- weak cache

    return function(value)
        local cached = cache[value]
        if cached ~= nil then
            return cached
        end
        local result = predicate(value)
        cache[value] = result
        return result
    end
end

-- ============================================================================
-- utility functions
-- ============================================================================

--- count array elements including nils
--- @param t table array to count
--- @return integer actual element count
local function array_count(t)
    if not t then return 0 end
    local max_idx = 0
    for k in pairs(t) do
        if type(k) == "number" and k > 0 and k == math_floor(k) and k > max_idx then
            max_idx = k
        end
    end
    return max_idx
end

--- safe table length that handles sparse arrays
-- @param t table array to measure
-- @return integer length including sparse elements
local function safe_len(t)
    if not t then return 0 end
    local max_idx = 0
    for k in pairs(t) do
        if type(k) == "number" and k > 0 and k == math_floor(k) and k > max_idx then
            max_idx = k
        end
    end
    return max_idx
end

-- ============================================================================
-- luna metatable
-- ============================================================================
local luna = {}
luna.__index = luna

--- create new luna object with minimal allocation
--- @param src_type integer source type code
--- @param src_data array source data
--- @param ops array operation list
--- @param n_ops integer operation count
--- @return luna object
local function new_luna(src_type, src_data, ops, n_ops)
    return setmetatable({
        _t = src_type,  -- source type
        _d = src_data,  -- source data array
        _o = ops,       -- operations array
        _n = n_ops or 0 -- operation count
    }, luna)
end

-- ============================================================================
-- constructors
-- ============================================================================

--- create iterator from table/string
--- @param data table|string|luna source data
--- @return luna iterator
function luna.from(data)
    if not data then
        return new_luna(SRC_TABLE, {}, nil, 0)
    end

    local t = type(data)
    if t == "table" then
        if getmetatable(data) == luna then return data end
        return new_luna(SRC_TABLE, data, nil, 0)
    elseif t == "string" then
        return new_luna(SRC_STRING, data, nil, 0)
    end

    error("cannot create iterator from " .. t)
end

--- create range iterator
--- @param a integer start (or stop if only arg)
--- @param b integer stop (optional)
--- @param c integer step (optional)
--- @return luna range iterator
function luna.range(a, b, c)
    local start, stop, step
    if not b then
        start, stop, step = 1, a, 1
    elseif not c then
        start, stop, step = a, b, 1
    else
        start, stop, step = a, b, c
    end
    return new_luna(SRC_RANGE, { start, stop, step }, nil, 0)
end

--- create repeat iterator
--- @param value any value to repeat
--- @param count integer repetition count (-1 for infinite)
--- @return luna repeat iterator
function luna.rep(value, count)
    return new_luna(SRC_REPEAT, { value, count or -1 }, nil, 0)
end

--- create unfold iterator
--- @param seed any initial state
--- @param func function(state) -> value, next_state
--- @return luna unfold iterator
function luna.unfold(seed, func)
    return new_luna(SRC_UNFOLD, { seed, func }, nil, 0)
end

-- ============================================================================
-- operation chaining - minimal allocation, operation reuse
-- ============================================================================

--- chain operation with minimal allocation
--- @param self luna iterator
--- @param op_type integer operation type code
--- @param a1 any operation arg 1
--- @param a2 any operation arg 2
--- @param a3 any operation arg 3
--- @param a4 any operation arg 4
--- @return luna new iterator with operation
local function chain_op(self, op_type, a1, a2, a3, a4)
    local old_ops = self._o
    local n = self._n
    local new_ops

    -- pre-allocate ops array
    if n == 0 then
        new_ops = table_new and table_new(4, 0) or {}
    else
        new_ops = table_new and table_new(n + 1, 0) or {}
        -- copy existing ops
        for i = 1, n do
            new_ops[i] = old_ops[i]
        end
    end

    -- store as flat array
    new_ops[n + 1] = { op_type, a1, a2, a3, a4 }
    return new_luna(self._t, self._d, new_ops, n + 1)
end

-- ============================================================================
-- transformations
-- ============================================================================

--- filter by predicate
--- @param predicate function(value) -> boolean
--- @return luna filtered iterator
function luna:where(predicate)
    return chain_op(self, OP_WHERE, predicate)
end

--- transform values
--- @param transform function(value) -> new_value
--- @return luna transformed iterator
function luna:select(transform)
    return chain_op(self, OP_SELECT, transform)
end

--- transform values with memoized predicate
--- @param predicate function(value) -> boolean
--- @return luna filtered iterator with memoization
function luna:memoize(predicate)
    local memoized = memoize_predicate(predicate)
    return chain_op(self, OP_MEMOIZE, memoized)
end

--- parallel map using coroutines
--- @param transform function(value) -> new_value
--- @param batch_size integer batch size for parallelization (default 10)
--- @return luna parallel mapped iterator
function luna:parallel_map(transform, batch_size)
    return chain_op(self, OP_PARALLEL_MAP, transform, batch_size or 10)
end

--- chunk elements into batches
--- @param size integer chunk size
--- @return luna chunked iterator
function luna:chunk(size)
    return chain_op(self, OP_CHUNK, size)
end

--- take first n elements
--- @param n integer element count
--- @return luna limited iterator
function luna:take(n)
    return chain_op(self, OP_TAKE, n)
end

--- skip first n elements
--- @param n integer element count
--- @return luna skipped iterator
function luna:skip(n)
    return chain_op(self, OP_SKIP, n)
end

--- reverse element order
--- @return luna reversed iterator
function luna:reverse()
    return chain_op(self, OP_REVERSE)
end

--- sort elements
--- @param comparator function(a,b) -> boolean (optional)
--- @return luna sorted iterator
function luna:order(comparator)
    return chain_op(self, OP_ORDER, comparator)
end

--- filter distinct elements
--- @param key_func function(value) -> key (optional)
--- @return luna distinct iterator
function luna:distinct(key_func)
    return chain_op(self, OP_DISTINCT, key_func)
end

--- flatten nested tables
--- @param depth integer flatten depth (default 1)
--- @return luna flattened iterator
function luna:flatten(depth)
    return chain_op(self, OP_FLATTEN, depth or 1)
end

--- create sliding windows
--- @param size integer window size
--- @param step integer step size (default 1)
--- @return luna window iterator
function luna:window(size, step)
    return chain_op(self, OP_WINDOW, size, step or 1)
end

--- accumulate with function
--- @param initial any initial accumulator value
--- @param func function(acc, value) -> new_acc
--- @return luna scan iterator
function luna:scan(initial, func)
    return chain_op(self, OP_SCAN, initial, func)
end

--- zip with another iterator
--- @param other table|luna other iterator
--- @return luna zipped iterator
function luna:zip(other)
    return chain_op(self, OP_ZIP, luna.from(other))
end

--- unzip paired elements
--- @return luna unzipped iterator
function luna:unzip()
    return chain_op(self, OP_UNZIP)
end

--- intersperse separator
--- @param separator any value to insert between elements
--- @return luna interspersed iterator
function luna:intersperse(separator)
    return chain_op(self, OP_INTERSPERSE, separator)
end

--- lag elements
--- @param n integer lag count (default 1)
--- @param default any default value for missing elements
--- @return luna lagged iterator
function luna:lag(n, default)
    return chain_op(self, OP_LAG, n or 1, default)
end

--- find first matching element
--- @param predicate function(value) -> boolean
--- @return luna find iterator
function luna:find(predicate)
    return chain_op(self, OP_FIND, predicate)
end

--- select elements between markers
--- @param start_val any start marker value
--- @param end_val any end marker value
--- @return luna between iterator
function luna:between(start_val, end_val)
    return chain_op(self, OP_BETWEEN, start_val, end_val)
end

--- union with another iterator
--- @param other table|luna other iterator
--- @return luna union iterator
function luna:union(other)
    return chain_op(self, OP_UNION, luna.from(other))
end

--- intersection with another iterator
--- @param other table|luna other iterator
--- @return luna intersection iterator
function luna:intersection(other)
    return chain_op(self, OP_INTERSECTION, luna.from(other))
end

--- complement with another iterator
--- @param other table|luna other iterator
--- @return luna complement iterator
function luna:complement(other)
    return chain_op(self, OP_COMPLEMENT, luna.from(other))
end

--- inner join
--- @param other table|luna other iterator
--- @param key_selector function(value) -> key
--- @param other_key_selector function(value) -> key
--- @param result_selector function(left, right) -> result
--- @return luna joined iterator
function luna:join(other, key_selector, other_key_selector, result_selector)
    return chain_op(self, OP_JOIN, luna.from(other), key_selector,
        other_key_selector, result_selector)
end

--- left join
function luna:ljoin(other, key_selector, other_key_selector, result_selector)
    return chain_op(self, OP_LJOIN, luna.from(other), key_selector,
        other_key_selector, result_selector)
end

--- right join
function luna:rjoin(other, key_selector, other_key_selector, result_selector)
    return chain_op(self, OP_RJOIN, luna.from(other), key_selector,
        other_key_selector, result_selector)
end

--- cartesian product
--- @param other table|luna other iterator
--- @return luna cross product iterator
function luna:cross(other)
    return chain_op(self, OP_CROSS, luna.from(other))
end

--- group by key
--- @param key_selector function(value) -> key
--- @return luna grouped iterator
function luna:group(key_selector)
    return chain_op(self, OP_GROUP, key_selector)
end

--- apply side effect
--- @param action function(value) action to perform
--- @return luna effect iterator
function luna:effect(action)
    return chain_op(self, OP_EFFECT, action)
end

--- partition into two tables
--- @param predicate function(value) -> boolean
--- @return table, table (pass, fail)
function luna:partition(predicate)
    local pass = table_new and table_new(100, 0) or {}
    local fail = table_new and table_new(100, 0) or {}
    local p_idx, f_idx = 0, 0

    local items = self:totable()
    for i = 1, #items do
        local value = items[i]
        if predicate(value) then
            p_idx = p_idx + 1
            pass[p_idx] = value
        else
            f_idx = f_idx + 1
            fail[f_idx] = value
        end
    end

    return pass, fail
end

-- ============================================================================
-- terminals
-- ============================================================================

--- iterate with action
--- @param action function(value) action to perform
function luna:each(action)
    local items = self:totable()
    for i = 1, #items do
        action(items[i])
    end
end

--- fold/reduce
--- @param initial any initial accumulator
--- @param func function(acc, value) -> new_acc
--- @return any final accumulator
function luna:fold(initial, func)
    local acc = initial
    local items = self:totable()
    for i = 1, #items do
        acc = func(acc, items[i])
    end
    return acc
end

--- pipe to function
--- @param func function(luna) -> result
--- @return any function result
function luna:pipe(func)
    return func(self)
end

-- ============================================================================
-- totable hotpaths
-- ============================================================================

--- materialize to table
--- @return table materialized elements
function luna:totable()
    local src_type = self._t
    local src_data = self._d
    local ops = self._o
    local n_ops = self._n

    -- no operations
    if n_ops == 0 then
        if src_type == SRC_TABLE then
            local len = safe_len(src_data)
            local result = table_new and table_new(len, 0) or {}
            for i = 1, len do
                result[i] = src_data[i]
            end
            return result
        elseif src_type == SRC_RANGE then
            return self:_range_direct()
        elseif src_type == SRC_STRING then
            local str = src_data
            local len = #str
            local result = table_new and table_new(len, 0) or {}
            for i = 1, len do
                result[i] = str:sub(i, i)
            end
            return result
        elseif src_type == SRC_REPEAT then
            local value, count = src_data[1], src_data[2]
            if count < 0 then error("cannot materialize infinite repeat") end
            local result = table_new and table_new(count, 0) or {}
            for i = 1, count do
                result[i] = value
            end
            return result
        elseif src_type == SRC_UNFOLD then
            local state = src_data[1]
            local func = src_data[2]
            local result = table_new and table_new(100, 0) or {}
            local idx = 0
            local safety_limit = 10000

            for i = 1, safety_limit do
                local value, next_state = func(state)
                if value == nil then break end
                idx = idx + 1
                result[idx] = value
                state = next_state
                if state == nil then break end
            end

            if idx >= safety_limit then
                error("unfold reached safety limit - use take() to limit iteration")
            end

            return result
        end
    end

    -- single take operation
    if n_ops == 1 and ops[1][1] == OP_TAKE then
        local limit = ops[1][2]

        if type(limit) ~= "number" or limit <= 0 then
            return {}
        end
        limit = math_floor(limit)
        if limit <= 0 then return {} end

        if src_type == SRC_TABLE then
            local src_len = safe_len(src_data)
            local copy_len = math_min(src_len, limit)
            if t_move then
                local result = table_new and table_new(copy_len, 0) or {}
                t_move(src_data, 1, copy_len, 1, result)
                return result
            else
                local result = table_new and table_new(copy_len, 0) or {}
                for i = 1, copy_len do
                    result[i] = src_data[i]
                end
                return result
            end
        elseif src_type == SRC_RANGE then
            local d = src_data
            local start, stop, step = d[1], d[2], d[3]

            local full_count
            if step > 0 then
                full_count = math_max(0, math_floor((stop - start) / step) + 1)
            elseif step < 0 then
                full_count = math_max(0, math_floor((stop - start) / step) + 1)
            else
                full_count = (start == stop) and 1e18 or 0
            end

            local copy_len = math_min(limit, full_count)
            if copy_len <= 0 then return {} end

            local result = table_new and table_new(copy_len, 0) or {}
            local v = start
            for i = 1, copy_len do
                result[i] = v
                v = v + step
            end
            return result
        elseif src_type == SRC_REPEAT then
            local value, count = src_data[1], src_data[2]
            local actual_limit = count < 0 and limit or math_min(count, limit)
            local result = table_new and table_new(actual_limit, 0) or {}
            for i = 1, actual_limit do
                result[i] = value
            end
            return result
        end
    end

    -- where + take
    if n_ops == 2 and ops[1][1] == OP_WHERE and ops[2][1] == OP_TAKE then
        local pred = ops[1][2]
        local limit = ops[2][2]

        if src_type == SRC_TABLE then
            local result = table_new and table_new(limit, 0) or {}
            local out_idx = 0
            local src_len = safe_len(src_data)
            for i = 1, src_len do
                local v = src_data[i]
                if pred(v) then
                    out_idx = out_idx + 1
                    result[out_idx] = v
                    if out_idx >= limit then break end
                end
            end
            return result
        elseif src_type == SRC_RANGE then
            local d = src_data
            local start, stop, step = d[1], d[2], d[3]
            local result = table_new and table_new(limit, 0) or {}
            local out_idx = 0
            if step > 0 then
                for v = start, stop, step do
                    if pred(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = v
                        if out_idx >= limit then break end
                    end
                end
            else
                for v = start, stop, step do
                    if pred(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = v
                        if out_idx >= limit then break end
                    end
                end
            end
            return result
        end
    end

    -- check fusion eligibility (order-independent)
    -- disable fusion if operation order matters (e.g., select before where, take before skip)
    local can_fuse = (src_type == SRC_TABLE or src_type == SRC_RANGE or src_type == SRC_REPEAT)
    if can_fuse then
        local has_select = false
        local has_take = false
        for i = 1, n_ops do
            local op_type = ops[i][1]
            if op_type == OP_SELECT then
                has_select = true
            elseif (op_type == OP_WHERE or op_type == OP_MEMOIZE) and has_select then
                -- select before where/memoize
                can_fuse = false
                break
            elseif op_type == OP_TAKE then
                has_take = true
            elseif op_type == OP_SKIP and has_take then
                -- take before skip
                can_fuse = false
                break
            elseif op_type > OP_SKIP and op_type ~= OP_MEMOIZE then
                can_fuse = false
                break
            end
        end
    end

    if can_fuse then
        return self:_fused_path()
    end

    -- check materialization requirement
    for i = 1, n_ops do
        if NEEDS_MATERIALIZE[ops[i][1]] then
            return self:_materialize_complex()
        end
    end

    return self:_streamable_path()
end

--- direct range materialization
function luna:_range_direct()
    local d = self._d
    local start, stop, step = d[1], d[2], d[3]

    local size
    if step > 0 then
        size = math_max(0, math_floor((stop - start) / step) + 1)
    elseif step < 0 then
        size = math_max(0, math_floor((stop - start) / step) + 1)
    else
        size = (start == stop) and 1 or 0
    end

    local result = table_new and table_new(size, 0) or {}
    local idx = 0

    if step > 0 then
        for i = start, stop, step do
            idx = idx + 1
            result[idx] = i
        end
    elseif step < 0 then
        for i = start, stop, step do
            idx = idx + 1
            result[idx] = i
        end
    elseif start == stop then
        result[1] = start
    end

    return result
end

--- hyper-optimized fused path for where/select/take/skip/memoize
function luna:_fused_path()
    local src_type = self._t
    local src_data = self._d
    local ops = self._o
    local n_ops = self._n

    -- parse operations
    local preds = {}
    local trans = {}
    local n_pred, n_trans = 0, 0
    local take_limit = nil
    local skip_count = 0

    for i = 1, n_ops do
        local op = ops[i]
        local op_type = op[1]
        if op_type == OP_WHERE then
            n_pred = n_pred + 1
            preds[n_pred] = op[2]
        elseif op_type == OP_SELECT then
            n_trans = n_trans + 1
            trans[n_trans] = op[2]
        elseif op_type == OP_MEMOIZE then
            n_pred = n_pred + 1
            preds[n_pred] = op[2]
        elseif op_type == OP_TAKE then
            take_limit = op[2]
        elseif op_type == OP_SKIP then
            skip_count = skip_count + op[2]
        end
    end

    local result = table_new and table_new(take_limit or 100, 0) or {}

    -- ========================================================================
    -- table source
    -- ========================================================================
    if src_type == SRC_TABLE then
        local src_len = safe_len(src_data)
        local out_idx = 0

        -- filter + map, no skip/take
        if n_pred == 1 and n_trans == 1 and skip_count == 0 and not take_limit then
            local p1 = preds[1]
            local t1 = trans[1]

            for i = 1, src_len do
                local v = src_data[i]
                if p1(v) then
                    out_idx = out_idx + 1
                    result[out_idx] = t1(v)
                end
            end
            return result
        end

        -- filter + map with take
        if n_pred == 1 and n_trans == 1 and skip_count == 0 and take_limit then
            local p1 = preds[1]
            local t1 = trans[1]

            for i = 1, src_len do
                local v = src_data[i]
                if p1(v) then
                    out_idx = out_idx + 1
                    result[out_idx] = t1(v)
                    if out_idx >= take_limit then break end
                end
            end
            return result
        end

        -- single filter, no skip/take
        if n_pred == 1 and n_trans == 0 and skip_count == 0 and not take_limit then
            local p1 = preds[1]

            for i = 1, src_len do
                local v = src_data[i]
                if p1(v) then
                    out_idx = out_idx + 1
                    result[out_idx] = v
                end
            end
            return result
        end

        -- single map, no skip/take
        if n_pred == 0 and n_trans == 1 and skip_count == 0 and not take_limit then
            local t1 = trans[1]

            for i = 1, src_len do
                out_idx = out_idx + 1
                result[out_idx] = t1(src_data[i])
            end
            return result
        end

        -- triple map, no skip/take
        if n_pred == 0 and n_trans == 3 and skip_count == 0 and not take_limit then
            local t1, t2, t3 = trans[1], trans[2], trans[3]

            for i = 1, src_len do
                out_idx = out_idx + 1
                result[out_idx] = t3(t2(t1(src_data[i])))
            end
            return result
        end

        -- triple filter, no skip/take
        if n_pred == 3 and n_trans == 0 and skip_count == 0 and not take_limit then
            local p1, p2, p3 = preds[1], preds[2], preds[3]

            for i = 1, src_len do
                local v = src_data[i]
                if p1(v) and p2(v) and p3(v) then
                    out_idx = out_idx + 1
                    result[out_idx] = v
                end
            end
            return result
        end

        -- general path with skip/take
        local skipped = 0

        if n_pred == 0 then
            -- select-only chains
            for i = 1, src_len do
                if take_limit and out_idx >= take_limit then break end

                local v = src_data[i]

                -- transforms
                for j = 1, n_trans do
                    v = trans[j](v)
                end

                -- skip/collect
                if skipped < skip_count then
                    skipped = skipped + 1
                else
                    out_idx = out_idx + 1
                    result[out_idx] = v
                end
            end
        else
            -- where/mixed chains
            for i = 1, src_len do
                if take_limit and out_idx >= take_limit then break end

                local v = src_data[i]
                local pass = true

                -- predicates
                for j = 1, n_pred do
                    if not preds[j](v) then
                        pass = false
                        break
                    end
                end

                if pass then
                    -- transforms
                    if n_trans > 0 then
                        for j = 1, n_trans do
                            v = trans[j](v)
                        end
                    end

                    -- skip/collect
                    if skipped < skip_count then
                        skipped = skipped + 1
                    else
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            end
        end
        return result
    end

    -- ========================================================================
    -- range source
    -- ========================================================================
    if src_type == SRC_RANGE then
        local d = src_data
        local start, stop, step = d[1], d[2], d[3]
        local out_idx = 0

        -- filter + map, no skip/take
        if n_pred == 1 and n_trans == 1 and skip_count == 0 and not take_limit then
            local p1 = preds[1]
            local t1 = trans[1]

            if step == 1 then
                for v = start, stop do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = t1(v)
                    end
                end
            elseif step > 0 then
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = t1(v)
                    end
                end
            else
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = t1(v)
                    end
                end
            end
            return result
        end

        -- filter + map with take
        if n_pred == 1 and n_trans == 1 and skip_count == 0 and take_limit then
            local p1 = preds[1]
            local t1 = trans[1]

            if step > 0 then
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = t1(v)
                        if out_idx >= take_limit then break end
                    end
                end
            else
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = t1(v)
                        if out_idx >= take_limit then break end
                    end
                end
            end
            return result
        end

        -- single filter
        if n_pred == 1 and n_trans == 0 and skip_count == 0 and not take_limit then
            local p1 = preds[1]

            if step > 0 then
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            else
                for v = start, stop, step do
                    if p1(v) then
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            end
            return result
        end

        -- single map
        if n_pred == 0 and n_trans == 1 and skip_count == 0 and not take_limit then
            local t1 = trans[1]

            if step > 0 then
                for v = start, stop, step do
                    out_idx = out_idx + 1
                    result[out_idx] = t1(v)
                end
            else
                for v = start, stop, step do
                    out_idx = out_idx + 1
                    result[out_idx] = t1(v)
                end
            end
            return result
        end

        -- general path
        local skipped = 0

        if n_pred == 0 then
            -- select-only chains
            if step > 0 then
                for v = start, stop, step do
                    if take_limit and out_idx >= take_limit then break end

                    for j = 1, n_trans do
                        v = trans[j](v)
                    end

                    if skipped < skip_count then
                        skipped = skipped + 1
                    else
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            else
                for v = start, stop, step do
                    if take_limit and out_idx >= take_limit then break end

                    for j = 1, n_trans do
                        v = trans[j](v)
                    end

                    if skipped < skip_count then
                        skipped = skipped + 1
                    else
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            end
        else
            -- where/mixed chains
            if step > 0 then
                for v = start, stop, step do
                    if take_limit and out_idx >= take_limit then break end

                    local pass = true
                    for j = 1, n_pred do
                        if not preds[j](v) then
                            pass = false
                            break
                        end
                    end

                    if pass then
                        if n_trans > 0 then
                            for j = 1, n_trans do
                                v = trans[j](v)
                            end
                        end

                        if skipped < skip_count then
                            skipped = skipped + 1
                        else
                            out_idx = out_idx + 1
                            result[out_idx] = v
                        end
                    end
                end
            else
                for v = start, stop, step do
                    if take_limit and out_idx >= take_limit then break end

                    local pass = true
                    for j = 1, n_pred do
                        if not preds[j](v) then
                            pass = false
                            break
                        end
                    end

                    if pass then
                        if n_trans > 0 then
                            for j = 1, n_trans do
                                v = trans[j](v)
                            end
                        end

                        if skipped < skip_count then
                            skipped = skipped + 1
                        else
                            out_idx = out_idx + 1
                            result[out_idx] = v
                        end
                    end
                end
            end
        end
        return result
    end

    -- ========================================================================
    -- repeat source
    -- ========================================================================
    if src_type == SRC_REPEAT then
        local value, count = src_data[1], src_data[2]
        local out_idx = 0
        local skipped = 0

        -- determine iteration limit
        local limit
        if count < 0 then
            -- infinite repeat
            if not take_limit then
                error("cannot materialize infinite repeat without take()")
            end
            limit = take_limit + skip_count
        else
            limit = count
            if take_limit then
                limit = math_min(limit, take_limit + skip_count)
            end
        end

        if n_pred == 0 and n_trans == 0 then
            -- no operations, just skip/take
            for i = 1, limit do
                if take_limit and out_idx >= take_limit then break end

                if skipped < skip_count then
                    skipped = skipped + 1
                else
                    out_idx = out_idx + 1
                    result[out_idx] = value
                end
            end
        elseif n_pred == 0 then
            -- only transforms
            for i = 1, limit do
                if take_limit and out_idx >= take_limit then break end

                local v = value
                for j = 1, n_trans do
                    v = trans[j](v)
                end

                if skipped < skip_count then
                    skipped = skipped + 1
                else
                    out_idx = out_idx + 1
                    result[out_idx] = v
                end
            end
        else
            -- with predicates
            for i = 1, limit do
                if take_limit and out_idx >= take_limit then break end

                local v = value
                local pass = true

                for j = 1, n_pred do
                    if not preds[j](v) then
                        pass = false
                        break
                    end
                end

                if pass then
                    if n_trans > 0 then
                        for j = 1, n_trans do
                            v = trans[j](v)
                        end
                    end

                    if skipped < skip_count then
                        skipped = skipped + 1
                    else
                        out_idx = out_idx + 1
                        result[out_idx] = v
                    end
                end
            end
        end
        return result
    end

    return {}
end

--- materialize complex operations
function luna:_materialize_complex()
    local src_type = self._t
    local src_data = self._d
    local ops = self._o
    local n_ops = self._n

    -- materialize source
    local items
    local idx = 0

    if src_type == SRC_TABLE then
        local len = safe_len(src_data)
        items = table_new and table_new(len, 0) or {}
        for i = 1, len do
            items[i] = src_data[i]
        end
        idx = len
    elseif src_type == SRC_RANGE then
        local d = src_data
        local start, stop, step = d[1], d[2], d[3]

        local size
        if step > 0 then
            size = math_max(0, math_floor((stop - start) / step) + 1)
        elseif step < 0 then
            size = math_max(0, math_floor((stop - start) / step) + 1)
        else
            size = (start == stop) and 1 or 0
        end

        items = table_new and table_new(size, 0) or {}

        if step > 0 then
            for i = start, stop, step do
                idx = idx + 1
                items[idx] = i
            end
        elseif step < 0 then
            for i = start, stop, step do
                idx = idx + 1
                items[idx] = i
            end
        elseif start == stop then
            items[1] = start
            idx = 1
        end
    elseif src_type == SRC_STRING then
        local str = src_data
        local len = #str
        items = table_new and table_new(len, 0) or {}
        for i = 1, len do
            items[i] = str:sub(i, i)
        end
        idx = len
    elseif src_type == SRC_REPEAT then
        local value, count = src_data[1], src_data[2]

        -- check for take in ops to determine limit
        local limit = count
        if count < 0 then
            limit = 1000 -- default safety limit
            for i = 1, n_ops do
                if ops[i][1] == OP_TAKE then
                    limit = math_min(limit, ops[i][2])
                    break
                end
            end
        end

        items = table_new and table_new(limit, 0) or {}
        for i = 1, limit do
            items[i] = value
        end
        idx = limit
    elseif src_type == SRC_UNFOLD then
        items = table_new and table_new(100, 0) or {}
        local state = src_data[1]
        local func = src_data[2]
        local limit = 1000

        -- check for take in ops
        for i = 1, n_ops do
            if ops[i][1] == OP_TAKE then
                limit = math_min(limit, ops[i][2])
                break
            end
        end

        for i = 1, limit do
            local value, next_state = func(state)
            if value == nil then break end
            idx = idx + 1
            items[idx] = value
            state = next_state
            if state == nil then break end
        end
    else
        items = {}
    end

    -- apply ops
    for i = 1, n_ops do
        local op = ops[i]
        local op_type = op[1]

        if op_type == OP_REVERSE then
            local len = #items
            local mid = math_floor(len / 2)
            for j = 1, mid do
                items[j], items[len - j + 1] = items[len - j + 1], items[j]
            end
        elseif op_type == OP_ORDER then
            table_sort(items, op[2])
        elseif op_type == OP_GROUP then
            local key_func = op[2]
            local groups = {}
            local group_order = {}
            local order_idx = 0

            for j = 1, #items do
                local item = items[j]
                local key = key_func(item)
                local group = groups[key]

                if not group then
                    order_idx = order_idx + 1
                    group_order[order_idx] = key
                    group = table_new and table_new(10, 0) or {}
                    groups[key] = group
                end

                group[#group + 1] = item
            end

            items = table_new and table_new(order_idx, 0) or {}
            for j = 1, order_idx do
                local key = group_order[j]
                items[j] = { key = key, items = groups[key] }
            end
        elseif op_type == OP_WINDOW then
            local size = op[2]
            local step_size = op[3]
            local src_len = #items

            if src_len < size then
                items = {}
            else
                local windowed = table_new and table_new(0, 0) or {}
                local out_idx = 0

                local pos = 1
                local stop = src_len - size + 1
                while pos <= stop do
                    local window = table_new and table_new(size, 0) or {}

                    for k = 1, size do
                        window[k] = items[pos + k - 1]
                    end

                    out_idx = out_idx + 1
                    windowed[out_idx] = window

                    pos = pos + step_size
                end

                items = windowed
            end
        elseif op_type == OP_CHUNK then
            local chunk_size = op[2]
            local src_len = #items
            local chunked = table_new and table_new(math_floor(src_len / chunk_size) + 1, 0) or {}
            local chunk_idx = 0
            local pos = 1

            while pos <= src_len do
                local chunk = table_new and table_new(chunk_size, 0) or {}
                local chunk_len = 0

                for k = 1, chunk_size do
                    if pos > src_len then break end
                    chunk_len = chunk_len + 1
                    chunk[chunk_len] = items[pos]
                    pos = pos + 1
                end

                chunk_idx = chunk_idx + 1
                chunked[chunk_idx] = chunk
            end

            items = chunked
        elseif op_type == OP_PARALLEL_MAP then
            local transform = op[2]
            local batch_size = op[3]
            local src_len = #items
            local result = table_new and table_new(src_len, 0) or {}

            -- process in batches using coroutines
            local function process_batch(start_idx, end_idx, batch_results)
                return coroutine_create(function()
                    for k = start_idx, end_idx do
                        batch_results[k] = transform(items[k])
                        coroutine_yield()
                    end
                end)
            end

            local batch_count = math_floor((src_len + batch_size - 1) / batch_size)
            local coros = table_new and table_new(batch_count, 0) or {}

            for b = 1, batch_count do
                local start_idx = (b - 1) * batch_size + 1
                local end_idx = math_min(b * batch_size, src_len)
                coros[b] = process_batch(start_idx, end_idx, result)
            end

            -- execute all coroutines round-robin
            local active = batch_count
            while active > 0 do
                for b = 1, batch_count do
                    local co = coros[b]
                    if co and coroutine_status(co) ~= "dead" then
                        local ok = coroutine_resume(co)
                        if not ok or coroutine_status(co) == "dead" then
                            active = active - 1
                        end
                    end
                end
            end

            items = result
        elseif op_type == OP_FLATTEN then
            local depth = op[2]
            local flattened = table_new and table_new(#items * 2, 0) or {}
            local f_idx = 0

            local function flatten_recursive(item, d)
                if d > 0 and type(item) == "table" then
                    for k = 1, #item do
                        flatten_recursive(item[k], d - 1)
                    end
                else
                    f_idx = f_idx + 1
                    flattened[f_idx] = item
                end
            end

            for j = 1, #items do
                flatten_recursive(items[j], depth)
            end

            items = flattened
        elseif op_type == OP_WHERE then
            local pred = op[2]
            local write_idx = 0
            for j = 1, #items do
                local item = items[j]
                if pred(item) then
                    write_idx = write_idx + 1
                    items[write_idx] = item
                end
            end
            for j = write_idx + 1, #items do
                items[j] = nil
            end
        elseif op_type == OP_MEMOIZE then
            local pred = op[2]
            local write_idx = 0
            for j = 1, #items do
                local item = items[j]
                if pred(item) then
                    write_idx = write_idx + 1
                    items[write_idx] = item
                end
            end
            for j = write_idx + 1, #items do
                items[j] = nil
            end
        elseif op_type == OP_SELECT then
            local func = op[2]
            for j = 1, #items do
                items[j] = func(items[j])
            end
        elseif op_type == OP_TAKE then
            local limit = op[2]
            for j = limit + 1, #items do
                items[j] = nil
            end
        elseif op_type == OP_SKIP then
            local to_skip = op[2]
            local len = #items
            if to_skip >= len then
                items = {}
            else
                if t_move then
                    t_move(items, to_skip + 1, len, 1, items)
                else
                    for j = 1, len - to_skip do
                        items[j] = items[j + to_skip]
                    end
                end
                for j = len - to_skip + 1, len do
                    items[j] = nil
                end
            end
        elseif op_type == OP_LAG then
            local lag_count = op[2]
            local lag_default = op[3]
            local lagged = table_new and table_new(#items, 0) or {}

            for j = 1, #items do
                local lagged_val
                if j <= lag_count then
                    lagged_val = lag_default
                else
                    lagged_val = items[j - lag_count]
                end
                lagged[j] = { items[j], lagged_val }
            end

            items = lagged
        elseif op_type == OP_UNZIP then
            local len = #items
            local left = table_new and table_new(len, 0) or {}
            local right = table_new and table_new(len, 0) or {}
            for j = 1, len do
                local pair = items[j]
                left[j] = pair[1]
                right[j] = pair[2]
            end
            items = { left, right }
        elseif op_type == OP_CROSS then
            local other = op[2]:totable()
            local left_len = #items
            local right_len = #other
            local crossed = table_new and table_new(left_len * right_len, 0) or {}
            local idx = 0

            for j = 1, left_len do
                for k = 1, right_len do
                    idx = idx + 1
                    crossed[idx] = { items[j], other[k] }
                end
            end

            items = crossed
        elseif op_type == OP_JOIN or op_type == OP_LJOIN or op_type == OP_RJOIN then
            local other = op[2]:totable()
            local key_sel = op[3]
            local other_key_sel = op[4]
            local result_sel = op[5]

            -- build lookup for other
            local other_map = {}
            for j = 1, #other do
                local key = other_key_sel(other[j])
                if not other_map[key] then
                    other_map[key] = {}
                end
                table_insert(other_map[key], other[j])
            end

            local joined = table_new and table_new(#items, 0) or {}
            local j_idx = 0

            if op_type == OP_JOIN then
                -- inner join
                for j = 1, #items do
                    local left_item = items[j]
                    local key = key_sel(left_item)
                    local matches = other_map[key]
                    if matches then
                        for k = 1, #matches do
                            j_idx = j_idx + 1
                            joined[j_idx] = result_sel(left_item, matches[k])
                        end
                    end
                end
            elseif op_type == OP_LJOIN then
                -- left join
                for j = 1, #items do
                    local left_item = items[j]
                    local key = key_sel(left_item)
                    local matches = other_map[key]
                    if matches then
                        for k = 1, #matches do
                            j_idx = j_idx + 1
                            joined[j_idx] = result_sel(left_item, matches[k])
                        end
                    else
                        j_idx = j_idx + 1
                        joined[j_idx] = result_sel(left_item, nil)
                    end
                end
            elseif op_type == OP_RJOIN then
                -- right join
                local matched_right = {}
                for j = 1, #items do
                    local left_item = items[j]
                    local key = key_sel(left_item)
                    local matches = other_map[key]
                    if matches then
                        for k = 1, #matches do
                            j_idx = j_idx + 1
                            joined[j_idx] = result_sel(left_item, matches[k])
                            matched_right[matches[k]] = true
                        end
                    end
                end
                -- add unmatched right items
                for j = 1, #other do
                    if not matched_right[other[j]] then
                        j_idx = j_idx + 1
                        joined[j_idx] = result_sel(nil, other[j])
                    end
                end
            end

            items = joined
        end
    end

    return items
end

--- streamable operations path
function luna:_streamable_path()
    local src_type = self._t
    local src_data = self._d
    local ops = self._o
    local n_ops = self._n

    -- parse ops
    local ordered_ops = {} -- preserve operation order for where/select
    local n_ordered = 0
    local preds, trans = {}, {}
    local n_pred, n_trans = 0, 0
    local skip_target, take_limit = 0, nil
    local take_before_skip = false -- track if take appears before any skip
    local has_scan, scan_acc, scan_func = false, nil, nil
    local has_distinct, distinct_key, distinct_seen = false, nil, nil
    local union_items, intersect_set, complement_set = nil, nil, nil
    local has_intersperse, intersperse_val = false, nil
    local has_find, find_pred = false, nil
    local has_between, between_start, between_end, between_active = false, nil, nil, false
    local has_lag, lag_count, lag_default = false, 0, nil
    local has_zip, zip_other = false, nil
    local has_effect, effect_func = false, nil
    local has_ordered_ops = false -- track if we need ordered execution

    -- parse ops
    for i = 1, n_ops do
        local op = ops[i]
        local op_type = op[1]

        if op_type == OP_WHERE then
            n_ordered = n_ordered + 1
            ordered_ops[n_ordered] = { type = "pred", func = op[2] }
            n_pred = n_pred + 1
            preds[n_pred] = op[2]
            if n_trans > 0 then has_ordered_ops = true end -- select before where
        elseif op_type == OP_MEMOIZE then
            n_ordered = n_ordered + 1
            ordered_ops[n_ordered] = { type = "pred", func = op[2] }
            n_pred = n_pred + 1
            preds[n_pred] = op[2]
            if n_trans > 0 then has_ordered_ops = true end
        elseif op_type == OP_SELECT then
            if has_lag or has_zip then
                return self:_materialize_complex()
            end
            n_ordered = n_ordered + 1
            ordered_ops[n_ordered] = { type = "trans", func = op[2] }
            n_trans = n_trans + 1
            trans[n_trans] = op[2]
        elseif op_type == OP_SKIP then
            if take_limit and not take_before_skip then
                -- skip appears after take - need to adjust source limit
                take_before_skip = true
            end
            skip_target = skip_target + op[2]
        elseif op_type == OP_TAKE then
            if skip_target == 0 then
                -- take appears before any skip
                take_before_skip = false
            end
            take_limit = op[2]
        elseif op_type == OP_DISTINCT then
            has_distinct = true
            distinct_key = op[2]
            distinct_seen = {}
        elseif op_type == OP_SCAN then
            has_scan = true
            scan_acc = op[2]
            scan_func = op[3]
        elseif op_type == OP_UNION then
            union_items = op[2]:totable()
            if not has_distinct then
                distinct_seen = {}
            end
        elseif op_type == OP_INTERSECTION then
            intersect_set = op[2]:toset()
        elseif op_type == OP_COMPLEMENT then
            complement_set = op[2]:toset()
        elseif op_type == OP_INTERSPERSE then
            has_intersperse = true
            intersperse_val = op[2]
        elseif op_type == OP_FIND then
            has_find = true
            find_pred = op[2]
        elseif op_type == OP_BETWEEN then
            has_between = true
            between_start = op[2]
            between_end = op[3]
        elseif op_type == OP_LAG then
            has_lag = true
            lag_count = op[2]
            lag_default = op[3]
        elseif op_type == OP_ZIP then
            has_zip = true
            zip_other = op[2]:totable()
        elseif op_type == OP_EFFECT then
            has_effect = true
            effect_func = op[2]
        end
    end

    local result = table_new and table_new(100, 0) or {}
    local out_idx = 0
    local skip_count = 0

    -- optimized scan path
    if has_scan and src_type == SRC_TABLE and n_pred == 0 and n_trans == 0 and
        not take_limit and skip_target == 0 and not has_distinct and
        not union_items and not intersect_set and not complement_set then
        local src_len = safe_len(src_data)
        local acc = scan_acc
        local func = scan_func

        local result = table_new and table_new(src_len, 0) or {}

        for i = 1, src_len do
            acc = func(acc, src_data[i])
            result[i] = acc
        end
        return result
    end

    -- general streamable path
    if src_type == SRC_TABLE then
        local src_len = safe_len(src_data)
        local zip_idx = 1
        local lag_buffer = has_lag and {} or nil

        for i = 1, src_len do
            if take_limit and out_idx >= take_limit then break end
            if has_find and out_idx > 0 then break end

            local v = src_data[i]

            -- between check
            if has_between then
                if not between_active and v == between_start then
                    between_active = true
                end
                if not between_active then goto continue end
            end

            if intersect_set and not intersect_set[v] then goto continue end
            if complement_set and complement_set[v] then goto continue end

            -- apply operations in order (preserves select before where, etc)
            if has_ordered_ops then
                for j = 1, n_ordered do
                    local opdata = ordered_ops[j]
                    if opdata.type == "pred" then
                        if not opdata.func(v) then
                            goto continue
                        end
                    else -- "trans"
                        v = opdata.func(v)
                    end
                end
            else
                -- all predicates then all transforms
                if n_pred > 0 then
                    local pass = true
                    for j = 1, n_pred do
                        if not preds[j](v) then
                            pass = false
                            break
                        end
                    end
                    if not pass then goto continue end
                end

                if n_trans > 0 then
                    for j = 1, n_trans do
                        v = trans[j](v)
                    end
                end
            end

            -- find check
            if has_find and not find_pred(v) then
                goto continue
            end

            if has_distinct or union_items then
                local key = distinct_key and distinct_key(v) or v
                if key == nil then key = NIL_SENTINEL end
                if distinct_seen[key] then goto continue end
                distinct_seen[key] = true
            end

            if has_scan then
                scan_acc = scan_func(scan_acc, v)
                v = scan_acc
            end

            -- zip operation
            if has_zip then
                if zip_idx <= #zip_other then
                    v = { v, zip_other[zip_idx] }
                    zip_idx = zip_idx + 1
                else
                    break
                end
            end

            -- lag operation
            if has_lag then
                local lagged_val
                if #lag_buffer < lag_count then
                    lagged_val = lag_default
                else
                    lagged_val = lag_buffer[1]
                    table_remove(lag_buffer, 1)
                end
                table_insert(lag_buffer, v)
                v = { v, lagged_val }
            end

            -- effect
            if has_effect then
                effect_func(v)
            end

            if skip_count < skip_target then
                skip_count = skip_count + 1
            else
                out_idx = out_idx + 1
                result[out_idx] = v

                -- intersperse (add separator after each element except last)
                if has_intersperse and (not take_limit or out_idx < take_limit) then
                    out_idx = out_idx + 1
                    result[out_idx] = intersperse_val
                end
            end

            -- between end check
            if has_between and between_active and v == between_end then
                break
            end

            ::continue::
        end

        -- remove trailing intersperse if added
        if has_intersperse and out_idx > 0 and result[out_idx] == intersperse_val then
            result[out_idx] = nil
            out_idx = out_idx - 1
        end
    elseif src_type == SRC_UNFOLD then
        -- unfold streaming
        local state = src_data[1]
        local func = src_data[2]
        local zip_idx = 1
        local lag_buffer = has_lag and {} or nil
        local iter_count = 0
        local max_iter = take_limit or 1000

        while iter_count < max_iter do
            if take_limit and out_idx >= take_limit then break end
            if has_find and out_idx > 0 then break end

            local v, next_state = func(state)
            if v == nil or next_state == nil then break end

            iter_count = iter_count + 1
            state = next_state

            if intersect_set and not intersect_set[v] then goto continue_unfold end
            if complement_set and complement_set[v] then goto continue_unfold end

            -- apply operations in order (preserves select before where, etc)
            if has_ordered_ops then
                for j = 1, n_ordered do
                    local opdata = ordered_ops[j]
                    if opdata.type == "pred" then
                        if not opdata.func(v) then
                            goto continue_unfold
                        end
                    else -- "trans"
                        v = opdata.func(v)
                    end
                end
            else
                -- all predicates then all transforms
                if n_pred > 0 then
                    local pass = true
                    for j = 1, n_pred do
                        if not preds[j](v) then
                            pass = false
                            break
                        end
                    end
                    if not pass then goto continue_unfold end
                end

                if n_trans > 0 then
                    for j = 1, n_trans do
                        v = trans[j](v)
                    end
                end
            end

            if has_find and not find_pred(v) then
                goto continue_unfold
            end

            if has_distinct or union_items then
                local key = distinct_key and distinct_key(v) or v
                if key == nil then key = NIL_SENTINEL end
                if distinct_seen[key] then goto continue_unfold end
                distinct_seen[key] = true
            end

            if has_scan then
                scan_acc = scan_func(scan_acc, v)
                v = scan_acc
            end

            if has_zip then
                if zip_idx <= #zip_other then
                    v = { v, zip_other[zip_idx] }
                    zip_idx = zip_idx + 1
                else
                    break
                end
            end

            if has_lag then
                local lagged_val
                if #lag_buffer < lag_count then
                    lagged_val = lag_default
                else
                    lagged_val = lag_buffer[1]
                    table_remove(lag_buffer, 1)
                end
                table_insert(lag_buffer, v)
                v = { v, lagged_val }
            end

            if has_effect then
                effect_func(v)
            end

            if skip_count < skip_target then
                skip_count = skip_count + 1
            else
                out_idx = out_idx + 1
                result[out_idx] = v

                if has_intersperse and (not take_limit or out_idx < take_limit) then
                    out_idx = out_idx + 1
                    result[out_idx] = intersperse_val
                end
            end

            ::continue_unfold::
        end

        if has_intersperse and out_idx > 0 and result[out_idx] == intersperse_val then
            result[out_idx] = nil
            out_idx = out_idx - 1
        end
    elseif src_type == SRC_RANGE then
        local d = src_data
        local start, stop, step = d[1], d[2], d[3]
        local zip_idx = 1
        local lag_buffer = has_lag and {} or nil

        -- if take appears before skip, limit source iteration
        if take_before_skip and take_limit then
            if step > 0 then
                local new_stop = start + (take_limit - 1) * step
                stop = math_min(stop, new_stop)
            elseif step < 0 then
                local new_stop = start + (take_limit - 1) * step
                stop = math_max(stop, new_stop)
            end
        end

        if step > 0 then
            for v = start, stop, step do
                if take_limit and out_idx >= take_limit then break end
                if has_find and out_idx > 0 then break end

                -- between check
                if has_between then
                    if not between_active and v == between_start then
                        between_active = true
                    end
                    if not between_active then goto continue end
                end

                if intersect_set and not intersect_set[v] then goto continue end
                if complement_set and complement_set[v] then goto continue end

                -- apply operations in order (preserves select before where, etc)
                if has_ordered_ops then
                    for j = 1, n_ordered do
                        local opdata = ordered_ops[j]
                        if opdata.type == "pred" then
                            if not opdata.func(v) then
                                goto continue
                            end
                        else -- "trans"
                            v = opdata.func(v)
                        end
                    end
                else
                    -- all predicates then all transforms
                    if n_pred > 0 then
                        local pass = true
                        for j = 1, n_pred do
                            if not preds[j](v) then
                                pass = false
                                break
                            end
                        end
                        if not pass then goto continue end
                    end

                    if n_trans > 0 then
                        for j = 1, n_trans do
                            v = trans[j](v)
                        end
                    end
                end

                -- find check
                if has_find and not find_pred(v) then
                    goto continue
                end

                if has_distinct then
                    local key = distinct_key and distinct_key(v) or v
                    if distinct_seen[key] then goto continue end
                    distinct_seen[key] = true
                end

                if has_scan then
                    scan_acc = scan_func(scan_acc, v)
                    v = scan_acc
                end

                -- zip operation
                if has_zip then
                    if zip_idx <= #zip_other then
                        v = { v, zip_other[zip_idx] }
                        zip_idx = zip_idx + 1
                    else
                        break
                    end
                end

                -- lag operation
                if has_lag then
                    local lagged_val
                    if #lag_buffer < lag_count then
                        lagged_val = lag_default
                    else
                        lagged_val = lag_buffer[1]
                        table_remove(lag_buffer, 1)
                    end
                    table_insert(lag_buffer, v)
                    v = { v, lagged_val }
                end

                -- effect
                if has_effect then
                    effect_func(v)
                end

                if skip_count < skip_target then
                    skip_count = skip_count + 1
                else
                    out_idx = out_idx + 1
                    result[out_idx] = v

                    -- intersperse
                    if has_intersperse and (not take_limit or out_idx < take_limit) then
                        out_idx = out_idx + 1
                        result[out_idx] = intersperse_val
                    end
                end

                -- between end check
                if has_between and between_active and v == between_end then
                    break
                end

                ::continue::
            end
        else
            for v = start, stop, step do
                if take_limit and out_idx >= take_limit then break end
                if has_find and out_idx > 0 then break end

                if has_between then
                    if not between_active and v == between_start then
                        between_active = true
                    end
                    if not between_active then goto continue end
                end

                if intersect_set and not intersect_set[v] then goto continue end
                if complement_set and complement_set[v] then goto continue end

                -- apply operations in order (preserves select before where, etc)
                if has_ordered_ops then
                    for j = 1, n_ordered do
                        local opdata = ordered_ops[j]
                        if opdata.type == "pred" then
                            if not opdata.func(v) then
                                goto continue
                            end
                        else -- "trans"
                            v = opdata.func(v)
                        end
                    end
                else
                    -- all predicates then all transforms
                    if n_pred > 0 then
                        local pass = true
                        for j = 1, n_pred do
                            if not preds[j](v) then
                                pass = false
                                break
                            end
                        end
                        if not pass then goto continue end
                    end

                    if n_trans > 0 then
                        for j = 1, n_trans do
                            v = trans[j](v)
                        end
                    end
                end

                if has_find and not find_pred(v) then
                    goto continue
                end

                if has_distinct then
                    local key = distinct_key and distinct_key(v) or v
                    if key == nil then key = NIL_SENTINEL end
                    if distinct_seen[key] then goto continue end
                    distinct_seen[key] = true
                end

                if has_scan then
                    scan_acc = scan_func(scan_acc, v)
                    v = scan_acc
                end

                if has_zip then
                    if zip_idx <= #zip_other then
                        v = { v, zip_other[zip_idx] }
                        zip_idx = zip_idx + 1
                    else
                        break
                    end
                end

                if has_lag then
                    local lagged_val
                    if #lag_buffer < lag_count then
                        lagged_val = lag_default
                    else
                        lagged_val = lag_buffer[1]
                        table_remove(lag_buffer, 1)
                    end
                    table_insert(lag_buffer, v)
                    v = { v, lagged_val }
                end

                if has_effect then
                    effect_func(v)
                end

                if skip_count < skip_target then
                    skip_count = skip_count + 1
                else
                    out_idx = out_idx + 1
                    result[out_idx] = v

                    if has_intersperse and (not take_limit or out_idx < take_limit) then
                        out_idx = out_idx + 1
                        result[out_idx] = intersperse_val
                    end
                end

                if has_between and between_active and v == between_end then
                    break
                end

                ::continue::
            end
        end

        -- remove trailing intersperse
        if has_intersperse and out_idx > 0 and result[out_idx] == intersperse_val then
            result[out_idx] = nil
            out_idx = out_idx - 1
        end
    end

    -- union handling
    if union_items then
        local union_len = #union_items
        for i = 1, union_len do
            if take_limit and out_idx >= take_limit then break end

            local v = union_items[i]
            local key = distinct_key and distinct_key(v) or v
            if key == nil then key = NIL_SENTINEL end
            if not distinct_seen[key] then
                distinct_seen[key] = true
                out_idx = out_idx + 1
                result[out_idx] = v
            end
        end
    end

    return result
end

-- ============================================================================
-- iterator protocol fallback
-- ============================================================================

--- create stateless iterator (avoid if possible, use totable instead)
--- @return function iterator function
function luna:iter()
    local items = self:totable()
    local idx = 0
    local len = #items
    return function()
        idx = idx + 1
        if idx <= len then
            return items[idx]
        end
    end
end

-- ============================================================================
-- conversion methods
-- ============================================================================

--- convert to string
--- @param separator string separator (default "")
--- @return string concatenated result
function luna:tostring(separator)
    local items = self:totable()
    local parts = table_new and table_new(#items, 0) or {}
    for i = 1, #items do
        parts[i] = tostring(items[i])
    end
    return table_concat(parts, separator or "")
end

--- convert to set (table with values as keys)
--- @return table set table
function luna:toset()
    local items = self:totable()
    local result = {}
    for i = 1, #items do
        result[items[i]] = true
    end
    return result
end

--- check if subset of other
--- @param other table|luna other iterator
--- @return boolean true if subset
function luna:subset(other)
    local other_set = luna.from(other):toset()
    local items = self:totable()
    for i = 1, #items do
        if not other_set[items[i]] then
            return false
        end
    end
    return true
end

--- check if superset of other
--- @param other table|luna other iterator
--- @return boolean true if superset
function luna:superset(other)
    local self_set = self:toset()
    local other_items = luna.from(other):totable()
    for i = 1, #other_items do
        if not self_set[other_items[i]] then
            return false
        end
    end
    return true
end

--- pivot table
--- @param row_key function(item) -> row_key
--- @param col_key function(item) -> col_key
--- @param value_key function(item) -> value
--- @param agg_func function(values) -> aggregated_value (optional)
--- @return table pivoted table
function luna:pivot(row_key, col_key, value_key, agg_func)
    local items = self:totable()
    local result = {}

    agg_func = agg_func or function(vals) return vals[1] end

    for i = 1, #items do
        local item = items[i]
        local row = row_key(item)
        local col = col_key(item)
        local val = value_key(item)

        local row_data = result[row]
        if not row_data then
            row_data = {}
            result[row] = row_data
        end

        local cell = row_data[col]
        if not cell then
            cell = {}
            row_data[col] = cell
        end

        cell[#cell + 1] = val
    end

    -- aggregate in place
    for row, cols in next, result do
        for col, vals in next, cols do
            result[row][col] = agg_func(vals)
        end
    end

    return result
end

-- ============================================================================
-- aggregations (direct execution)
-- ============================================================================

--- count elements
--- @return integer count
function luna:count()
    local items = self:totable()
    return array_count(items)
end

--- sum numeric values
--- @return number sum
function luna:sum()
    local items = self:totable()
    local total = 0
    for i = 1, #items do
        total = total + items[i]
    end
    return total
end

--- get minimum value
--- @return any minimum value
function luna:min()
    local items = self:totable()
    if #items == 0 then return nil end
    local min_val = items[1]
    for i = 2, #items do
        if items[i] < min_val then
            min_val = items[i]
        end
    end
    return min_val
end

--- get maximum value
--- @return any maximum value
function luna:max()
    local items = self:totable()
    if #items == 0 then return nil end
    local max_val = items[1]
    for i = 2, #items do
        if items[i] > max_val then
            max_val = items[i]
        end
    end
    return max_val
end

--- calculate average
--- @return number average
function luna:avg()
    local items = self:totable()
    local len = #items
    if len == 0 then return 0 end
    local total = 0
    for i = 1, len do
        total = total + items[i]
    end
    return total / len
end

--- get first element
--- @return any first element or nil
function luna:first()
    local items = self:totable()
    return items[1]
end

--- get last element
--- @return any last element or nil
function luna:last()
    local items = self:totable()
    return items[#items]
end

--- check if any element matches predicate
--- @param predicate function(value) -> boolean
--- @return boolean true if any match
function luna:any(predicate)
    local items = self:totable()
    for i = 1, #items do
        if predicate(items[i]) then
            return true
        end
    end
    return false
end

--- check if all elements match predicate
--- @param predicate function(value) -> boolean
--- @return boolean true if all match
function luna:all(predicate)
    local items = self:totable()
    for i = 1, #items do
        if not predicate(items[i]) then
            return false
        end
    end
    return true
end

--- check if contains value (handles nil properly)
--- @param value any value to find
--- @return boolean true if contains
function luna:contains(value)
    local items = self:totable()
    local len = array_count(items)
    for i = 1, len do
        if items[i] == value then
            return true
        end
    end
    return false
end

return luna
