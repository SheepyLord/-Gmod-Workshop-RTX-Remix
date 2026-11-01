# debris_detail.lua

MIT pure numeric client planning helper. `Pack(fragments, first, last, coarse, localEye)` validates
bounded positive-area polygon metadata and returns ordered groups referencing every retained input
once. Does not modify any polygon or authoritative pane state, build geometry, read engine objects,
send messages or write files. Geometry validation still runs before any mesh/native allocation.

When crowded, fragments whose bounds lie fully beyond 256 units of the viewer may share one rigid
transform. Groups stay in a 32-unit pane-local cell, contain at most eight fragments/512 hull points,
and only include fragments whose width/height are at most 64. Thickness must match. All original
polygons/sub-hulls remain intact, including disjoint outlines and holes. Nearby and large fragments
remain separate. Groups respond to subsequent damage by moving; fine pieces retain binary fracture.
No exit code or side effects; invalid metadata is omitted.
