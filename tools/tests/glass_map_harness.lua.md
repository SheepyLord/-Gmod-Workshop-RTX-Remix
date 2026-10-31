# glass_map_harness.lua

LuaJIT assertions for the shipped glass brush geometry, native-break integration and packet writer.
Run through test_glass_map.py. Generated thin, horizontal and rotated boxes exercise fracture count,
closed hull volume and invalid geometry. Engine stubs cover native event ordering, duplicate events,
non-glass entities, ordinary removal, cleanup, persistent independent pieces and the debris budget.

The actual network writer gets a generated late-join pile of 256 shards (about 920 KB): the request
handler writes nothing, then each `Tick` sends at most one full-update batch of at most 16,000 bytes
per player until every valid shard was delivered, with two joiners getting one batch each per tick.
Empty requests repeated during a resync or within 30 seconds of the last one are ignored; one after
that is served. Single-shard requests are answered on the tick, a repeated shard once, invalid or
empty shards never, and at most 16,000 bytes (16 answers) per player per tick; a disconnected
player's queue is dropped. No game is launched.
