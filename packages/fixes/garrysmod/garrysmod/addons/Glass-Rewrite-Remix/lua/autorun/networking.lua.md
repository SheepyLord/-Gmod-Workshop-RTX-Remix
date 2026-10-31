# networking.lua

Shared shard mesh, crack and collision messages. The server answers individual shard requests and
full resyncs with 16-bit entity/vertex counts and three floats per vertex; invalid or individually
oversized meshes (60,000 bytes and more) are not sent. The client rebuilds its render mesh and bounds
from the received triangles. Uses session hooks and net messages, with no file writes. Existing
messages remain wire-compatible. GPL-2.0.
The client builds a shard's new mesh before it replaces the old one, and destroys replaced meshes eight frames later (GlassRewriteRetireMesh), since a queued frame may still draw them with mat_queue_mode 2 (review R4, 2026-10-31).

Answers are queued per player and paced by a `Tick` hook (review R4, 2026-10-31): writing a late
joiner's whole pile inside one `net.Receive` could overflow its reliable buffer, and any client could
make the server serialize every shard by repeating the empty request. Each tick a player gets about
16,000 bytes: its queued single shards first (at least one, at most 16), otherwise one full-update
batch of its resync. A full resync (the empty request a client sends after joining) is granted once
per 30 seconds per player (`CurTime`); repeats meanwhile, and while one is being sent, are ignored. A
shard already queued for a player is not queued again. A player's queue goes when the player leaves
(`PlayerDisconnected`, or invalid at the next tick).
