# Ideas

Stuff worth considering. Not commitments, not plans — just interesting directions that came up during development.

## Crew Competency Levels

Crew members could have leveled knowledge of ship systems. "Warp engine knowledge level 1" vs "level 5" gates what the AI crew member knows and can reason about. A level 1 engineer can reroute power but doesn't understand why the plasma manifold is overheating. A level 5 engineer knows the thermal coupling coefficient is off and suggests recalibrating it.

This creates scenario variety: navigating a crisis with a crew of doctors and one entry-level engineer is a fundamentally different challenge than commanding a flagship's full complement of experts going into battle. The player's job shifts from "give the right order" to "figure out what orders this crew can actually execute."

## Three Knowledge Layers

Distinct from each other, serve different purposes:

1. **Crew competency data** — structured, leveled. Gates what each crew member knows. Used to select which knowledge gets included in their prompt.

2. **Crew working knowledge** — operational understanding of how systems work, written at the level a working crew member thinks about them. "When you allocate pips to the main thruster, the ship accelerates." This is what the AI uses to reason about commands.

3. **The ship's technical manual** — an in-universe published document. Dense, complete, technobabbly. What the ship's computer quotes when the captain asks "how does the defluxer work?" Deliberately harder to parse than crew working knowledge because it's a reference document, not operational experience.

## The Ship's Computer as a Crew Member

The ship's computer is a crew member, but a strange one. It doesn't have personality or initiative. It reads from the technical manual and gives precise, formal, sometimes hard-to-parse answers. "Computer, describe the warp engine defluxer component" returns technobabble that the captain has to interpret — or ask the engineer to translate.

## Player Skill as Understanding Your Ship

A captain who's read the technical manual and understands the defluxer can give better orders than one who hasn't. The player skill curve isn't twitch reflexes or system mastery — it's understanding your ship well enough to lead effectively. You learn the ship by reading the manual, by asking the computer, by talking to your crew, and by watching what happens when things go wrong.

## Zachtronics-Adjacent Puzzle Space

Zachtronics games (TIS-100, Shenzhen I/O) ship in-universe documentation that IS the game — you read it, misunderstand it, re-read it, build understanding. Here the twist is that your crew members are also reading it (at their competency level), and their interpretation may differ from yours. The puzzle isn't strictly deterministic like Zachtronics — the non-deterministic AI behavior is intentionally part of the draw. But there might be something in the space of: "here is a complex system described in a manual, here is a problem, here is a crew with varying levels of understanding — figure out how to talk them through fixing it."

## Scenario Variety from Crew Composition

Same ship, same crisis, wildly different experience based on who's on the bridge. Full expert crew = tactical challenge. Skeleton crew of non-specialists = communication and improvisation challenge. One scenario, many replays with different difficulty curves based purely on crew composition rather than enemy scaling.
