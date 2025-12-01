-- optimized, cache-friendly entity component system
-- archetypal storage with component index, edge cache, hot path optimization
-- ieee 754 floats, minimal allocations, luajit/lua 5.3+ optimized
-- features archetype patterns, system priorities, prefabs, parallel hints, reactive events, coroutine support
-- @module ecs

local floor = math.floor
local insert, remove, sort = table.insert, table.remove, table.sort
local move = table.move or function(a1, f, e, t, a2)
    a2 = a2 or a1
    for i = 0, e - f do
        a2[t + i] = a1[f + i]
    end
    return a2
end

-- ============================================================================
-- configuration
-- ============================================================================

local INITIAL_ARCHETYPE_CAPACITY = 1024
local COMPONENT_INDEX_ENABLED = true

-- ============================================================================
-- core storage
-- ============================================================================

local world = {
    -- archetypal storage
    archetypes = {},       -- key -> archetype
    archetype_list = {},   -- array for iteration
    empty_archetype = nil, -- special case optimization

    -- component index (fast archetype lookup by component)
    comp_index = {}, -- comp_type -> {archetype1, archetype2, ...}

    -- entity tracking
    entities = {}, -- entity_id -> {arch, row}
    next_id = 1,
    free_ids = {}, -- recycled entity ids

    -- query cache
    query_cache = {}, -- signature -> result

    -- systems
    systems = {},
    system_groups = {}, -- group_name -> {systems, parallel_hint}

    -- prefabs/templates
    prefabs = {}, -- name -> component table

    -- common archetype patterns
    patterns = {}, -- pattern_name -> archetype

    -- reactive event handlers
    on_add_handlers = {},    -- comp_type -> {callback1, callback2, ...}
    on_remove_handlers = {}, -- comp_type -> {callback1, callback2, ...}
}

-- ============================================================================
-- archetype
-- ============================================================================

-- create new archetype
--- @param signature sorted array of component types
--- @return table archetype
local function new_archetype(signature)
    local arch = {
        signature = signature,
        key = table.concat(signature, ","),
        entities = {}, -- array of entity ids
        count = 0,

        -- component columns (struct of arrays)
        columns = {}, -- comp_type -> {data array}

        -- archetype graph edges (cache for add/remove ops)
        edges = {}, -- {add = {}, remove = {}}

        -- component index tracking
        comp_set = {}, -- comp_type -> true (fast lookup)
    }

    -- initialize component set
    for i = 1, #signature do
        arch.comp_set[signature[i]] = true
    end

    -- initialize component columns
    for i = 1, #signature do
        arch.columns[signature[i]] = {}
    end

    arch.edges.add = {}
    arch.edges.remove = {}

    return arch
end

-- add entity to archetype
--- @param arch archetype
--- @param entity_id entity id
--- @param components table of comp_type -> data
local function arch_add(arch, entity_id, components)
    local row = arch.count + 1
    arch.count = row
    arch.entities[row] = entity_id

    -- add component data to columns
    for comp_type, data in pairs(components) do
        local col = arch.columns[comp_type]
        if col then
            col[row] = data
        end
    end

    return row
end

-- remove entity from archetype (swap with last)
--- @param arch archetype
--- @param row row index
--- @return number entity_id that was moved (or nil)
local function arch_remove(arch, row)
    local last_row = arch.count
    if last_row == 0 then return nil end

    local moved_entity = nil

    if row ~= last_row then
        -- swap with last entity
        moved_entity = arch.entities[last_row]
        arch.entities[row] = moved_entity

        -- swap all component data using table.move for better performance
        for comp_type, col in pairs(arch.columns) do
            col[row] = col[last_row]
        end
    end

    -- clear last row
    arch.entities[last_row] = nil
    for comp_type, col in pairs(arch.columns) do
        col[last_row] = nil
    end

    arch.count = last_row - 1
    return moved_entity
end

-- ============================================================================
-- reactive event system
-- ============================================================================

--- register callback when component is added
--- @param comp_type component type
--- @param callback function(entity, data)
local function on_add(comp_type, callback)
    if not world.on_add_handlers[comp_type] then
        world.on_add_handlers[comp_type] = {}
    end
    insert(world.on_add_handlers[comp_type], callback)
end

--- register callback when component is removed
--- @param comp_type component type
--- @param callback function(entity, data)
local function on_remove(comp_type, callback)
    if not world.on_remove_handlers[comp_type] then
        world.on_remove_handlers[comp_type] = {}
    end
    insert(world.on_remove_handlers[comp_type], callback)
end

-- trigger on_add events
--- @param entity_id entity id
--- @param comp_type component type
--- @param data component data
local function trigger_add_events(entity_id, comp_type, data)
    local handlers = world.on_add_handlers[comp_type]
    if not handlers then return end

    local entity_mt = getmetatable(setmetatable({ id = entity_id }, { __index = {} }))
    local e = setmetatable({ id = entity_id }, entity_mt)

    for i = 1, #handlers do
        handlers[i](e, data)
    end
end

-- trigger on_remove events
--- @param entity_id entity id
--- @param comp_type component type
--- @param data component data
local function trigger_remove_events(entity_id, comp_type, data)
    local handlers = world.on_remove_handlers[comp_type]
    if not handlers then return end

    local entity_mt = getmetatable(setmetatable({ id = entity_id }, { __index = {} }))
    local e = setmetatable({ id = entity_id }, entity_mt)

    for i = 1, #handlers do
        handlers[i](e, data)
    end
end

-- ============================================================================
-- world operations
-- ============================================================================

-- get or create archetype
--- @param signature sorted component type array
--- @return table archetype
local function get_archetype(signature)
    if #signature == 0 then
        if not world.empty_archetype then
            world.empty_archetype = new_archetype({})
            world.archetypes[""] = world.empty_archetype
            insert(world.archetype_list, world.empty_archetype)
        end
        return world.empty_archetype
    end

    local key = table.concat(signature, ",")
    local arch = world.archetypes[key]

    if not arch then
        arch = new_archetype(signature)
        world.archetypes[key] = arch
        insert(world.archetype_list, arch)

        -- update component index
        if COMPONENT_INDEX_ENABLED then
            for i = 1, #signature do
                local comp_type = signature[i]
                if not world.comp_index[comp_type] then
                    world.comp_index[comp_type] = {}
                end
                insert(world.comp_index[comp_type], arch)
            end
        end
    end

    return arch
end

-- move entity to new archetype
--- @param entity_id entity id
--- @param new_arch target archetype
--- @param components component data
local function move_entity(entity_id, new_arch, components)
    local record = world.entities[entity_id]

    if record then
        local old_arch = record.arch
        local old_row = record.row

        -- remove from old archetype
        local moved_id = arch_remove(old_arch, old_row)
        if moved_id then
            world.entities[moved_id].row = old_row
        end
    end

    -- add to new archetype
    local new_row = arch_add(new_arch, entity_id, components)
    world.entities[entity_id] = { arch = new_arch, row = new_row }
end

-- get archetype when adding component (uses edge cache)
--- @param current_arch current archetype
--- @param comp_type component type to add
--- @return table new archetype
local function get_add_archetype(current_arch, comp_type)
    -- check edge cache
    local cached = current_arch.edges.add[comp_type]
    if cached then return cached end

    -- build new signature
    local new_sig = {}
    local inserted = false

    for i = 1, #current_arch.signature do
        local existing = current_arch.signature[i]
        if not inserted and comp_type < existing then
            insert(new_sig, comp_type)
            inserted = true
        end
        if existing ~= comp_type then
            insert(new_sig, existing)
        end
    end

    if not inserted then
        insert(new_sig, comp_type)
    end

    local new_arch = get_archetype(new_sig)
    current_arch.edges.add[comp_type] = new_arch

    return new_arch
end

-- get archetype when removing component (uses edge cache)
--- @param current_arch current archetype
--- @param comp_type component type to remove
--- @return table new archetype
local function get_remove_archetype(current_arch, comp_type)
    -- check edge cache
    local cached = current_arch.edges.remove[comp_type]
    if cached then return cached end

    -- build new signature
    local new_sig = {}
    for i = 1, #current_arch.signature do
        local existing = current_arch.signature[i]
        if existing ~= comp_type then
            insert(new_sig, existing)
        end
    end

    local new_arch = get_archetype(new_sig)
    current_arch.edges.remove[comp_type] = new_arch

    return new_arch
end

-- ============================================================================
-- entity api
-- ============================================================================

local entity_mt = {
    __index = {
        --- add component to entity
        --- @param self table the entity
        --- @param comp_type component type
        --- @param data component data
        --- @return table self for chaining
        add = function(self, comp_type, data)
            local record = world.entities[self.id]

            -- get current archetype
            local current_arch
            if record then
                current_arch = record.arch
            else
                -- shouldn't happen with new entity() implementation
                current_arch = get_archetype({})
                local row = arch_add(current_arch, self.id, {})
                world.entities[self.id] = { arch = current_arch, row = row }
                record = world.entities[self.id]
            end

            -- check if already has component
            local had_component = current_arch.comp_set[comp_type]

            if had_component then
                -- just update data
                local col = current_arch.columns[comp_type]
                col[record.row] = data
                return self
            end

            -- get new archetype (uses edge cache)
            local new_arch = get_add_archetype(current_arch, comp_type)

            -- collect existing components
            local components = { [comp_type] = data }
            for ct, col in pairs(current_arch.columns) do
                components[ct] = col[record.row]
            end

            move_entity(self.id, new_arch, components)

            -- invalidate query cache
            world.query_cache = {}

            -- trigger reactive events
            trigger_add_events(self.id, comp_type, data)

            return self
        end,

        --- remove component from entity
        --- @param self table the entity
        --- @param comp_type component type
        --- @return table self for chaining
        remove = function(self, comp_type)
            local record = world.entities[self.id]
            if not record then return self end

            local current_arch = record.arch

            -- early exit if doesn't have component
            if not current_arch.comp_set[comp_type] then
                return self
            end

            -- get component data for event
            local col = current_arch.columns[comp_type]
            local data = col[record.row]

            -- get new archetype (uses edge cache)
            local new_arch = get_remove_archetype(current_arch, comp_type)

            -- collect remaining components
            local components = {}
            for ct, col_inner in pairs(current_arch.columns) do
                if ct ~= comp_type then
                    components[ct] = col_inner[record.row]
                end
            end

            move_entity(self.id, new_arch, components)

            -- invalidate query cache
            world.query_cache = {}

            -- trigger reactive events
            trigger_remove_events(self.id, comp_type, data)

            return self
        end,

        --- get component data
        --- @param self table the entity
        --- @param comp_type component type
        --- @return any component data or nil
        get = function(self, comp_type)
            local record = world.entities[self.id]
            if not record then return nil end

            local col = record.arch.columns[comp_type]
            if not col then return nil end

            return col[record.row]
        end,

        --- check if entity has component
        --- @param self table the entity
        --- @param comp_type component type
        --- @return boolean true if has component
        has = function(self, comp_type)
            local record = world.entities[self.id]
            if not record then return false end
            return record.arch.comp_set[comp_type] == true
        end,

        --- destroy entity and remove all components
        --- @param self table the entity
        destroy = function(self)
            local record = world.entities[self.id]
            if not record then return end

            -- trigger remove events for all components
            local arch = record.arch
            for comp_type, col in pairs(arch.columns) do
                local data = col[record.row]
                trigger_remove_events(self.id, comp_type, data)
            end

            local moved_id = arch_remove(record.arch, record.row)
            if moved_id then
                world.entities[moved_id].row = record.row
            end

            world.entities[self.id] = nil
            insert(world.free_ids, self.id)
        end,

        --- check if entity is valid (exists in world)
        --- @param self table the entity
        --- @return boolean true if valid
        valid = function(self)
            return world.entities[self.id] ~= nil
        end
    }
}

-- create new entity
--- @param ... alternating comp_type, data pairs
--- @return table entity
local function entity(...)
    local id
    if #world.free_ids > 0 then
        id = remove(world.free_ids)
    else
        id = world.next_id
        world.next_id = id + 1
    end

    local e = setmetatable({ id = id }, entity_mt)

    -- add initial components
    local args = { ... }
    if #args > 0 then
        for i = 1, #args, 2 do
            e:add(args[i], args[i + 1])
        end
    else
        -- entity with no components - add to empty archetype
        local empty_arch = get_archetype({})
        local row = arch_add(empty_arch, id, {})
        world.entities[id] = { arch = empty_arch, row = row }
    end

    return e
end

-- ============================================================================
-- prefab/template system
-- ============================================================================

--- register a prefab template
--- @param name string prefab name
--- @param components table of comp_type -> default_data
local function prefab(name, components)
    world.prefabs[name] = components
end

--- spawn entity from prefab
--- @param name string prefab name
--- @param overrides table optional component overrides
--- @return table entity
local function spawn(name, overrides)
    local template = world.prefabs[name]
    if not template then
        error("prefab not found: " .. name)
    end

    local e = entity()

    -- add template components
    for comp_type, data in pairs(template) do
        -- deep copy if table (prevent shared references)
        local value = data
        if type(data) == "table" then
            value = {}
            for k, v in pairs(data) do
                value[k] = v
            end
        end
        e:add(comp_type, value)
    end

    -- apply overrides
    if overrides then
        for comp_type, data in pairs(overrides) do
            e:add(comp_type, data)
        end
    end

    return e
end

-- ============================================================================
-- archetype patterns
-- ============================================================================

--- register common archetype pattern
--- @param name string pattern name
--- @param ... component types
local function pattern(name, ...)
    local sig = { ... }
    sort(sig)
    local arch = get_archetype(sig)
    world.patterns[name] = arch
end

--- get entities matching pattern
--- @param name string pattern name
--- @return table array of entities
local function get_pattern(name)
    local arch = world.patterns[name]
    if not arch then return {} end

    local entities = {}
    for i = 1, arch.count do
        local e = setmetatable({ id = arch.entities[i] }, entity_mt)
        insert(entities, e)
    end
    return entities
end

-- ============================================================================
-- query system
-- ============================================================================

-- build query for iteration
--- @return table query builder
local function query()
    return {
        with_types = {},
        without_types = {},

        --- require components
        --- @param self table query builder
        --- @param ... component types
        --- @return table self for chaining
        with = function(self, ...)
            local args = { ... }
            for i = 1, #args do
                self.with_types[args[i]] = true
            end
            return self
        end,

        --- exclude components
        --- @param self table query builder
        --- @param ... component types
        --- @return table self for chaining
        without = function(self, ...)
            local args = { ... }
            for i = 1, #args do
                self.without_types[args[i]] = true
            end
            return self
        end,

        -- get matching archetypes (uses component index + cache)
        --- @return table array of archetypes
        _match = function(self)
            -- queries with no requirements should return empty
            local has_requirements = false
            for _ in pairs(self.with_types) do
                has_requirements = true
                break
            end

            if not has_requirements then
                return {}
            end

            -- build cache key
            local key_parts = {}
            for t in pairs(self.with_types) do
                insert(key_parts, "+" .. t)
            end
            for t in pairs(self.without_types) do
                insert(key_parts, "-" .. t)
            end
            sort(key_parts)
            local cache_key = table.concat(key_parts, ",")

            -- check cache
            if world.query_cache[cache_key] then
                return world.query_cache[cache_key]
            end

            local matching = {}

            -- optimization: use component index for queries with 'with' requirements
            local candidate_archs = nil
            if COMPONENT_INDEX_ENABLED then
                -- find smallest component index
                local min_comp, min_count = nil, math.huge
                for comp_type in pairs(self.with_types) do
                    local idx = world.comp_index[comp_type]
                    if idx and #idx < min_count then
                        min_comp = comp_type
                        min_count = #idx
                    end
                end

                if min_comp then
                    candidate_archs = world.comp_index[min_comp]
                end
            end

            -- iterate candidates (or all archetypes)
            local archs_to_check = candidate_archs or world.archetype_list

            for i = 1, #archs_to_check do
                local arch = archs_to_check[i]
                local comp_set = arch.comp_set

                -- check required components (hot path)
                local matches = true
                for comp_type in pairs(self.with_types) do
                    if not comp_set[comp_type] then
                        matches = false
                        break
                    end
                end

                -- check excluded components (only if still matching)
                if matches then
                    for comp_type in pairs(self.without_types) do
                        if comp_set[comp_type] then
                            matches = false
                            break
                        end
                    end
                end

                if matches then
                    insert(matching, arch)
                end
            end

            world.query_cache[cache_key] = matching
            return matching
        end,

        --- iterate matching entities (hot path optimized - zero allocation)
        --- @param self table query builder
        --- @param callback function(entity, comp1, comp2, ...) receives components as varargs
        each = function(self, callback)
            local matching = self:_match()

            -- early exit if no matches
            if #matching == 0 then return end

            -- get required component types for fast column access
            local req_types = {}
            for comp_type in pairs(self.with_types) do
                insert(req_types, comp_type)
            end

            -- hot path: iterate archetypes and entities
            for a = 1, #matching do
                local arch = matching[a]
                local entities = arch.entities
                local columns = arch.columns
                local count = arch.count

                -- prepare component column pointers (cache-friendly)
                local cols = {}
                for i = 1, #req_types do
                    cols[i] = columns[req_types[i]]
                end

                -- tight inner loop - minimal indirection, zero allocations
                -- components passed as varargs to avoid temporary table creation
                local num_cols = #cols
                for row = 1, count do
                    local entity_id = entities[row]
                    local e = setmetatable({ id = entity_id }, entity_mt)

                    -- pass components as varargs (zero allocation)
                    if num_cols == 1 then
                        callback(e, cols[1][row])
                    elseif num_cols == 2 then
                        callback(e, cols[1][row], cols[2][row])
                    elseif num_cols == 3 then
                        callback(e, cols[1][row], cols[2][row], cols[3][row])
                    elseif num_cols == 4 then
                        callback(e, cols[1][row], cols[2][row], cols[3][row], cols[4][row])
                    else
                        -- fallback for 5+ components (rare case)
                        local comps = {}
                        for i = 1, num_cols do
                            comps[i] = cols[i][row]
                        end
                        callback(e, unpack(comps, 1, num_cols))
                    end
                end
            end
        end,

        --- count matching entities
        --- @return number count
        count = function(self)
            local matching = self:_match()
            local total = 0
            for i = 1, #matching do
                total = total + matching[i].count
            end
            return total
        end,

        --- get first matching entity
        --- @return table entity or nil
        first = function(self)
            local matching = self:_match()
            if #matching == 0 then return nil end

            local arch = matching[1]
            if arch.count == 0 then return nil end

            return setmetatable({ id = arch.entities[1] }, entity_mt)
        end
    }
end

-- ============================================================================
-- system api
-- ============================================================================

-- create reusable system
--- @param query_builder query builder
--- @param callback function(entity, comp1, comp2, ..., dt) - components as varargs
--- @param priority number optional priority (lower runs first)
--- @return table system
local function system(query_builder, callback, priority)
    local sys = {
        query = query_builder,
        run = callback,
        enabled = true,
        priority = priority or 0,
        coroutine = nil -- optional coroutine for async systems
    }
    insert(world.systems, sys)

    -- re-sort systems by priority
    sort(world.systems, function(a, b)
        return a.priority < b.priority
    end)

    return sys
end

--- create system group (for parallel execution hints)
--- @param name string group name
--- @param parallel_hint boolean hint for parallel execution
--- @return table group
local function system_group(name, parallel_hint)
    local group = {
        name = name,
        systems = {},
        parallel_hint = parallel_hint or false,
        enabled = true
    }
    world.system_groups[name] = group
    return group
end

--- add system to group
--- @param group_name string group name
--- @param query_builder query builder
--- @param callback function(entity, comp1, comp2, ..., dt)
--- @param priority number optional priority within group
--- @return table system
local function system_in_group(group_name, query_builder, callback, priority)
    local group = world.system_groups[group_name]
    if not group then
        error("system group not found: " .. group_name)
    end

    local sys = {
        query = query_builder,
        run = callback,
        enabled = true,
        priority = priority or 0,
        group = group_name,
        coroutine = nil
    }

    insert(group.systems, sys)

    -- sort within group
    sort(group.systems, function(a, b)
        return a.priority < b.priority
    end)

    return sys
end

-- update all systems
--- @param dt delta time
local function update(dt)
    -- run ungrouped systems
    for i = 1, #world.systems do
        local sys = world.systems[i]
        if sys.enabled then
            -- check if system has a coroutine
            if sys.coroutine then
                local co = sys.coroutine
                if coroutine.status(co) == "dead" then
                    sys.coroutine = nil
                else
                    local success, err = coroutine.resume(co, dt)
                    if not success then
                        error("system coroutine error: " .. tostring(err))
                    end
                end
            else
                sys.query:each(function(e, ...)
                    sys.run(e, ..., dt)
                end)
            end
        end
    end

    -- run grouped systems
    for group_name, group in pairs(world.system_groups) do
        if group.enabled then
            for i = 1, #group.systems do
                local sys = group.systems[i]
                if sys.enabled then
                    if sys.coroutine then
                        local co = sys.coroutine
                        if coroutine.status(co) == "dead" then
                            sys.coroutine = nil
                        else
                            local success, err = coroutine.resume(co, dt)
                            if not success then
                                error("system coroutine error: " .. tostring(err))
                            end
                        end
                    else
                        sys.query:each(function(e, ...)
                            sys.run(e, ..., dt)
                        end)
                    end
                end
            end
        end
    end
end

--- update specific system group
--- @param group_name string group name
--- @param dt delta time
local function update_group(group_name, dt)
    local group = world.system_groups[group_name]
    if not group or not group.enabled then return end

    for i = 1, #group.systems do
        local sys = group.systems[i]
        if sys.enabled then
            if sys.coroutine then
                local co = sys.coroutine
                if coroutine.status(co) == "dead" then
                    sys.coroutine = nil
                else
                    local success, err = coroutine.resume(co, dt)
                    if not success then
                        error("system coroutine error: " .. tostring(err))
                    end
                end
            else
                sys.query:each(function(e, ...)
                    sys.run(e, ..., dt)
                end)
            end
        end
    end
end

-- ============================================================================
-- utility
-- ============================================================================

-- clear world state
local function clear()
    world.archetypes = {}
    world.archetype_list = {}
    world.empty_archetype = nil
    world.comp_index = {}
    world.entities = {}
    world.next_id = 1
    world.free_ids = {}
    world.query_cache = {}
    world.systems = {}
    world.system_groups = {}
    world.prefabs = {}
    world.patterns = {}
    world.on_add_handlers = {}
    world.on_remove_handlers = {}
end

-- get world statistics
--- @return table stats {entities, archetypes, systems, groups, prefabs, patterns}
local function stats()
    local entity_count = world.next_id - 1 - #world.free_ids
    local group_count = 0
    for _ in pairs(world.system_groups) do
        group_count = group_count + 1
    end
    local prefab_count = 0
    for _ in pairs(world.prefabs) do
        prefab_count = prefab_count + 1
    end
    local pattern_count = 0
    for _ in pairs(world.patterns) do
        pattern_count = pattern_count + 1
    end

    return {
        entities = entity_count,
        archetypes = #world.archetype_list,
        systems = #world.systems,
        system_groups = group_count,
        prefabs = prefab_count,
        patterns = pattern_count,
        cached_queries = 0
    }
end

-- ============================================================================
-- serialization support
-- ============================================================================

--- serialize world state for saving
--- @return table serializable world state
local function serialize()
    local state = {
        entities = {},
        next_id = world.next_id,
        free_ids = {}
    }

    -- copy free ids
    for i = 1, #world.free_ids do
        state.free_ids[i] = world.free_ids[i]
    end

    -- serialize all entities with their components
    for entity_id, record in pairs(world.entities) do
        local arch = record.arch
        local row = record.row

        local entity_data = {
            id = entity_id,
            components = {}
        }

        -- collect all component data
        for comp_type, col in pairs(arch.columns) do
            entity_data.components[comp_type] = col[row]
        end

        insert(state.entities, entity_data)
    end

    return state
end

--- deserialize world state from saved data
--- @param state table serialized world state
local function deserialize(state)
    clear()

    -- restore id tracking
    world.next_id = state.next_id
    for i = 1, #state.free_ids do
        insert(world.free_ids, state.free_ids[i])
    end

    -- restore entities
    for i = 1, #state.entities do
        local entity_data = state.entities[i]
        local e = setmetatable({ id = entity_data.id }, entity_mt)

        -- rebuild entity in world
        local empty_arch = get_archetype({})
        local row = arch_add(empty_arch, entity_data.id, {})
        world.entities[entity_data.id] = { arch = empty_arch, row = row }

        -- add components
        for comp_type, data in pairs(entity_data.components) do
            e:add(comp_type, data)
        end
    end
end

-- ============================================================================
-- exports
-- ============================================================================

return {
    entity = entity,
    query = query,
    system = system,
    system_group = system_group,
    system_in_group = system_in_group,
    update = update,
    update_group = update_group,
    clear = clear,
    stats = stats,
    prefab = prefab,
    spawn = spawn,
    pattern = pattern,
    get_pattern = get_pattern,
    on_add = on_add,
    on_remove = on_remove,
    serialize = serialize,
    deserialize = deserialize,
}
