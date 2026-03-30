local runner = require("tests.runner")
local entities = require("src.sim.entities")
local store = require("src.core.store")
local bus = require("src.core.bus")
local M = {}

function M.setup()
    runner.resetSim()
end

function M.teardown()
    runner.resetSim()
end

function M.testCreateAutoId()
    local id = entities.create("ship")
    runner.assertEqual("ship_1", id)
end

function M.testCreateAutoIdIncrements()
    local id1 = entities.create("ship")
    local id2 = entities.create("ship")
    runner.assertEqual("ship_1", id1)
    runner.assertEqual("ship_2", id2)
end

function M.testCreateExplicitId()
    local id = entities.create("ship", "player_ship")
    runner.assertEqual("player_ship", id)
end

function M.testCreateDuplicateIdErrors()
    entities.create("ship", "dupe")
    runner.assertThrows(function()
        entities.create("ship", "dupe")
    end, "duplicate ID should error")
end

function M.testExists()
    local id = entities.create("ship")
    runner.assert(entities.exists(id))
    runner.assert(not entities.exists("nonexistent"))
end

function M.testDestroy()
    local id = entities.create("ship")
    store.set(id, "spatial", "x", 100)

    entities.destroy(id)
    runner.assert(not entities.exists(id))
    runner.assertNil(store.get(id, "spatial", "x"),
        "store should be cleaned up on destroy")
end

function M.testGetType()
    local id = entities.create("asteroid")
    runner.assertEqual("asteroid", entities.getType(id))
end

function M.testAll()
    entities.create("ship")
    entities.create("asteroid")
    local all = entities.all()
    runner.assertEqual(2, #all)
end

function M.testAllOfType()
    entities.create("ship")
    entities.create("ship")
    entities.create("asteroid")
    runner.assertEqual(2, #entities.allOfType("ship"))
    runner.assertEqual(1, #entities.allOfType("asteroid"))
end

function M.testCreateEmitsEvent()
    local created = false
    bus.subscribe("entity.created", function(event)
        created = true
    end)

    entities.create("ship")
    bus.drain()
    runner.assert(created, "should emit entity.created")
end

function M.testDestroyEmitsEvent()
    local destroyed = false
    bus.subscribe("entity.destroyed", function(event)
        destroyed = true
    end)

    local id = entities.create("ship")
    bus.drain()
    entities.destroy(id)
    bus.drain()
    runner.assert(destroyed, "should emit entity.destroyed")
end

return M
