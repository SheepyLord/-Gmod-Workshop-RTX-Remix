# Dedicated broken-glass world (G1-B)

C++20 x64 client module/core, MIT. Built by `tools/build.ps1`; nothing is installed by this build.
Jolt 5.3.0 is statically linked from [the pinned source](../../third_party/jolt/README.md).

| Source | Purpose |
|---|---|
| `geometry.h` | Source-unit geometry, input limits and hull validation |
| `bsp.h`, `bsp.cpp` | Bounded little-endian VBSP reader, LZMA collision lumps, world brushes, displacement triangles and static-prop metadata |
| `world.h`, `world.cpp` | Separate Jolt world, worker pool, pieces, fixed stepping, interpolated poses, sleep/wake and budgets |
| `fracture.h`, `fracture.cpp` | Convex XY outlines, equal-area binary clipping, centroids and extrusion for follow-up splits |
| `module.cpp` | Client-only `ILuaBase` binding, raw table access, numeric/type validation and exception-to-result boundary |
| `tests/fixture.h` | Generated synthetic room, displacement and static-prop BSP; no game files |
| `tests/test_glass.cpp` | Parser, hull, boundary, lifecycle, interpolation and 4,000-piece benchmark tests |
| `tests/test_interaction.cpp` | One-way kinematics, contact/bullet/blast/fall damage, convex area/minimum-size/capacity tests and bounded-cost benchmarks |
| `tests/import_probe.cpp` | Read-only offline map counts/timings; run `nl_glass_import_probe <map.bsp>` explicitly, never via CTest |
| `tests/scene_replay.cpp` | Replays actual Lua capture rows from stdin into a generated sleeping nine-piece pile; checks movement/damage, prescribed mirror trajectories and the disabled control |
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
Models with no client collision are skipped. The static import contains no moving props, players
or other gameplay bodies. Unknown/malformed collision data leaves an empty
unready world; the manager logs once and chooses fallback.

R7-C extends the world with read-only Source snapshots under [ADR 0084](../../docs/decisions/0084-glass-one-way-interaction.md).
Source bodies enter as at most 96 kinematic mirrors, on their own collision layer; they touch
pieces only. Their transform is controlled exclusively by snapshots. Source never receives any
response, and mirror IDs cannot alias piece IDs. Active mirror bodies are excluded from piece pose
queues/statistics. With interaction off the contact listener is detached. With it on, the listener
ignores piece-piece damage, rejects minimum-size pieces early and records only hard contacts in a
64-entry, per-piece-coalescing atomic queue; workers never allocate or call Lua in contact callbacks.

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
| `SetInteraction` | `(boolean)` -> true; enables contact damage/mirrors, or removes both and clears damage |
| `SyncBodies` | `(rows, sampleDt)` -> number moving/new; each row `{key, position, angles, halfExtents, mass, optionalConvexes, velocity}`; 96 rows, 2 new shapes/snapshot, 8 convexes/512 points per shape |
| `ReadRegions` | `(optionalFocus)` -> at most 32 `{minimum, maximum}` arrays around live glass, prioritizing cells closest to the viewer; no regions when empty |
| `Ray` | `(from, to, energy, kickSpeed)` -> nearest piece id or 0; endpoints must already be Source-clipped |
| `ReadDamage` | `()` -> false when empty, else up to 64 `{pieceId, energy, causeBits}`; drains safely between steps |
| `CanSplit`, `Split` | `(pieceId, minimumSize)` -> boolean / false or two `{id, poly, thickness, position, angles, velocity, spin}` fragments replacing the parent |
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

`Spawn` also accepts an optional sixth minimum-size argument (4–64, default 4). It only affects
follow-up fracture eligibility. `Split` preserves area/thickness, recentres child hulls and inherits
linear plus angular point velocity. Two private staging slots allow rollback of refused replacements;
completed operations never exceed capacity. A full native world refuses splitting until the manager
has evicted its oldest piece. Cause bits are bullet=1, blast=2, Source body=4, fall=8.
`scene_pose` is a read-only C++ test accessor, never exposed to the game Lua API.

New statistics: `interaction`, `scene_bodies`, `scene_moves`, `scene_cooks`, `damage_dropped`,
`ray_hits`, `splits`. Scene masses are clamped to .01–50,000 kg, half extents to .05–1024 units;
snapshots reject duplicate/zero keys, malformed convexes and nonfinite input before mutation.

The R7-C fast-body fix sweeps each mirror's **actual sampled translation**, before the worker is
dispatched. Jolt's CCD deliberately excludes kinematics (`PhysicsSystem.cpp`'s `body.IsDynamic()`
gate); discovery alone can still leave a thin floor piece pinned or tunneled through. Native shape
casts against the glass layers transfer only closing normal velocity to pieces and queue the same
body damage energy as contacts. No predicted pose is used and the mirror still reaches its exact
Source target. Rotation-only changes, motion below 160 units/s and >128-unit teleport corrections
are not swept. Off performs no sweep. Piece-piece collision off still permits mirror interaction.

Per snapshot: at most **16 casts, eight unique hits/cast, 64 body visits and 64 hit callbacks/cast,
and 64 distinct kicked pieces total**; fixed collector/budget buffers introduce no heap buffer. Closing speed
must reach 160 units/s; velocity transfer caps at 2000 units/s. Damage uses the existing minimum-size,
mass and energy gates. Saturation drops cosmetic contacts and increments `scene_sweep_limited`.
`scene_sweeps` and `scene_sweep_hits` count cumulative casts/transfers. These are count limits;
Jolt's bounded shape queries cannot be preempted. No falling solver, sleep, renderer or batching
setting changes. The only added work runs in Source snapshot sync when a mirror translates fast.

After `tools/build.ps1 -Config Release`, the Python glass interaction test feeds real Lua rows to
`out/build/win64-release/glass/native/nl_glass_scene_replay.exe [--off]` through stdin. Input is up
to 120 `frame dt count` records, each followed by `count` numeric rows:
`key x y z pitch yaw roll halfX halfY halfZ mass velX velY velZ` (boxes, <=96 rows).
Exit 0 requires a settled nine-piece fixture, unchanged mirror targets, and movement plus body
damage when enabled; `--off` requires zero movement/damage. No files, installed assets or game are
used. Native tests separately cover 650/3600-unit/s boxes at 60/30 Hz, both glass layers, caps,
minimum-size movement, teleports and disabling. Offline timings are in the R7-C report.

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

G1-B second-pass rendering stays in the owned `debris*.lua` helpers; the native ABI/Jolt settings
are unchanged. The manager groups individual material binds, caches matrices, culls current-view
spheres and consolidates settled material areas with bounded pooled uploads. `NLGlassDebris.Stats()`
adds `think_ms`/`draw_ms` (120-frame means), last/peak hook times, completed/current/average draw
calls, culled pieces and rebuild/upload timings/peaks. Draw timing sums passes per engine frame.
These are client CPU hook costs; `Spawn`/fracture outside Think and GPU time are excluded. See
[the manager fields](../addon/lua/nlglass/debris.lua.md) for sampling/reset details. Existing
sleep tuning remains 0.35 s with a 0.06 m/s point-velocity threshold; rendering optimization does
not force bodies asleep in flight. Game targets remain with Claude.

R8-G: SetCollisionFlags(mask) accepts 0?15 (objects=1, ragdolls=2, living players=4, living NPCs/NextBots=8), default 3. Changes clear mirrors at an idle boundary. SyncBodies row 8 tags one category; omitted tags remain objects for older Lua. Stats adds collision_flags. Native validates tags/masks before mutation and excludes disabled categories; Lua also filters before extraction. The manager always enables map/piece collision.

R8-G Melee(from,to,energy,kickSpeed,radius) casts a 1-16-unit sphere over at most 256 Source units. A fixed collector visits at most 64 bodies/64 hit callbacks and transfers velocity/damage to at most eight distinct pieces. Minimum-size pieces still move; large pieces queue cause bit 16. No Source query/response occurs here: Lua supplies Source-clipped endpoints. Stats adds cumulative melee_hits and melee_limited. Tests include a sleeping pile older than 120 seconds, both movement/fracture paths, bounds, disabling and the actual raw-table binding.

R8-G SpawnGroup(hulls,position,angles,velocity,spin) creates one dynamic rigid body from 2-8 exact original sub-hulls (512 points total, existing per-hull/local bounds). It never fills a geometric gap; the renderer combines the same original triangles. Groups count as one native body but Lua charges their original fragment count to the user's budget. They respond by moving; CanSplit returns false and Split refuses compound shapes before the convex-only path. Fine pieces retain their existing binary fracture. No Jolt sleep/solver/CCD setting changed. Tests cover gap rays, movement, safe split refusal, malformed/budget boundaries and a paired 2000-quad/250-group benchmark.
