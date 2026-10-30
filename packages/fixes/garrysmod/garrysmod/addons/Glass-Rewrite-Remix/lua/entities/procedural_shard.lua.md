# procedural_shard.lua

Shared procedural glass entity: convex VPhysics, networked mesh, crack drawing and damage/impact
splitting. Its original spawn/tool glass behavior remains. Native-map debris sets RTX_MAP_DEBRIS
before Spawn: it remains a persistent independent piece, without recursive fracture or parent-shard
cleanup. Client mesh removal tolerates a not-yet-created mesh. No configuration files are written;
existing glass convars are used. GPL-2.0.
