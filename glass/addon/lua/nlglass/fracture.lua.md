# fracture.lua

G1 integration (the user, 2026-11-01: breaks were always an octagon): a new hit takes 6–10 rays by
its seed (two more per 120,000 energy, at most 16), splits the turn at seeded gap weights 7–13 (the
widest wedge stays under 100 degrees, so tiles stay convex and the outer ring covers the pane) and
gives every ray its own inner ring radii, 0.8–1.2 of the ring's (consecutive radii grow at least
1.55 times, so a ray's rings stay ordered). A break also releases about a third of the next ring's
cells (seeded by cell ID) that are small (at most 2.5 piece sizes squared) and do not lie along the
frame: a ragged hole edge. All of it is integer-seeded, identical on server and clients.

Second pass: CellLimit caps live annealed topology at 200 and tempered shatter at 300 (also
bounded by the 512-cell wire ceiling). Complete distant groups coarsen before refinement can
exceed the kind's cap. Radial cuts retain their small inner rings and stretch the final far ring
when necessary to fit the budget. Tempered uses an evenly divided grid with a bounded integer
row/column product, including thin/huge outlines. Break radius queries generate radii only,
without allocating unused tile polygons. See ADR 0076 and the README's measured counts.

G1-A fix pass: Apply accumulates positive weak hits in `pending`/damage; the crack floor is capped
at 36,000. Cells are immutable live convexes with stable IDs, plus a bounded subdivision tree.
Only the contact neighbourhood is refined. Complete distant subtrees can coarsen to their exact
parent; incomplete groups are pruned after breaks, preserving holes. Remaining/Cracks are cached;
support connectivity runs once only when glass is released. Snapshot returns an immutable view;
Restore accepts cells, pending/retired energy, groups and nextCellID after the original arguments.
Tempered pieces are generated only at shatter; pre-break cracks are small local spiderwebs.
Hull/Clip collapse adjacent vertices closer than 1/256; crack edges omit the pane perimeter.
Remaining/Cracks/Snapshot arrays are read-only to callers. Repeated hits preserve the cell array
identity so clients can reuse pane meshes. If dense cuts on a still-intact engine-owned pane
cannot coarsen enough, simplify its visual topology and refine the actual latest contact; native
health never causes an early cosmetic shatter.

Pure Lua 5.1 deterministic fracture and support connectivity.

Use dofile/include to obtain New, Apply, Restore, Remaining, Cracks, Hull and geometry helpers. Inputs are validated convex CCW definitions and quantized impacts; outputs are bounded state and piece polygons/local velocity/spin. Apply mutates its state. No GMod globals, global randomness, files or network are used.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.


R9-G: annealed rings start at max(0.75, 0.14*piece_size), branch into tapered triangles and grow
more rapidly outside the crushed core. Tempered shatter recursively cuts oblique convex cells with
seeded shared intersections and greater density near the impact. No uniform grid remains. The
200/300 live and 512 wire bounds remain. A visual-only cut at capacity can simplify intact glass;
it never refills a real hole or releases glass before the energy threshold. Follow-up local Jolt
fracture has an independent one-unit area floor; initial spacing remains a pane setting.

R9 review (Claude): each tempered cut now crosses the cell's longest extent, chosen from six seeded
directions by a linear scan, at 40-60 % across. With purely random directions, cuts often ran along
a long side and left full-length slivers and seams. The granules are now compact and irregular,
like tempered glass dicing. Counts, areas, limits and determinism are unchanged.
