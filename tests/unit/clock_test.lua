local runner = require("tests.runner")
local clock = require("src.core.clock")
local M = {}

function M.setup()
    runner.resetSim()
end

function M.teardown()
    runner.resetSim()
end

function M.testFixedTimestep()
    local ticks = 0
    clock.accumulate(1 / 60)
    clock.step(function(dt)
        ticks = ticks + 1
        runner.assertInRange(1/60 - 0.001, 1/60 + 0.001, dt, "dt should be fixed")
    end)
    runner.assertEqual(1, ticks, "should tick once for one frame")
end

function M.testMultipleSteps()
    local ticks = 0
    clock.accumulate(3 / 60)  -- 3 frames worth
    clock.step(function(dt)
        ticks = ticks + 1
    end)
    runner.assertEqual(3, ticks, "should tick 3 times")
end

function M.testNoTickWhenFrozen()
    local ticks = 0
    clock.freeze("test")
    clock.accumulate(1 / 60)
    clock.step(function(dt)
        ticks = ticks + 1
    end)
    runner.assertEqual(0, ticks, "should not tick when frozen")
end

function M.testUnfreezeDiscardsAccumulated()
    clock.freeze("test")
    clock.accumulate(10)  -- lots of time
    clock.unfreeze()

    local ticks = 0
    clock.step(function(dt)
        ticks = ticks + 1
    end)
    runner.assertEqual(0, ticks, "should discard accumulated time on unfreeze")
end

function M.testFreezeReason()
    clock.freeze("player")
    runner.assert(clock.isFrozen())
    runner.assertEqual("player", clock.getFreezeReason())

    clock.unfreeze()
    runner.assert(not clock.isFrozen())
    runner.assertNil(clock.getFreezeReason())
end

function M.testSimTime()
    runner.assertEqual(0, clock.getSimTime())
    clock.accumulate(2 / 60)
    clock.step(function() end)
    runner.assertGreaterThan(0, clock.getSimTime())
end

function M.testTimeScale()
    clock.setTimeScale(2.0)
    local ticks = 0
    clock.accumulate(1 / 60)  -- at 2x, this should produce 2 ticks
    clock.step(function() ticks = ticks + 1 end)
    runner.assertEqual(2, ticks, "2x time scale should double ticks")
end

return M
