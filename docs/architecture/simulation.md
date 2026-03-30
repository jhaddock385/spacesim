# Simulation Layer

## Overview

The simulation layer (`src/sim/`) is the deterministic game logic. No rendering, no AI, no Love2D draw calls. It takes commands (via bus events), ticks physics, and updates state (in the store).

## Entity Registry (`src/sim/entities.lua`)

Every object in the universe has a stable string ID. The registry manages creation, destruction, and lookup.

**Creating entities:**
```lua
local id = entities.create("ship")           -- auto-generates "ship_1"
local id = entities.create("ship", "player_ship")  -- explicit ID
```

**Auto-ID format:** `{type}_{n}` where n increments per type. So the first ship is `ship_1`, the first asteroid is `asteroid_1`, etc.

**Lifecycle events:** Creating an entity emits `entity.created`, destroying emits `entity.destroyed`. The entity registry also cleans up the store on destroy — `store.removeEntity(id)`.

**Important:** The entity registry only tracks existence and type. All actual data (position, systems, etc.) lives in the store as components. The registry is a thin ID manager, not an object system.

## Spatial Physics (`src/sim/spatial.lua`)

2D physics with position, velocity, rotation, and damping.

### Components

When `spatial.init(entityId, config)` is called, these keys are set in the store under the `"spatial"` component:

| Key | Type | Description |
|-----|------|-------------|
| x, y | number | Position in world units |
| vx, vy | number | Velocity in world units/sec |
| rotation | number | Heading in radians (0 = right/east, increases clockwise) |
| rotVel | number | Rotational velocity in radians/sec |
| mass | number | Affects acceleration (force/mass) |

### Physics Step

Each tick (at 60Hz fixed timestep):

```
-- Damping (applied before integration)
rotVel *= 0.98
vx *= 0.995
vy *= 0.995

-- Integration
rotation += rotVel * dt
x += vx * dt
y += vy * dt
```

Rotation is normalized to `[0, 2*pi)`.

### Forces

Spatial subscribes to two event types:

**`spatial.thrust`** — applies force along the entity's current heading:
```lua
bus.emit({
    type = "spatial.thrust",
    target = entityId,
    data = { force = 50.0 },
})
-- Internally: acceleration = heading_vector * force / mass
-- Then: velocity += acceleration
```

**`spatial.torque`** — applies rotational force:
```lua
bus.emit({
    type = "spatial.torque",
    target = entityId,
    data = { torque = 2.0 },  -- positive = clockwise
})
-- Internally: rotVel += torque / mass
```

### Damping Constants

| Constant | Value | Effect |
|----------|-------|--------|
| VELOCITY_DAMPING | 0.995 | Ships slow down gradually when thrust stops |
| ROTATION_DAMPING | 0.98 | Rotation settles faster than translation |

These are tuning knobs. Lower values = more drag, things settle faster. At 0.995, a ship at speed 100 will take several seconds to drift to a stop. These values are initial guesses and should be tuned by feel.

### Coordinate System

- Origin is (0, 0) at the center of the world
- X increases rightward, Y increases downward (Love2D convention)
- Rotation 0 = facing right (east), increases clockwise
- World units are abstract — the dev display scales them to pixels via camera zoom

## Ship Subsystems (`src/sim/ship/`)

### Ship Factory (`src/sim/ship/init.lua`)

Creates a ship entity with all subsystems initialized:

```lua
local id = ship.create({
    id = "player_ship",  -- optional, auto-generated if omitted
    x = 0, y = 0,
    rotation = 0,
    mass = 1,
})
```

This calls `entities.create()`, then `spatial.init()`, then `engineering.init()`. The ship factory is the only place that knows what components a ship needs.

### Engineering (`src/sim/ship/engineering.lua`)

Models the warp core and power distribution using a discrete pip system.

**Store keys** (under `"engineering"` component):

| Key | Description |
|-----|-------------|
| pip_pool | Current unallocated pips |
| max_pip_pool | Maximum pool size (10) |
| pip_gen_rate | Pips generated per second (2.0) |
| pip_gen_accumulator | Fractional pip generation progress |
| thruster_main | Pips allocated to main (forward) thruster |
| thruster_port | Pips allocated to port turning thruster |
| thruster_starboard | Pips allocated to starboard turning thruster |

**Pip generation:** Each tick, the warp core generates pips at `pip_gen_rate`. An accumulator tracks fractional progress. When it reaches 1.0, a pip is added to the pool (up to max). Emits `engineering.pip.generated`.

**Allocation:** Controlled via bus events:
- `engineering.allocate` with `data.thruster` — moves 1 pip from pool to the named thruster
- `engineering.deallocate` with `data.thruster` — moves 1 pip back to pool

Both validate preconditions (pool not empty, thruster has pips) and emit success/failure events.

**Bus event setup:** `engineering.setup()` subscribes to allocate/deallocate events. Must be called once during initialization (done by `sim/init.lua`).

### Helm (`src/sim/ship/helm.lua`)

Translates thruster power allocations into physics forces. Has no state of its own — it reads engineering state from the store and emits spatial events.

**Each tick:**
1. Reads `thruster_main`, `thruster_port`, `thruster_starboard` from the store
2. If main thruster has pips: emits `spatial.thrust` with force = `pips * THRUST_FORCE_PER_PIP * dt`
3. Computes net torque from port/starboard difference: `(port - starboard) * TORQUE_PER_PIP * dt`
4. If net torque is nonzero: emits `spatial.torque`

**Thruster physics:**
- Port thruster fires on the port (left) side → pushes the nose starboard → **positive rotation** (clockwise)
- Starboard thruster fires on starboard (right) side → pushes the nose port → **negative rotation** (counter-clockwise)
- Equal power to both = no rotation

**Force constants:**

| Constant | Value | Effect |
|----------|-------|--------|
| THRUST_FORCE_PER_PIP | 50.0 | Forward force per pip per tick |
| TORQUE_PER_PIP | 2.0 | Rotational torque per pip per tick |

These are tuning knobs, like the damping values.

## Simulation Coordinator (`src/sim/init.lua`)

Orchestrates the per-frame tick cycle. Called by the simulator screen's `update(dt)`.

**Setup:** `sim.setup()` calls `spatial.setup()` and `engineering.setup()` to register bus subscriptions. Called once in `onEnter`.

**Update cycle** (runs inside `clock.step` at fixed 60Hz):

```
1. engineering.tick(dt)   -- generate pips
2. helm.tick(dt)          -- read power, emit thrust/torque events
3. bus.drain()            -- process all events (thrust handlers update velocity)
4. spatial.tick(dt)       -- integrate physics (position += velocity * dt)
```

The ordering matters:
- Engineering ticks first so pips are up to date
- Helm reads engineering state and emits force events
- Bus drain processes those force events (spatial handlers modify velocity)
- Spatial tick integrates the new velocity into position

## Extending

To add a new ship subsystem:
1. Create `src/sim/ship/newsystem.lua`
2. Add an `init(entityId)` function that sets up store keys
3. Add a `setup()` function that subscribes to relevant bus events
4. Add a `tick(dt)` function if it needs per-frame processing
5. Call `init()` from `ship/init.lua`, `setup()` from `sim/init.lua`, `tick()` from the sim update cycle

To add a new entity type:
1. Create it via `entities.create("typename")`
2. Initialize its components with `spatial.init()` and any subsystem-specific init
3. It will automatically participate in physics ticks and bus events
