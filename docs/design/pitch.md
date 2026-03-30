# Starship Captain — Architectural Pitch & Design Brief

## For: Claude Code (implementation partner)
## From: Design & architecture collaboration (Claude + human)

---

## The Concept

A single-player, turn-based strategy game where you are the captain of a starship (Star Trek style). Your **only means of interaction** is issuing natural language commands to your AI-powered crew. You cannot directly control the ship. You talk to people, and those people operate the ship.

Each crew member is an **individual AI agent** — powered by the Claude API (or potentially OpenAI). They have distinct personalities, skill levels, knowledge, and access to specific ship systems based on their station. When the player (captain) speaks to a crew member, their input is sent to the Claude API with a carefully constructed prompt that models who that crew member is and what they can do.

The crew members don't just talk back. They **take actions** against a deterministic ship simulation. And that simulation is the source of truth — no hallucinations, no fudging. If the warp core is misconfigured, the ship behaves accordingly regardless of what any AI agent *thinks* is happening.

---

## Why This Is Interesting

The player's challenge is **leadership and communication**, not system mastery. You can't click a "fire torpedoes" button. You have to tell your tactical officer to fire, and they interpret your command through their own skill level and personality. A nervous pilot might hesitate. A cocky engineer might override your power routing suggestion. The AI agents are **fallible interpreters** standing between your intent and the hard simulation.

This is a genuinely unexplored design space. Existing AI-in-games work falls into two camps: pure narrative (AI Dungeon — no deterministic simulation underneath) or dialogue bolt-ons (Inworld AI, NVIDIA ACE — conventional games with LLM-powered NPC chat). Nobody has built the three-layer architecture described below, where AI agents serve as the core interaction mechanic mediating between player intent and a deterministic simulation.

---

## The Three-Layer Architecture

### Layer 1: The Universe & Ship Simulation (Pure Lua, No AI)

This is the deterministic backbone. Zero AI involvement. It models:

**Space:**
- 2D (or simple 3D-projected-to-2D) spatial model
- Ship position, velocity, heading
- Other objects: planets, starbases, enemy ships, anomalies
- Distances, travel times, sensor ranges

**The Ship — Interconnected Subsystems:**
- **Helm/Navigation:** Heading, speed, warp factor, impulse, current course
- **Warp Drive:** Warp core status, fuel/energy, warp factor limits, potential malfunctions
- **Impulse Engines:** Sublight movement, maneuvering
- **Shields:** Shield strength (possibly per-facing), power draw, modulation
- **Weapons:** Torpedo inventory/loading/firing arcs, phaser banks, power draw, targeting
- **Sensors:** Detection ranges, scan capabilities, what's currently visible
- **Power Grid:** Total power generation, distribution across subsystems, the ability to route more power to one system at the cost of another — this is where Star Trek-style tradeoffs live
- **Hull Integrity:** Damage model, breaches, affected systems
- **Communications:** Hailing, distress signals
- **Transporters:** Range, requirements (shields down), personnel movement
- **Life Support:** Usually background, becomes critical under damage

**Key design principle:** These systems should be **interdependent**. Shields draw power. Firing weapons draws power. Warp drive draws a lot of power. Damage to the power grid cascades. A hull breach near engineering might knock out warp. This interdependence creates the emergent complexity that makes the game interesting — and makes the AI crew's job nontrivial.

**The Ship API:**
This layer exposes a clean Lua API — a set of functions that represent the actions available at each console/station. Examples:

```lua
-- Helm
ship:setHeading(bearing)
ship:engageWarp(factor)
ship:engageImpulse(throttle)
ship:allStop()
ship:plotCourse(destination)

-- Tactical
ship:lockTarget(targetId)
ship:fireTorpedo(targetId)
ship:firePhasers(targetId, power)
ship:raiseShields()
ship:lowerShields()
ship:modulateShields(frequency)

-- Engineering
ship:routePower(fromSystem, toSystem, amount)
ship:repairSystem(systemName)
ship:ejectWarpCore() -- desperate times
ship:setWarpCoreOutput(level)

-- Science/Sensors
ship:scanObject(targetId)
ship:longRangeScan()
ship:analyzeAnomaly(targetId)

-- Communications
ship:hail(targetId)
ship:broadcastDistress()

-- Ops/Transporter
ship:transportTo(targetId, personnel)
ship:transportFrom(targetId, personnel)
```

Each function validates its inputs, checks preconditions (can't fire torpedoes if torpedo bay is damaged, can't go to warp if warp core is offline), and returns a result struct indicating success/failure and any relevant data.

**This API is NOT exposed to the player.** It is exposed to the crew agents (Layer 2), scoped by station.

---

### Layer 2: The Crew Agents (AI-Powered via Claude API)

Each crew member is defined by:

1. **Identity & Personality:** Name, background, temperament, quirks
2. **Skills:** A specific list of what they know and how well they know it (expert pilot but poor combat tactician, etc.)
3. **Station Assignment:** Which console they're at, which determines...
4. **Available Actions:** A subset of the Ship API commands they can invoke
5. **Visible State:** What ship/universe data their console can display (helm sees navigation data, tactical sees weapons and shields, engineering sees power grid and system health)

**How a turn works:**

1. Player types a command: *"Mr. Kim, set a course for Starbase 12, warp 6."*
2. The game identifies the addressed crew member (Kim, helm officer).
3. A prompt is constructed and sent to the Claude API:

```
You are Lieutenant Kim, helm officer aboard the USS Resolute.

PERSONALITY: Disciplined, slightly anxious under pressure, very by-the-book.
SKILLS: Expert stellar navigation, proficient impulse maneuvering, competent warp transit (occasionally overthinks warp calculations under stress).

CURRENT SHIP STATE (your console):
- Position: Sector 4.7.2
- Heading: 147 mark 3
- Speed: Full stop
- Warp core: Online, nominal
- Warp fuel: 78%
- [Starbase 12 is at Sector 9.1.4, bearing 042 mark 0, distance 14.3 light years]

AVAILABLE ACTIONS (you may invoke zero or more):
- setHeading(bearing)
- engageWarp(factor)
- engageImpulse(throttle)
- allStop()
- plotCourse(destination)

YOUR CAPTAIN HAS JUST SAID TO YOU:
"Mr. Kim, set a course for Starbase 12, warp 6."

Respond with:
1. What you SAY back to the captain (in character).
2. What ACTIONS you take (as a JSON array of action calls, or empty if none).
3. Optionally, any CREW COMMUNICATION — things you say to other crew members that should trigger their response.

Format your response as:
SPEECH: [your verbal response to the captain]
ACTIONS: [{"action": "setHeading", "params": {"bearing": "042 mark 0"}}, {"action": "engageWarp", "params": {"factor": 6}}]
CREW_COMM: [{"to": "engineering", "message": "..."}] or []
```

4. The API response is parsed:
   - SPEECH is displayed to the player in the text log
   - ACTIONS are validated and executed against Layer 1 (the ship sim)
   - CREW_COMM triggers follow-up prompts to other agents (which may themselves take actions)

5. After all cascading agent actions resolve, the ship simulation ticks forward (if turn-based) or continues running (if real-time-with-pause).

**Agent-to-agent communication** is important. The captain says "get us out of here." The pilot might realize they need more power to warp and message engineering. Engineering might respond by pulling power from sensors. This cascade should be visible to the player in the text log — like overhearing bridge chatter.

**Error handling is critical.** The AI will sometimes produce malformed or nonsensical action calls. The ship API should reject invalid calls gracefully, and the game should handle API failures (timeouts, rate limits) without crashing — perhaps with a "crew member is momentarily unresponsive" in-fiction explanation.

---

### Layer 3: The Interface

**Text Layer (always present):**
- Scrolling log of all captain/crew dialogue, crew-to-crew chatter, and system events ("Torpedo impact — forward shields at 63%")
- Text input field for the captain's commands
- Possibly a command history

**Visual Debug Layer (always present during development, selectively exposed to player later):**
- **Star map:** 2D view showing ship position, nearby objects, course heading, sensor range rings
- **Ship schematic:** Top-down or side-view of the ship showing subsystem locations and damage
- **Power grid display:** How power is distributed across systems, total generation vs. demand
- **System status panels:** Quick-read status of each major subsystem
- **Agent state inspector:** (Dev-only) Shows each crew member's current prompt context, last response, and queued actions

The open design question: how much of the visual layer does the player ultimately see? The captain wouldn't be blindfolded — in Star Trek, Picard looks at the viewscreen and reads status displays. So the player probably gets the star map and some system readouts. But the player cannot *click* anything on those displays to issue commands — they must still speak to crew. This question can be answered through playtesting. The important thing is that the **full visual layer exists from day one for development and debugging.**

---

## Technical Considerations

**Engine:** LÖVE (love2d). Lua-based game framework. Chosen because the deterministic ship simulation benefits from a real game loop (`love.update(dt)`), and the visual debug/display layer is dramatically easier to build with LÖVE's rendering than in a browser. The game is fundamentally a simulation with a text interface bolted on — not a text app with a simulation bolted on.

**HTTP/API Calls:** LÖVE doesn't include HTTP natively. You'll need `luasocket` + `luasec` for HTTPS. Since the game is turn-based and pauses during command processing, blocking HTTP calls are fine — no async complexity needed. Just: pause → call API → get response → parse → execute actions → unpause. Lua coroutines could also work here if we want the UI to show a "thinking..." animation during the call.

**API Choice:** Claude API (api.anthropic.com) is the current preference. The endpoint is a simple POST to `/v1/messages` with JSON body. Response is JSON with a `content` array of text blocks. Nothing exotic.

**Response Parsing:** The structured response format (SPEECH/ACTIONS/CREW_COMM) needs robust parsing. The AI won't always format perfectly. Consider: asking for JSON-only responses, then post-processing to extract dialogue. Or: using XML-style tags in the prompt to get more reliable structured output. Build the parser to be forgiving and to gracefully handle malformed responses.

**Cost:** Each crew interaction is one API call. A cascading command (captain → pilot → engineer) could be 2-3 calls. At Claude Sonnet pricing this is fractions of a cent per call. For single-player development this is negligible. For a shipped product with many users, it's a real concern — but that's a future problem.

---

## Suggested Implementation Order

1. **Ship simulation layer first.** Get the data model working — ship state, subsystems, power grid, spatial model. Get the Ship API working and tested with direct Lua calls (no AI yet). Build the visual debug display so you can see the state.

2. **Single crew agent.** Get one agent (the pilot) working end-to-end: player types command → prompt is constructed → API is called → response is parsed → actions execute against ship sim → results display. This proves the full pipeline.

3. **Multiple agents & cascading.** Add more crew stations. Implement agent-to-agent communication and action cascading.

4. **Scenario & gameplay.** Build a simple scenario (navigate to starbase, encounter enemy, survive combat) that exercises the full system. Playtest. Tune prompts.

5. **Polish the player interface.** Decide what the player sees vs. what's dev-only. Add the text log, star map, ship displays.

---

## What We'd Like From You (Claude Code)

1. **Review this architecture.** Does it hold up? Are there structural problems we're not seeing? Are there Lua/LÖVE-specific considerations that affect the design?

2. **Propose a project structure.** Directory layout, module organization, how the three layers are separated in code.

3. **Flag risks.** What's going to be harder than we think? What should we prototype first to de-risk?

4. **Suggest simplifications for V1.** Where can we cut scope to get a playable proof-of-concept faster without compromising the core concept?

We're not looking for final code yet — we want your architectural feedback first. Then we'll iterate on the design together before you start building.