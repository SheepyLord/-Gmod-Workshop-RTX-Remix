# protocol.lua

Snapshots now include bounded live pane cells and their complete subdivision groups, stable IDs,
pending weak energy and the ID counter. Shared vertices are encoded once at 1/1024 precision.
This topology is needed to resume local refinement/coarsening exactly after join/resync; restoring
it does no fracture replay. Ordinary hit payloads remain compact. No live debris/pose stream is sent.
The 501-cell generated probe's snapshot is 16,721 bytes, below GMod's message limit.

The bounded glass snapshot and quantized impact wire format.

The bootstrap includes this module in both realms. WriteRecord/WriteImpact append to a started net message; ReadRecord/ReadImpact consume the matching fields. Records contain definitions and at most eight impacts, not per-piece meshes. A trusted server is the only state writer. Coordinates and directions use a 1/1024 grid.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
