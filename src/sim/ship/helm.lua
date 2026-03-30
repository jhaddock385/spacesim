local M = {}

local store = require("src.core.store")
local bus = require("src.core.bus")

local THRUST_FORCE_PER_PIP = 50.0    -- forward force per pip on main thruster
local TORQUE_PER_PIP = 2.0           -- rotational torque per pip on turning thruster

-- Tick: read thruster power allocations, emit force/torque events
-- This runs each physics step, translating power state into physics forces
function M.tick(dt)
    local entities = store.entitiesWithComponent("engineering")

    for _, id in ipairs(entities) do
        local eng = store.getComponent(id, "engineering")
        if not eng then goto continue end

        -- Main thruster -> forward force along heading
        local mainPips = eng.thruster_main or 0
        if mainPips > 0 then
            bus.emit({
                type = "spatial.thrust",
                target = id,
                data = { force = mainPips * THRUST_FORCE_PER_PIP * dt },
            })
        end

        -- Port thruster fires on port side -> ship rotates clockwise (starboard)
        -- Starboard thruster fires on starboard side -> ship rotates counter-clockwise (port)
        local portPips = eng.thruster_port or 0
        local starboardPips = eng.thruster_starboard or 0
        local netTorque = (portPips - starboardPips) * TORQUE_PER_PIP * dt

        if netTorque ~= 0 then
            bus.emit({
                type = "spatial.torque",
                target = id,
                data = { torque = netTorque },
            })
        end

        ::continue::
    end
end

return M
