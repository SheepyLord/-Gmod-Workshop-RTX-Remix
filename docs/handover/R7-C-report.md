# R7-C: one-way interaction and follow-up fracture for local glass

Implemented on `r7-glass-interact`, based on `42bd1e9`, for Claude's review and PoC acceptance.
No game was launched. No install, Steam file, Remix `user.conf`, package input, loader source,
Workshop item, remote branch, merge or tag was changed. All generated files are in this worktree's
ignored `out/`. The Model Hotloader collision file was read for behaviour; this is original MIT code.

## Delivery

- `d4da583`: native kinematic mirrors, bounded contact/ray damage, transactional convex replacement,
  generated-fixture tests and [ADR 0084](../decisions/0084-glass-one-way-interaction.md).
- `2722d5f`: client capture, server pellet forwarding, staged render replacement, inherited lifetime,
  the setting/translations, floor-contact/nearest-region regressions, harnesses and the QA sequence.
- A separate documentation commit carries this report and additive shared-document evidence.

The rebuilt module is `out/build/win64-release/glass/native/gmcl_nlglass_win64.dll`, 1,490,944 bytes,
SHA-256 `896688ba73638acce684ad0a08916ed9bfa259b8bf7304d0015b75889f6c3d68`.
Claude imports this module into `packages/glass` after review, together with the matching
`glass/addon` Lua. No import was performed here.

## What changed, by brief item

1. **Source bodies push glass one way.** The existing client Jolt world now holds bounded kinematic
   mirrors of living players/NPCs/NextBots, ragdoll physics bones (or bone hitboxes where client
   physics is absent), and other physics objects. Available convexes are used; oversized/unavailable
   meshes fall back to boxes. The capture helper reads Source poses, velocities and masses only.
   Jolt never sends a force, pose, damage or collision update back to Source. Mirrors collide only
   with glass, independently of the piece-piece collision checkbox.
2. **Follow-up damage.** Sufficiently hard bullets, blast kicks, body contacts and landings queue
   local damage. A large convex piece bisects into two convex equal-area children, retaining thickness,
   material, colour, original lifetime and linear/angular point velocity. The original pane's piece
   size supplies the floor; the smallest pieces only move. Replacement respects the player budget
   (default 2000), evicting the oldest remaining piece for the extra child. A struck oldest parent
   is replaced rather than disappearing at the budget boundary.
3. **Bullets reach client pieces.** A read-only server `PostEntityFireBullets` listener forwards the
   actual pellet trace only through recently broken-glass regions. It preserves callbacks, damage,
   spread, actual Source occlusion and other hooks. The client's Jolt raycast pushes/damages its
   nearest piece. There is no predicted duplicate, per-piece network stream or client request.
   The hook's final-pellet contract is documented by [Facepunch](https://wiki.facepunch.com/gmod/GM:PostEntityFireBullets).
4. **Per-player setting.** `rtx_glass_debris_interact=1`, archived on the client, appears in the glass
   menu with English plus Simplified/Traditional Chinese, Japanese, Korean, French and Russian.
   Reset to Defaults restores it for non-admins too, without a server request. Off removes mirrors
   and follow-up damage/rays while retaining G1 map/piece collision, lifetime, budgets and blast pushes.
5. **Decision record.** ADR 0084 (numbered 0082 on the branch) supersedes ADR 0070's map/piece-only contact rule. That rule is printed
   as point 5 in ADR 0070, although the brief calls it decision 3. Point 3's authoritative deterministic
   pane fracture is retained, as are all initial pane/network/map-import guarantees.

## Design and bounds

- Interest is at most 32 live-piece cells of 512 units, expanded by 96, prioritizing the viewer.
  Discovery runs at 10 Hz; at most 128 candidates are retained, with nearby players first. Up to 96
  body transforms refresh at each idle worker boundary; ragdolls use at most 24 bodies. At most two
  new shapes are extracted/cooked per snapshot (eight convexes/512 points each). No whole-map scan.
- Living hulls have an eight-unit extension below the feet in the **mirror only**. A native regression
  found that an exact flat-bottomed Source hull could pin thin floor glass without moving it sideways.
  The extension gives a lateral contact while Source keeps its own floor height. Both large and
  minimum-size floor pieces now move, with the kinematic trajectory unchanged.
- Native kinematic velocities come from motion toward successive poses. Initial velocity supplies
  one sample of incoming motion; teleports over 128 units correct poses without an enormous kick.
  Missing/removed/out-of-region bodies leave the next snapshot. Invalid PhysObjs are checked before
  equality; replaced bodies get fresh identities.
- Contact energy uses pre-solver normal speed: bodies require 160 units/s, falls 220. Falls use piece
  mass; bodies use `min(Source mass, 8 * piece mass)`; living mass follows the existing player/NPC mass
  setting (85 kg default). Threshold: `max(12000, 36000 * sqrt(area / 64) * thickness^2)`. These are
  gameplay defaults. There is no piece-piece damage cascade or change to G1's solver/sleep settings.
- Worker callbacks coalesce 64 damage records with atomics. Lua coalesces another bounded queue and
  processes one binary replacement/frame; stale work yields after 0.75 ms. Individual cooking,
  mesh-upload and engine-query calls cannot be preempted. Two private native slots permit rollback;
  completed replacements never exceed native capacity. Descendant expiry uses a bounded indexed heap;
  ordinary G1 pieces retain their existing expiry cursor and settled drawing path.
- Bullet interest: 32 regions, 120 seconds, radius 768–2048. Inspection itself caps at 256 pellets/s,
  burst 64. Forwarding caps at 64 rays/s globally (burst 32), 16/s per firing entity (burst 8), to the
  regions' PVS and actual player attacker. Payload is 28 bytes before headers: at most 1.75 KiB/s per
  recipient at the global sustained cap. Clients retain 32 rays for 0.5 s and cast at most eight/frame.
- Older/missing native modules retain G1's conservative behaviour; `interaction_available` reports
  availability. The fallback may simply have no new interaction, as the brief permits.

## Offline measured costs

All numbers below are generated-room CPU or engine/physics doubles, **not RTX game frame times**.
No falling-piece rendering/batching or solver tuning was undertaken. Three interleaved comparisons
use the preserved starting helpers/executable and current code; the table reports medians of means.

| Controlled workload | Starting G1 | R7-C off | R7-C on, no Source bodies/damage |
|---|---:|---:|---:|
| Lua Think + draw, 2000 moving quads | 0.1857 ms | 0.1744 ms | 0.1826 ms |
| Same, settling | 0.1247 ms | 0.1205 ms | 0.1139 ms |
| Same, settled | 0.0153 ms | 0.0127 ms | 0.0129 ms |
| Same, only 500 visible moving pieces | 0.1316 ms | 0.1350 ms | 0.1229 ms |

Each phase has 240 samples per run. Moving draws remain 2000, settled batches four, culled draws
500. The enabled moving p99 is 0.4135 ms versus 0.3607 ms initially; these small double-based timings
are noisy and establish no game improvement. Enabled settled allocation is 44.6 KiB/240 frames versus
2.1 KiB initially; warm draw paths still construct zero per-piece Vector/Angle/Matrix userdata.

The unchanged 4000-piece native benchmark settles in 11.0167 simulated seconds with no contact
overflows. Three-run median step mean is 4.0037 -> 3.7881 ms; spawn 22.52 -> 22.33 ms, simulation
wall 2.647 -> 2.504 s. This is a regression check, not a claimed performance improvement.

Latest isolated feature costs:

| Operation | Measured CPU |
|---|---:|
| 2000 minimum-size pieces, native step, off / on | 0.3126 / 0.3195 ms mean |
| Create 96 box mirrors | 0.1057 ms |
| Warm 96 mirrors plus collecting 2000-piece regions | 0.1079 ms mean |
| One raycast against 2000 pieces (640 rays) | 0.00102 ms mean |
| Two worst-limit shapes, each eight convexes/512 points | 2.6443 ms |
| CanSplit + native replacement (120 samples) | 0.0197 mean / 0.0344 p99 / 0.0500 ms max |

Warm source capture's real engine calls and Remix mesh ingestion remain unmeasured. New-shape
cooking is indivisible and can exceed the extraction-time allowance; its count/geometry caps bound
the burst. The measured two-shape stress cost is explicitly not a hard per-frame time guarantee.
The existing real-game baseline remains **25.31 / 113.22 ms** falling mean/p99 and **9.74 / 16.39 ms**
settled (G1 `10-field/console.log:661,663`, read only). Claude must reject a repeatable game slowdown.

Evidence in this worktree: `out/r7-c/costs.json`, `native-before-matched.log`,
`native-after-matched.log`, `native-priority.log`, `render-{before,off,on}-complete.log`, and saved
starting helpers/executable. Full-gate native output is also in the usual CTest `LastTest.log`.

## Validation

`tools/test.ps1 -Config Release` **passes**: 25/25 CTests, including 29 native glass cases;
468 Python tests (415 tools, 28 gmapack, 25 steam), with two existing skips. Targeted glass Python
validation passes 68 cases, including 12 new interaction cases and the real pane-interest regression.
Receipt: `out/r7-c/test-release-final.log`; convention and whitespace checks pass again after the
report/shared-document additions. The final gate uses the documented local guard-output workaround: ignored
`out/r7-c/short-guard-output.cmake` via `CMAKE_PROJECT_native_loader_INCLUDE`, moving only the guard
test executable to the ignored build's `g/`. The unmodified baseline also failed the known long-path
fixture; no loader code, test, registered CTest or tracked build setting was changed.

Native coverage includes motion without reverse reaction, both piece collision layers, thin floor
pieces, fast/heavy body damage, falls/blasts/bullets, coalescing/overflow, repeated convex area and
minimum-size preservation across 80 seeds, capacity/rollback boundaries, nearest interest regions,
raw-table binding validation and worker exclusion. Lua coverage includes read-only scene capture,
live/shadow/ragdoll classification, shape/row/region caps, stale physics, real pane break-interest
registration, final pellet/PVS/ammo/attacker forwarding and rate limits, menu/reset/translations,
one-split/frame render adoption, oldest-parent replacement, original lifetime/settings changes,
worker-safe disabling, ray expiration and the QA fixture/statistics path. Existing G1 tests remain.

## Claude's PoC acceptance

Detailed labels and expected counters are in the [QA sidecar](../../tools/qa/nlglass_qa/lua/autorun/nlglass_qa.lua.md).
After review/import of the module and matching Lua, use gm_construct, Jolt, piece size 8, budget
2000, lifetime 120 and interaction 1. Run `nlglass_qa interact`, or the new
[`nlglass_interaction_start.lua`](../../tools/qa/nlglass_interaction_start.lua.md) with the existing
screenshot workflow. The 19 screenshot steps must show:

1. A genuine pane break registers bullet interest, and follow-up Source bullets are forwarded.
2. The empty walk and pile walk reach the same Source speed/end position with unchanged health;
   pieces move. Running also splits large pieces (`body > 0`); glass never slows or damages Source.
3. A dropped ragdoll and thrown drum push/split the pile (`body > 0`), without reverse reaction.
4. One actual Source bullet into a large slab increases native ray hits and `bullet`; a real blast
   moves/splits it and increments `blast`.
5. A slab falls 256 units with no injected damage, splits on landing (`fall > 0`), then settles.
6. Cleanup leaves zero local pieces/mirrors/pending work. Repeat with interaction 0: no new body/
   bullet/fall/blast fracture or mirrors; blasts still push. Re-enable and verify a shot works.

Repeat unchanged `nlglass_qa field` on fresh matching sessions, on and off, against G1 run 10's
falling/settled numbers; preserve camera, resolution and RTX settings. Run `nlglass_qa map` on
modern_house. Also check two clients with different settings, a walking NPC, remote ragdoll fallback,
floor/displacement/prop landings, minimum-size movement, budgets 1/2000/8192, lifetime changes and
near-expiry splits, cleanup/reload/older-module fallback, all seven labels and non-admin reset.

## Limits

Real engine contact tuning, materials/Remix ingestion, frame-time parity and two actual clients
remain Claude's QA. Discovery margins/caps, teleport handling, partial ragdoll bones, coarse fallback
shapes, unavailable client matrices, unreliable/rate-limited rays and old/distant piles outside
server break interest can miss cosmetic interactions. Weapons that bypass FireBullets need their
own adapter. Follow-up pieces intentionally differ between clients; pane state stays authoritative.
Saturation drops cosmetic work. No pickup, reverse Source force, glass-inflicted gameplay damage,
piece-piece fracture cascade, package import or falling-renderer performance work was added.

## R7-C fast-body fix pass (`r7-glass-fix`)

Based on `7b49de9` on `r7-glass-fix`, for Claude's review and PoC recheck. The read-only run 11
evidence (`out/qa-poc/r7/11-interact/console.log:656–662` in the main checkout) records nine sleeping
pieces before and after the 30 kg, 650-unit/s drum, with zero mirrors/body splits at the after shot.
No game was launched, install/Steam/Remix file changed, package imported, download performed,
Workshop item updated, or branch pushed/merged/tagged. All generated evidence stays in this
worktree's `out/r7-glass-fix/`. The ground-level drum throw line is unchanged.

### Changes and bounds

- Discovery remains 10 Hz over at most 32 native interest regions. Spatial queries gain a 192-unit
  margin; retention tests current bounds plus velocity times 0.25 s, clamped to 192 units. Inspect
  at most 512 entries total, including duplicate query results and the player prefix. Rank incoming
  bodies (at least 160 units/s) before players and other candidates, then retain at most 128.
  The existing 96 mirrors, 24 bones/entity and two convex extractions/snapshot remain capped.
- Cold fast physics bodies get boxes immediately, without calling engine mesh extraction while
  fast. They can upgrade on slowing under the existing eight-convex/512-point/two-shape limits.
  Snapshot poses remain actual Source poses; discovery does not predict an early impact.
- Earlier capture alone still failed the thin-floor-box replay. Jolt explicitly excludes kinematics
  from CCD (`third_party/jolt/Jolt/Physics/PhysicsSystem.cpp:1564`). Fast actual mirror translations
  now shape-cast against glass before worker dispatch, transferring closing normal velocity only to
  pieces. They queue the existing body damage energy and preserve the Source-driven mirror target.
  No mirror/map response or Source write is introduced. No falling solver/render/batching change.
- Native snapshot caps: 16 casts, eight unique hits/cast, 64 body visits and 64 hit callbacks/cast,
  64 distinct velocity transfers total. Collector/budget buffers are fixed on the stack. Closing
  speed must reach 160 units/s; added speed caps at 2000. The existing 128-unit teleport correction
  bypasses sweeps. Minimum-size pieces only move, and interaction off does no sweep.
- QA prints peak mirrors/cold fast boxes, retained fast candidates/inspected entries, and cumulative
  native sweeps/hits/limited counters. A prop can leave before its screenshot, so current mirrors
  alone are insufficient. Native totals must be compared before/after each fixture.

### Regression and validation

The new end-to-end regression feeds the real `debris_scene.lua` snapshots into the offline native
`nl_glass_scene_replay` executable. It settles the same nine 32x32x0.5 pieces on a generated floor,
then replays a 3600-unit/s box and a 650-unit/s box behind 120 slow candidates. Their 108-unit
contact spans last about 0.03/0.17 s: within one/two discovery periods. Both 60 and 30 Hz snapshots
are tested, preserving the prescribed kinematic trajectory, with enabled and disabled controls.
The starting implementation fails both cases: zero pieces moved, zero body hits. Earlier discovery
with the starting native executable also fails. With both fixes, the four enabled replays move
3–5 pieces and register 5–6 body-damage events; every disabled replay moves/hits zero.

Two native cases independently cover both box speeds/cadences and both piece collision layers,
plus cast/transfer caps, minimum-size movement, teleport bypass and disabling. Lua checks also
cover moving-away/distant rejection, displacement caps, deferred convex upgrades and counter reset.
All 31 native glass cases and all 70 glass Python cases pass on the final code. The broader Release
run passes 26/26 CTests and 470 Python tests (417 tools, 28 gmapack, 25 steam; two existing skips).
Its only failure is conventions: three pre-existing links in `R7-plan.md` and the handover index
target the absent `R7-A-mmd-alpha.md`. A four-line redirect to Claude's existing investigation is
prepared under `out/r7-glass-fix/R7-A-mmd-alpha.redirect.md`; adding that separate handover document
requires scope clarification. It has not been written into `docs/`. No test is skipped or relaxed
to hide the failure. Receipts: `out/r7-glass-fix/test-release.log`, `test-release-final.log`; targeted receipts:
`glass-final.log` and `native-final.log`. No guard-path workaround was needed in this shorter worktree.

### Offline costs

Three interleaved before/after comparisons use preserved starting helpers/executable. Values below
are medians of run means; engine doubles and generated Jolt rooms, **not game or RTX frame times**.

| Controlled workload | Before | Fix |
|---|---:|---:|
| Empty capture, 1200 samples/run | 0.00027 ms | 0.00037 ms |
| Lua capture, 96 warm bodies, 1200 samples/run | 0.1428 ms | 0.1447 ms |
| Lua capture, 512-entry crowded prefix, 1200 samples/run | 0.1563 ms | 0.1959 ms |
| Native 96 warm mirrors + 2000-piece regions, 120 samples/run | 0.06035 ms | 0.05966 ms |
| Lua Think + draw, 2000 moving pieces, 240 frames/run | 0.1568 ms | 0.1691 ms |
| Same, settled in four batches | 0.0130 ms | 0.0129 ms |
| Native unchanged 4000-piece step benchmark | 3.5990 ms | 3.6797 ms |
| Native 2000 minimum-size steps, interaction on | 0.2564 ms | 0.2409 ms |

The crowded Lua prefix adds about **0.040 ms mean**; its p99 is 0.7772 ms versus 0.4917 before,
including 10 Hz discovery bursts. One moving box/native sync averages 0.0011–0.0033 ms across
the native speed/cadence/layer cases (largest sampled sync 0.0139 ms). The 96-mirror/128-leaf stress
snapshot reaches the 64-transfer cap in 0.0693 ms median (three samples, 0.0664/0.0799/0.0693 ms).

The moving Lua p99 is 0.2567 -> 0.2559 ms; draw counts and warm Vector/Angle allocations are
unchanged (2000 moving draws, four settled batches, 500 visible culled draws). The 4000-piece
benchmark still settles in exactly 11.0167 simulated seconds, with identical scratch use and zero
contact overflows. The renderer and fixed-step loop are unchanged; these noisy offline numbers
include a 0.0123 ms increase in mocked moving-frame mean and cannot establish game frame parity.
Real engine spatial-query/result construction and extraction
remain unmeasured and indivisible; bounded counts are not a wall-clock guarantee.

Evidence: `out/r7-glass-fix/regression-before.log`, `regression-after.log`, `measured-results.txt`,
`costs-{raw,summary}.json`, `capture-{before,after}-[1–3].log`, `render-{before,after}-[1–3].log`,
`native-{before,after}-[1–3].log`, `fast-box-[1–3].log`, and `sweep-cap-[1–3].log`. The native replay
is a test executable; only the rebuilt client module and matching Lua are candidates for import.

### Limits and Claude's QA

Repeat `nlglass_qa interact` with the matching Lua/module. The unchanged drum must move/split the
pile (`body > 0`), with nonzero fast-box/peak-mirror counters and new sweep hits. Repeat off: no
new mirror/body/sweep activity. Keep Source speed, health and trajectory unchanged. Recheck the
unchanged `field` on/off falling/settled frame-time acceptance from G1 run 10; no repeatable slowdown
is acceptable. The QA sidecar describes counter deltas and saturation evidence.

Finite discovery/lookahead, missing client entities/velocities, dense query prefixes, 32-region/
96-body limits and the native cast/transfer caps can still miss cosmetic contacts. More than 128
units between samples is treated as a teleport. Rotation-only motion is not swept; fast cold boxes
approximate convexes until slowing. Saturation reports skipped/truncated sweeps rather than delaying
Source. Actual drum contact tuning and RTX frame parity remain Claude's PoC acceptance work.

Implementation commit: `b9ff677` (fix, regression, caps, sidecars and QA counters). Rebuilt module:
`out/build/win64-release/glass/native/gmcl_nlglass_win64.dll`, 1,496,064 bytes, SHA-256
`4d40352c4d55424f14ce12d557ba087800306b42ceb7566f3f0ba2154939a014`.

### Delivery report

Implemented on `r7-glass-fix` in `b9ff677`, with report/shared evidence in a separate documentation
commit. Fast bodies use bounded swept discovery, priority and immediate boxes; capped native sweeps
transfer velocity/damage only to glass. No Source response or falling solver/render change.

The real Lua-to-Jolt regression fails before and now moves/damages a settled nine-piece pile at
650/3600 units/s and 60/30 Hz; disabled controls stay inert. All 31 native glass cases, 70 glass
Python cases, 26 CTests and 470 Python tests pass.

Offline cost: crowded capture adds about 0.040 ms mean; the capped 64-transfer native stress
snapshot costs 0.069 ms median. Mocked moving Think/draw measured 0.157 -> 0.169 ms; real drum
acceptance and falling-frame parity remain Claude's PoC checks. Saturated caps, finite lookahead,
missing client state, >128-unit corrections and rotation-only motion can still miss contacts.

The full Release gate is not green: three pre-existing links target the missing R7-A brief.
Your scope restriction requires clarification before adding that separate handover document;
the proposed four-line redirect is prepared under `out`. No game/install/package/Workshop/remote
action was taken. The unchanged ground-level drum throw is preserved.
