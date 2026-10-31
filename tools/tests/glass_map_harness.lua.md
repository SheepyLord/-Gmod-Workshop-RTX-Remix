# glass_map_harness.lua

LuaJIT assertions for the shipped glass brush geometry, native-break integration, loose broken glass
and packet writer. Run through test_glass_map.py, which passes the add-on folder and plain-Lua copies
of `networking.lua`, `procedural_shard.lua` and `world_functions.lua` (`luajit glass_map_harness.lua
<addon> <networking> <procedural_shard> <world_functions>`). Generated thin, horizontal and rotated
boxes exercise fracture count, closed hull volume and invalid geometry. Engine stubs cover native event
ordering, duplicate events, non-glass entities, ordinary removal, cleanup, independent moving pieces in
`COLLISION_GROUP_WEAPON` and the debris budget, with the real map controller and debris registry
(`glass_debris.lua`; the harness runs without it for a comparison with older code).

The actual network writer gets a generated late-join pile of 256 shards (about 920 KB): the request
handler writes nothing, then each `Tick` sends at most one full-update batch of at most 16,000 bytes
per player until every valid shard was delivered, with two joiners getting one batch each per tick.
Empty requests repeated during a resync or within 30 seconds of the last one are ignored; one after
that is served. Single-shard requests are answered on the tick, a repeated shard once, invalid or
empty shards never, and at most 16,000 bytes (16 answers) per player per tick; a disconnected
player's queue is dropped.

Loose broken glass (ADR 0061) runs the real entity: `procedural_shard.lua` in the server realm
(`BuildCollision`, `Split`, `OnTakeDamage`, `PhysicsCollide`, `FadeOut`, `OnRemove`) and in the client
realm (`Draw`), with `world_functions.lua`, the registry and the map controller, over a mocked entity
system, convars and timers that run at their due time on a mocked clock. The VPhysics mock builds the
convex hull of the points the entity passes, so a fragment's mesh and bounding radius come from the
shipped geometry. Each scenario starts on a clean map and is reported on its own, so a run against
older code lists every one that fails:

- map window debris: every piece moves, is in `COLLISION_GROUP_WEAPON` (`COLLISION_GROUP_DEBRIS`
  with `rtx_glass_expensive_shards 0`), is not welded, is counted, and a bullet pushes it;
- the add-on's own pane: frozen and solid until it breaks, then a frozen hidden placeholder; its
  fragments are loose physics, counted, none below the dust size becomes an entity, dust is shown;
- recursive fracture: a big window's debris shot round after round breaks two or more generations
  deep until nothing is left but dust, and no placeholder remains;
- the budget: 15 broken windows keep 256 pieces, the oldest gone; fragments of a broken piece count,
  and room for them is made by removing the oldest piece;
- hard impacts: a landing at 450 units/s leaves a piece whole, a hit by another loose piece never
  breaks it, 700 units/s does;
- the lifetime: `rtx_glass_debris_lifetime` is archived and replicated, default 120; pieces fade
  within a second of their lifetime, a fading piece is pushed but never breaks, it is gone a second
  later, younger fragments keep their own lifetime, and the original goes with its last fragment;
- lifetime 0: one sparse sweep timer, pieces stay an hour, and a new lifetime applies to them;
- the client: an expired piece shrinks from full size to nothing over one second by its transform,
  and no mesh is built or freed.

No game is launched.
