local M = {}

local store = require("src.core.store")
local bus = require("src.core.bus")

local PIP_GEN_RATE = 2.0       -- pips generated per second
local MAX_PIP_POOL = 10        -- maximum pips in the unallocated pool

-- Initialize engineering components for a ship entity
function M.init(entityId)
    store.set(entityId, "engineering", "pip_pool", MAX_PIP_POOL)
    store.set(entityId, "engineering", "pip_gen_rate", PIP_GEN_RATE)
    store.set(entityId, "engineering", "max_pip_pool", MAX_PIP_POOL)
    store.set(entityId, "engineering", "pip_gen_accumulator", 0)

    -- Thruster allocations (pips assigned to each)
    store.set(entityId, "engineering", "thruster_main", 0)
    store.set(entityId, "engineering", "thruster_port", 0)
    store.set(entityId, "engineering", "thruster_starboard", 0)
end

-- Handle pip allocation request: move a pip from pool to a thruster
local function handleAllocatePip(event)
    local id = event.target
    if not id then return end

    local eng = store.getComponent(id, "engineering")
    if not eng then return end

    local thruster = event.data and event.data.thruster
    if not thruster then return end

    local key = "thruster_" .. thruster
    if eng[key] == nil then return end  -- invalid thruster name

    if eng.pip_pool <= 0 then
        bus.emit({
            type = "engineering.allocate.failed",
            source = id,
            data = { thruster = thruster, reason = "no pips available" },
        })
        return
    end

    store.set(id, "engineering", "pip_pool", eng.pip_pool - 1)
    store.set(id, "engineering", key, eng[key] + 1)

    bus.emit({
        type = "engineering.pip.allocated",
        source = id,
        data = { thruster = thruster, amount = eng[key] + 1, pool = eng.pip_pool - 1 },
    })
end

-- Handle pip deallocation request: move a pip from a thruster back to pool
local function handleDeallocatePip(event)
    local id = event.target
    if not id then return end

    local eng = store.getComponent(id, "engineering")
    if not eng then return end

    local thruster = event.data and event.data.thruster
    if not thruster then return end

    local key = "thruster_" .. thruster
    if eng[key] == nil then return end

    if eng[key] <= 0 then
        bus.emit({
            type = "engineering.deallocate.failed",
            source = id,
            data = { thruster = thruster, reason = "no pips allocated" },
        })
        return
    end

    local newPool = math.min(eng.pip_pool + 1, eng.max_pip_pool)
    store.set(id, "engineering", key, eng[key] - 1)
    store.set(id, "engineering", "pip_pool", newPool)

    bus.emit({
        type = "engineering.pip.deallocated",
        source = id,
        data = { thruster = thruster, amount = eng[key] - 1, pool = newPool },
    })
end

-- Subscribe to bus events
function M.setup()
    bus.subscribe("engineering.allocate", handleAllocatePip)
    bus.subscribe("engineering.deallocate", handleDeallocatePip)
end

-- Tick: generate pips over time
function M.tick(dt)
    local entities = store.entitiesWithComponent("engineering")

    for _, id in ipairs(entities) do
        local eng = store.getComponent(id, "engineering")
        if eng then
            local acc = eng.pip_gen_accumulator + eng.pip_gen_rate * dt
            while acc >= 1.0 and eng.pip_pool < eng.max_pip_pool do
                acc = acc - 1.0
                eng.pip_pool = eng.pip_pool + 1
                store.set(id, "engineering", "pip_pool", eng.pip_pool)

                bus.emit({
                    type = "engineering.pip.generated",
                    source = id,
                    data = { pool = eng.pip_pool },
                })
            end
            -- Clamp accumulator if pool is full
            if eng.pip_pool >= eng.max_pip_pool then
                acc = 0
            end
            store.set(id, "engineering", "pip_gen_accumulator", acc)
        end
    end
end

return M
