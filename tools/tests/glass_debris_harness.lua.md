# glass_debris_harness.lua

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
