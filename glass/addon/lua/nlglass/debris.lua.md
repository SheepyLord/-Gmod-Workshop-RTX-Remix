# debris.lua

Client module included by G1-A's client initializer. Defines `NLGlassDebris` with the agreed API:

- `Spawn(frame, pieces)`: frame origin/angles/material/optional color, convex CCW pane-local
  polygons, thickness, world velocity and world spin (degrees/s); keeps the newest within budget.
- `Prepare()`: starts the map import ahead of the first break (G1-A's client calls it when it learns
  of a pane, so the world is usually ready before anything breaks). Pieces that arrive while the import
  still runs are drawn where they broke off until physics takes them.
- `Impulse(origin, radius, speed)`: radial, linearly attenuated velocity kick; wakes and unbatches.
- `Clear()`, `Count()`, `Backend()` (`jolt`, `vphysics`, `none`). Cleanup keeps map collision cached.
- `Stats()` is a QA extension returning a reused table with live/moving/sleeping/pending/merged counts,
  batch and rebuild counts, skipped model count and reused native statistics. Copy it to retain a sample.
- `Shutdown()` releases the world, used on client shutdown or re-inclusion of this module.

Creates archived per-player client convars: `rtx_glass_debris_lifetime` (120 seconds, 0 until cleanup),
`rtx_glass_debris_budget` (2000, 0-8192) and `rtx_glass_debris_collide` (1). Reserves the native hard
capacity of 8192 once per map so budget changes never reread the BSP. Pending pieces are bounded by
the current budget; map-import failure switches to a 64-piece Source fallback. A runtime failure
migrates the newest surviving pieces at their last pose. No native restart loop occurs after failure.

Moving pieces use individual meshes; sleeping pieces batch by 256-unit XYZ area, material and color,
with at most 60000 vertices per mesh. Changed areas immediately invalidate old geometry, debounce
100 ms and rebuild at most two areas/frame. Waking, removal and shrinking unbatch pieces immediately.
Lifetime uses game time; the last second scales the transform without changing alpha. Oldest pieces
go first over budget. `Think`, `PostDrawTranslucentRenderables`, `PreCleanupMap` and `ShutDown` hooks
own stepping, drawing and cleanup. No server/network traffic or disk writes except the engine's
ordinary archived client-convar persistence. No process exit code; malformed pieces are ignored.
