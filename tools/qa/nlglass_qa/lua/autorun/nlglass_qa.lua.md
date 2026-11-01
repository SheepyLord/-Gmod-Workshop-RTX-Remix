# nlglass_qa.lua

A QA add-on for the G1 glass system, never shipped: copy `tools/qa/nlglass_qa` into a test install's
`garrysmod/addons/` for one session (the PoC), then remove it. It needs the glass add-on (`nlglass_pane`,
`NLGlassDebris`) and a listen server. Start it with [`nlglass_qa_start.lua`](../../../nlglass_qa_start.lua.md).

Server: the console command `nlglass_qa [field|map]` (the listen-server host only) runs steps in order,
each waiting for the client to report its screenshot, and prints `NL_QA <step>` lines.

`field` (gm_construct; the player on (831.235, 576, -143.08), facing west):

1. Bullets (15 damage) at one point of an annealed 96x64 pane: after one round, after two, after six,
   and three seconds later.
2. A 400-damage round at a corner of one pane and at the centre of another, in flight and settled.
3. Twelve 8-damage rounds at one point of a 256x128 pane (weak hits must add up).
4. A thrown oil drum (700 units/s), 5. a thrown ragdoll (650 units/s).
6. The player walks, then 7. runs, into a 64x96 pane from 160 units away: the player's own movement,
   with forward (and sprint) held in the user command for 1.6 s by a `StartCommand` hook that both realms
   run (GMod takes the run speed from the command's buttons, so changing the move data alone keeps the
   walk speed); prints whether the pane entity is still there, the impacts the glass server accepted
   on it, the share of glass left and the top speed reached. A walk must leave it whole (no impact,
   100 % left), a run must break it. The entity alone proves nothing: annealed glass keeps its frame
   after a breakout. The impacts are counted by wrapping `NLGlass.Server.Impact`, the one entry point
   of every cause.

`nlglass_qa contact` runs only steps 6 and 7.

`old` (gm_construct, with the package from before G1, whose fixes part still carries Glass-Rewrite-Remix):
the performance scene of step 11 with the old system, for the before/after comparison: 50 96x64
`procedural_shard` panes built the way that add-on's map replacement builds one (its block model scaled
to the pane), broken by the same blasts; prints the number of shard entities while they fall and 15 s
later. Start it with a client Lua that runs `nlglass_qa old`.
8. An explosion in front of a pane, 9. four rounds into a tempered pane, then a blast at it, 10. a
   scripted `Break` input.
11. Performance: the empty field for 6 s, 50 panes broken by blasts (frame times over 4 s while they
    fall), then 15 s later.

`map` (a map with native `func_breakable` glass, such as modern_house): the nearest glass pane to the
player gets one round (crack), then up to eight more until the engine breaks it (break, settled), and
the second nearest is hit by a thrown ragdoll. The player stands 90 units in front of the first pane.

It removes its own panes, props and ragdolls between steps. Client: frames each step with a `CalcView`
camera (HUD hidden), samples frame times with `PostRender`, prints `NL_QA client <label> backend
<jolt|vphysics|none> live moving sleeping batches frames mean_ms p99_ms | jolt step_ms awake brushes
skipped refused statics models` from `NLGlassDebris.Stats()`, then `NL_SHOT <label>`; the
`nl_shot_taken` reply from `poc_session.py --lua-shots` moves the server to the next step, and
`NL_SHOT_DONE` ends it.

Side effects: the session's player position, entities it spawns and removes, and the glass broken.
Exit codes: none (game Lua).

## R7-C interaction acceptance (Claude)

Run on the PoC only after review/import of the rebuilt module and the matching `glass/addon` Lua;
R7-C itself never installs or launches a game. Use gm_construct, Jolt, piece size 8, debris budget
2000, lifetime 120, and `rtx_glass_debris_interact 1`. Run `nlglass_qa interact`, or pass
[`nlglass_interaction_start.lua`](../../../nlglass_interaction_start.lua.md) to the existing
`poc_session.py --lua-shots` workflow. Keep the console and screenshots.

The interaction sequence is 19 screenshot steps, advancing through the existing screenshot reply.
Its small client fixtures use only `NLGlassDebris.Clear/Spawn`, not direct native impulses/splits.
They intentionally contain larger convex pieces so secondary fracture is observable. It never
changes settings; restore any operator-changed convars through the menu afterward.

| Labels / action | Must show |
|---|---|
| `interact_real_pane`, `interact_real_followup` | A genuine pane breaks and a second Source bullet is forwarded through the real server break-interest path. No fixture interest was registered for this pair; the client receives rays. Minimum-size real fragments may only move. |
| `interact_empty_walk_before`, `interact_empty_walk` | Empty traversal control; Source peak speed about 200, `passed true`, health unchanged. |
| `interact_walk_before`, `interact_walk` | Nine settled pieces visibly move as the player crosses; mirrors become nonzero and pieces may split. Source reaches the same speed/end position as control and health stays unchanged. |
| `interact_run_before`, `interact_run` | Running pushes/breaks the larger pieces; `body > 0`, Source peak speed about 400, no slowdown or glass damage. |
| `interact_ragdoll_before`, `interact_ragdoll` | A dropped Source ragdoll pushes/splits a settled 96x64 slab (`body > 0`); multiple bone mirrors follow it. No visible reaction in the ragdoll from the cosmetic slab. |
| `interact_prop_before`, `interact_prop` | The 650-unit/s drum pushes and breaks the pile (`body > 0`). Source mass is printed; no reverse deflection caused by glass. |
| `interact_bullet_before`, `interact_bullet` | One real Source bullet, directed down at the slab: native `ray_hits > 0`, `bullet > 0`, local pieces move and become smaller. |
| `interact_blast_before`, `interact_blast` | A real blast (a damageable witness prop supplies Source's damage callback) pushes and splits the local slab; `blast > 0`. |
| `interact_fall`, `interact_fall_settled` | A single slab falls 256 units, breaks on landing with `fall > 0`, then settles as smaller convex parts. No damage or impulse is injected into that piece. |
| `interact_cleanup` | Zero local pieces, mirrors and pending work after clearing fixtures. |

Every screenshot also prints `NL_QA interaction`: enabled/available, mirrors/candidates/queries,
capture/split CPU times, total/per-cause splits, pending damage/rays, native ray hits and drop counts.
Before each fixture, manager counters reset. Native ray/split totals are cumulative for the map;
compare their before/after values. A low-budget/shotgun overload may drop cosmetic work by design.

Then repeat the interaction run with **only** `rtx_glass_debris_interact 0`: mirrors must stay zero,
no secondary split counter increases, bullets/body contacts do nothing to pieces, falls retain the
original larger shape, and blasts still move them. Source traversals match the enabled control.
The repeated run's native ray-hit total can retain its earlier value; it must not increase.
Set it back to 1 in the menu and verify a shot works again. In each of English, zh-CN, zh-TW, ja,
ko, fr and ru, check the checkbox/help text and Reset to Defaults restoring it for a non-admin too.

For performance acceptance, start a fresh matching session and run the unchanged `nlglass_qa field`
scene with interaction on, then off in another matching session. Keep G1's camera, RTX settings and
resolution. Compare against read-only G1 run 10: falling **25.31 ms mean / 113.22 ms p99**, settled
**9.74 / 16.39 ms**; 2000 live, 1236 moving while falling. Repeat a noisy result; do not accept a
repeatable slowdown. Inspect capture/split/drop counters alongside frame time. Offline timing cannot
substitute for this gate. `nlglass_qa map` on modern_house must still show original pane cracks/breaks.

Additional manual checks: two clients (one disabled) receive identical authoritative pane cracks but
independent cosmetic debris; an NPC walks through a pile; client/remote ragdoll bone fallback; a hard
landing on displacement/props; budget 1/2000/8192 and oldest-first eviction; minimum-size pieces only
move; lifetime changes and a split just before expiration; map cleanup/reload and missing/older-module
fallback. No pickup, server piece entities, reverse Source forces or glass-inflicted damage should exist.

## R7-C fast-body fix recheck

Run 11's ground-level drum crosses the settled pile without a piece moving (`console.log:656–662`
in the read-only `out/qa-poc/r7/11-interact` evidence). Its throw position/velocity is unchanged by
this fix. After importing the matching Lua/module, repeat `interact_prop_before`/`interact_prop`
through `nlglass_qa interact`: the 30 kg drum at 650 units/s must move/split pieces (`body > 0`),
with no glass-caused change to Source. Repeat off: no body contacts, mirrors or new sweep hits.

`NL_QA fast` now prints current fast bodies, peak mirror count and cumulative cold fast boxes since
the fixture reset, latest fast candidates/examined entries, and native sweeps/hits/limited totals.
The peak/box counters preserve a brief pass even if current mirrors are zero at the after shot.
Native counters are cumulative for the map: compare deltas. With on, fast boxes/peak must become
nonzero and sweep hits should increase; with off, none increases. A nonzero limited delta marks
intentional saturation and must be retained alongside the frame samples.

Keep the unchanged `field` on/off frame-time check above. No game was run during the fix; offline
capture/native/falling checks and remaining limits are recorded in the R7-C report.
