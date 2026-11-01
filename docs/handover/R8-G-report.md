# R8-G: falling load, collision choices and follow-up hits

Implemented on `r8-glass` from `fd82075`, for Claude's review and game acceptance. No GMod was
launched and no game installation, package input or remote was changed. The rebuilt module is
`out/build/win64-release/glass/native/gmcl_nlglass_win64.dll`, 1,505,280 bytes,
SHA-256 `2d2eda99dbbfadd24f14abeaaedf27e21017a1d263a3d073634322c48fcd3e13`. Claude imports it together with the matching `glass/addon` Lua after review.

The implementation checkpoints are `8d47c93` (collision flags), `58a1bd0` (live interest and melee),
`c97eb12` (fists/SWEP trace coalescing), `64498f1` (construction and distant groups) and `7225a11`
(shape-cache/animation boundaries). The final commit carries the remaining boundary protection,
GPU retirement, executable QA, measurement tool and this report. Every commit has the requested
Codex co-author trailer. Design: [ADR 0085](../decisions/0085-glass-load-collision-and-hits.md).

| Brief item | Delivered behaviour |
|---|---|
| 3: falling cost | Break receipt plans descriptors; Think constructs at most 12 meshes/bodies and 8192 vertices/frame, yielding after 0.75 ms. Under crowded distant load, at most eight original fragments share a mesh and exact compound body in a 32-unit pane-local cell. Original polygons, UVs, colours and collision gaps remain. Bounds within 256 units of the actual render camera retain individual pieces. Evicted individual GPU meshes retire at most 16/frame instead of synchronously in the break callback. |
| 4: collision levels | Archived `rtx_glass_debris_collide_with`: objects=1, ragdolls=2, living players=4, living NPCs/NextBots=8. Default **3**. Four independent checkboxes, seven translations and non-admin local Reset. Discovery filters before extraction; tagged snapshots are checked natively. Equipped weapons/bone followers cannot bypass living-off choices. Map/piece contacts stay enabled; the interaction master remains independent. |
| 5: bullets and melee | Each client renews interest around its actual live pieces, including sleeping/infinite-lifetime piles. The server forwards final bullets and observes stock crowbar/stunstick swings plus short trace-based melee SWEPs/fists. The client's bounded native sweep pushes small pieces and can split large fine pieces. It also moves adaptive groups. No Source force/damage or weapon trace/callback return is changed. |

Grouping charges every original fragment to the budget, including queued work: the 2000-fragment
setting cannot silently become 2000 groups. Whole-group eviction may underfill by at most seven.
Groups deliberately move rigidly and respond to subsequent hits by moving; they do not split.
Fine pieces keep R7's binary fracture/minimum size. Queued work and descendants keep the original
deadline. A bounded numeric blast history applies later kicks to deferred construction. Cleanup
cancels descriptors and releases retired resources. The ordinary missing-module fallback remains
64 fragments; runtime failure can migrate exact grouped geometry through client compound physics.
The Jolt solver, sleep/CCD tuning, authoritative pane holes, deterministic initial fracture and
map import are unchanged.

The collision migration retires the obsolete piece/piece checkbox once, without resetting the
master switch, budget, lifetime or an explicit new mask. Later choices survive reload. Native mask
changes remove mirrors at an idle boundary; Lua invalidates its shape cache and recooks within
the existing two-shape limit. Existing 10 Hz/512-entry/128-candidate/96-body capture caps and numeric
region tests remain.

R7 forwarded only through 32 recent server break regions with a 120-second expiry, independent of
client debris lifetime/location, and had no melee route. Those are confirmed coverage gaps; the
R7 `26-interact` slab bullet did work, so this does not claim to reproduce every reported weapon
failure without the game. New interest is at most 32 spheres/client, refreshed every two seconds,
leased for six; server accepts at most one update/second and 128 clients. There are no client
damage claims. A two-second recent-break bridge covers initial advertisement. Inspection/delivery
retain 256/64 hits/s global limits and 16/s per firing entity. Clients queue 32 hits for 0.5 s and
cast at most eight/frame. Native melee caps at eight distinct pieces and 64 body/hit visits.

SWEP observations defer until line/hull tracing completes and retain the wider trace. Stock fists'
line-then-hull pattern is documented in [Facepunch's source](https://raw.githubusercontent.com/Facepunch/garrysmod/master/garrysmod/lua/weapons/weapon_fists.lua).
A separate containing Source-box trace clips the forwarded melee volume, including line-only
SWEPs, so its width cannot extend through a wall. Those extra queries cap at 64/s, burst 32.
Solid starts are ignored. Stock observations tolerate animation-before-command ordering; old
deferred work is discarded across cleanup. Queued endpoints own copies even when the weapon
reuses its trace vectors. No predicted duplicate or per-piece network stream.

The offline numbers below are **CPU/engine doubles and generated Jolt fixtures, not RTX frame
times**. Three interleaved comparisons use preserved `fd82075` helpers/executable and the final
renderer/physics implementation. Values are medians of run means or of each run's p99/max.
The Lua workload receives 50 real deterministic fractures over 1.5 simulated seconds and measures
240 frames; the native paired workload drops 2000 quads, separate or in 250 eight-hull groups.

| Controlled workload | Before | R8-G |
|---|---:|---:|
| Break receipt, mean CPU ms | 1.5297 | 0.1549 |
| Break receipt, median run maximum ms | 9.4634 | 2.1978 |
| Full Lua replay, mean / p99 ms | 0.6318 / 4.6306 | 0.5623 / 4.3526 |
| Moving rigid draws, retained fragments | 2000 / 2000 | 348 / 1998 |
| Settled draws in that replay | 4 | 4 |
| Native paired falling step mean ms | 0.3382 | 0.0872 |
| Native paired spawn total ms | 11.5613 | 11.1875 |
| Fixed 2000 independent pieces, moving Think/draw off / on ms | 0.1542 / 0.1636 | 0.1535 / 0.1608 |
| Same fixed scene, settled Think/draw off ms | 0.0123 | 0.0111 |
| Source capture double, warm 96 bodies ms | 0.0630 | 0.0696 |
| Source capture double, crowded 512 entries ms | 0.0818 | 0.0854 |
| Unchanged 4000-piece native guard, mean step ms | 3.9053 | 3.9394 |

Moving draws fall **82.6%**; the paired native mean falls about **74%**. Lua still constructs all
retained triangles, and moving groups have different trajectories, so these are not equal-motion
or game speedups. Settled batching stays four draws. The unchanged native guard settles at
11.0167 simulated seconds on both sides, with identical scratch use and zero contact overflows.
Warm fixed-scene drawing still allocates no per-piece Vector/Angle/Matrix userdata. Primary
construction peaks reached 3.35 ms; an earlier colder comparison reached 9.81 ms. The 0.75 ms
allowance yields after an indivisible call; neither it nor the release-count cap is a wall-time
guarantee. Actual engine extraction, GPU release, Remix ingestion/TLAS work and GPU time remain
unmeasured. R7's evidence identifies about 6.9 ms in ~1330 moving draws, but does not separate all
remaining engine/Remix costs.

Reproduce with `tools/qa/measure_nlglass.py` and its sidecar. Primary raw logs, all samples and
`costs.json` are under `out/r8-g/release-costs/`; preserved starting inputs are in
`out/r8-g/before/`. Earlier comparisons remain under `out/r8-g/measurements*` and `final-costs`.

`tools/test.ps1 -Config Release` passes: **26/26 CTests**, including **35 native glass cases**;
**479 Python tests** (426 tools, 28 gmapack, 25 steam; two existing skips), including **79 glass
Python cases**. Final receipt: `out/r8-g/test-release-frozen.log`. No checks are relaxed or skipped
for this work. Coverage includes all collision masks/migration, equipment exclusion/shape-cache
boundaries, 160 full/partial annealed/tempered area and front-triangle checks, camera proximity,
construction/release caps, original expiry/queued blasts, worker exclusion, 50-pane replay,
compound gaps/fallback, delayed interest at 60/130 seconds, leases, rates, stock/fist/SWEP traces,
conservative occlusion and QA setting restoration. Existing one-way, fracture, map and budget tests
remain.

Claude's [executable QA and detailed expected counters](../../tools/qa/nlglass_qa/lua/autorun/nlglass_qa.lua.md)
are ready; use the matching Lua/module and gm_construct, piece size 8, budget 2000:

1. Run `nlglass_qa r8` (or `nlglass_r8_start.lua`, `--lua-shots 240`). After the **61-second**
   sleeping-pile wait, real pistol and SMG input must increase forwarded/native ray hits and move
   or split glass. Real crowbar input must increase melee hits and move/split the settled slab.
2. The default mask-3 walk must leave the pile unaffected by the walker. Mask 7 must move pieces.
   Both walks retain Source speed/end position and health. Cleanup restores saved client settings
   and leaves zero live/queued fragments, mirrors, pending hits and retired meshes.
3. Repeat unchanged `nlglass_qa field` on/off in at least three fresh matching sessions. Target:
   **falling mean minus settled mean ≤8.5 ms, falling p99 ≤67 ms, settled unchanged**. R7 is
   26.28/134.30 ms off and 28.60/134.33 ms on, settled 9.17/9.32 ms. With that settled baseline,
   falling mean should be about ≤17.7 ms. Expect far fewer rigid draws, ≤12 constructions and ≤16
   individual GPU releases/frame; verify original fragments including pending work stay ≤2000.
4. Check modern_house/map import, blasts during queued construction, cleanup mid-burst,
   missing/older-module fallback, all four collision targets/seven languages and non-admin Reset.
   Also check stunstick, crouched fists/one trace-based SWEP, Source-wall occlusion and two clients
   with masks 3/7. A shooter with budget 0 must still forward to another client's pieces. With
   lifetime 0, shoot again after 130 seconds; clearing/lost interest must stop delivery.

The in-game half-cost target and two actual clients are **not verified here**; Claude owns those
checks. Saturated queues/rate caps, >32 separated regions, fast movement between interest updates,
missing remote shapes, functional melee filters/unrecognized hold types or later replacement of
the trace adapters can miss cosmetic contacts. Groups keep exact area but constrain motion and
only move on follow-up hits. Conservative melee volumes can miss a wide/long custom attack.
Nearby full-detail crowds can still be expensive. Fallback interaction remains conservative. No Source reaction, forced sleep, gameplay damage,
package import or claimed RTX frame-time result was added.
