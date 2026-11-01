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

Moving/pending/unbatched pieces draw individually; `debris_batches.lua` retains and incrementally
replaces settled chunks. Think, translucent drawing, cleanup and shutdown hooks own the lifecycle.
Only cleanup/shutdown joins an in-flight step. No server/network traffic or file writes except the
engine's ordinary archived convar persistence. No exit code; malformed fragments are ignored.
