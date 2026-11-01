# shared.lua

Pane entity metadata, spawn function and transmit policy.

Included by server/client entity entry points. Describes one convex pane, creates a pane at a hit surface for sandbox spawning and requests always-transmit state. The default follows spawned-kind settings; inherited presets offer explicit kinds/sizes. No direct disk/network writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
