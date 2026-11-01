# R7-C: broken glass reacts to the world, one way (brief)

Read [AGENTS.md](../../AGENTS.md), [R7-plan.md](R7-plan.md), [G1-report.md](G1-report.md) (what G1 built and
measured), [glass/README.md](../../glass/README.md), [glass/native/README.md](../../glass/native/README.md)
and [ADR 0070](../decisions/0070-glass-overhaul.md). Work on branch `r7-glass-interact` in
`out/worktrees/r7-glass-interact`. Owns: `glass/**`, `third_party/jolt/**` (unchanged unless needed),
`tools/tests/*glass*` and `tools/tests/*nlglass*`, `tools/qa/nlglass_qa/**` and `tools/qa/*glass*`, a new
ADR, and additive edits to CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS. Does not touch `loader/**`,
`packages/**`, `runtime/**`, `skills/**`.

## The user's decision (2026-11-01)

"Further improve the interaction of the scattered glass, make it interact with follow up damage like
falling, shooting and explosion. Player and physics objects in Source (like ragdolls) should push or damage
the glass, but glass should not affect them in reverse (like what we implemented for the MMD physics)."
This supersedes ADR 0070's decision 3 (pieces collided only with the map and each other); record it in a
new ADR that supersedes that point.

## What to build

1. **Source bodies push pieces, one way.** In each client's Jolt world, mirror the Source bodies near live
   pieces as kinematic bodies that move with their entities (velocity from their motion, so contacts push
   pieces naturally): players and NPCs (their hull, or per-bone shapes from hitboxes and bone matrices),
   ragdolls (per bone), props and other physics objects (their physics shape where the client has one,
   else their oriented box). Only bodies whose bounds come near live pieces, with a cap, refreshed each
   step; nothing goes back to Source: pieces never push, slow or damage anything. The Model Hotloader's MMD
   physics does the same for hair and cloth (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua`:
   region-limited capture, living players/NPCs told apart, ragdolls as objects); read it for behaviour and
   write our own (MIT).
2. **Follow-up damage breaks pieces.** A piece breaks into smaller pieces when hit hard enough: by a
   bullet, by a blast (blasts already push through `NLGlassDebris.Impulse`), by a fast or heavy body (a
   thrown prop, a falling ragdoll, a running player), and by its own fall (a large piece landing at speed).
   Split a piece's convex polygon into a few convex parts (keep area and thickness, small parts fast,
   respect the minimum piece size, smallest pieces only move), under the existing budget (2,000 live,
   oldest first) and without a burst that stalls a frame.
3. **Bullets reach the pieces.** Pieces exist only on clients. Get bullets to them with a bounded cost:
   for example the server sends rays only near where glass broke recently (PVS, rate-limited), and/or
   each client uses its own predicted bullets; then ray-cast the Jolt world, push and break what is hit.
4. **A setting** to turn the interaction off per player, in the glass settings menu with its seven
   translations (`tools/glass_i18n.py`).

Keep G1's guarantees: deterministic panes and fracture on server and clients, pieces local to each client,
the budget, lifetime, explosions, map import, the fallback without the module (it may simply not interact,
or interact coarsely). Do not work on the falling-pieces frame cost (the user, 2026-11-01), and do not
make it worse: in field run 10 the 50-pane scene measured 25.31 ms mean, 113 ms p99 falling, 9.74 ms
settled (`glass/README.md`, `docs/handover/G1-report.md`).

## Tests and report

Native tests (kinematic bodies push pieces and are never moved by them; split pieces keep area, stay
convex and respect the budget), the Lua harnesses for scene capture, bullet messages and the setting, and
QA steps in `tools/qa/nlglass_qa` for Claude to run on the PoC: walk through a pile, drop a ragdoll and
throw a prop onto one, shoot into one, blast one, drop a large piece from a window. `tools\test.ps1 -Config
Release` must pass; commit on `r7-glass-interact` (no push, merge, package import, game install change or
Workshop update; Claude imports the rebuilt module). Report in `docs/handover/R7-C-report.md`: commits,
design, measured costs (offline), the QA steps, limits.
