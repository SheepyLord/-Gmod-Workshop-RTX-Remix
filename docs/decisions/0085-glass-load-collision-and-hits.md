# 0085: Bound falling-glass work, choose Source contacts, and route hits to live local piles

- Status: Accepted 2026-11-01 (R8-G, the user's request).
- Supersedes ADR [0084](0084-glass-one-way-interaction.md)'s fixed recent-break routing and all-Source
  contact default. Pane authority, local cosmetic pieces and one-way contacts remain unchanged.

## Context

R7's 50-pane test costs 26.28/134.30 ms mean/p99 with interaction off and 28.60/134.33 ms on,
against 9.17/9.32 ms settled. About 1,300 moving draws cost 6.9 ms in the Lua draw hook alone.
Synchronous creation also introduces large bursts. Recent server break regions expire independently
of client lifetimes, cannot follow displaced pieces, and do not observe melee misses through local
glass. The user requests smart load mitigation, collision checkboxes with living entities off, and
bullets/melee affecting pieces regardless of when the pane broke.

## Decision

1. Separate receipt of a break from bounded client mesh/body creation. Under load coarsen only local
   released fragments, preserving their covered area and the pane's authoritative outline/hole.
   Keep nearby detail. Measure the actual algorithm and creation/draw counts offline; game mean/p99
   acceptance belongs to Claude. Keep the sleeping-pile batching path and Jolt sleep/solver settings.
2. `rtx_glass_debris_collide_with` is a client bit mask: objects=1, ragdolls=2, living players=4,
   living NPCs/NextBots=8. Default 3. Filter discovery before engine shape extraction and tag native
   snapshot rows for a second check. Changing the native mask removes obsolete mirrors immediately
   at the next idle boundary. The interaction switch remains the master, including follow-up damage.
   Map/piece contacts are always enabled by the manager. Retire the old piece-collision checkbox once,
   without changing the master switch, lifetime, budget or explicit new mask. Preserve later choices.
3. Route cosmetic hit observations to bounded, expiring interest refreshed by each client's actual
   live-piece regions; a finite lease is refreshed even with indefinite debris lifetime. Client input
   describes interest only, never damage, target IDs or gameplay state. Validate/rate-limit it and
   rate-limit server hit inspection/delivery. Server observations preserve Source occlusion and never
   modify weapon callbacks, traces, damage or animation returns. Add a bounded melee path for stock
   weapons and trace-based SWEPs. Clients retain a bounded short-lived queue and only mutate Jolt.
4. Continue oldest-first budgets, original descendant expiry, minimum-size movement, blast pushes,
   deterministic pane replay, optional module fallback, numerical region tests and all capture caps.
   Saturation drops cosmetic work, never delays Source. Publish counters and executable QA steps for
   delayed pistol/SMG hits, crowbar, independent client masks and the unchanged 50-pane frame scene.

## Consequences

Cosmetic fragment detail and subsequent motion can differ between clients. Discovery, creation and
hit delivery have finite caps; these are work limits, not guarantees about indivisible engine calls.
No Source force/damage, server shard entities, package imports or game installation changes are needed.
The report records exact implemented limits, measurements and remaining game acceptance checks.

## Alternatives considered

- Changing authoritative pane density: changes all players' holes/collision and is unnecessary.
- Sleeping falling glass early: visible mid-air freezes and missed landings.
- Broadcasting all bullets forever or networking pieces: traffic grows unrelated to local interest.
- Applying damage from client claims: unnecessary trust; only the server observes attacks.
