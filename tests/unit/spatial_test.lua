local runner = require("tests.runner")
local spatial = require("src.sim.spatial")
local store = require("src.core.store")
local bus = require("src.core.bus")
local M = {}

function M.setup()
    runner.resetSim()
    spatial.setup()
end

function M.teardown()
    runner.resetSim()
end

function M.testInitSetsDefaults()
    spatial.init("e1")
    runner.assertEqual(0, store.get("e1", "spatial", "x"))
    runner.assertEqual(0, store.get("e1", "spatial", "y"))
    runner.assertEqual(0, store.get("e1", "spatial", "vx"))
    runner.assertEqual(0, store.get("e1", "spatial", "vy"))
    runner.assertEqual(0, store.get("e1", "spatial", "rotation"))
    runner.assertEqual(0, store.get("e1", "spatial", "rotVel"))
    runner.assertEqual(1, store.get("e1", "spatial", "mass"))
end

function M.testInitWithConfig()
    spatial.init("e1", { x = 100, y = 200, rotation = 1.5 })
    runner.assertEqual(100, store.get("e1", "spatial", "x"))
    runner.assertEqual(200, store.get("e1", "spatial", "y"))
    runner.assertEqual(1.5, store.get("e1", "spatial", "rotation"))
end

function M.testThrustEvent()
    spatial.init("e1", { rotation = 0 })  -- facing right

    bus.emit({
        type = "spatial.thrust",
        target = "e1",
        data = { force = 10 },
    })
    bus.drain()

    local vx = store.get("e1", "spatial", "vx")
    runner.assertGreaterThan(0, vx, "thrust should increase vx when facing right")
end

function M.testTorqueEvent()
    spatial.init("e1")

    bus.emit({
        type = "spatial.torque",
        target = "e1",
        data = { torque = 1.0 },
    })
    bus.drain()

    local rotVel = store.get("e1", "spatial", "rotVel")
    runner.assertGreaterThan(0, rotVel, "torque should increase rotational velocity")
end

function M.testTickIntegratesPosition()
    spatial.init("e1")
    store.set("e1", "spatial", "vx", 60)  -- 60 units/sec
    store.set("e1", "spatial", "vy", 0)

    spatial.tick(1 / 60)

    local x = store.get("e1", "spatial", "x")
    runner.assertGreaterThan(0, x, "position should advance from velocity")
end

function M.testDampingReducesVelocity()
    spatial.init("e1")
    store.set("e1", "spatial", "vx", 100)

    spatial.tick(1 / 60)

    local vx = store.get("e1", "spatial", "vx")
    runner.assertLessThan(100, vx, "damping should reduce velocity")
    runner.assertGreaterThan(0, vx, "velocity should still be positive")
end

function M.testRotationDamping()
    spatial.init("e1")
    store.set("e1", "spatial", "rotVel", 5.0)

    spatial.tick(1 / 60)

    local rotVel = store.get("e1", "spatial", "rotVel")
    runner.assertLessThan(5.0, rotVel, "rotation damping should reduce rotVel")
    runner.assertGreaterThan(0, rotVel, "rotVel should still be positive")
end

function M.testRotationNormalized()
    spatial.init("e1")
    store.set("e1", "spatial", "rotation", 7.0)  -- > 2pi

    spatial.tick(1 / 60)

    local rot = store.get("e1", "spatial", "rotation")
    runner.assertLessThan(2 * math.pi, rot, "rotation should be normalized")
    runner.assertInRange(0, 2 * math.pi, rot)
end

function M.testMultipleEntities()
    spatial.init("e1")
    spatial.init("e2")
    store.set("e1", "spatial", "vx", 10)
    store.set("e2", "spatial", "vx", -10)

    spatial.tick(1 / 60)

    local x1 = store.get("e1", "spatial", "x")
    local x2 = store.get("e2", "spatial", "x")
    runner.assertGreaterThan(0, x1, "e1 should move right")
    runner.assertLessThan(0, x2, "e2 should move left")
end

return M
