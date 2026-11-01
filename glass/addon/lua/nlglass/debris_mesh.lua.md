# debris_mesh.lua

Pure client helper included by `debris.lua`. `Geometry(poly, thickness, color)` validates a finite,
convex counter-clockwise polygon, centres it, and returns an extruded hull, both-face/edge triangles,
pane-space UVs and glass mass. `Build` owns one engine mesh, `Transformed` appends world-space
triangles to a settled batch, and `Draw` uses a reusable matrix/vector for position, rotation and
expiry scale. Meshes are destroyed by their owning manager or on failed construction.
No files, networking, entities, timers or hooks; invalid geometry returns nil, mesh failures throw
to the manager's protected construction call. No process exit code.
