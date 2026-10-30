# networking.lua

Shared shard mesh, crack and collision messages. The server answers individual shard requests and
full resyncs with 16-bit entity/vertex counts and three floats per vertex. Full updates are batched
below 60,000 bytes; invalid or individually oversized meshes are not sent. The client rebuilds its
render mesh and bounds from the received triangles. Uses session hooks and net messages, with no
file writes. Existing messages remain wire-compatible. GPL-2.0.
