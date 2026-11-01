# debris_mesh.lua

Pure client helper included by `debris.lua`. `Geometry(poly, thickness, color)` validates a finite,
convex counter-clockwise polygon, centres it, and returns an extruded hull, both-face/edge triangles,
pane-space UVs, a bounding radius and glass mass. `Build` owns one engine mesh. `Transformed(piece,
out, pool)` appends world-space triangles using one Source pitch/yaw/roll basis per piece and
reuses the supplied pool's vertex tables/position/normal vectors. No `LocalToWorld`/temporary
Angle is needed per vertex. Engine upload copies these records before they are reused.
`Draw` changes its cached matrix translation/rotation only when `piece.poseDirty` is set, and
scale only when the shrink factor changes. Culled pieces defer updates until visible again.
Meshes are destroyed by their owning manager or on failed construction.
No files, networking, entities, timers or hooks; invalid geometry returns nil, mesh failures throw
to the manager's protected construction call. No process exit code.

R8-G Geometry also returns exact area. Group(fragments,color) builds the same original triangles and sub-hulls, recentered around their combined mass centroid; returns vertices/hulls/center/radius/mass/area for one rigid group. Does not fill gaps or change source polygons. Each original colour/UV/thickness/normal is retained. The manager averages the group's initial velocities/spins; later motion shares a transform.
