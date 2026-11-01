# config.lua

Creates the same replicated gameplay convars in both realms, so a remote client can receive and
read the server's values. These remain server/admin settings; debris controls belong to G1-B.

Shared glass setting names, defaults and bounds.

Included by the bootstrap in both realms. Creates eight archived replicated gameplay convars in
each realm; returns Settings, Debris and read helpers. G1-B owns creation of the three client debris
convars. No direct file writes or debris calls.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
