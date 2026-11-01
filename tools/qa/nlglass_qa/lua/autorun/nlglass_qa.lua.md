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

## R8-G acceptance (Claude; matching R8-G Lua and module required)

Run `nlglass_qa r8` on gm_construct, or use [nlglass_r8_start.lua](../../../nlglass_r8_start.lua.md)
with the established `poc_session.py --lua-shots 240` workflow. Allow at least 240 seconds for the
whole capture: the first screenshot waits **61 seconds**. Jolt must be ready, piece size 8, budget
2000. This sequence saves and prints the client's collision/master/lifetime values, temporarily
uses interaction 1 and lifetime 180, then restores them at completion. On interruption restore the
three printed values manually; the QA also changes host position, gives weapons/ammo and simulates
attack commands. Run only in the dedicated test session. This branch itself never installs/runs it.

| Labels / action | Must show |
|---|---|
| `r8_old_pile_before` | The public Spawn/Clear fixture has slept for 61 s. Jolt is ready, `flags 3`, interaction on, no creation pending. Interest continues even without a recent pane break or moving bodies. |
| `r8_pistol_60s` | Real `weapon_pistol` input, rather than a synthetic injected native ray. Server forwarded-hit delta and native `ray_hits` increase. The old slab moves and/or `bullet` splits increase. |
| `r8_smg_60s` | Real `weapon_smg1` input reaches the same older pile; more ray hits and visible movement/fracture. No Lua/weapon errors or damage callback changes. |
| `r8_crowbar_before`, `r8_crowbar` | A fresh settled slab, then real crowbar input. Server melee delta and native `melee_hits` increase; large fine pieces can add `melee_splits`, minimum pieces must move. Shooting the empty air above a pile is not a valid contact. |
| `r8_default_walk_before`, `r8_default_walk` | Mask 3 (objects/ragdolls only), a settled nine-piece pile, then a 200-unit/s walk. No player mirror/contact or glass movement caused by the walker; Source health/speed/end position stay normal. Compare native/body counters as deltas since native counters can be cumulative. |
| `r8_players_walk_before`, `r8_players_walk` | Mask 7 adds living players. The same traversal now moves pieces and can split large ones; mirrors become nonzero. Source crosses at full speed with unchanged health and no reverse force. |
| `r8_cleanup` | Saved client settings restored; no live fragments, queued construction, mirrors or pending damage/rays. Native hit totals may remain cumulative. |

`NL_QA r8` lines add the mask, original fragment count, queued bodies/fragments, creations in the last
frame, creation CPU/peak, cumulative grouped fragments, native melee hits/limits and melee splits.
`live`/`moving` count rigid bodies; `fragments` charges all original polygons inside groups. The
budget still limits those original fragments, including queued work. A whole-group eviction can
underfill by at most seven. Creation must stay at most 12 bodies/meshes per frame; 0.75 ms is a
yielding allowance, **not** a hard upper bound on an individual geometry/upload/cook.

Run unchanged `nlglass_qa field` in fresh matching sessions, interaction off and on, with the same
camera, resolution and Remix settings as R7 runs 27/28. Keep piece size 8, budget 2000, lifetime 120;
defaults use mask 3. Also run mask 15 once for comparison with R7's all-target contact configuration.
Do not compare a background window, mismatched package/module or another active game.

| Capture | R7 mean / p99 | R8 acceptance |
|---|---|---|
| Falling, interaction off | 26.28 / 134.30 ms | Falling minus its settled mean ≤8.5 ms; p99 ≤67 ms. With a 9.17 ms settled mean, about ≤17.67 ms falling. |
| Falling, interaction on | 28.60 / 134.33 ms | Same ≤8.5 ms excess / ≤67 ms p99 target. |
| Settled, off/on | 9.17 / 9.32 ms mean | No repeatable regression. Queue drained, sleeping glass remains batched. |

Repeat the whole matching comparison at least three times: a 140–150-frame falling p99 is sensitive
to a single frame. Expect hundreds of rigid draws under distant burst load, original fragments
≤2000 including pending work, smaller creation bursts, identical pane holes/remaining collision and
full nearby detail. Groups intentionally move rigidly instead of splitting further; their original
triangles and exact collision sub-hulls remain. Fine pieces still split. Recheck `nlglass_qa map`
on modern_house, blasts during construction, cleanup mid-burst and missing/older-module fallback.

Manual coverage: toggle each target independently, including a living NPC/NextBot and a client
ragdoll; Reset works for a non-admin and console changes update checkboxes in all seven languages.
Use stunstick, crouched fists (their reach is short), and one trace-based melee SWEP. Test a piece
behind a Source wall (no hit) and two clients: masks 3/7 produce different cosmetic contacts while
pane holes agree. With the shooter at budget 0, another client still receives shots near its own
pieces. At lifetime 0, shoot again after 130 s, then stop/clear interest and confirm delivery ceases.
Saturated queues/leases, unavailable remote shapes, >32 separated regions and unsupported melee
filters/hold types remain bounded cosmetic limitations; watch the dropped/limited counters.

The older `interact` sequence below tests the all-target R7 behaviour: set
`rtx_glass_debris_collide_with 15` before running it. The R8 default intentionally leaves its
walking/running contacts disabled; use `r8` for the new defaults.

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

R8-G also reports `retired`/`released` individual meshes. Burst eviction must not synchronously
release a whole old pile; at most 16 individual GPU objects retire per frame. This exceeds the
12 initial plus two split-child allocations, keeping sustained replacement bounded. Cleanup must
leave no retired meshes. The separate settled-batch queue keeps its existing two releases/frame.
