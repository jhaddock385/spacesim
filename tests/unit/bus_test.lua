local runner = require("tests.runner")
local bus = require("src.core.bus")
local M = {}

function M.setup()
    runner.resetSim()
end

function M.teardown()
    runner.resetSim()
end

function M.testEmitRequiresType()
    runner.assertThrows(function()
        bus.emit({})
    end, "emit without type should error")
end

function M.testSubscribeAndDrain()
    local received = nil
    bus.subscribe("test.event", function(event)
        received = event
    end)

    bus.emit({ type = "test.event", data = { value = 42 } })
    runner.assertNil(received, "should not receive before drain")

    bus.drain()
    runner.assertNotNil(received, "should receive after drain")
    runner.assertEqual(42, received.data.value, "should have correct data")
end

function M.testMultipleSubscribers()
    local count = 0
    bus.subscribe("test.multi", function() count = count + 1 end)
    bus.subscribe("test.multi", function() count = count + 1 end)

    bus.emit({ type = "test.multi" })
    bus.drain()
    runner.assertEqual(2, count, "both subscribers should fire")
end

function M.testFilteredSubscription()
    local received = false
    bus.subscribe("test.filtered", function()
        received = true
    end, { target = "ship_1" })

    bus.emit({ type = "test.filtered", target = "ship_2" })
    bus.drain()
    runner.assert(not received, "should not fire for wrong target")

    bus.emit({ type = "test.filtered", target = "ship_1" })
    bus.drain()
    runner.assert(received, "should fire for matching target")
end

function M.testWildcardSubscription()
    local events = {}
    bus.subscribe("*", function(event)
        table.insert(events, event.type)
    end)

    bus.emit({ type = "foo" })
    bus.emit({ type = "bar" })
    bus.drain()
    runner.assertEqual(2, #events, "wildcard should receive all events")
end

function M.testHistoryTracked()
    bus.emit({ type = "test.history" })
    bus.drain()

    local history = bus.getHistory()
    runner.assertGreaterThan(0, #history, "history should have entries")
    runner.assertEqual("test.history", history[#history].type)
end

function M.testUnsubscribe()
    local count = 0
    local handler = function() count = count + 1 end
    bus.subscribe("test.unsub", handler)

    bus.emit({ type = "test.unsub" })
    bus.drain()
    runner.assertEqual(1, count)

    bus.unsubscribe("test.unsub", handler)
    bus.emit({ type = "test.unsub" })
    bus.drain()
    runner.assertEqual(1, count, "should not fire after unsubscribe")
end

function M.testCascadingEvents()
    bus.subscribe("test.first", function()
        bus.emit({ type = "test.second" })
    end)

    local secondFired = false
    bus.subscribe("test.second", function()
        secondFired = true
    end)

    bus.emit({ type = "test.first" })
    bus.drain()
    runner.assert(secondFired, "cascading event should fire")
end

function M.testEventHasTimestamp()
    bus.emit({ type = "test.time" })
    bus.drain()

    local history = bus.getHistory()
    local evt = history[#history]
    runner.assertNotNil(evt.time, "event should have timestamp")
end

return M
