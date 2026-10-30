# glass_map_geometry.lua

Server helper for map-glass debris. `include` returns Bounds, Volume, Copy, Clip and Fracture.
Copies validated convex physics triangles, clips them into closed fragments and caps every cut.
Fractures use the pane's plane, so vertical, horizontal and rotated windows work. Shapes are bounded
to 1,800 vertices and 24 fragments. Has no hooks, entities, networking or file writes. GPL-2.0.
