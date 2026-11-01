# 0082: Source bodies and follow-up damage affect local broken glass one way

- Status: Accepted 2026-11-01 (R7-C, the user's request).
- Supersedes the map/piece-only contact rule in [0070](0070-glass-overhaul.md), printed decision 5
  (called decision 3 in the R7-C brief). Decision 3's deterministic pane fracture remains in force.
- Decided by: the user, asking for the Model Hotloader's one-way contact behaviour for broken glass.

## Context

G1 pieces share a bounded client Jolt world; Source cannot see them. The user now wants players,
NPCs, ragdolls and physics props to push and damage those pieces, with no reaction in Source.
Bullets, explosions and hard landings must also break large pieces again. Falling-piece rendering
and simulation performance work is explicitly deferred. See [the brief](../handover/R7-C-glass-interaction.md).

## Decision

1. Mirror nearby Source bodies as **kinematic** bodies in the existing client Jolt world. Living
   players/NPCs use axis-aligned collision hulls; ragdolls use up to 24 physics bones, or bone hitboxes
   when client physics is unavailable. Other objects use available physics convexes, with an oriented
   box fallback. Source transforms, velocities and masses are read only. No entity, PhysObj, damage,
   force or network update is ever sent back to Source.
2. Capture only live-piece interest regions: up to 32 512-unit cells, expanded by 96 units; discover
   up to 128 candidate entities at 10 Hz and refresh at most 96 body transforms each dispatched step.
   Cook at most two new shapes per snapshot (8 convexes/512 points per shape). Missing bodies are
   removed. Teleports over 128 units correct poses without producing enormous collision velocities.
3. Estimate contact energy from pre-solver normal speed. Body contacts require 160 units/s, falls
   220; use the piece's mass for falls, and the lesser of source mass and eight piece masses for
   bodies. Threshold is `max(12000, 36000 * sqrt(area / 64) * thickness^2)`. These are tunable gameplay
   defaults. Only sufficiently large pieces queue damage; small pieces still move. No piece-piece
   damage cascade runs in a falling pile. Blast velocity kicks also supply damage energy.
4. Bisect a damaged convex polygon along its longest axis into two convex equal-area parts. Preserve
   area, thickness, the parent's pose and point velocities (including angular velocity). Descendants
   inherit the original expiration time. Respect the configured piece-size floor and existing budget,
   with oldest-first eviction. Native replacement is transactional and stays within its hard capacity.
   Coalesce at most 64 damage events; process at most one binary replacement per client frame, stopping
   stale work after 0.75 ms. A mesh/cooking call cannot be preempted.
5. Observe the server's `PostEntityFireBullets` final pellet traces without changing bullets or weapon
   callbacks. Forward Source-clipped rays only through one of 32 recent-break regions (120 s, radius
   768–2048), to their PVS and the shooter. Token buckets cap traffic at 64 rays/s globally (burst 32)
   and 16/s per firing entity (burst 8). A client queues 32 rays for at most 0.5 s, raycasts at most
   eight/frame, and pushes/damages the nearest local piece. No client-to-server ray or per-piece state.
6. `rtx_glass_debris_interact` defaults to 1, archived per player, with a checkbox and all seven menu
   translations. Off removes mirrors/damage work and keeps G1's map/piece collision and blast push.
   A missing or older native module retains G1's conservative fallback and reports interaction unavailable.

## Consequences

Panes and their initial fracture remain deterministic and authoritative; subsequent cosmetic pieces
may differ between clients. Engine shapes and ray delivery remain bounded approximations: dense scenes,
remote ragdoll bone availability, fast bodies outside discovery margins, old/distant piles outside recent
break regions, and weapons that do not use FireBullets can miss interactions. Saturation drops cosmetic
work rather than delaying Source gameplay. Real frame-time parity and contact tuning require Claude's
PoC QA; offline measurements do not establish a game-performance result.

## Alternatives considered

- Two-way Source physics/per-piece server entities: contradict the user's one-way/local requirement.
- Whole-map entity scans or every bullet broadcast: unbounded work unrelated to visible glass.
- Splitting on every piece-piece collision: creates cascades while many pieces fall, outside this task.
- Predicted and server bullet rays together: duplicates local bullet effects without adding needed coverage.
