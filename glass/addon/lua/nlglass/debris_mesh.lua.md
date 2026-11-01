# debris_mesh.lua

Pure client helper included by `debris.lua`. `Geometry(poly, thickness, color)` validates a finite,
convex counter-clockwise polygon, centres it, and returns an extruded hull, both-face/edge triangles,
pane-space UVs, a bounding radius and glass mass. `Build` owns one engine mesh. `Transformed(piece,
out, pool)` appends world-space triangles using one Source pitch/yaw/roll basis per piece and
reuses the supplied pool's vertex tables/position/normal vectors. No `LocalToWorld`/temporary
Angle is needed per vertex. Engine upload copies these records before they are reused.
`Draw` uses a reusable matrix/vector for position, rotation and
expiry scale. Meshes are destroyed by their owning manager or on failed construction.
No files, networking, entities, timers or hooks; invalid geometry returns nil, mesh failures throw
to the manager's protected construction call. No process exit code.
