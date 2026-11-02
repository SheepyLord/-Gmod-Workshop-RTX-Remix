# glass_debris_harness.lua

R7-C adds `interaction_manager`, `interaction_budget`, `interaction_lifetime`, `interaction_off`
and `interaction_rays` as the third argument (after the existing probe path). `interaction_qa` runs
the QA add-on's actual client fixtures and statistics output. These enable strict
new native-API doubles and execute the actual manager, including render adoption and expiry.
`interactionperf` runs the same 2,000-piece QPC render comparison with native interaction available
and on, empty Source interest and no damage. Existing `renderperf` keeps older-module compatibility.
`interactionoffperf` supplies the new native API with the local setting off for a matched comparison.

Runs the actual G1-B `debris*.lua` and `world.lua` through mocked engine APIs. Called by
`test_glass_debris.py`, or `luajit tools/tests/glass_debris_harness.lua glass/addon/lua`.

Checks pending map import, collision-model deduplication/skips, budgets, expiry/shrink, moving and
settled draws, debounced batch rebuilding, explosions, cleanup, native failure migration and absent
backends. An optional second argument executes the actual Jolt QA probe, including setting restore
and cancellation with an intervening player edit. Inputs are the Lua source directory and generated vectors/entities; no game files, network
or filesystem writes. Prints assertion count; exit 0 on success, nonzero on assertion/error.

The fix-pass harness also checks asynchronous import polls, refused-model isolation, bounded spawn
queues, deferred removal/impulses, chunk retention across multi-frame rebuilds, per-frame transform
bounds, affected-chunk wake drawing and in-flight cleanup. A third argument `perf` (use `skip` for
the unused second argument) runs a 4,000-piece mocked-physics CPU benchmark instead of assertions:
`luajit tools/tests/glass_debris_harness.lua glass/addon/lua skip perf`. It prints spawn, active and
settled manager CPU times and final batch counts. It can run against an old copy of the Lua helpers
for a controlled comparison. This excludes actual Jolt, engine mesh upload and Remix drawing.

Second-pass regressions check pooled transforms against the complete Source basis, tint/alpha
updates, 2,000 tinted pieces across zero in four consolidated draws, bounded/shared scratch,
zero new vertex vectors on a warmed rebuild, deferred retirement and complete cleanup.
`skip renderperf` runs moving/settling/settled samples with 2,000 quads in a 50-pane footprint.
It uses Windows QueryPerformanceCounter through LuaJIT FFI, stops GC during each 240-frame sample
to count allocations, and prints manager Think+draw mean/p99/max, allocations, userdata/transform,
matrix-write/material-call counts and final draw counts. GC restarts after every sample; only
stdout is written. Timings use mocks and do not establish a game or GPU performance result.

Rendering/instrumentation checks cover side/vertical/rear/distance/subpixel and sphere-edge culls,
rotated/rolled wide-FOV cameras, camera changes, conservative settled bounds, one material bind
per visible group, lazy matrix writes, no per-piece draw userdata, ignored depth/sky callbacks,
two passes in one engine frame, exact injected millisecond means/peaks/call counts, the 120-frame
window and `Clear` reset. The optional render benchmark also moves three quarters of pieces
behind/outside/distant from the view and reports how much work is skipped. FFI only calls QPC;
there is no native module load or game access.

A slow-vector double also makes the measured 0.6 ms preparation allowance stop before the
1,800-vertex hard cap; an injected 2.5 ms upload is retained in Stats after quiet frames.

R8-G collision_settings checks the archived one-time migration, explicit mask/master preservation, reload and always-on map/piece contacts.

R8-G interaction_rays also checks native melee dispatch and malformed radius/range rejection in the shared expiring queue.

R8-G load_queue checks receipt without mesh/body allocation, the 12-item/time allowance, worker exclusion, original expiry, queued blast inheritance, budget changes and cleanup. load_area checks 160 real annealed/tempered full/partial breaks for exact polygon/front-triangle area, no missing/duplicate input, geometry bounds and preserved nearby detail. load_manager replays 50 real fractures over 1.5 seconds, keeping the original 2000-fragment budget with fewer than 600 rigid instances. loadperf measures the same path against preserved starting helpers. Warm renderperf/off/on modes remain comparable; preparation now drains before timing. All are engine/physics doubles, never game timings.

R8 QA regression also checks temporary masks 3/7 and restoration of the original mask, master and
lifetime through the actual client fixture receiver. No game or install is used.

load_manager additionally verifies near-detail protection from the actual scripted render camera when the physical player eye is distant.

load_queue injects a slow mesh Destroy to prove that budget receipt performs no synchronous GPU release, drains at most 16/frame, and frees the retirement queue at cleanup.

The real-fracture load scenario also forces a native failure and verifies exact compound fallback within the 64-original-fragment cap.


R9-G adds r9_preview (120 queued fragments visible in five shared meshes in the receipt frame,
12-body construction cap, complete handoff and cleanup) and r9_sounds (four/frame, burst 24,
per-piece cooldown, distance culling, switch and cleanup). Existing older-module interaction tests
retain binary replacements, exercising the compatibility path.

`r9_multi` verifies six-child adoption within the original fragment budget, inherited expiry and
nonblocking motion diagnostics between worker steps.
