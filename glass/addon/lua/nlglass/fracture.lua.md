# fracture.lua

Pure Lua 5.1 deterministic fracture and support connectivity.

Use dofile/include to obtain New, Apply, Restore, Remaining, Cracks, Hull and geometry helpers. Inputs are validated convex CCW definitions and quantized impacts; outputs are bounded state and piece polygons/local velocity/spin. Apply mutates its state. No GMod globals, global randomness, files or network are used.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
