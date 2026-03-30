# Event Bus and State Store

## Overview

The event bus (`src/core/bus.lua`) and state store (`src/core/store.lua`) are the two foundational systems that everything else builds on. The bus is how things happen. The store is where state lives.

**Core rule:** Subsystems never directly mutate each other's state. They emit events onto the bus. Event handlers read and write through the store.

## Event Bus (`src/core/bus.lua`)

### What It Does

The bus is a queue-based event system. Systems emit events, other systems subscribe to event types, and the bus dispatches events to matching subscribers.

### Event Structure

Every event is a table with:
```lua
{
    type = "engineering.allocate",  -- required: dot-namespaced event type
    source = "player_ship",         -- optional: entity that caused this
    target = "player_ship",         -- optional: entity this affects
    data = { thruster = "main" },   -- optional: event-specific payload
    time = 12345.67,                -- auto-set by bus on emit
}
```

### API

- `bus.emit(event)` — queue an event for processing
- `bus.subscribe(eventType, handler, filter)` — register a handler for an event type
- `bus.unsubscribe(eventType, handler)` — remove a handler
- `bus.drain()` — process all queued events (called once per sim tick)
- `bus.getHistory()` — returns the event log (for debug display)
- `bus.clear()` — reset everything (used on screen exit)

### Subscribing

```lua
bus.subscribe("engineering.allocate", function(event)
    -- event.target is the ship ID
    -- event.data.thruster is "main", "port", or "starboard"
end)
```

**Filtered subscriptions:** You can pass a filter table to only receive events matching specific source/target:
```lua
bus.subscribe("spatial.thrust", handler, { target = "player_ship" })
```

**Wildcard:** Subscribe to `"*"` to receive all events (useful for debug logging).

### Drain Cycle

`bus.drain()` processes events one at a time, in FIFO order. Handlers may emit new events during processing — those go to the back of the queue. The drain continues until the queue is empty.

**Depth limit:** If event handlers keep emitting events that trigger more handlers that emit more events, this could loop forever. The bus enforces a hard depth limit (currently 20). If exceeded, remaining events are dropped and a `bus.overflow` event is logged to the history. This is a safety valve, not expected behavior — if it fires, something is wrong.

### Event Naming Convention

Dot-namespaced by system:
- `engineering.allocate`, `engineering.pip.generated`, `engineering.allocate.failed`
- `spatial.thrust`, `spatial.torque`
- `entity.created`, `entity.destroyed`

### Why a Queue, Not Pub/Sub

Events are queued and processed in order, not dispatched immediately on emit. This means:
1. You can emit events during update logic without worrying about reentrant mutations
2. The order of processing is deterministic (FIFO)
3. The full event chain for a frame is inspectable in the history

This is the deferred mutation pattern from the design docs — nothing changes mid-iteration.

## State Store (`src/core/store.lua`)

### What It Does

A partitioned key-value store. All simulation state lives here. Organized by entity ID, then component name, then key.

### Data Model

```
store
├── "player_ship"
│   ├── "spatial"
│   │   ├── x = 0
│   │   ├── y = 0
│   │   ├── vx = 12.5
│   │   ├── vy = 0
│   │   ├── rotation = 0.3
│   │   ├── rotVel = 0
│   │   └── mass = 1
│   └── "engineering"
│       ├── pip_pool = 8
│       ├── pip_gen_rate = 2.0
│       ├── max_pip_pool = 10
│       ├── thruster_main = 2
│       ├── thruster_port = 0
│       └── thruster_starboard = 0
├── "asteroid_1"
│   └── "spatial"
│       ├── x = 500
│       └── ...
```

### API

**Read:**
- `store.get(entityId, component, key)` — single value
- `store.getComponent(entityId, component)` — whole component table
- `store.getEntity(entityId)` — all components for an entity
- `store.hasEntity(entityId)` — existence check

**Write:**
- `store.set(entityId, component, key, value)` — set a single value (auto-creates entity/component if needed)

**Delete:**
- `store.removeEntity(entityId)` — wipe all data for an entity
- `store.removeComponent(entityId, component)` — remove one component

**Query:**
- `store.entitiesWithComponent(component)` — all entity IDs that have a given component
- `store.allEntities()` — all entity IDs

### Why a Central Store Instead of Object State

1. **Inspectability:** The dev display can read any entity's state without needing a reference to the object. Just `store.getComponent("player_ship", "engineering")`.
2. **Decoupling:** Subsystems don't need references to each other. Helm reads engineering state from the store, not from an engineering object.
3. **Serialization:** Saving/loading game state is "serialize the store." No scattered state to collect.
4. **Single source of truth:** There's one place to look for what any value is. No "is the ship's position in the spatial module or the ship object?"

### Store vs Bus

- **Store** = what the state IS right now (nouns)
- **Bus** = what just HAPPENED (verbs)

A system reads from the store and emits events onto the bus. Event handlers modify the store. The dev display reads the store for current state and the bus history for what happened.

## Clock (`src/core/clock.lua`)

### What It Does

Manages the fixed-timestep simulation loop and freeze/unfreeze for pausing.

### Fixed Timestep

Love2D's `love.update(dt)` gives variable dt based on frame rate. The clock accumulates this dt and steps the simulation in fixed increments (1/60th of a second). This means the simulation behaves identically regardless of frame rate.

```lua
-- In love.update(dt):
clock.accumulate(dt)
clock.step(function(fixedDt)
    -- This runs 0 or more times per frame
    -- fixedDt is always exactly 1/60
    engineeringTick(fixedDt)
    helmTick(fixedDt)
    bus.drain()
    spatialTick(fixedDt)
end)
```

### Freeze

`clock.freeze("player")` or `clock.freeze("ai")` stops the simulation. `clock.unfreeze()` resumes and discards any time accumulated during the freeze (so the simulation doesn't "catch up" after unpausing).

### Time Scale

`clock.setTimeScale(2.0)` makes the simulation run at double speed. Useful for testing.

## How They Work Together

A complete frame cycle:

1. `love.update(dt)` fires
2. Clock accumulates dt, then steps in fixed increments. For each step:
   a. **Engineering tick:** generates pips (emits `engineering.pip.generated`)
   b. **Helm tick:** reads thruster power from store, emits `spatial.thrust` / `spatial.torque`
   c. **Bus drain:** processes all queued events. Thrust/torque handlers update velocity in store.
   d. **Spatial tick:** integrates physics — reads velocity from store, computes new position, writes back
3. `love.draw()` fires — screens read from store and bus history to render
