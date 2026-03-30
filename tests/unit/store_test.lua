local runner = require("tests.runner")
local store = require("src.core.store")
local M = {}

function M.setup()
    runner.resetSim()
end

function M.teardown()
    runner.resetSim()
end

function M.testSetAndGet()
    store.set("e1", "comp", "key", 42)
    runner.assertEqual(42, store.get("e1", "comp", "key"))
end

function M.testGetNonexistent()
    runner.assertNil(store.get("nope", "nope", "nope"))
end

function M.testGetComponent()
    store.set("e1", "spatial", "x", 10)
    store.set("e1", "spatial", "y", 20)

    local comp = store.getComponent("e1", "spatial")
    runner.assertNotNil(comp)
    runner.assertEqual(10, comp.x)
    runner.assertEqual(20, comp.y)
end

function M.testGetEntity()
    store.set("e1", "spatial", "x", 10)
    store.set("e1", "engineering", "pips", 5)

    local entity = store.getEntity("e1")
    runner.assertNotNil(entity)
    runner.assertNotNil(entity.spatial)
    runner.assertNotNil(entity.engineering)
end

function M.testHasEntity()
    runner.assert(not store.hasEntity("e1"))
    store.set("e1", "comp", "key", 1)
    runner.assert(store.hasEntity("e1"))
end

function M.testRemoveEntity()
    store.set("e1", "comp", "key", 1)
    store.removeEntity("e1")
    runner.assert(not store.hasEntity("e1"))
    runner.assertNil(store.get("e1", "comp", "key"))
end

function M.testRemoveComponent()
    store.set("e1", "a", "x", 1)
    store.set("e1", "b", "y", 2)
    store.removeComponent("e1", "a")
    runner.assertNil(store.getComponent("e1", "a"))
    runner.assertNotNil(store.getComponent("e1", "b"))
end

function M.testEntitiesWithComponent()
    store.set("e1", "spatial", "x", 0)
    store.set("e2", "spatial", "x", 0)
    store.set("e3", "other", "y", 0)

    local ids = store.entitiesWithComponent("spatial")
    runner.assertEqual(2, #ids)
end

function M.testAllEntities()
    store.set("e1", "a", "x", 1)
    store.set("e2", "b", "y", 2)
    local all = store.allEntities()
    runner.assertEqual(2, #all)
end

function M.testOverwriteValue()
    store.set("e1", "comp", "key", 1)
    store.set("e1", "comp", "key", 2)
    runner.assertEqual(2, store.get("e1", "comp", "key"))
end

return M
