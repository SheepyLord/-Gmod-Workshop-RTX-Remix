# R9-G: shards, break latency, sound, water, blasts, stable transfer and clearing

Implemented on `r9-glass`, based on `2b54300`, for Claude's review/import. Design:
[ADR 0087](../decisions/0087-glass-shards-and-environment.md). Evidence and generated packages stay
in this worktree's `out/qa-r9`. Only the PoC was used. The Modern House BSP came from the already
installed Workshop archive, CRC-verified into `out`, then deployed as a journaled test add-on; no
download, Steam depot edit, `user.conf` edit, field access, package import, upload, push, merge or tag.

The rebuilt `out/build/win64-release/glass/native/gmcl_nlglass_win64.dll` is **1,536,512 bytes**,
SHA-256 **327ddf260d437e13ffa12d63442f3699c27af9b8af7029e19208e818116059e4**. Claude imports
it into `packages/glass` together with the matching `glass/addon`; no import was performed here.

| Request | Finding and change |
|---|---|
| Realistic, very small fragments | R8 used a tempered grid and longest-axis binary halves with a four-unit minimum (normally the pane's eight-unit spacing). Annealed cells now branch across radial rings into tapered triangles, with a crushed core. Tempered uses seeded oblique convex cuts, denser near the hit. The shared integer generator, snapped intersections, area and 200/300-cell limits remain; snapshots still cap at 512. Over 40 seeds each, the smallest initial annealed/tempered areas are **0.030804 / 6.674136 units²**. Follow-up native cuts use the local hit and two to six irregular fragments, down to **1 unit²**, independent of initial spacing. Across 80 repeated-cut fixtures, area error stays below **0.02 units²** on a 3072-unit² polygon; 65 seeds make more than two children. Tiny pieces below 4 units² retain map/mirror contact but omit mutual glass constraints. Original fragment budgets, expiry and exact distant R8 groups remain. |
| Break latency | The old FIFO makes 28–49-piece spawned breaks finish bodies after **45–82 ms**. With a camera actually facing them, first pieces take **16–21 ms** and partial holes build after **23–33 ms**. Breaking holes now build immediately; weak crack updates still coalesce. All queued fragments draw in shared ballistic face meshes in the receiving frame. Bodies are prioritized by impact then camera distance, still limited to 12/frame, 8192 vertices and a 0.75-ms soft allowance. They start at the preview pose, retaining blast history and expiry. Changed-build gm_construct receipts show hole builds in **2.9–4.0 ms**, with first draws in the **same FrameNumber** as receipt. Native engine health/OnBreak remains authoritative. |
| Glass sounds | All nine selected `physics/glass` soft/hard-impact and sheet-break WAVs exist in vanilla GMod. Native contacts, landings, splits and water entries fill a fixed **128-event** buffer; no worker calls Lua/Source or allocates contact records. Client sounds are positional, size/speed-sensitive, culled beyond **1536 units**, limited to **4/frame**, **24/s** (burst 24), and **one/0.12 s/piece**. A settled pile stays quiet. `rtx_glass_debris_sounds=1` is archived, resettable locally and translated into all seven menu languages. An empty native sound read returns false without allocating Lua tables. |
| Water and explosions | gm_construct has one parsed water brush: **x [-3072,1856], y [1985,6464], z [-960,-160]**. Water/slime halfspaces are separate from solid collision, in a bounded BVH. Active hulls, including compounds, use Jolt buoyancy at water/glass density ratio **0.4**, linear/angular drag **1.4/0.08**. The real pool produced **25 entries and 5534 buoyancy applications** while all 25 pieces remained moving after four seconds. R8 sent no empty-space util blast. Exact Lua blast APIs, native explosion inputs and grenade sounds now work without victims. PoC confirms **five routes**: util blast, env_explosion, grenade, explosive barrel and RPG. GMod routes the native barrel/RPG through AcceptInput too; no speculative entity polling remains. Nearby signals coalesce over 32 units/0.1 s; pending events cap at 32, delivery at 32/s (burst 16), radius at 2048 and kick speed at 1800. |
| Stable velocity | Initial mirror overlap, overlap-start sweep axes and pose corrections could resolve a shard toward the incoming body. Spawn/correction overlaps now remain suppressed until separation; corrections include the shard's next swept extent. Overlap-start sweeps transfer along actual sampled travel and suppress a second penetration solve. **0/672** generated free-flight velocity samples reverse, across 250/700/3600-unit/s, fresh/existing mirrors and teleports. There is no global sign clamp or Source response. Ordinary separated collisions and real bounces remain physical. |
| Clear broken glass | Local Clear removes built, queued, preview and batched glass. An admin on a single-player/listen server also gets an everyone button; the server validates admin/listen status and a one-second cooldown. Both routes retain pane state. The actual Derma buttons were found/clicked in the PoC: local **25 → 0**, everyone request accepted. All labels and sound reset defaults have English plus six complete translations. |

The old blast fallback preferred `GetReportedPosition`. Valve's grenade code puts the thrower's
position there, so the blast could be far from the pile. The new fallback uses the inflictor; exact
Lua calls retain their actual origin/radius. The server still defers two turns so native OnBreak
pieces receive the kick. Lua wrapper refresh disables old observers even beneath another add-on's
wrapper, preserves arguments/returns, and removes only wrappers it owns. These behaviours have
regressions. See [Valve's grenade implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/basegrenade_shared.cpp)
and [Facepunch's sound hook contract](https://wiki.facepunch.com/gmod/GM:EntityEmitSound).

Controlled single-player PoC timing (1280x720, RTX active; milliseconds from the breaking
client receipt). Each weapon/type has two repetitions. The full chain and frame numbers are in
`out/qa-r9/latency-summary.json`, with raw console in runs 03/10/12/17:

| Pane / controlled burst | First draw before -> R9 | Hole build before -> R9 | Last body before -> R9 |
|---|---:|---:|---:|
| Spawned, pistol | 15.84-21.39 -> 9.97-18.14 ms | 23.26-33.43 -> 3.59-3.96 ms | 66.17-81.94 -> 73.25-83.91 ms |
| Spawned, SMG | 16.74-20.62 -> 14.68-19.58 ms | 24.56-27.27 -> 2.92-3.90 ms | 44.91-76.42 -> 66.55-69.69 ms |
| Native Modern House, pistol | 31.99-52.20 -> 14.84-45.05 ms | engine-owned -> 0.64-0.68 ms add-on state | 149.42-175.96 -> 299.33-373.64 ms |
| Native Modern House, SMG | 22.40-29.94 -> 13.85-15.06 ms | engine-owned -> 0.35-0.51 ms add-on state | 68.41-175.21 -> 156.19-222.94 ms |

Before, first pieces are one FrameNumber after receipt; partial-hole drawing is two frames after.
R9's first pieces, hole build and next hole draw all have the receiving FrameNumber. The native
hole markers describe empty add-on state after engine OnBreak; the engine owns its brush display.
No extra server tick was observed: the breaking damage and sent event share a tick before/after.
Sent-to-breaking-receipt wall time, including preceding weak packets in the burst, is 2.57-6.61 ms
before versus 3.10-4.72 ms after on gm_construct, and 2.13-4.52 versus 4.32-6.20 ms for native
Modern House windows. More detailed geometry raises native-window body counts from 32-63 to
59-108, so last-body completion can take longer; all queued faces are already visible. These
measurements are scripted energy bursts and render-hook observations, not optical/input latency.
`out/qa-r9/fracture-comparison.png` plots exact before/after polygons: the same seed makes
90/96 annealed/tempered fragments before and 158/148 after.

The offline results below are CPU fixture/engine-double costs, **not RTX frame times**. Three
interleaved runs use preserved baseline Lua/executable and current sources. Raw logs, every sample
and median JSON are in `out/qa-r9/trusted-feature-costs` and `trusted-load-costs`; reproduce with
[measure_nlglass_r9.py](../../tools/qa/measure_nlglass_r9.py.md) and
[measure_nlglass.py](../../tools/qa/measure_nlglass.py.md).

| Offline operation | Before | R9-G |
|---|---:|---:|
| Pure near-cap pane break, mean / p99 | 0.302 / 1.445 ms | 0.512 / 1.376 ms |
| Server wire-replay whole break, mean / p99 | 1.938 / 9.805 ms | 1.648 / 4.646 ms |
| Client whole-break handler, mean / p99 | 2.023 / 9.323 ms | 1.504 / 5.131 ms |
| CanSplit + two-child replacement, mean | 0.01324 ms | 0.01289 ms |
| Actual 2–6-child replacement, mean / p99 | two children above | 0.02248 / 0.0437 ms; 3.267 children mean |
| 1000-piece native dry step, audio off / on | no sound buffer | 0.315 / 0.312 ms |
| Same wet step, audio off / on | no buoyancy | 0.551 / 0.527 ms |
| Buoyancy work alone, wet 1000-piece step | 0 | 0.128–0.129 ms |
| 50-break receipt, mean / median run max | 0.160 / 2.464 ms | 0.270 / 1.840 ms |
| Complete 50-break Lua replay, mean / p99 | 0.681 / 4.120 ms | 0.923 / 9.669 ms |
| Moving rigid draws / retained originals | 348 / 1998 | 294 / 1999 |
| Settled draws in that replay | 4 | 3 |
| Unchanged 4000-piece native guard, mean step | 4.212 ms | 4.392 ms |

Audio's small dry-step difference is timing noise, not a claimed speedup. The native guard settles
at **11.0167 simulated seconds** on both sides, with identical scratch peak/reserve and zero contact
overflows. Buoyancy changes trajectories, so wet/dry totals are feature costs rather than identical
motion comparisons. More detailed fracture and complete queued visibility cost CPU; the replay's
mean rises about **0.24 ms**. The first preview version rebuilt full edge extrusions and reached
33.5-ms p99; two-face previews reduced that to 9.7 ms. A single mesh/cooking call can exceed the
soft allowance. These measurements do not establish the user's game-performance target.

Final-layout PoC runs 17-19 quit normally with zero Lua errors. Run 18 logs all five blast
routes. Pool samples contain all 25 pieces: mean Z/vertical speed at 0.2, 0.5 and 1 s are
**-142.330/-125.234**, **-164.113/-22.691**, **-178.445/-32.099** units and units/s.
The surface is -160: entry replaces accelerating air fall with a slow sink. All 25 remain moving
four seconds later; cleanup's actual local button changes 25 to 0 and the everyone button is present.

The game velocity run (15, same native module) records **1172/55713 = 2.10%** negative-direction
observations: running-speed prop 66/7941, thrown prop 423/13683, fast prop 438/16643, running player
53/6922 and bullet 192/10524. Worst negative speed is **28.995 units/s**. These include floor/prop
contacts, tumbling and descendant point velocities; they are not independent fragments or proof
that every negative sample is a bounce. The isolated no-contact reproductions are **0/672**.
No large backward launch was measured; preserve the real-bounce/rotation distinction in visual QA.

In the isolated final-layout 50-pane scene (19, interaction on, mask 3), empty is **8.846 ms mean /
12.319 ms p99**, falling **12.999 / 45.023 ms**, and the 15-second settled window **8.705 / 16.033 ms**.
The falling-minus-settled mean is **4.294 ms**, under 8.5, and falling p99 under 67. Retained originals
are **1993**; queued work is zero at the falling sample, with about 281 moving draws. However,
**102 native bodies are still awake** at the settled sample: this is a settling-window result,
not a proven fully sleeping baseline. Repeated off/on runs and a longer sleep baseline remain
Claude's acceptance. The earlier concurrent-test run (16) was 19.670/59.902 falling and 17.896
settling; it is retained as diagnostic evidence, not the primary performance comparison.

`tools/test.ps1 -Config Release` **passes**: **26/26 CTests**, including **43 native glass cases**,
and **515 Python tests** (462 tools + 28 gmapack + 25 steam; two existing skips), including **88 glass
cases**. Receipt: `out/qa-r9/test-release-frozen.log`. Coverage includes deterministic source/client
replay, conserved area, non-axis tiny cuts, per-frame queue/preview limits, six-child budget/expiry,
contact/sound bounds, water/compound bodies, free-flight direction, native and victim-free blasts,
wrapper refresh under another add-on, moving-worker diagnostics, actual translations, local/admin/
remote-listen permissions and exact render-guard source inventory. No checks were weakened.
The helpers are embedded in existing trusted Lua files; no loader source/inventory was changed.

Claude's repeatable acceptance steps, using matching Lua/module and the development QA add-on:

1. `nlglass_qa r9-latency`: gm_construct measures spawned panes; modern_house measures real native
   windows. Check server damage/sent ticks, client receipt, first draw, hole build/draw and last body
   rows. The scripted bursts use controlled FireBullets energies 15/5 for pistol/SMG comparison.
   Every queued piece must already be visible at the first render, with impact-adjacent bodies first;
   partial holes must be built in the receipt frame. Native windows must wait for engine OnBreak.
2. `nlglass_qa r9-velocity`: 250/700/3600-unit/s props, running player and bullet. Read per-case
   dot-product samples and distinguish initial flight from real frame/map/prop bounces. Source
   movement/health is never driven by Jolt; repeat the existing R8 collision-mask/two-client checks.
3. `nlglass_qa r9`: a sleeping pile, empty util blast, env_explosion, grenade, barrel, RPG, real pool,
   sounds and actual menu buttons. Blasts must wake/split the pile without victims. Event counters
   must obey native/client bounds; settled glass stays quiet, and sound off silences it.
4. `nlglass_qa r9-water`: seven-second isolated pool fixture; expect negative but drag-limited
   velocity, water entries/applications and tumbling without water becoming solid. The read-only
   import probe's `--water` prints actual map bounds. Repeat on another map and near water edges.
5. `nlglass_qa r9-perf` or the unchanged `field` mode, interaction off/on, three fresh sessions each:
   same 50 96×64 panes and timed blasts. Require **falling mean ≤ settled + 8.5 ms**, **p99 ≤67 ms**,
   unchanged settled rendering and ≤2000 retained originals including queued work. Check close views,
   splits/blasts during construction, cleanup mid-burst and missing/older-module fallback too.

Limits: previews share one ballistic trajectory per 24 construction rows, omit edge faces/spin until
handoff and pause at 0.5 s during a long import; physical contact begins at native construction.
Distant exact R8 groups remain rigid and do not split. Static brush water uses body-centre side
membership and a surface-plane submerged volume; moving water brushes are not imported. Very close
explosions/rate saturation coalesce/drop cosmetic work; unknown custom native explosions need a
recognized API/input/sound. Native hull/capture/budget limits remain. Cosmetic descendants can differ
between clients. Real-weapon feel, two actual clients, other maps and repeated performance acceptance
remain Claude's integration checks. No field or public release acceptance is claimed here.

The PoC configuration is restored to Workshop-only **3829070317**, with empty local/dev lists.
Verification run 20 activates the Workshop package, reports `qa_file=false pieces=0`, has zero
Lua errors and quits normally. No PoC game remains running.

Logical commits: `8712b94` native features, `56a6c99` client behaviour/menu/localization,
`9029200` seed/quiet-reader/measurement boundaries, `4c7e58f` exact trusted-file integration,
and `96a1359` regression/measurement/game QA. A final documentation commit carries ADR 0087,
this report and additive shared-document evidence. Every commit ends with the requested Codex
co-author trailer. The branch is retained for Claude; nothing is pushed or merged.
