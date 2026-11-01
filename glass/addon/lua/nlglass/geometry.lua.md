# geometry.lua

Engine frame, outline, collision-point and render-triangle helpers.

Included after Fracture. ValidDefinition rejects invalid shape/settings data and canonicalizes valid convex outlines; FromEntity reads brush surfaces and physics convexes, returning a pane frame, convex outline and thickness. Convexes and Triangles return extruded geometry. Helpers do not create entities or physics objects, or change the input entity.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
