# G1-B second fix pass report

Implemented and validated offline, 2026-11-01, on `g1-native-fix2` from `ad3ed46`.
Claude owns integration, packaging and the game targets. The game receipts in the main checkout's
`out/qa-poc/g1/03-qa` and `04-map` were read only. No game was launched, install/Steam file or
user.conf touched, package/Workshop item changed, download made, or push/merge/tag/main commit made.
G1-A's files, `glass/README.md`, and `tools/qa` are untouched.

## Commits

- `27a4992`: consolidate settled material areas; reuse bounded upload scratch; stage mesh retirement;
  test transforms, tint/alpha, consolidation, warmed rebuild allocations and cleanup.
- `36bf60f`: group and cull individual drawing, cache transforms, expose rolling frame costs/calls;
  test camera/scale/timing behavior, slow preparation and upload peak retention.
- This report and completion status are committed separately. Every commit message ends with the
  requested `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>` trailer.

## 1. Settled piles in few draws

`debris_batches.lua` consolidates into half-cell-offset 1024-unit XYZ areas by material, with tint
and alpha retained in vertex colors. Uploads hold up to 24,000 vertices. One snapshot shares a
bounded vertex pool across all areas: `debris_mesh.Transformed` computes one Source rotation basis
per piece and mutates pooled vertex/position/normal records instead of calling LocalToWorld twice
per vertex. Pooled records survive Clear for reuse and release on Shutdown.

Rebuilding waits 200 ms after changes, starting by 750 ms during ongoing arrivals. Oldest-due areas
get priority. Preparation stops at 1,800 vertices or a measured 0.6 ms allowance, checked after each
whole piece. At least one piece can progress. There is at most one upload/frame. Old valid chunks
remain until the complete replacement exists; removed/woken/shrinking members invalidate their
affected chunk immediately. Failed uploads retain old geometry and retry. Superseded/canceled GPU
meshes retire at most two/frame; cleanup frees all outstanding resources.

The old path creates concrete allocation/release bursts: the controlled settling scene constructs
288,000 Vector and 144,000 Angle userdata and allocates about 40.8 MiB with GC stopped. The new path
constructs 47,952 Vector and zero Angle userdata and allocates about 13.9 MiB; a warmed rebuild
constructs no vertex vectors. These changes remove transient transformed-vertex churn and a
whole-pile GPU destruction burst. Aggregate game logs alone cannot prove these caused every p99
spike. Native upload calls remain indivisible; actual <=1 ms settled delta/no >16 ms spikes need
game measurement. Upload/rebuild peaks now expose such stalls after the scene becomes quiet.

## 2. Moving pieces

`debris_draw.lua` maintains material groups containing only individual pieces, so merged piles
leave the per-piece render loop. It binds once per visible material group, with no per-piece
Vector/Angle/Matrix/table allocation during drawing. Matrices update lazily after published poses
or scale changes; repeated passes reuse them. Non-unit shrink reapplies after a changed rotation.

`debris_view.lua` captures the current render camera, including scripted/third-person views, once
per pass. Conservative sphere/frustum bounds reject rear/side/vertical pieces and settled areas;
rendering stops beyond 8192 units plus radius. Individual pieces beyond 256 units skip when their
projected radius is below 0.75 pixels, using camera depth and viewport scale. Culling leaves physics,
lifetime and explosions running; a camera move restores drawing without rebuilding. Missing camera
context disables culling. Secondary reflections may lose off-camera cosmetic debris, as implied by
the requested view culling.

Native code, ABI and byte-identical vendored Jolt **5.3.0** are unchanged. Existing 0.35 s / 0.06 m/s
sleep tuning is retained: no new heuristic risks freezing airborne pieces. The public NLGlassDebris
API is unchanged. Initial Spawn geometry/individual mesh construction still runs synchronously;
this pass does not claim to remove that cost or include it in hook timings.

## 3. Instrumentation

`NLGlassDebris.Stats()` reuses its output table and now includes:

- `think_ms`, `draw_ms`: means of the last 120 sampled frames, or fewer while warming up.
- `think_last_ms`, `draw_last_ms`, `think_peak_ms`, `draw_peak_ms`: latest and worst hook frame costs.
- `draw_calls`, `draw_calls_avg`, `draw_calls_current`: completed-frame, rolling mean and current-frame
  submitted mesh counts. Eligible passes with the same FrameNumber accumulate into one frame;
  depth/sky callbacks are ignored. Completed draw samples publish on the next frame.
- `think_samples`, `draw_samples`, `culled_pieces`, `rebuild_ms`, `upload_ms`, `rebuild_peak_ms`,
  `upload_peak_ms`, `rebuild_pool_vertices`, `retiring_meshes`.

Times are client CPU milliseconds, covering the manager hooks and their rebuild/upload work.
They exclude asynchronous Jolt worker/GPU execution and Spawn/fracture outside Think. Timing peaks
reset on Clear. Copy fields if retaining samples. Exact injected regressions measure 1.25 ms Think,
two two-mesh render passes totaling 1.6 ms/four calls in one frame, rolling-window expiry and reset.
A slow-vector double proves preparation yields before the count cap; an injected 2.5 ms upload
remains in the peak metric through subsequent quiet frames.

## Tests and measurements

`tools/test.ps1 -Config Release` passes **25 CTests and 448 Python tests** (395 tools, 28 gmapack,
25 steam; two existing skips). Native glass has 19 cases. The final direct LuaJIT manager/probe
run passes **14,576 assertions**. Repo conventions and diff whitespace checks pass.

The initial full gate reproduced only the known guard MAX_PATH failure at `test_early.cpp:198`.
The successful gate uses the previously documented local-only CMake output relocation to
`${CMAKE_BINARY_DIR}/g`, via `out/g1-native-fix2/short-guard-output.cmake` and the ignored build
cache's `CMAKE_PROJECT_native_loader_INCLUDE`. Guard/loader source, registered tests and tracked
build settings are unchanged; all 22 guard cases execute.

Matched QPC/LuaJIT comparison: same starting/current helpers, 2,000 quads across 50 locations,
240 frames per phase, GC stopped to count allocations. Physics, engine upload and rendering use
doubles; real binding/GPU costs are absent.

| Measurement | Starting helpers | Second pass |
|---|---:|---:|
| Settled draws, 2,000 pieces | 15 | 4 |
| Separate one-area/tint/grid-zero regression | fragmented | 4 draws for 2,000 pieces |
| Settling allocation | 41,795 KiB | 14,220 KiB |
| Settling Vector / Angle constructions | 288,000 / 144,000 | 47,952 / 0 |
| Fully visible material binds/frame | 2,000 | 1 |
| Fully visible matrix writes, 240 frames | 1,440,000 | 962,000 |
| Fully visible Think+draw mean | 0.1623 ms | 0.1650 ms |
| Mixed-visibility submitted draws | 2,000 | 500 |
| Mixed-visibility Think+draw mean | 0.1349 ms | 0.1144 ms |
| Settled Think+draw mean | 0.0155 ms | 0.0119 ms |

Culling/instrumentation can add Lua work when everything is visible; earlier samples measured
0.132 -> 0.164 ms. The useful reductions are engine calls, hidden draws and allocation pressure;
the mock timings do not establish the <20 ms falling target. All warm drawing phases construct
zero per-piece Vector/Angle/Matrix userdata; the original draw path already avoided those allocations.

The unchanged native recheck sleeps 4,000 colliding pieces in 11.0167 simulated seconds with zero
contact overflows. Settled core step+poses averages 0.00165 ms. No native performance improvement
is claimed from this rendering-only pass.

Evidence in this worktree's `out/g1-native-fix2/`: `test-release-final.log`,
`test-release-initial-path-failure.log`, `lua-final.log`, `render-before-final.log`,
`render-after-final.log`, baseline helpers under `before/`, and the local CMake workaround.
Native CTest measurements also remain in `out/build/win64-release/Testing/Temporary/LastTest.log`.

## Delivery and remaining game checks

Package all owned `debris*.lua` helpers, including the new `debris_draw.lua` and `debris_view.lua`,
and their existing dependencies. G1-A's autorun already AddCSLuaFile-globs them. No G1-A API or
native ABI change is required. Decisions are [0079](../decisions/0079-glass-pile-consolidation.md)
and [0080](../decisions/0080-glass-visibility-and-frame-costs.md); field descriptions are in
[the manager documentation](../../glass/addon/lua/nlglass/debris.lua.md).

The normal Release build also produces `out/build/win64-release/glass/native/gmcl_nlglass_win64.dll`
(1,428,480 bytes) and PDB (15,781,888 bytes). DLL SHA-256:
`9aa88d6964ff3243cfffc83058fed024a5e02f450e1592b4bde9eb27a336d8f7`.
No binary or package input is committed/imported by this pass.

Claude should check:

1. Same-camera empty/falling/settled fifty-pane frame statistics after combining both second passes:
   settled delta <=1 ms with no >16 ms settled spikes; falling mean <20 ms. Retain total frame
   percentiles, manager means/peaks/draw calls, upload/rebuild peaks, native awake/pending counts,
   discarded time and cache overflows. Compare the supplied 388-batch scene with actual new counts.
2. Few draws per settled area; retained geometry through incremental rebuilds; no stale/duplicate
   glass after explosions, wakes, budget eviction, expiry/shrink, cleanup or failed replacement.
3. Camera turns, edge-of-view spheres, wide-FOV/rolled/third-person cameras, view distance and distant
   tiny pieces under Remix. Check appearance at the actual resolution, including reflection tradeoffs.
4. Responsive first/burst Spawn and all G1-A break causes/piece-density changes with the integrated
   package. Hook timing deliberately excludes fracture/Spawn work, so a total-frame spike with low
   Think/draw peaks still needs client-handler/GC attribution.
