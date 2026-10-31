# rtx_map_glass.lua

Server autorun for native func_breakable brushes whose VPhysics material is glass. Caches validated
convex geometry, listens for the native break_breakable event and creates independent networked
procedural_shard debris afterward. Native health, collisions, inputs and outputs stay in control.
Damage force and pane velocity affect scatter. Existing shard count and velocity transfer settings
apply. Each piece is handed to `glass_debris.lua` (ADR 0061): it becomes loose physics (collision
group from `rtx_glass_expensive_shards`, motion on), counts in the shared 256-piece oldest-first
budget with every other broken piece, can break again like any shard, and fades out after
`rtx_glass_debris_lifetime` seconds (0: until map cleanup or the budget). The pieces are not welded,
and a piece of any size stays until then; only the fragments of a piece that breaks again become dust
below the dust size. Cleanup cancels queued breaks; dynamic panes and scripted Break inputs are
tracked. Other entities are untouched. No configuration or file writes. GPL-2.0.
