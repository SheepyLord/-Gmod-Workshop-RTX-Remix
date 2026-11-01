# debris.lua

Client module included by G1-A's client initializer. Defines `NLGlassDebris` with the agreed API:

- `Spawn(frame, pieces)`: frame origin/angles/material/optional color, convex CCW pane-local
  polygons, thickness, world velocity and spin (degrees/s); newest fragments within budget survive.
- `Prepare()`: starts background map preparation ahead of the first break. Pieces arriving during
  preparation or a worker step stay drawn at their last known pose, bounded by the player budget.
- `Impulse(origin, radius, speed)`: radial velocity kick; wakes and unbatches affected pieces.
- `Ray(from, to, damage)`: validated server pellet trace; queues at most 32 for 0.5 s and applies
  at most eight/frame, only with native interaction available and the local setting enabled.
- `Clear`, `Count`, `Backend` (`jolt`, `vphysics`, `none`); cleanup keeps the imported map.
- `Stats`: reused QA counts and native statistics. Adds `worker_busy`, `pose_updates` and
  `rebuild_vertices`, `rebuild_ms`, `upload_ms`, `rebuild_pool_vertices` and `retiring_meshes`
  (copy values if retaining a sample). Upload timing measures the engine call on the client.
  `rebuild_peak_ms`/`upload_peak_ms` retain the worst frame/call until `Clear`.
- `Shutdown`: releases all resources; also called before re-inclusion.

Creates archived per-player client convars: `rtx_glass_debris_lifetime` (120 seconds, 0 until
cleanup), `rtx_glass_debris_budget` (2000, 0-8192), `rtx_glass_debris_collide` (1). The native body
capacity is 8192 once per map; scratch is lazy and sized to live/observed demand, not reserved at
Init. Budget changes never reread a BSP. Missing/failed native worlds use at most 64 Source pieces.
A runtime failure migrates the newest surviving pieces at their last published poses.

Think polls a single in-flight native step, applies queued removals/impulses and up to 128 pending
spawns, consumes only changed pose IDs, then starts the next step without waiting. Sleeping worlds
need no step dispatch. Pending mutations never touch a worker-owned world. Up to 64 impulse events
are queued; overload retains the newest. The pose/native-ID maps handle evictions and stale poses
without reusing identities. Lifetime work visits the final-second birth cohort, with a cursor reset
when settings change; expiry shrinks the transform without changing alpha. Oldest pieces go first.

Moving/pending/unbatched pieces draw through `debris_draw.lua`: one material bind per group,
cached matrices updated only after pose/scale changes, no per-piece draw allocations. Both
individuals and areas use `debris_view.lua`'s current-camera culling. Physics continues while hidden.
The 8192-unit rendering distance and subpixel rejection (0.75-pixel radius beyond 256 units) bound
distant cosmetic detail. `debris_batches.lua` retains and incrementally replaces settled chunks.
Think, translucent drawing, cleanup and shutdown hooks own the lifecycle.
Only cleanup/shutdown joins an in-flight step. No server/network traffic or file writes except the
engine's ordinary archived convar persistence. No exit code; malformed fragments are ignored.

Timing fields are milliseconds: `think_ms` and `draw_ms` average the last 120 sampled frames
(or fewer initially); `think_last_ms`/`draw_last_ms` are the latest samples, and
`think_peak_ms`/`draw_peak_ms` are maxima since `Clear`. Draw sampling sums every eligible
translucent pass with the same `FrameNumber`; depth/sky passes are ignored. The completed draw
frame publishes on the next frame. `draw_calls` is that completed frame's calls,
`draw_calls_avg` is the rolling mean, `draw_calls_current` is the current frame's running count,
and `culled_pieces` its running skipped-piece count. `think_samples`/`draw_samples` cap at 120.
Timings cover only the manager hooks (including its rebuild/upload work), not fracture/network
handlers or GPU time; `Spawn` outside Think is not included. Counters use reused numeric rings.

R7-C adds archived per-player `rtx_glass_debris_interact` (default 1). Native capability detection
lets older modules retain G1 behaviour. At idle worker boundaries, the setting enables/disables
mirrors/contact damage, drains bounded ray/damage queues and captures Source through `debris_scene`.
Coalesce at most 64 damage records; replace at most one convex parent with two fragments/frame,
stopping stale work after 0.75 ms. Mesh/cooking calls are indivisible. Minimum size comes from the
original pane's `minimum_size` metadata, or the current setting for other API callers. The oldest remaining
piece is evicted if the extra child needs budget. Minimum-size/one-piece-budget refusals keep motion.
`debris_expiry` retains original expiration across generations without scanning normal settled glass.
Off clears mirrors/interaction queues while keeping G1 blast push, life, budgets, collision and draws.

Statistics add `interaction`, `interaction_available`, `scene_bodies`, `scene_candidates`,
`scene_queries`, `capture_ms`, `capture_peak_ms`, `scene_cooks`, `split_ms`, `split_peak_ms`, `splits`, `splits_bullet`, `splits_blast`,
`splits_body`, `splits_fall`, `damage_pending`, `ray_pending`, `damage_dropped`, `rays_dropped`.
Capture includes native snapshot/cooking time; split includes bounded mesh builds. Native stats
provide cumulative ray hits, splits and dropped contact events. Clear resets manager counters.

The fast-body fix adds `scene_examined`, `scene_fast_candidates`, `scene_fast_bodies`,
`scene_fast_boxes` and `scene_peak_bodies` from `debris_scene`. They preserve evidence after a fast
prop leaves the pile; current `scene_bodies` can already be zero at the screenshot. Native
`scene_sweeps`, `scene_sweep_hits` and `scene_sweep_limited` are cumulative for the world and must
be compared before/after. Think/step dispatch, falling-piece draws and batching are unchanged.

R8-G always enables map/piece collision and reads the archived Source collision mask from debris_settings.lua. At idle worker boundaries it updates optional SetCollisionFlags and passes the mask to scene capture. Stats adds collision_flags. The interaction master stays independent.

R8-G Ray(from,to,damage,radius=0) shares the 32-entry/0.5-second/eight-casts-per-frame queue for bullets and melee. Radius 1-16 uses optional native Melee, with a 256-unit range cap; old modules fall back to a line kick. Idle boundaries renew actual local interest, including fully sleeping scenes. Splits add cause bit 16 (melee).

R8-G replaces synchronous receipt with a FIFO construction queue. Receipt plans numeric descriptors only; Think creates at most 12 meshes/bodies and 8192 vertices per frame, yielding after 0.75 ms (a single geometry/upload/cook cannot be preempted). Never enters an in-flight world. Pending descriptors share the configured fragment budget with live glass; oldest-first eviction counts every original fragment inside a rigid group, so grouping cannot multiply the geometry budget. Group eviction may underfill by at most seven fragments. Count includes planned bodies; Stats.live counts built bodies, fragments counts their retained original fragments, creation_pending/creation_fragments describe the queue. created_last/creation_ms/creation_peak_ms/creation_peak_pending and grouped_fragments expose work and pressure.

A decaying demand counter (256 fragments/s, threshold 192) or >256 moving bodies permits distant detail grouping when SpawnGroup is available. debris_detail.lua keeps every original polygon/hull and protects bounds within 256 units of the eye. Groups share one mesh/rigid transform, at most eight fragments/512 hull points in a 32-unit cell; large fragments remain separate. Groups move on further hits instead of splitting. Fine pieces retain R7 fracture. No authoritative pane density/outline/hole changes, and no forced sleeps or solver changes.

Constructed pieces retain receipt time via inherited expiry; expired queued work creates nothing. A 64-event numeric blast history applies at most eight relevant later kicks at construction, without per-queued-fragment work in the blast callback. Cleanup cancels descriptors/history and frees built meshes. Missing modules keep the conservative 64-fragment fallback and disable new grouping. Settled meshes still use the existing batching path.

Near-detail protection uses the last actual render-camera snapshot, falling back to EyePos before one is available. A third-person/scripted camera near glass therefore retains individual pieces even when the player eye is farther away.

Budget receipt also retires erased individual meshes instead of synchronously releasing hundreds of GPU objects. Think drains at most 16/frame through debris_draw.lua; Stats adds retired_individual/released_individual. Cleanup joins/frees everything as before. Native removals remain immediate/at the worker boundary so invisible old collision bodies cannot intercept later hits.
