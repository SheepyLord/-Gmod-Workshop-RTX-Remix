# fracture.lua

G1-A fix pass: Apply accumulates positive weak hits in `pending`/damage; the crack floor is capped
at 36,000. Cells are immutable live convexes with stable IDs, plus a bounded subdivision tree.
Only the contact neighbourhood is refined. Complete distant subtrees can coarsen to their exact
parent; incomplete groups are pruned after breaks, preserving holes. Remaining/Cracks are cached;
support connectivity runs once only when glass is released. Snapshot returns an immutable view;
Restore accepts cells, pending/retired energy, groups and nextCellID after the original arguments.
Tempered pieces are generated only at shatter; pre-break cracks are small local spiderwebs.
Hull/Clip collapse adjacent vertices closer than 1/256; crack edges omit the pane perimeter.

Pure Lua 5.1 deterministic fracture and support connectivity.

Use dofile/include to obtain New, Apply, Restore, Remaining, Cracks, Hull and geometry helpers. Inputs are validated convex CCW definitions and quantized impacts; outputs are bounded state and piece polygons/local velocity/spin. Apply mutates its state. No GMod globals, global randomness, files or network are used.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
