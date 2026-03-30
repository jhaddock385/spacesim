local M = {}

local partitions = {}  -- entityId -> {component -> {key -> value}}

-- Set a value in the store
-- store.set("ship_1", "spatial", "x", 100)
-- store.set("ship_1", "engineering", "pip_pool", 5)
function M.set(entityId, component, key, value)
    if not partitions[entityId] then
        partitions[entityId] = {}
    end
    if not partitions[entityId][component] then
        partitions[entityId][component] = {}
    end
    partitions[entityId][component][key] = value
end

-- Get a value from the store
-- store.get("ship_1", "spatial", "x") -> 100
function M.get(entityId, component, key)
    local entity = partitions[entityId]
    if not entity then return nil end
    local comp = entity[component]
    if not comp then return nil end
    return comp[key]
end

-- Get an entire component table (read-only intent, but Lua won't enforce)
-- store.getComponent("ship_1", "spatial") -> {x=100, y=200, ...}
function M.getComponent(entityId, component)
    local entity = partitions[entityId]
    if not entity then return nil end
    return entity[component]
end

-- Get all components for an entity
-- store.getEntity("ship_1") -> {spatial={...}, engineering={...}, ...}
function M.getEntity(entityId)
    return partitions[entityId]
end

-- Check if an entity exists in the store
function M.hasEntity(entityId)
    return partitions[entityId] ~= nil
end

-- Remove an entire entity from the store
function M.removeEntity(entityId)
    partitions[entityId] = nil
end

-- Remove a component from an entity
function M.removeComponent(entityId, component)
    local entity = partitions[entityId]
    if entity then
        entity[component] = nil
    end
end

-- Get all entity IDs that have a given component
function M.entitiesWithComponent(component)
    local result = {}
    for entityId, entity in pairs(partitions) do
        if entity[component] then
            table.insert(result, entityId)
        end
    end
    return result
end

-- Get all entity IDs in the store
function M.allEntities()
    local result = {}
    for entityId, _ in pairs(partitions) do
        table.insert(result, entityId)
    end
    return result
end

-- Clear all state
function M.clear()
    partitions = {}
end

return M
