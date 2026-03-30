local M = {}

local accumulator = 0
local FIXED_DT = 1 / 60    -- 60 Hz physics
local simTime = 0           -- total simulation time elapsed
local frozen = false
local freezeReason = nil    -- "player", "ai", nil
local timeScale = 1.0       -- speed multiplier (1.0 = normal)

-- Accumulate real dt from love.update
-- Returns nothing; call step() to consume accumulated time
function M.accumulate(dt)
    if frozen then return end
    accumulator = accumulator + dt * timeScale
end

-- Step through accumulated time in fixed increments
-- Calls the provided tick function for each fixed step
-- tick(fixedDt) is called zero or more times
function M.step(tick)
    if frozen then return end
    while accumulator >= FIXED_DT do
        accumulator = accumulator - FIXED_DT
        simTime = simTime + FIXED_DT
        tick(FIXED_DT)
    end
end

-- Get the interpolation alpha for rendering between physics steps
-- Returns 0..1 representing how far between the last step and the next
function M.getAlpha()
    return accumulator / FIXED_DT
end

-- Freeze the simulation
-- reason: "player" or "ai" — tracked so we know why it's frozen
function M.freeze(reason)
    frozen = true
    freezeReason = reason or "unknown"
end

-- Unfreeze the simulation
function M.unfreeze()
    frozen = false
    freezeReason = nil
    accumulator = 0  -- discard accumulated time during freeze
end

-- Check if frozen
function M.isFrozen()
    return frozen
end

-- Get freeze reason
function M.getFreezeReason()
    return freezeReason
end

-- Get total simulation time
function M.getSimTime()
    return simTime
end

-- Get the fixed timestep value
function M.getFixedDt()
    return FIXED_DT
end

-- Set time scale (1.0 = normal, 2.0 = double speed, 0.5 = half)
function M.setTimeScale(scale)
    timeScale = math.max(0, scale)
end

function M.getTimeScale()
    return timeScale
end

-- Clear all state
function M.clear()
    accumulator = 0
    simTime = 0
    frozen = false
    freezeReason = nil
    timeScale = 1.0
end

return M
