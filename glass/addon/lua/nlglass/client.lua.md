# client.lua

Crack strips use the lit VertexLitGeneric shader and a white base texture, without selfillum.
The distinct nlglass_frost_lit name prevents Lua refresh from reusing the former unlit shader.
Geometry remains thin and has outward normals on both pane faces; dark/night Remix QA remains.

Fix pass: prefer an already matching revision instead of building a break's pre-snapshot. A
recovery pre-state is stored without a build; apply the hit then build final meshes/collision once.
Pending weak hits keep geometry; unchanged cells reuse the pane mesh. Native glass retains engine
collision. Stale hit/snapshot revisions are ignored. Initial state uses one InitPostEntity request
(zero-delay only on Lua refresh); nlglass_sync carries a single pane ID, or 0 for initial state.

Each record caches its validated entity, material/color, bounds radius and Matrix. Poses update
only after an entity position/angle change; ordinary frames have no class lookup, Matrix creation
or LocalToWorld. Drawing culls beyond 8,192 units plus radius and wholly behind the eye plane.
NetworkEntityCreated/EntityRemoved maintain attachment caches, including reused-index guards.

Cached pane/crack rendering, collision prediction and debris event replay.

Client-only bootstrap include. Consumes authoritative records/impacts; creates meshes and matching frozen pane collision and updates them on state changes or late network entity creation. Calls only NLGlassDebris Spawn/Impulse/Clear, plays glass sounds and impact effects. Clears meshes/debris on cleanup/shutdown. The debris manager itself belongs to G1-B. No direct disk writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
