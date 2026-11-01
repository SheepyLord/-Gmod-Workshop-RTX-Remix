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
