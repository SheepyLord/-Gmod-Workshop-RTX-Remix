# cl_init.lua

Client entity entry point suppressing the placeholder model.

Includes shared metadata. Empty Draw/DrawTranslucent leave the client global renderer to draw the authoritative geometry. No side effects beyond entity method definitions; no filesystem or network writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
