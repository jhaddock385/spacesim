# Space Sim - Project Context
A space simulation game built with Love2D. Early development.

## Run
```
love .
```

## File Index
```
main.lua              -- LOVE callback delegation
conf.lua              -- window config (1280x720, resizable)
src/
├── init.lua          -- wires modules, registers states, global input
├── core/
│   ├── state.lua     -- state machine (register, set, onEnter/onExit)
│   ├── input.lua     -- centralized input routing by state
│   ├── bus.lua       -- event bus: emit, subscribe, drain with depth limit
│   ├── store.lua     -- partitioned state store: entity/component/key
│   └── clock.lua     -- fixed timestep accumulator, freeze/unfreeze
├── sim/
│   ├── init.lua      -- simulation coordinator: ticks systems, drains bus
│   ├── entities.lua  -- entity registry: create/destroy/lookup by string ID
│   ├── spatial.lua   -- 2D physics: position, velocity, rotation, damping
│   └── ship/
│       ├── init.lua      -- ship entity factory: creates ship with subsystems
│       ├── engineering.lua -- warp core, pip generation, power allocation
│       └── helm.lua      -- reads thruster power, emits thrust/torque events
├���─ ui/
│   └── button.lua    -- clickable button widget
├��─ screens/
│   ├── menu.lua      -- main menu (Start Run, Simulator, Options, Quit)
│   ├── play.lua      -- game run (placeholder)
│   ├── simulator.lua -- dev display: spatial map, ship systems, event log
│   └── options.lua   -- settings (placeholder)
├── data/             -- pure data definitions
assets/
├── images/           -- sprites, textures
├── sounds/           -- audio files
├── fonts/            -- custom fonts
lib/                  -- third-party (luasocket, luasec, json)
```

## Tech
Love2D 11.4, Lua/LuaJIT, VSCode

## Conventions

### Lua / Love2D
- 4 spaces indent
- Module pattern: `local M = {} ... return M`
- Love callbacks: `love.load()`, `love.update(dt)`, `love.draw()`
- Lazy loading to avoid circular requires: `if not _mod then _mod = require(...) end`
- Entity IDs: stable string identifiers (`ship_1`, `asteroid_3`), never raw table references
- Events and commands reference entities by ID, resolved at apply time

### Project Structure
- Three layers: `src/sim/` for deterministic simulation, `src/agents/` (future) for AI crew, `src/screens/` for presentation
- `src/data/` for pure data definitions, `src/ui/` for reusable widgets
- All state changes flow through the event bus (`src/core/bus.lua`) and state store (`src/core/store.lua`)
- Mode orchestrators manage lifecycle; coordinator modules (`init.lua`) wire submodules together
- One module per concern — don't scatter related logic across the codebase

### File Size Guidelines
- Target: under 250 lines per file
- Warning: 250-550 lines — consider splitting
- Mandatory: over 750 lines — must split into modules
- When splitting: identify distinct responsibilities, extract into focused submodules in a folder, use `init.lua` as coordinator, keep shared state in a dedicated `state.lua` if needed

## Architecture Principles

### Centralized Systems
Each concern has exactly one home. When implementing new features, do not add functionality in random or convenient locations.

- **Input**: All input handling goes through one module. No other module should directly handle `love.keypressed`, `love.mousepressed`, etc.
- **State**: All state transitions go through a centralized state module. Don't track game state in scattered variables.
- **Render**: All coordinate transforms go through one place. Don't manually calculate window/virtual coords in random files.

As new systems are added (physics, audio, effects, etc.), each gets a dedicated module. The rule is: when debugging "what happens when X", there should be exactly one place to look.

If you find yourself thinking "I'll just handle this here because it's convenient" — stop and add it to the centralized system instead. Short-term convenience creates long-term maintenance burden.

### Draw Order
Maintain an explicit, centralized draw order. Layers (background, game world, particles, UI) are drawn in a defined sequence from one place, not scattered across modules. When adding new visual elements, slot them into the existing layer order rather than drawing ad-hoc.

### State Management
Use explicit state machines with `onEnter`/`onExit` callbacks and a centralized state module. Game modes and screens are states, not flags.

### Event Bus Architecture
All simulation state changes flow through the central event bus. Subsystems communicate by emitting and subscribing to events — they never directly mutate each other's state. This applies at every scale: within subsystems (engineering components), between subsystems (tactical -> shields), and between entities (ship-to-ship). The bus drains once per frame with a hard depth limit to prevent infinite cascades.

### Deferred Mutation
Prefer queuing changes and processing them at defined points in the frame, rather than mutating game state mid-iteration. This prevents order-dependent bugs and makes the frame lifecycle predictable.

### ID-Based References
Game entities are referenced by stable string IDs in events, commands, and cross-system communication. Resolved to actual objects only at the point of use. This decouples systems and makes serialization straightforward.

## Policy

### Think Before Building
The default AI instinct is to race toward a visible result. Resist this. This project prioritizes well-structured, easy-to-reason-about systems over speed to features. When facing a design decision, discuss tradeoffs before implementing. When facing an implementation choice, consider long-term maintainability over short-term convenience. Don't take shortcuts that violate the architecture, but don't build abstractions for hypothetical future callers either.

### Read Before Modifying
Before changing existing code, read it first. Before starting new work in an area with documentation, read the relevant docs. Check gotchas when debugging strange issues.

### No Parallel Abstractions
Before creating a new module, system, or pattern, check if an existing one covers the same concern. Extending an existing system is almost always better than creating a second one that partially overlaps.

## Git
- Never commit without being asked
- Stage files explicitly (no `git add .` or `git add -A`)
- No AI attribution in commits
- Keep commit messages concise and focused on the "why"

## Documentation
Before starting new work, read the relevant INDEX file(s) to see what documentation exists.

- **Design** — `docs/design/INDEX.md` — game concept, architectural decisions, project structure
- **Architecture** — `docs/architecture/INDEX.md` — how subsystems work and why
- **Gotchas** — `docs/gotchas.md` — things that went wrong and why; check when debugging

### When to Write Docs
- **Architecture docs**: Write one when a major subsystem is built (new system, significant module, core pattern). If the user asks for one, write it immediately. After building something substantial, suggest writing an architecture doc and adding it to the index.
- **Gotchas**: Add an entry whenever a problem took more than 2-3 passes to solve — especially if the solution turned out to be simple but deceptive. If we were stuck on something for a while, write it up. The goal is to never hit the same non-obvious problem twice.
