local M = {}

local store = require("src.core.store")
local bus = require("src.core.bus")

local VELOCITY_DAMPING = 0.995    -- per-tick multiplier, settles slowly
local ROTATION_DAMPING = 0.98     -- per-tick multiplier, rotation settles faster

-- Initialize spatial components for an entity
-- Sets up position, velocity, rotation, and physics properties in the store
function M.init(entityId, config)
    config = config or {}
    store.set(entityId, "spatial", "x", config.x or 0)
    store.set(entityId, "spatial", "y", config.y or 0)
    store.set(entityId, "spatial", "vx", config.vx or 0)
    store.set(entityId, "spatial", "vy", config.vy or 0)
    store.set(entityId, "spatial", "rotation", config.rotation or 0)  -- radians
    store.set(entityId, "spatial", "rotVel", config.rotVel or 0)      -- radians/sec
    store.set(entityId, "spatial", "mass", config.mass or 1)
end

-- Apply a force along the entity's current heading
local function handleThrust(event)
    local id = event.target
    if not id then return end

    local spatial = store.getComponent(id, "spatial")
    if not spatial then return end

    local force = event.data and event.data.force or 0
    if force == 0 then return end

    local rotation = spatial.rotation
    local mass = spatial.mass

    -- Force along heading -> acceleration
    local ax = math.cos(rotation) * force / mass
    local ay = math.sin(rotation) * force / mass

    store.set(id, "spatial", "vx", spatial.vx + ax)
    store.set(id, "spatial", "vy", spatial.vy + ay)
end

-- Apply rotational torque
local function handleTorque(event)
    local id = event.target
    if not id then return end

    local spatial = store.getComponent(id, "spatial")
    if not spatial then return end

    local torque = event.data and event.data.torque or 0
    if torque == 0 then return end

    local mass = spatial.mass
    store.set(id, "spatial", "rotVel", spatial.rotVel + torque / mass)
end

-- Subscribe to physics events
function M.setup()
    bus.subscribe("spatial.thrust", handleThrust)
    bus.subscribe("spatial.torque", handleTorque)
end

-- Integrate physics for all spatial entities over one fixed timestep
function M.tick(dt)
    local entities = store.entitiesWithComponent("spatial")

    for _, id in ipairs(entities) do
        local s = store.getComponent(id, "spatial")
        if s then
            -- Integrate rotation
            local rotVel = s.rotVel * ROTATION_DAMPING
            local rotation = s.rotation + rotVel * dt

            -- Normalize rotation to [0, 2pi)
            rotation = rotation % (2 * math.pi)

            -- Integrate position
            local vx = s.vx * VELOCITY_DAMPING
            local vy = s.vy * VELOCITY_DAMPING
            local x = s.x + vx * dt
            local y = s.y + vy * dt

            store.set(id, "spatial", "x", x)
            store.set(id, "spatial", "y", y)
            store.set(id, "spatial", "vx", vx)
            store.set(id, "spatial", "vy", vy)
            store.set(id, "spatial", "rotation", rotation)
            store.set(id, "spatial", "rotVel", rotVel)
        end
    end
end

return M
