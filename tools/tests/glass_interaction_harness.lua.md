# glass_interaction_harness.lua

MIT LuaJIT harness for the actual `debris_scene.lua` and `debris_bullets.lua`. Run through
`test_glass_interaction.py`, or `luajit tools/tests/glass_interaction_harness.lua glass/addon/lua CASE`.
Cases: `scene_kinds`, `scene_caps`, `scene_fallback`, `bullets_filter`, `bullets_rate`, `bullets_client`.

`scene_sweep_bounds` verifies approaching/away/distant bodies, the 192-unit lookahead cap,
immediate fast boxes, later convex upgrade, stable identities and resettable fast counters.
`scene_fast_replay` (3600 units/s) and `scene_fast_crowded_replay` (650 units/s behind 120 slow
candidates) implement spatial box queries and emit the actual captured rows between
`REPLAY_BEGIN`/`REPLAY_END` for the native replay regression. An optional third argument sets
the snapshot interval (1/60 or 1/30 seconds). Fast physics mesh extraction must not be called.
The Python test passes those rows to Jolt; this Lua harness does not pretend to simulate contacts.

`SysTime` is the harness's Source clock (`CurTime`), which only the cases advance, so the capture's
wall-clock budgets (the second shape cook within 0.5 ms) never depend on the machine: on a loaded
2-vCPU CI runner, `os.clock` (wall time on Windows) once deferred a cook and failed `scene_flags`.

`sceneperf` prints 1200-sample QueryPerformanceCounter timings after 80 warm frames: empty,
96 warm bodies and a 512-entry priority prefix. Timings include real capture code with engine
doubles and a native-sync double; no real engine query, native sync, Remix or GPU costs.

The physics-object double returns `GetAABB` in its own frame and places it with `LocalToWorld`, as the
game does; `scene_fallback` checks that a coarse box takes its body's world position and yaw, and
`scene_sweep_bounds` that a fast box sits at the body (both fail on capture code that used the AABB as
world bounds).

Source doubles forbid all position, velocity, force and damage writes and whole-map scans. Checks
living/shadow classification, per-bone ragdolls, stale physics identity, fallback shapes, spatial/body/
shape caps, removals, final trace/PVS forwarding, unchanged weapon callbacks, ammo metadata, token
buckets, expired/cleaned interest and receive-only clients. No game, native module, installed assets,
network or files are changed. Exit 0 prints an assertion count; assertion/Lua errors exit nonzero.
The replay emits only text to stdout and takes no installed assets.

R8-G scene_flags checks all 16 masks, default living exclusion, live/dead classification, NextBots and client ragdolls; capture rows carry their native category.

R8-G adds long-lived per-client interest/lease validation, actual client refresh/empty-update cadence, stock swing cooldown/animation coalescing, and read-only Source-clipped SWEP trace regressions. Existing bullet tests use the new bounded payload and verify numeric region tests.

The SWEP scenario also exercises stock fists' delayed line-then-hull pattern: one message keeps
the larger hull and the mean of the configured HitDamage range. Trace results remain unchanged.

Additional boundary regressions cover animation-before-command initialization and resending cooked shapes after a collision-mask change.

The all-mask regression also includes an equipped weapon, a dropped pickup and a living actor's bone follower: equipment/shadow contacts cannot bypass living-off flags.

The melee scenario additionally proves that conservative Source re-clipping shortens the forwarded endpoint while preserving the SWEP result, rejects solid starts, and bounds extra clipping queries even when no recipient region overlaps.

The SWEP regression mutates the returned vectors before the deferred send and verifies that the owned observation and the weapon's mutated result remain independent.
