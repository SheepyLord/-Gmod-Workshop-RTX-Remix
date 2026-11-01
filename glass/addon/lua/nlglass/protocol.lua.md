# protocol.lua

The bounded glass snapshot and quantized impact wire format.

The bootstrap includes this module in both realms. WriteRecord/WriteImpact append to a started net message; ReadRecord/ReadImpact consume the matching fields. Records contain definitions and at most eight impacts, not per-piece meshes. A trusted server is the only state writer. Coordinates and directions use a 1/1024 grid.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
