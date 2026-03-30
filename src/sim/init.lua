local M = {}

local clock = require("src.core.clock")
local bus = require("src.core.bus")
local spatial = require("src.sim.spatial")
local engineering = require("src.sim.ship.engineering")
local helm = require("src.sim.ship.helm")

local initialized = false

-- Set up all simulation subsystems (subscribe to bus events)
function M.setup()
    if initialized then return end
    spatial.setup()
    engineering.setup()
    initialized = true
end

-- Called every frame from love.update(dt)
-- Accumulates time, then steps the simulation in fixed increments
function M.update(dt)
    clock.accumulate(dt)

    clock.step(function(fixedDt)
        -- 1. Subsystem ticks: engineering generates pips, helm emits forces
        engineering.tick(fixedDt)
        helm.tick(fixedDt)

        -- 2. Drain the bus: process all events from this tick
        --    (thrust/torque events from helm get picked up by spatial handlers)
        bus.drain()

        -- 3. Physics integration: move everything
        spatial.tick(fixedDt)
    end)
end

-- Clear all simulation state
function M.clear()
    bus.clear()
    initialized = false
end

return M
