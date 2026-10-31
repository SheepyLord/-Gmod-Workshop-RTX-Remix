# networking.lua

Shared shard mesh, crack and collision messages. The server answers individual shard requests and
full resyncs with 16-bit entity/vertex counts and three floats per vertex. Full updates are batched
below 60,000 bytes; invalid or individually oversized meshes are not sent. The client rebuilds its
render mesh and bounds from the received triangles. Uses session hooks and net messages, with no
file writes. Existing messages remain wire-compatible. GPL-2.0.
The client builds a shard's new mesh before it replaces the old one, and destroys replaced meshes eight frames later (GlassRewriteRetireMesh), since a queued frame may still draw them with mat_queue_mode 2 (review R4, 2026-10-31).
