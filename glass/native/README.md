# Dedicated broken-glass world (G1-B)

C++20 x64 client module/core, MIT. Built by `tools/build.ps1`; nothing is installed by this build.
Jolt 5.3.0 is statically linked from [the pinned source](../../third_party/jolt/README.md).

| Source | Purpose |
|---|---|
| `geometry.h` | Source-unit geometry, input limits and hull validation |
| `bsp.h`, `bsp.cpp` | Bounded little-endian VBSP reader, LZMA collision lumps, world brushes, displacement triangles and static-prop metadata |
| `world.h`, `world.cpp` | Separate Jolt world, worker pool, pieces, fixed stepping, interpolated poses, sleep/wake and budgets |
| `module.cpp` | Client-only `ILuaBase` binding, raw table access, numeric/type validation and exception-to-result boundary |
| `tests/fixture.h` | Generated synthetic room, displacement and static-prop BSP; no game files |
| `tests/test_glass.cpp` | Parser, hull, boundary, lifecycle, interpolation and 4,000-piece benchmark tests |
| `tests/import_probe.cpp` | Read-only offline map counts/timings; run `nl_glass_import_probe <map.bsp>` explicitly, never via CTest |
| `tests/fake_lua.h`, `tests/test_binding.cpp` | Strict stack-based `ILuaBase` double executing the actual exported callbacks, including realm refusal and reused pose tables |

All API vectors use Source coordinates (Z up), one unit = 0.0254 metres. Angles are Source
pitch/yaw/roll, spin is a world-space axis times degrees/s. Gravity defaults to 600 units/s².
The world uses `max(1, min(8, hardware_concurrency - 2))` Jolt workers. A background coordinator
owns the world during asynchronous imports/finishes/steps; Lua polls and renders the last published
poses without waiting. All Jolt jobs join before a result is published. Only cleanup/shutdown may
wait for an in-flight operation; ordinary busy mutations return nil/reason. No worker calls an
engine or Lua interface. `Stats` returns a pre-dispatch snapshot while busy.

Body budget is 1-8192. Map bytes/expanded collision data cap at 256 MiB, each inflated lump at
128 MiB, LZMA dictionary at 64 MiB, static bodies at 32768, prop collision models at 2048,
convexes/model at 128, points/hull at 256. Init/map import reserve no simulation scratch. On the
first active step the reserve follows live demand (2 MiB + 8 KiB per live piece, rounded to 256
pieces), then grows to observed peak demand. Jolt's non-aborting heap fallback handles a new peak;
body/pair/contact limits bound work. Pair/contact capacities are `max(1024,budget*8)` and
`max(1024,budget*4)` respectively.
Cache saturation increments per-kind counters and continues Jolt's safe partial-contact update.
Substeps are 1/60 s, capped at four per dispatch and by a measured 4 ms catch-up budget (one update
always runs, even when it exceeds 4 ms). Excess whole steps are discarded/counted; fractional time
is retained for interpolation. Completely sleeping worlds skip physics updates.

Import accepts VBSP 19, 20 and 21 (including the L4D2 reordered directory). It traverses model 0's
node/leaf tree, imports only its referenced brushes, and clips their plane halfspaces to convex
hulls in double precision, deduplicated before float conversion. Individual unusable/refused brush
and prop convex shapes are skipped and counted; only an empty finished world falls back.
Contents use `MASK_SOLID_BRUSHONLY` (`0x400b`: solid/window/grate/moveable); player and
monster clips, water and entity brush models are excluded. Displacement powers 2-4 become two-sided
triangle meshes: columns run toward corner 3, rows toward corner 1. REMOVE-tagged triangles
(bit 5) are omitted; SURFACE bit 0 is not required (gm_construct sets it on no triangles).
`sprp` versions 4-11 return solid model
instances, including v11 uniform scale; Lua supplies each unique model's collision convexes.
Models with no client collision are skipped. Moving props, players, dynamic brush entities and
other gameplay bodies never enter this world. Unknown/malformed collision data leaves an empty
unready world; the manager logs once and chooses fallback.

`require("nlglass")` exposes global `nlglass` (also returned from module open). Functions return
`nil, reason` for refused input/failure, without `ThrowError`, metamethods or engine calls from workers:

| Function | Arguments/result |
|---|---|
| `Init` | `(budget, gravity)` -> true; replaces any prior world |
| `LoadMap` | `(bspBytes)` -> array of `{model, position={x,y,z}, angles={pitch,yaw,roll}, solid, scale}` |
| `BeginLoadMap`, `PollLoadMap` | `(bspBytes)` -> true after owned byte copy / `()` -> false while pending, then prop array; parse and cooking run on a worker |
| `AddModel` | `(name, convexes)` -> boolean; true if any convex survived cooking |
| `AddProp` | `(name, position, angles, scale)` -> boolean; missing/refused model instance is skipped |
| `FinishWorld` | `()` -> true; optimize the static broadphase, enable spawning |
| `BeginFinishWorld`, `PollFinishWorld` | `()` -> true / false while pending, then true; background broadphase optimization |
| `Spawn` | `(hullPoints, position, angles, velocity, spin)` -> unique nonzero id |
| `Remove` | `(id)` -> boolean; stale ids return false, never alias a new body |
| `Impulse` | `(origin, radius, speed)` -> true; radial speed falloff, independent of mass |
| `SetCollide`, `SetGravity` | `(boolean)` / `(Source units/s²)` -> true; wake pieces when changed |
| `Step` | `(dtSeconds)` -> true; synchronous core/test compatibility; invalid inputs return nil/reason |
| `BeginStep`, `PollStep` | `(dtSeconds)` -> true / `()` -> false while pending, then true; manager uses these to keep physics off the client thread |
| `ReadPoses` | `(posesById, changedIds)` -> count; writes existing rows `{x,y,z,pitch,yaw,roll,sleeping}` and changed ids `[1..count]` |
| `IsSleeping` | `(id)` -> boolean; stale ids return nil/reason |
| `Stats` | `(existingTable)` -> true; fills live/awake/statics/models/workers/substeps/step_ms/dropped_seconds/ready |
| `Clear`, `Shutdown` | `()` -> true; remove pieces / release the whole world and worker pool |

Vectors/angles accept typed GMod values or raw three-number arrays. Hulls require 4-256 finite
noncoplanar points; glass points must lie within 1024 units of their local origin. Coordinates
cap at +/-131072, angles/spin at +/-36000, velocity components at +/-100000, gravity at 0-10000.
`ReadPoses` does not construct tables or Vector/Angle userdata: the manager allocates one row on
spawn and mutates its own drawing objects. It writes active pieces and one final pose when a piece
sleeps; consume only the returned number of changed ids. Reused native buffers are reserved up front.

Import statistics include `brushes` (considered solid world brushes), `skipped_brushes` (clipping),
`refused_brushes`, `refused_convexes`, `refused_meshes` (Jolt cooking) and `skipped_props`.
Runtime statistics add `busy`, `pose_visits`, `contact_overflows`, `manifold_overflows`,
`pair_overflows`, `constraint_overflows`, `temp_reserved_bytes`, `temp_peak_bytes`.
Active body IDs are copied only across an update; the old/new sets capture final sleeps and pile
wakes. Body reads/mutations use Jolt's NoLock interfaces only while the coordinator has exclusive
world access. A dense pose queue visits active/changed bodies instead of all 8192 slots.

The read-only import probe prints synchronous counts/times and asynchronous enqueue (including
byte copy), poll and total preparation times. It omits static-prop model collision (requires client
engine extraction); no installed assets are included in tests or written by the probe.
