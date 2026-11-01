# server.lua

Authoritative pane registry, map glass adapters, network state and admin settings.

Server-only bootstrap include. Registers damage/input/entity/map/cleanup/join hooks and network handlers. Inputs are engine callbacks and validated definitions; outputs are compact impacts, bounded state, blasts and removals. Builds frozen remaining-cell collision, hides original surface brushes as output bridges, and removes fully broken panes. Native glass remains engine-owned. No per-tick pane polling, per-piece server entities or direct filesystem writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
