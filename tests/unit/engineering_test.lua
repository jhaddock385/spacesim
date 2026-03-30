local runner = require("tests.runner")
local engineering = require("src.sim.ship.engineering")
local store = require("src.core.store")
local bus = require("src.core.bus")
local M = {}

function M.setup()
    runner.resetSim()
    engineering.setup()
    engineering.init("ship_1")
end

function M.teardown()
    runner.resetSim()
end

function M.testInitState()
    runner.assertEqual(10, store.get("ship_1", "engineering", "pip_pool"))
    runner.assertEqual(10, store.get("ship_1", "engineering", "max_pip_pool"))
    runner.assertEqual(0, store.get("ship_1", "engineering", "thruster_main"))
    runner.assertEqual(0, store.get("ship_1", "engineering", "thruster_port"))
    runner.assertEqual(0, store.get("ship_1", "engineering", "thruster_starboard"))
end

function M.testAllocatePip()
    bus.emit({
        type = "engineering.allocate",
        target = "ship_1",
        data = { thruster = "main" },
    })
    bus.drain()

    runner.assertEqual(9, store.get("ship_1", "engineering", "pip_pool"))
    runner.assertEqual(1, store.get("ship_1", "engineering", "thruster_main"))
end

function M.testDeallocatePip()
    -- First allocate
    bus.emit({
        type = "engineering.allocate",
        target = "ship_1",
        data = { thruster = "port" },
    })
    bus.drain()

    -- Then deallocate
    bus.emit({
        type = "engineering.deallocate",
        target = "ship_1",
        data = { thruster = "port" },
    })
    bus.drain()

    runner.assertEqual(10, store.get("ship_1", "engineering", "pip_pool"))
    runner.assertEqual(0, store.get("ship_1", "engineering", "thruster_port"))
end

function M.testAllocateFromEmptyPool()
    -- Drain the pool
    for i = 1, 10 do
        bus.emit({
            type = "engineering.allocate",
            target = "ship_1",
            data = { thruster = "main" },
        })
    end
    bus.drain()
    runner.assertEqual(0, store.get("ship_1", "engineering", "pip_pool"))

    -- Try one more
    bus.emit({
        type = "engineering.allocate",
        target = "ship_1",
        data = { thruster = "main" },
    })
    bus.drain()

    runner.assertEqual(10, store.get("ship_1", "engineering", "thruster_main"),
        "should not exceed allocated amount")
end

function M.testDeallocateFromZero()
    bus.emit({
        type = "engineering.deallocate",
        target = "ship_1",
        data = { thruster = "starboard" },
    })
    bus.drain()

    runner.assertEqual(0, store.get("ship_1", "engineering", "thruster_starboard"),
        "should not go negative")
    runner.assertEqual(10, store.get("ship_1", "engineering", "pip_pool"),
        "pool should not change")
end

function M.testInvalidThruster()
    local poolBefore = store.get("ship_1", "engineering", "pip_pool")
    bus.emit({
        type = "engineering.allocate",
        target = "ship_1",
        data = { thruster = "nonexistent" },
    })
    bus.drain()

    runner.assertEqual(poolBefore, store.get("ship_1", "engineering", "pip_pool"),
        "pool should not change for invalid thruster")
end

function M.testPipGeneration()
    -- Set pool to 0 to see generation
    store.set("ship_1", "engineering", "pip_pool", 0)
    store.set("ship_1", "engineering", "pip_gen_accumulator", 0)

    -- Tick enough for at least 1 pip (gen rate is 2.0/sec, so ~0.55 sec > 1 pip)
    for i = 1, 33 do
        engineering.tick(1 / 60)
        bus.drain()
    end

    local pool = store.get("ship_1", "engineering", "pip_pool")
    runner.assertGreaterThan(0, pool, "should have generated at least 1 pip")
end

function M.testPipPoolCapped()
    -- Pool already at max (10)
    store.set("ship_1", "engineering", "pip_gen_accumulator", 0.99)

    engineering.tick(1 / 60)
    bus.drain()

    runner.assertInRange(0, 10, store.get("ship_1", "engineering", "pip_pool"),
        "pool should not exceed max")
end

function M.testAllocateEmitsEvent()
    local emitted = false
    bus.subscribe("engineering.pip.allocated", function()
        emitted = true
    end)

    bus.emit({
        type = "engineering.allocate",
        target = "ship_1",
        data = { thruster = "main" },
    })
    bus.drain()

    runner.assert(emitted, "should emit pip.allocated event")
end

return M
