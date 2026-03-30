local M = {}

local store = require("src.core.store")
local bus = require("src.core.bus")

local registry = {}  -- id -> {type=string, alive=bool}
local nextId = {}    -- type -> next numeric suffix

-- Create an entity with a given type and optional explicit ID
-- Returns the entity ID
-- entities.create("ship") -> "ship_1"
-- entities.create("ship", "player_ship") -> "player_ship"
function M.create(entityType, explicitId)
    local id
    if explicitId then
        if registry[explicitId] then
            error("entities.create: ID already exists: " .. explicitId)
        end
        id = explicitId
    else
        if not nextId[entityType] then
            nextId[entityType] = 1
        end
        id = entityType .. "_" .. nextId[entityType]
        nextId[entityType] = nextId[entityType] + 1
    end

    registry[id] = {
        type = entityType,
        alive = true,
    }

    bus.emit({
        type = "entity.created",
        source = id,
        data = { entityType = entityType },
    })

    return id
end

-- Destroy an entity
function M.destroy(id)
    if not registry[id] then return end

    registry[id].alive = false

    bus.emit({
        type = "entity.destroyed",
        source = id,
        data = { entityType = registry[id].type },
    })

    store.removeEntity(id)
    registry[id] = nil
end

-- Check if an entity exists and is alive
function M.exists(id)
    return registry[id] ~= nil and registry[id].alive
end

-- Get an entity's type
function M.getType(id)
    local entry = registry[id]
    if entry then return entry.type end
    return nil
end

-- Get all entity IDs
function M.all()
    local result = {}
    for id, entry in pairs(registry) do
        if entry.alive then
            table.insert(result, id)
        end
    end
    return result
end

-- Get all entity IDs of a given type
function M.allOfType(entityType)
    local result = {}
    for id, entry in pairs(registry) do
        if entry.alive and entry.type == entityType then
            table.insert(result, id)
        end
    end
    return result
end

-- Clear all entities
function M.clear()
    -- Remove all entity data from store
    for id, _ in pairs(registry) do
        store.removeEntity(id)
    end
    registry = {}
    nextId = {}
end

return M
