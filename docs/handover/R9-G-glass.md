# R9-G: realistic fracture, instant breaks, sounds, water, blasts, stable pushes, a clear button (brief)

Read [AGENTS.md](../../AGENTS.md), [R9-plan.md](R9-plan.md), [R8-G-report.md](R8-G-report.md),
[R8-report.md](R8-report.md), [R7-C-report.md](R7-C-report.md), [G1-report.md](G1-report.md),
[glass/README.md](../../glass/README.md), [glass/native/README.md](../../glass/native/README.md) and ADRs
[0070](../decisions/0070-glass-overhaul.md), [0071](../decisions/0071-glass-impact-model.md),
[0074](../decisions/0074-glass-contact-and-quiet-map-outputs.md), [0075](../decisions/0075-incremental-glass-topology.md),
[0076](../decisions/0076-glass-bounded-break-density.md), [0077](../decisions/0077-glass-client-build-queue.md),
[0084](../decisions/0084-glass-one-way-interaction.md) and [0085](../decisions/0085-glass-load-collision-and-hits.md).
Work on branch `r9-glass` in `out/worktrees/r9-glass`. Owns: `glass/**`, `tools/tests/*glass*` and
`tools/tests/*nlglass*`, `tools/qa/nlglass_qa/**` and `tools/qa/*glass*`, `tools/glass_i18n.py` (and
`glass/i18n`), ADR 0087, and additive edits to CHANGELOG (its `### R9` section), ROADMAP, RESEARCH, TESTING
and COMPONENTS. Does not touch `loader/**`, `companion/**`, `packages/**`, `runtime/**`, `skills/**`.

## The user's requests (2026-11-02)

1. "Glass fractures' break down is always square and uniform, and it could not be broken down into very
   small pieces. Make the breaking of glass fracture realistic."
2. "There is a highly visible latency when the bullet (the window take damage) and the window start to
   break."
3. "Glass fracture has no sound effect when interacting with the world, when broke or collision."
4. "Glass fracture has no buoyancy and does not interact with explosions."
5. "The velocity transfer is not stable enough, the glass can fly out in reverse."
6. "Add a button in the menu to clean up the broken glass."

## What Claude found by reading (starting points: verify them)

1. **Fracture.** A fallen piece splits in `split_polygon` (`glass/native/fracture.cpp`): it halves the
   piece's bounding box along its longer axis by area, so every follow-up break makes two near-rectangles.
   `World::split` refuses a minimum size under 4 units, and `create()` marks a piece unsplittable below
   twice the minimum; the pane's `piece_size` (default 8, 4-64) is that minimum. Tempered panes shatter
   into an evenly divided grid of near-square tiles (`fracture.lua`, `uniform`, at most 300). Annealed
   panes use G1's seeded radial rays and rings, at most 200 live cells.
2. **Latency.** On a hit the client queues the pieces in R8-G's FIFO construction queue: at most 12
   meshes/bodies and 8,192 vertices a frame, yielding after 0.75 ms (`debris.lua`). A 100-300 piece break
   needs 8-25 frames to appear, in fracture order, not nearest the impact or the camera first. The pane's
   remaining mesh (the hole) builds no earlier than the next frame, two panes a frame within 1 ms
   (`client.lua`, ADR 0077). Map windows keep engine health: our break follows the engine's OnBreak bridge
   (`server.lua`, ADR 0074), possibly a tick or more after the bullet. Measure before changing anything:
   the bullet's server damage, the client's receipt, the first piece drawn, the hole drawn, the last piece
   built, for a spawned pane and a map window, pistol and SMG, in single player.
3. **Sound.** Only a pane's break plays a sound: `physics/glass/glass_sheet_break1-3.wav` at the impact
   (`client.lua`). Pieces are client-only Jolt bodies: their impacts with the map, props or each other,
   their landings and their later splits are silent.
4. **Water and blasts.** Pieces fall through water as through air. The server sends `nlglass_blast` from
   `EntityTakeDamage` for `DMG_BLAST` on any entity (`server.lua`, `S.Blast`: radius damage×4 in 64-2048,
   speed damage×6 in 50-900, two turns later); clients call `NLGlassDebris.Impulse` (`World::impulse`, a
   radial velocity kick with linear falloff). The user says piles do not react to explosions. Find out
   why in the game: an explosion that damages no entity sends nothing; the speeds may be too low; sleeping,
   batched or grouped pieces; a capability or interest gate.
5. **Reverse flight.** Break velocities look correctly signed (`damage.lua`: bullet force, the hitting
   body's relative velocity, blast force). Candidates on the native side: pieces spawned overlapping a
   Source-body mirror (a player or prop still passing through the hole); kinematic mirrors that move
   (`MoveKinematic`) or are teleported (`skip_mirrors` pose corrections, the 128-unit teleport rule) into
   thin pieces, which Jolt's penetration recovery pushes out along the shortest axis, often backwards
   (Jolt's CCD excludes kinematic bodies, `world.cpp`); the sweep transfer's penetration axis when the cast
   starts overlapped. Reproduce first: per-piece velocity against the impact direction after a pane breaks
   under a running player, a thrown prop, a fast prop and bullets.

## What to build

1. **Realistic fracture, down to very small pieces.**
   - Annealed panes keep radial cracks from the impact and concentric rings, but the cells become shards:
     long, thin, irregular triangles and polygons, many very small fragments near the impact (a crushed
     zone), larger shards farther out, branching secondary cracks. It stays deterministic and
     integer-seeded, identical on server and clients, within the per-pane cell limits and the 512-cell
     snapshot ceiling (or change them with a measured reason, superseding ADR 0076's numbers).
   - Tempered panes shatter whole into many small, slightly irregular pieces, denser near the impact, not
     a regular grid.
   - A hit on a fallen piece splits it realistically around the hit point: several fragments (say 2-6), cut
     by crack lines through or near the hit at seeded irregular angles, not an axis-aligned halving.
     Repeated hits keep breaking pieces down to very small fragments, well below today's 4-unit floor (for
     example 1 unit), within the piece budget. Tiny fragments may be made cheaper if the cost demands it
     (no collision with each other, simpler hulls, or a dust/particle effect below a size): say what you
     chose and why.
   - Keep: no glass lost or duplicated (area), the budget and lifetime, R8's grouping of distant detail,
     and R8's falling cost (the 50-pane field scene: falling mean at most settled + 8.5 ms, p99 at most
     67 ms; Claude remeasures).
2. **Breaks without visible latency.** The hole and the first pieces appear in the frame the hit reaches
   the client, nearest the impact (and the camera) first, the rest without visible popping: for example
   draw not-yet-built pieces from one shared mesh, moving ballistically until their bodies exist, or give
   one pane's break a larger first-frame budget. Report the chain above before and after, in numbers. If
   the server or the map-window bridge adds a delay, remove it where safe: never break an engine-owned
   window early (ADR 0074).
3. **Sounds**, played by the client from the native world: piece impacts with the map, props and each
   other (soft or hard by impact speed and size), landings, and splits (a small break sound). Use the
   game's own glass sounds (`physics/glass/*`; confirm they ship with vanilla GMod). Positional,
   distance-culled and rate-limited per piece, per frame and per second: a settling pile must not spam.
   The native contact events must be bounded and cheap: a fixed-size buffer filled in a contact listener,
   read at the worker boundary. Add an archived client setting to turn them off, in the menu, in seven
   languages.
4. **Water and blasts.**
   - Pieces in water sink slowly, with drag, and tumble, as glass does (density about 2.5). Find water
     volumes from the map (the BSP's water brushes or leaves, whichever is reliable). Use Jolt's buoyancy
     (`Body::ApplyBuoyancyImpulse`) for each piece in water. A splash sound or effect on entry is welcome.
   - Every explosion near pieces pushes them, wakes sleeping and batched ones and breaks the weak ones.
     That includes explosions that damage no entity: barrels, grenades, RPG rockets, `env_explosion` and
     `util.BlastDamage`. Find a reliable server signal and keep it bounded.
5. **Stable velocity transfer.** No piece flies backwards toward what broke or pushed it, except a small,
   measured share from real bounces. Fix the cause, for example spawn-time overlap with mirrors, teleports
   or deep penetration, rather than clamping every velocity. Keep the one-way rule: pieces never push or
   damage Source.
6. **A "Clear broken glass" button** in the glass settings menu. It clears this client's fallen pieces. An
   admin in single player or on a listen server also gets a way to clear everyone's; the server's
   `nlglass_clear` already clears all clients. Seven languages through `tools/glass_i18n.py`.

## Tests, evidence and report

- Native and LuaJIT tests for each change:
  - Pane fracture is deterministic, on server and client and across runs.
  - Area is conserved; piece counts and sizes are right.
  - Splits are irregular, not axis-aligned halves.
  - Sound events stay within their bounds; buoyancy works; blasts are detected.
  - No backward velocity in the reproduction cases.
  - The clear button works.
- Offline cost before and after: ms per pane break, the native split, contact events, buoyancy.
- QA modes in `tools/qa/nlglass_qa` that print numbers:
  - the latency chain;
  - per-piece velocity against the impact direction;
  - an explosion beside a settled pile;
  - pieces in water;
  - sound event counts.
- PoC sessions are allowed with `tools/poc_session.py`, on the PoC only, never the field. Check that no
  PoC game is running first. The PoC takes the RTX package from the Workshop. To test your build there:
  - build a local package in your worktree, with the rebuilt module in your worktree's
    `out/inputs/glass/bin` (never `packages/`);
  - allow it with `poc_session.py install --allow-local <gma> --replace-config`;
  - put the Workshop-only config back when you finish.
- `tools\test.ps1 -Config Release` must pass. Commit on `r9-glass`: no push, merge, package import, field
  install or Workshop update. Claude imports the rebuilt module.
- Record decisions in ADR 0087.
- Report in `docs/handover/R9-G-report.md`, for each item: what you found (with numbers), what you
  changed, and what Claude must check in game.
