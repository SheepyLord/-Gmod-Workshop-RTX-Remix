# G1-B fix pass report

Implementation and offline checks complete, 2026-11-01, on `g1-native-fix` from `3096b2e`.
Claude owns integration, packaging and game acceptance. No game was launched; no install, Steam
file, user.conf, Workshop item or package input was written. No download, push, merge, tag or main
commit occurred. QA runs 01-qa/02-qa and the PoC's gm_construct BSP were read only.

## Commits

- `8e622e2`: isolate refused brush/prop shapes, double-precision clipping, displacement orientation
  and tag corrections, generated regressions and read-only offline import probe.
- `6ea7407`: background preparation/physics, active-body/changed-pose processing, measured catch-up
  cap, nonfatal contact saturation, demand-sized scratch and staged pile replacement with tests.
- This report and completion status are committed separately. All messages end with the requested
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>` trailer.

## The six requested items

1. **One shape never disables the world.** Brushes clip/deduplicate in double precision before
   conversion to float. A 62-sided generated prism produces exactly 124 vertices. Unusable brush
   hulls, Jolt-refused brushes/prop convexes and refused prop instances have separate statistics.
   A model can retain its good convexes after a flat/refused one; an entirely refused model is
   skipped. Finalization refuses a world only when it has no usable collision. Structural/unsupported
   BSP errors still select fallback. Generated tests include a finite, noncoplanar tiny hull that
   Jolt actually refuses, plus displacement-only usable and genuinely empty worlds.
2. **Displacements.** The fast index now goes toward corner 3; rows go toward corner 1. A fixture
   asserts the raised vertex at (200,210,1.25), excluding its transposed position. Real gm_construct
   has 20,992 triangle tags: 20,801 values of 6, 122 of 2 and 69 of 0; none sets SURFACE bit 0.
   Requiring that bit removed all terrain. Only REMOVE bit 5 omits triangles now; tests cover
   ordinary 0/2/6 tags and explicit holes. Local Source references were read for format facts only.
3. **Per-frame cost.** Jolt samples its old/new active sets through exclusive NoLock access,
   including final sleeping and newly woken bodies. A dense pose queue avoids full slot scans.
   Lua consumes only returned changed IDs, maintains native/individual lookups and visits only
   the final-second expiry cohort. Unchanged areas leave the rebuild work set. Physics runs on
   an asynchronous coordinator: Lua polls, applies queued removals/impulses and at most 128 pending
   spawns, publishes poses, then starts the next step. Busy frames use the last published poses;
   entirely sleeping worlds dispatch no worker. Substeps have a measured 4 ms catch-up allowance,
   at most four, always allowing one; discarded whole steps are counted.
4. **Pile rebuilding.** Keep old valid chunks until replacements exist. Transform at most 1,800
   vertices/frame, accumulate at most 6,000/mesh and upload at most one mesh/frame. A removed/woken/
   shrinking member hides only its affected immutable chunk; its survivors draw individually.
   New arrivals request another revision, removals cancel stale staging, and failed uploads retain
   old valid chunks and retry. Harness tests cover these transitions and complete resource cleanup.
5. **Full contact cache.** Jolt's safe partial-contact update continues. Total saturation and
   manifold/pair/constraint counters are exposed. A generated 128-body overlap fills the cache
   without disabling the world; the ordinary 4,000-body pile has zero saturations.
6. **Map preparation and memory.** Lua copies BSP bytes into `BeginLoadMap`, polls its worker,
   extracts two client prop models or adds 64 instances/frame, then polls background finalization.
   Parsing/cooking and release of the large byte buffer occur on the worker. Lua's VFS read and
   owned-byte copy remain on the client thread. Init/map import reserve zero simulation scratch,
   replacing the old 144 MiB Init(8192) reserve. Active scratch follows live/observed demand with a
   non-aborting fallback. Pair/contact tables are max(1024,budget*8) / max(1024,budget*4).

## Measurements

Read-only gm_construct import, no client prop collision extraction:

| Result | Value |
|---|---:|
| BSP bytes | 36,735,656 |
| Solid world brushes considered / clipped | 2,095 / 2,092 |
| Skipped during clipping / refused by Jolt | 3 / 1 |
| Displacement triangles / refused mesh batches | 20,992 / 0 |
| Solid prop metadata records | 4 |
| Static bodies | 2,094 (2,091 brush + 3 terrain batches) |
| Standalone parse / Init / parse+cook+finish | 14.50 / 1.13 / 46.60 ms |
| Async enqueue including owned byte copy | 3.79 ms |
| Maximum async poll / total preparation | 0.0069 / 76.12 ms |

The original probe reproduced the QA failure: 2,095 considered, 3 skipped, then one refused Jolt
hull aborted the world after 55.38 ms. The corrected probe accepts it. Counts exclude the four
prop instances, which require engine model collision. Byte reads/cooking write no game assets.

Representative Release measurements, Ryzen 9 9950X3D, eight Jolt workers, 8,192 capacity,
4,000 colliding 4x4x0.6-unit pieces in four layers:

| Measurement | Before | Corrected |
|---|---:|---:|
| Simulated time to sleep | 11.0167 s | 11.0167 s |
| Core simulation wall / all-thread CPU | 2.706 / 18.797 s | 3.295 / 22.703 s |
| Synchronous active step mean / max | 4.094 / 7.380 ms | 4.983 / 7.874 ms |
| Settled core step + poses | 0.0640 ms | 0.00162 ms |
| Client-side async dispatch mean / max | synchronous | 0.0134 / 0.0605 ms |
| Client-side poll mean / max | synchronous | 0.00296 / 0.0203 ms |
| Simulation scratch at Init | 144 MiB | 0 |
| Scratch held / requested peak at 4,000 | 144 MiB reserved | 34 MiB / 28.83 MiB |
| Mocked Lua active Think | 0.165 ms | 0.135 ms |
| Mocked Lua settled Think | 0.130 ms | 0.026 ms |

Active worker throughput did **not** improve in that comparison; removing its synchronous wait
from the client thread is the improvement. A separate async sample averaged 5.434 ms on the
worker. A .25-second dispatch allowed one substep and counted .233333 seconds discarded.
Lua timings use identical mocked physics and exclude real native binding, engine upload and
Remix drawing. The synthetic single-area pile uses 25 small chunks instead of 3 large meshes.
Initial creation of all 4,000 individual meshes still costs about 100 ms CPU in that harness
(108 ms before, 111 ms in the comparison, 94 ms in a later run). No game performance claim follows.

## API, files and artifact

Jolt stays byte-identical **5.3.0**; no third-party source changed. Existing synchronous functions
remain. Added binding pairs are `BeginLoadMap`/`PollLoadMap`, `BeginFinishWorld`/`PollFinishWorld`,
`BeginStep`/`PollStep`. Poll returns false while pending, then its result, or nil/reason on error.
Busy mutations refuse immediately; Stats returns a pre-dispatch snapshot. Cleanup/shutdown joins
before freeing resources. All worker results/errors cross the guarded binding on the client thread.

`NLGlassDebris` keeps the agreed public API, adds no required G1-A call and includes the new
`nlglass/debris_batches.lua` helper. The existing autorun's `debris*.lua` AddCSLuaFile glob serves
it already. **Package the DLL and B Lua helpers together.** G1-A's files and glass/README.md were
not edited. Details are in [the native README](../../glass/native/README.md), companion script
docs and [ADRs 0074](../decisions/0074-glass-native-fix-pass.md) /
[0075](../decisions/0075-glass-background-work-and-staged-piles.md).

Artifact: `out/build/win64-release/glass/native/gmcl_nlglass_win64.dll` (1,428,480 bytes), PDB
16,166,912 bytes. DLL SHA-256:
`12734173e1659b1d81635213eeaf85c6cd6354c39efd704ff2512b42f437ccc5`.
No binary or game fixture is committed; Claude imports the binary through normal package tooling.

## Tests and remaining game acceptance

`tools/test.ps1 -Config Release` passes **25 CTests and 426 Python tests** (373 tools, 28 gmapack,
25 steam; two expected skips). The glass native executable contains **19 cases**; the actual
LuaJIT manager/probe harness passes **3,264 assertions**. Evidence is under this worktree's
`out/g1-native-fix/`, including `test-release-final.log`, `native-measured.log`, `import-delivery.log`,
the original repro and Lua comparisons.

The plain first gate hit the existing guard MAX_PATH failure at `test_early.cpp:198`. The final
gate uses the documented local-only CMake output relocation to `${CMAKE_BINARY_DIR}/g` via
`out/g1-native-fix/short-guard-output.cmake` and the ignored build cache. All 22 guard assertions
and every other registered test run. No guard/loader source or tracked build setting was changed.

Claude should verify in game:

- gm_construct reaches `backend=jolt`, retains terrain and client static-prop collision, and logs
  the isolated skip/refusal counts. Community displacement variants need real contact checks.
- Preparing a map and breaking the first pane remain responsive; pending pieces drain and become
  simulated, with no disappearing debris during polls, expiry, cleanup or a module failure.
- Piles retain valid chunks while rebuilding; wake/explosions/removal/shrink show no duplicate or
  stale geometry. Queued explosions reach pieces spawned while the worker is busy.
- Run the updated [debris QA probe](../../tools/qa/glass_debris_jolt_probe.lua.md) with thousands of
  pieces and the integrated fifty-window case. Retain empty/falling/settled percentiles, zero final
  moving/pending counts, cache saturation and discarded-time counts. Compare Remix frame cost and
  the increased chunk draw count; offline tests do not establish the few-percent target.
- Repeat G1-A's acceptance causes and the rest of the integrated game checks after merging both
  fix branches. This report establishes native/debris offline acceptance only.
