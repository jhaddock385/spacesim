# Project Structure

## Directory Layout

```
main.lua                        -- LOVE callback delegation
conf.lua                        -- window config (1280x720, resizable)

src/
├── init.lua                    -- wires modules, registers states, global input

├── core/
│   ├── state.lua               -- screen state machine (register, set, onEnter/onExit)
│   ├── input.lua               -- centralized input routing by state
│   ├── clock.lua               -- fixed timestep accumulator, freeze/unfreeze, time scale
│   ├── bus.lua                 -- event bus: emit, subscribe, drain queue
│   └── store.lua               -- state store: partitioned, event-sourced mutations

├── sim/
│   ├── init.lua                -- simulation coordinator: registers systems, ticks clock, drains bus
│   ├── spatial.lua             -- 2D physics: positions, velocities, collision detection
│   ├── entities.lua            -- entity registry: create/destroy/lookup by string ID
│   ├── ship/
│   │   ├── init.lua            -- ship coordinator: creates subsystem components for a ship entity
│   │   ├── helm.lua            -- heading, thrust, rotation, course plotting
│   │   ├── tactical.lua        -- phasers, targeting, firing arcs, weapon state
│   │   ├── shields.lua         -- shield state, strength, power draw, absorption
│   │   ├── engineering.lua     -- power graph: components, conduits, routing, distribution
│   │   ├── sensors.lua         -- detection ranges, scanning, visibility
│   │   └── hull.lua            -- HP, damage tracking

├── agents/                     -- (future) AI crew layer
│   ├── init.lua                -- agent coordinator: prompt construction, response parsing
│   ├── crew/                   -- individual crew member definitions
│   └── station.lua             -- station -> available actions + visible state mapping

├── ui/
│   └── button.lua              -- clickable button widget

├── screens/
│   ├── menu.lua                -- main menu (Start Run, Simulator, Options, Quit)
│   ├── play.lua                -- the actual game (text log + player-facing displays)
│   ├── simulator.lua           -- dev display: full sim visibility + direct command input
│   └── options.lua             -- settings

├── data/                       -- pure data definitions (ship templates, weapon stats, etc.)

assets/
├── images/
├── sounds/
├── fonts/

lib/                            -- third-party (luasocket, luasec, json parser)

docs/
├── architecture/INDEX.md
├── design/INDEX.md
├── gotchas.md
```

## Core Systems

### Event Bus (`src/core/bus.lua`)

The bus is the central nervous system of the simulation. All state changes flow through it as events. All systems interact by emitting and subscribing to events.

**Pattern:**
- Systems subscribe to event types they care about
- Actions (from player, AI, or other systems) are emitted as events onto the bus
- The bus drains its queue each frame: dispatch event -> handlers run -> handlers may emit new events -> repeat until quiescent
- Hard depth limit prevents infinite cascades

**Why everything is an event:**
The same pattern works at every scale. "Reverse the polarity of the phase inverter" is an event targeting an engineering component. "Fire phasers at target" is an event from tactical. "Phaser beam hits shields" is an event between entities. One bus, one pattern, one place to look when debugging.

**What this enables:**
- The dev display subscribes to the bus and logs everything — full causal chain for any state change
- AI agents emit events onto the same bus as manual commands — no special path
- New systems slot in by declaring what they emit and subscribe to
- Event log IS the debug tool

### State Store (`src/core/store.lua`)

Partitioned state store. All simulation state lives here. Mutations happen only through the store (triggered by event handlers). Partitioned by entity and subsystem so you can inspect "ship_1.shields" or "asteroid_3.position" directly.

The store is the single source of truth. The bus is how changes get there.

### Clock (`src/core/clock.lua`)

Manages the fixed timestep for physics. Accumulates `dt` from `love.update()`, steps in fixed increments. Also manages freeze/unfreeze for AI command resolution and player pause.

States: running, frozen (player pause), frozen (AI processing).

## Simulation Layer (`src/sim/`)

No rendering code. No AI code. No Love2D draw calls. Pure game logic.

### Simulation Coordinator (`src/sim/init.lua`)

Each frame:
1. Clock decides if a physics step should happen
2. If yes: spatial.lua integrates physics (emits movement/collision events)
3. Subsystems process (emit/handle events as needed)
4. Bus drains until quiescent
5. State store has the new ground truth

### Entities (`src/sim/entities.lua`)

Entity registry. Every object in the universe gets a stable string ID (`ship_1`, `asteroid_3`, `starbase_alpha`). Systems reference entities by ID, resolved at point of use. The registry handles create, destroy, lookup, and enumeration.

### Spatial (`src/sim/spatial.lua`)

2D physics. Positions, velocities, accelerations, rotation. Fixed-timestep integration. Collision detection. Distance calculations. Sensor range checks.

Subscribes to: thrust events, heading change events.
Emits: collision events, proximity events.

### Ship Subsystems (`src/sim/ship/`)

Each subsystem is a module that subscribes to relevant events and emits its own.

**How subsystems interact (example — firing phasers):**
1. `tactical.lua` receives a "fire phasers" event (from player command or AI agent)
2. Tactical checks: weapon online? power available? target in arc? If no, emits a failure event.
3. If yes, tactical emits a "phaser beam" event with source, target, power level
4. `spatial.lua` validates range
5. Target's `shields.lua` handles the beam event: absorbs what it can, emits "damage through shields" for remainder
6. Target's `hull.lua` handles remaining damage, updates HP
7. All of this is visible in the event log

**How internal engineering works (example — rerouting power):**
1. Engineering receives a "route power" event
2. The power graph model processes it: component states change, power flows through conduits
3. Downstream components react: shield power changes, weapon power changes
4. Each change is an event — fully traceable

No subsystem directly mutates another subsystem's state. They communicate through events.

## AI Agent Layer (`src/agents/` — future)

Not built until the simulation is proven. When it's time:

- **Station mapping:** Each crew station maps to a subset of events it can emit (its "available actions") and a subset of state it can read (its "console view")
- **Prompt construction:** Read station's visible state from the store, list available actions as Claude API tools, include crew personality/skills
- **Response handling:** Claude returns tool-use calls. Each tool call becomes an event on the bus. Same path as manual commands.
- **Cascade:** A crew member's response may include communication to another crew member, which triggers another API call, which may emit more events. Hard limit on cascade depth.

## Interface Layer (`src/screens/`)

### Simulator Screen (Dev Display)

The primary development tool. Shows:
- **Spatial map:** all entities, positions, headings, velocities, ranges
- **Ship status:** every subsystem's state, power levels, damage
- **Event log:** real-time feed of all events flowing through the bus
- **Direct command input:** issue events directly onto the bus, bypassing AI
- **Power grid view:** engineering component graph, power flow

Not pretty. Functional. Full visibility.

### Play Screen (Player Game — later)

What the captain sees. Likely:
- Text log (crew dialogue, system events)
- Simple star map (positions, rough distances)
- Text input for captain commands
- Limited ship status (what you'd see on a bridge viewscreen)

Exact scope TBD through playtesting after AI agents are working.

## Design Principles

### One bus, one store, one truth
All state changes flow through the bus. All state lives in the store. When debugging "what happened," read the event log.

### Subsystems don't know each other
Tactical doesn't import shields. Engineering doesn't import helm. They communicate through events. This means you can add, remove, or modify any subsystem without touching others.

### Same path for all commands
A manual dev command, an AI crew action, and an automatic system response all emit events onto the same bus. No special paths.

### ID-based everything
Entities are string IDs. Events reference entities by ID. Resolved to actual state only at point of use.
