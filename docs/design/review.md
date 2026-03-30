# Design Review — Architectural Feedback & Decisions

Feedback on the [design pitch](pitch.md), with owner responses and agreed decisions.

---

## Viability Assessment

**Verdict: Viable.** The three-layer architecture is sound, Love2D can handle it, and API costs for single-player dev are trivial. The hard part isn't technical — it's tuning the crew agents to be fun. That's prompt engineering and playtesting, which can only happen by building it.

The concept occupies a genuinely unexplored design space. It's not "AI chatbot with a game skin" and it's not "conventional game with AI dialogue." The AI crew as fallible interpreters between player intent and a deterministic simulation — that's the core mechanic, and it's a smart use of LLMs.

---

## What Works

### Simulation as ground truth
The AI can hallucinate in dialogue all it wants; the simulation doesn't care. If the warp core is offline, `engageWarp()` returns failure regardless of what the engineer *says*. This solves the biggest AI-in-games problem.

### Turn-based is the right model
API latency becomes "the crew is processing your order" instead of a bug. Also eliminates the need for async HTTP, which simplifies the Love2D side enormously.

### Star Trek fantasy
Everyone already understands the captain-gives-orders-to-bridge-crew dynamic. No need to teach the interaction model — players know it from TV.

---

## Risks & Mitigations

### 1. The fun/frustration razor's edge

**Risk:** The pitch says "a nervous pilot might hesitate, a cocky engineer might override you." In practice: the player types a perfectly clear command, the AI misinterprets it because of "personality," and the ship takes damage. That's not emergent gameplay — that's fighting your own UI.

**The critical question:** When the crew "fails," is it the player's fault or random bad luck? If it's random, it's frustrating. If the player can learn to communicate better with specific crew members, then crew personalities become a puzzle to solve. That's where the game lives.

**Decision:** Skill levels affect *competence* (how well they execute). Personality affects *how you need to communicate* (not whether they obey). A nervous pilot still sets the course — they just respond better to calm, clear orders than to shouted panic. Personality should never override a direct order from the captain. That breaks the fantasy.

> **Owner note:** Agreed. Hard rule.

### 2. Response parsing is the #1 technical risk

**Risk:** Asking an LLM to return structured SPEECH/ACTIONS/CREW_COMM output in text format. It will forget the format, put actions in the speech, use wrong parameter names, invent nonexistent actions, and return malformed JSON ~5% of the time. This isn't a "maybe" — it will happen.

**Decision:** Use **Claude API tool use / function calling** instead of text parsing. This is purpose-built for this problem — available actions are defined as tools, and Claude returns structured tool-use blocks that are guaranteed well-formed. Fallback: if tool use fails or returns nothing, treat the turn as "speech only, no actions taken." Never crash on malformed output.

> **Owner note:** Agreed. Tool use is the right approach.

### 3. Cascading agent communication needs hard limits

**Risk:** Captain tells pilot to go to warp. Pilot asks engineering for more power. Engineering reroutes power and tells pilot. Pilot tries again and asks engineering again... This can loop indefinitely, triggering unbounded API calls.

**Decision:** Hard limits:
- Maximum cascade depth: 2-3 levels
- Maximum API calls per player turn: ~5
- Each agent gets only one "turn" per cascade chain

Without these, one player command could trigger 10+ API calls and take 30+ seconds.

> **Owner note:** Agreed.

### 4. Prompt size growth

**Risk:** Each crew prompt includes personality, skills, full visible ship state, available actions, the captain's command, and prior context. As the simulation gets more complex, prompts grow. Could hit 2000+ tokens of context per call.

**Mitigation:** Not a cost problem for dev, but worth monitoring. The `getStationView(stationName)` approach (see Architecture section) naturally limits what goes into each prompt.

> **Owner note:** Acknowledged, watch it.

### 5. What the player sees is a core design question

**Risk:** The pitch punts this to playtesting, but it's more load-bearing than that. If the player sees a full tactical display with shield percentages and torpedo counts, why ask the tactical officer for a status report? The information asymmetry between player and crew is where interesting gameplay lives.

**Decision (for shipped game, eventually):** The player sees *less* than the crew — they're the captain looking at a viewscreen, not the officer at a console. Likely: a simple star map and a text log. Detailed information comes through crew dialogue. This reinforces the core mechanic.

**Decision (for development):** Build a fully deep dev display from day one. Full ship state, power grid, spatial map, system health, everything visible. This is the primary testing tool — without it, you can't tell whether a weird outcome is a simulation bug or an AI doing something unexpected. The dev UI is not the player UI. It's how we validate correctness.

> **Owner note:** Agreed emphatically. The dev display is non-negotiable. We need full observability to develop the simulation properly. The question of what the player sees comes later, after the simulation is proven.

---

## V1 Scope — Agreed Cuts

### Ship systems to include:
- **Helm:** heading, speed (impulse only — cut warp for V1)
- **Weapons:** phasers only (cut torpedoes — no ammo tracking)
- **Shields:** on/off, single strength value (cut per-facing, cut modulation)
- **Power:** total pool, simple percentage allocation (shields/weapons/engines)
- **Sensors:** see nearby objects, basic scan
- **Hull:** single HP value

### Cut from V1:
- Warp drive (use impulse + smaller map)
- Torpedoes
- Per-facing shields
- Shield modulation
- Communications/hailing
- Transporters
- Life support
- System damage/repair (hull takes damage, but individual system damage adds too much complexity)
- Agent-to-agent communication (V1: each agent responds independently)

### V1 crew:
- Helm officer
- Tactical officer
- Engineer (power routing only)

Three agents, three stations, three subsets of the API. Enough to prove the concept.

### V1 scenario:
Navigate to a waypoint. Encounter a hostile ship. Survive the fight (or don't). Exercises helm, tactical, shields, power tradeoffs, and sensors.

> **Owner note:** Agreed on all cuts.

---

## Architecture Decisions

### Event bus as the simulation backbone
All state changes flow through a central event bus. All systems interact by emitting and subscribing to events. This applies at every scale: within a subsystem (engineering components affecting each other), between subsystems (tactical firing -> shields absorbing -> hull taking damage), and between entities (ship-to-ship, ship-to-asteroid, anomaly-to-ship).

This is NOT a generic "everything is an event" pub/sub bolted onto conventional code. The bus IS the simulation. The same pattern handles "reverse the polarity of the phase inverter" and "fire phasers at the Klingon ship." One bus, one pattern, one place to look when debugging.

No subsystem directly mutates another's state. They communicate through events. This means systems are decoupled — you can add, remove, or modify any subsystem without touching others.

> **Owner note:** This was the key architectural discussion. The bus needs to work at every level — inside engineering (components and conduits), between subsystems, and between entities. Without this, you can't model Star Trek-style engineering problems where the player reroutes plasma through conduit B to bypass a blown relay. The bus makes that possible with the same pattern used everywhere else.

### Station-scoped state views
Each crew member sees different data. A `getStationView(stationName)` function returns only what that station's console would show. Keeps prompts focused and prevents agents from "knowing" things they shouldn't.

### Rich event results for AI agents
When events resolve (e.g., phasers hit a target), the results include full data — damage dealt, shield status, power consumed. AI agents receive these results so they can formulate realistic responses based on real simulation data, not hallucination.

### Cascade depth limits
Events can trigger other events (phaser hit -> shield absorption -> hull damage). The bus enforces a hard depth limit to prevent infinite loops. Same limit applies to AI agent cascades (captain -> pilot -> engineer -> done).

> **Owner note:** Agreed on all.

---

## Simulation Model — Real-Time with Freeze

Discussed two options: pure turn-based (discrete ticks, animated interpolation) vs. real-time with freeze (continuous simulation, pause for commands).

**Decision: Real-time with freeze.**

**Rationale:** The simulation needs to be tuned by feel. Adjusting thruster power and watching the ship arc in real time, then tweaking until it feels right — that's a fundamentally real-time feedback loop. Turn-based requires analytically computing "where will the ship be after N seconds of this acceleration and turning rate" (dead reckoning), which is harder math and harder to tune. With real-time, the physics IS the simulation — `velocity = velocity + acceleration * dt`, `position = position + velocity * dt`. What you see is what the simulation is actually doing.

**How it works:**
- Simulation runs in real time, always. Ships move, systems tick, power flows.
- When the player issues a command involving AI, the simulation **freezes** while the API call resolves. In-fiction: time pauses while the crew processes the order.
- **Periodic auto-freezes** (every N seconds, tunable) give the player natural decision points. Like a heartbeat — "here's what's happening, do you want to say anything?"
- Player can also **manually freeze** at any time to assess and issue commands.
- During a freeze, the player can queue multiple commands to different crew members. All resolve, then time resumes.
- Auto-freeze interval is a tuning knob: frequent = tactical/deliberate, infrequent = pressure/chaos. Could vary by situation (combat freezes more often than cruising).

**Fixed timestep physics:** The simulation uses a fixed internal timestep (e.g. 60Hz) regardless of frame rate. `love.update(dt)` accumulates dt and steps in fixed increments, with rendering interpolating between physics states. Prevents simulation from behaving differently at different frame rates. Worth doing from day one.

> **Owner note:** Agreed. Real-time is actually easier to develop and tune than turn-based for this kind of simulation. Fixed timestep confirmed.

---

## Build Order — Revised

The original pitch's implementation order was mostly right, but revised based on discussion:

1. **Ship data model + systems** — all state, interdependencies, power grid, damage propagation. Pure Lua, no rendering, no AI.
2. **Ship API** — the command interface. Functions callable directly from a dev console or test harness.
3. **Dev display** — full visibility into everything. Not pretty, but complete. Ship status panels, power distribution, spatial map, system health. Plus a way to issue Ship API commands directly (text input or clickable controls).
4. **Validate the simulation** — fly the ship around manually. Route power. Fire weapons. Take damage. Break things. Fix bugs. Spend real time here. If the simulation isn't interesting to interact with directly, it won't be interesting through AI intermediaries.
5. **Single AI agent** — hook up one crew member (pilot). Prove the full pipeline: player types command -> prompt constructed -> API called -> response parsed -> actions execute -> results display.
6. **Multiple agents & cascading** — add remaining crew stations, implement agent communication.
7. **Scenario & gameplay** — build the V1 scenario, playtest, tune prompts.
8. **Player interface** — decide what the player sees vs. dev-only.

The key insight: steps 1-4 are a game in themselves — a direct-control bridge sim. That's the foundation. Get it right before adding AI.

**Open question:** Consider proving Claude API connectivity early (before step 1) as a quick spike, since everything ultimately depends on it. Doesn't need to be integrated — just confirm luasocket/luasec + HTTPS to api.anthropic.com works from Love2D.

> **Owner note:** This is the plan. Simulation first, full observability, AI later. API spike noted — may do this first as a quick sanity check.
