# R8-G: glass under load, collision levels and follow-up hits (brief)

Read [AGENTS.md](../../AGENTS.md), [R8-plan.md](R8-plan.md), [R7-report.md](R7-report.md) (the 50-pane
measurements and R7's integration fixes), [R7-C-report.md](R7-C-report.md), [G1-report.md](G1-report.md),
[glass/README.md](../../glass/README.md), [glass/native/README.md](../../glass/native/README.md),
[ADR 0070](../decisions/0070-glass-overhaul.md) and [ADR 0084](../decisions/0084-glass-one-way-interaction.md).
Work on branch `r8-glass` in `out/worktrees/r8-glass`. Owns: `glass/**`, `tools/tests/*glass*` and
`tools/tests/*nlglass*`, `tools/qa/nlglass_qa/**` and `tools/qa/*glass*`, `tools/glass_i18n.py` (and its
data), ADR 0085, and additive edits to CHANGELOG, ROADMAP, RESEARCH, TESTING, COMPONENTS. Does not touch
`loader/**`, `companion/**`, `packages/**`, `runtime/**`, `skills/**`.

## The user's requests (2026-11-01)

3. "Investigate and resolve the frame cost while lots of glass falls at the same time. Some smart
   mitigation is okay."
4. "For glass, add collision level settings like what we had in the mmd physics, it should by default not
   collide with any living entities like players and NPCs."
5. "For glass, shooting the fractured glass with bullet or crowbar damage does not break them further."

## What to build

1. **Falling cost.** The 50-pane field scene (the QA's `field` mode: the G1 sequence, then 50 panes broken
   by blasts within 1.5 s; gm_construct, Jolt, piece size 8, 2,000-piece budget) measured, same build:
   interaction off 26.28 ms mean / 134 ms p99 while 2,000 pieces fall (manager think 1.79 ms, draw
   6.90 ms, ~1,230 moving, ~1,330 draws), on 28.60 / 134 ms; settled 9.2-9.3 ms. Find where the time goes
   (Lua per piece, draw calls, mesh creation and the break burst, native step, and what the engine and
   Remix pay per moving draw: ~1,300 extra instances a frame) and cut it. Smart mitigation is welcome:
   for example spread piece creation of a burst over frames, adaptive detail when many pieces move at
   once (fewer, larger pieces for a falling region on this client; the pane's outline and hole stay
   deterministic), size/distance limits for tiny moving pieces, fewer draw calls for moving pieces, less
   per-piece Lua. Keep what the player sees near the camera. Target in game (Claude measures): the
   falling mean and p99 at least halved relative to settled (from +17 ms to at most +8.5 ms mean; p99 at
   most 67 ms), settled unchanged.
2. **Collision levels.** A bit-flag client setting like the MMD physics' `mmdhl_collide_with`
   (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua` and `settings.lua`: one
   checkbox per target): objects (props and other physics objects), ragdolls, players, NPCs (and
   NextBots). Pieces always collide with the map and each other. Default: objects and ragdolls; living
   entities off. Checkboxes in the glass settings menu with the seven translations
   (`tools/glass_i18n.py`); the existing interaction switch stays the master switch. Existing archived
   settings migrate once.
3. **Follow-up hits.** Find why bullets and melee (crowbar, stunstick, fists, and SWEP melee that traces)
   do not break pieces in play, in single player and multiplayer: for example the server forwards bullets
   only near recent breaks and that interest expires, or melee never reaches the clients. Every piece
   hit by a bullet or a melee swing should break or be pushed, whenever the glass broke, at a bounded
   cost; each client receives the hits near its own pieces.

Keep G1's and R7's guarantees: deterministic panes and fracture on server and clients, pieces local to
each client, the budget and lifetime, explosions, map import, the fallback without the module, one-way
contacts (pieces never push or damage Source), and the bounded capture cost (R7 measured 35 ns per
Source vector component read; keep region tests on numbers).

## Tests and report

Native and LuaJIT tests for each change (burst spreading, adaptive detail keeps area, collision flags and
the migration, bullet and melee forwarding, expiry), offline costs measured before and after, and QA
steps in `tools/qa/nlglass_qa` for Claude to run on the PoC: shoot a settled pile 60 s after the break
(pistol, SMG), crowbar one, walk through one with the defaults (no contact) and with players enabled
(contact), the 50-pane scene with frame metrics. `tools\test.ps1 -Config Release` must pass; commit on
`r8-glass` (no push, merge, package import, game install change or Workshop update; Claude imports the
rebuilt module). Report in `docs/handover/R8-G-report.md`.
