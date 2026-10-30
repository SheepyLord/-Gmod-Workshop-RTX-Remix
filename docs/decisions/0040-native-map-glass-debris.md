# 0040: Persistent debris for native map glass

- Status: Accepted 2026-10-30, implementing the user's request: "Fix glass effect on map glasses."
  The reported failure was Modern House windows disappearing without scattered glass.
- Scope: the bundled GPL-2.0 Glass-Rewrite-Remix input in `packages/fixes`; no native loader or
  runtime binary changes, and no change to the map or Modern House's separate Workshop package.

## Decision

Keep native `func_breakable` panes intact until the engine actually breaks them. Cache the convex
VPhysics geometry of brushes whose physical material is `glass`, then listen to the engine's
`break_breakable` event. Native health, damage filters, collisions, inputs and `OnBreak` outputs
remain authoritative. Non-glass breakables, props and ordinary entity removals do not create debris.

The existing code only replaced `func_breakable_surf`. Modern House instead has 52
`func_breakable` entities; 44 expose glass VPhysics meshes. That class mismatch caused the missing
procedural debris. The new handler also tracks dynamic panes and scripted `Break` inputs.

Split the cached convexes into closed fragments in the pane's own plane, including horizontal and
rotated panes. Spawn independent `procedural_shard` entities, with valid VPhysics, the addon's
existing glass material and networked render meshes. They inherit the pane's motion and the
damage impulse. Existing shard count, velocity transfer and collision settings apply.

Map fragments do not use the old particle-only tiny-shard path, recursive splitting or welds.
They persist until map cleanup or eviction by a 256-piece oldest-first map-debris budget. There is
no age-based disappearance. Cleanup invalidates queued fractures and rebuilds the brush cache.

Full shard updates are batched below 60,000 bytes so a joining/resyncing client can receive a large
pile. The message layout is unchanged. Client render bounds are rebuilt from the actual received
vertices. Invalid or individually oversized mesh updates are refused rather than overflowing a packet.

## Validation and delivery

Generated LuaJIT fixtures execute the actual geometry, map lifecycle and packet writer: closed-hull
volume, arbitrary pane orientation, duplicate events, non-glass entities, removal, cleanup, budget
and bounded full updates. The real Modern House PoC session compares the old zero-shard behavior
with the fix, then checks RTX rendering, native output delivery, scripted breaks, resync and cleanup.

The main RTX Workshop item carries the fix. Update `packages/fixes/files.json` only through
`tools/inputs.py import`; test the package on the branch before merging into the publishing `main`.
