local M = {}

local queue = {}        -- pending events: {type, source, target, data}
local subscribers = {}  -- type -> list of {handler, filter}
local history = {}      -- completed events for debug display
local draining = false
local depth = 0
local MAX_DEPTH = 20
local MAX_HISTORY = 500

-- Subscribe a handler to an event type
-- filter is optional: {source=id, target=id} — handler only called if match
function M.subscribe(eventType, handler, filter)
    if not subscribers[eventType] then
        subscribers[eventType] = {}
    end
    table.insert(subscribers[eventType], {
        handler = handler,
        filter = filter,
    })
end

-- Remove a handler from an event type
function M.unsubscribe(eventType, handler)
    local subs = subscribers[eventType]
    if not subs then return end
    for i = #subs, 1, -1 do
        if subs[i].handler == handler then
            table.remove(subs, i)
        end
    end
end

-- Remove all subscriptions for a given event type
function M.unsubscribeAll(eventType)
    subscribers[eventType] = nil
end

-- Emit an event onto the bus
-- event = {type=string, source=string|nil, target=string|nil, data=table|nil}
function M.emit(event)
    if not event.type then
        error("bus.emit: event must have a type")
    end
    event.time = love.timer.getTime()
    table.insert(queue, event)
end

-- Drain the event queue, dispatching to subscribers
-- Called once per frame by the simulation coordinator
function M.drain()
    if draining then
        depth = depth + 1
        if depth > MAX_DEPTH then
            local overflow = {}
            for _, evt in ipairs(queue) do
                table.insert(overflow, evt.type)
            end
            queue = {}
            depth = 0
            -- Log the overflow as an event itself so the debug display can show it
            table.insert(history, {
                type = "bus.overflow",
                time = love.timer.getTime(),
                data = { depth = MAX_DEPTH, dropped = overflow },
            })
            return
        end
    end

    draining = true

    while #queue > 0 do
        -- Take the first event off the queue
        local event = table.remove(queue, 1)

        -- Record in history for debug display
        table.insert(history, event)
        if #history > MAX_HISTORY then
            table.remove(history, 1)
        end

        -- Dispatch to subscribers
        local subs = subscribers[event.type]
        if subs then
            for _, sub in ipairs(subs) do
                local pass = true
                if sub.filter then
                    if sub.filter.source and sub.filter.source ~= event.source then
                        pass = false
                    end
                    if sub.filter.target and sub.filter.target ~= event.target then
                        pass = false
                    end
                end
                if pass then
                    sub.handler(event)
                end
            end
        end

        -- Wildcard subscribers (subscribe to "*" to see everything)
        local wildcards = subscribers["*"]
        if wildcards then
            for _, sub in ipairs(wildcards) do
                sub.handler(event)
            end
        end

        -- Check depth limit for events emitted during handling
        if depth > MAX_DEPTH then
            break
        end
    end

    draining = false
    depth = 0
end

-- Get the event history (for debug display)
function M.getHistory()
    return history
end

-- Clear all state (for testing or screen transitions)
function M.clear()
    queue = {}
    subscribers = {}
    history = {}
    draining = false
    depth = 0
end

-- Clear just the history
function M.clearHistory()
    history = {}
end

return M
