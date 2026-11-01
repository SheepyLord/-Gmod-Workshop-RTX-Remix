# debris_draw.lua

Client-only helper included by `debris.lua`. `Add(piece)`/`Remove(piece)` maintain only individual
(moving, pending, shrinking or temporarily unmerged) pieces in material groups. Merged pieces
leave the groups, so stable piles are never scanned by this renderer. Tint/alpha remain vertex
colors and do not split material groups. `Draw(view)` binds once per visible material group,
rejects hidden/distant/subpixel spheres before touching their matrices, and returns draw/culled
piece counts. `debris_mesh.Draw` lazily updates cached transforms/scales. No per-piece temporary
Vector, Angle, Matrix or table is allocated by drawing. No files, networking, hooks or exit code.
