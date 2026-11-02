# debris_draw.lua

Client-only helper included by `debris.lua`. `Add(piece)`/`Remove(piece)` maintain only individual
(moving, pending, shrinking or temporarily unmerged) pieces in material groups. Merged pieces
leave the groups, so stable piles are never scanned by this renderer. Tint/alpha remain vertex
colors and do not split material groups. `Draw(view)` binds once per visible material group,
rejects hidden/distant/subpixel spheres before touching their matrices, and returns draw/culled
piece counts. `debris_mesh.Draw` lazily updates cached transforms/scales. No per-piece temporary
Vector, Angle, Matrix or table is allocated by drawing. No files, networking, hooks or exit code.

R8-G also owns a deferred individual-mesh retirement queue. Erasure removes a piece from drawing immediately; Tick destroys at most 16 retired meshes/frame. This exceeds the maximum 12 initial creations plus two split children, so sustained replacement cannot grow the queue without bound. The burst is limited by the existing 8192-body/fragment budget, with at most one creation-frame overshoot in resource ownership. ClearRetired frees all remaining resources at cleanup/shutdown. Empty ticks allocate no table. This is a count limit, not a renderer wall-time guarantee.


R9-G also retires transient preview meshes through this queue. Secondary construction can produce
up to six children in a frame; previews use shared meshes. The 16-release per-frame bound remains.

R9-G embeds Audio, with archived rtx_glass_debris_sounds=1. Drain(api) consumes a fixed native
event buffer at an idle boundary; sounds are culled past 1536 units, limited to four/frame,
24/s (burst 24), and one/0.12 s/piece. Native impact speed/mass select soft/hard stock glass
sounds and bounded volume. Splits and water entries use small break/splash sounds. Clear resets
counters/rate state. No files, network or Source-physics writes; old modules remain silent.
