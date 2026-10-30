# rtx_map_glass.lua

Server autorun for native func_breakable brushes whose VPhysics material is glass. Caches validated
convex geometry, listens for the native break_breakable event and creates independent networked
procedural_shard debris afterward. Native health, collisions, inputs and outputs stay in control.
Damage force and pane velocity affect scatter. Existing shard count, velocity transfer and collision
settings apply. Debris remains until map cleanup or eviction by the 256-piece oldest-first budget.
Cleanup cancels queued breaks; dynamic panes and scripted Break inputs are tracked. Other entities
are untouched. No configuration or file writes. GPL-2.0.
