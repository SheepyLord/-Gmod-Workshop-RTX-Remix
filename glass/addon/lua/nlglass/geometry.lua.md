# geometry.lua

PaneGeometry returns render triangles and collision convexes from one extrusion, sharing the
two positions per outline vertex. Triangles optionally fills a supplied convex list and reuses
face/side vertex records across triangles. Outputs are read-only. Standalone Convexes remains
available for server-only and late-attachment collision without unnecessary render geometry.

Engine frame, outline, collision-point and render-triangle helpers.

Included after Fracture. ValidDefinition rejects invalid shape/settings data and canonicalizes valid convex outlines; FromEntity reads brush surfaces and physics convexes, returning a pane frame, convex outline and thickness. Convexes and Triangles return extruded geometry. Helpers do not create entities or physics objects, or change the input entity.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
