local runner = require("tests.runner")
local helm = require("src.sim.ship.helm")
local spatial = require("src.sim.spatial")
local engineering = require("src.sim.ship.engineering")
local store = require("src.core.store")
local bus = require("src.core.bus")
local M = {}

function M.setup()
    runner.resetSim()
    spatial.setup()
    engineering.setup()

    -- Create a ship manually (not using ship factory to isolate helm tests)
    spatial.init("ship_1", { x = 0, y = 0, rotation = 0, mass = 1 })
    engineering.init("ship_1")
end

function M.teardown()
    runner.resetSim()
end

function M.testMainThrusterEmitsThrust()
    -- Allocate pips to main thruster
    store.set("ship_1", "engineering", "thruster_main", 3)

    helm.tick(1 / 60)
    bus.drain()

    -- Ship should have velocity after thrust event processed
    local vx = store.get("ship_1", "spatial", "vx")
    runner.assertGreaterThan(0, vx,
        "main thruster should produce forward velocity (facing right)")
end

function M.testPortThrusterRotatesStarboard()
    store.set("ship_1", "engineering", "thruster_port", 2)

    helm.tick(1 / 60)
    bus.drain()

    local rotVel = store.get("ship_1", "spatial", "rotVel")
    runner.assertGreaterThan(0, rotVel,
        "port thruster should produce positive (clockwise) rotation")
end

function M.testStarboardThrusterRotatesPort()
    store.set("ship_1", "engineering", "thruster_starboard", 2)

    helm.tick(1 / 60)
    bus.drain()

    local rotVel = store.get("ship_1", "spatial", "rotVel")
    runner.assertLessThan(0, rotVel,
        "starboard thruster should produce negative (counter-clockwise) rotation")
end

function M.testBalancedThrustersNoRotation()
    store.set("ship_1", "engineering", "thruster_port", 3)
    store.set("ship_1", "engineering", "thruster_starboard", 3)

    helm.tick(1 / 60)
    bus.drain()

    local rotVel = store.get("ship_1", "spatial", "rotVel")
    runner.assertEqual(0, rotVel,
        "equal port/starboard should produce zero rotation")
end

function M.testNoPipsNoForce()
    -- All thrusters at 0 (default)
    helm.tick(1 / 60)
    -- No bus events should be emitted, but drain anyway
    bus.drain()

    runner.assertEqual(0, store.get("ship_1", "spatial", "vx"))
    runner.assertEqual(0, store.get("ship_1", "spatial", "vy"))
    runner.assertEqual(0, store.get("ship_1", "spatial", "rotVel"))
end

function M.testMorePipsMoreForce()
    -- 1 pip
    store.set("ship_1", "engineering", "thruster_main", 1)
    helm.tick(1 / 60)
    bus.drain()
    local vx1 = store.get("ship_1", "spatial", "vx")

    -- Reset velocity
    store.set("ship_1", "spatial", "vx", 0)

    -- 5 pips
    store.set("ship_1", "engineering", "thruster_main", 5)
    helm.tick(1 / 60)
    bus.drain()
    local vx5 = store.get("ship_1", "spatial", "vx")

    runner.assertGreaterThan(vx1, vx5,
        "more pips should produce more velocity")
end

return M
