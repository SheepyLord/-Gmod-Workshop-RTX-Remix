# procedural_shard.lua

Shared procedural glass entity: convex VPhysics, networked mesh, crack drawing and damage/impact
splitting. Its original spawn/tool glass behavior remains. Native-map debris sets RTX_MAP_DEBRIS
before Spawn: it remains a persistent independent piece, without recursive fracture or parent-shard
cleanup. Client mesh removal tolerates a not-yet-created mesh. No configuration files are written;
existing glass convars are used. GPL-2.0.
The client draws a shard's mesh itself in ENT:Draw (the entity's material override and colour apply). DrawModel with GetRenderMesh rendered it through studiorender, which crashed on the material system's render thread with mat_queue_mode 2 as soon as a shard was drawn in an RTX session (review R4, 2026-10-31). Meshes that may still be queued for drawing (replaced render meshes, crack meshes, those of removed shards) are retired through networking.lua and destroyed eight frames later.
