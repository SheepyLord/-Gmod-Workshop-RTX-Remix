# debris.lua

Client module included by G1-A's client initializer. Defines `NLGlassDebris` with the agreed API:

- `Spawn(frame, pieces)`: frame origin/angles/material/optional color, convex CCW pane-local
  polygons, thickness, world velocity and spin (degrees/s); newest fragments within budget survive.
- `Prepare()`: starts background map preparation ahead of the first break. Pieces arriving during
  preparation or a worker step stay drawn at their last known pose, bounded by the player budget.
- `Impulse(origin, radius, speed)`: radial velocity kick; wakes and unbatches affected pieces.
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
