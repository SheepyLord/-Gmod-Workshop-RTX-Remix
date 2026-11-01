# config.lua

Creates the same replicated gameplay convars in both realms, so a remote client can receive and
read the server's values. These remain server/admin settings; debris controls belong to G1-B.

Shared glass setting names, defaults and bounds.

Included by the bootstrap in both realms. On the server creates eight archived replicated gameplay convars; returns Settings, Debris and read helpers. G1-B owns creation of the three client debris convars. No file writes or debris calls.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
