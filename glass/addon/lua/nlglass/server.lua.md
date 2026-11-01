# server.lua

Player contact also uses a pre-movement hull trace in SetupMove, with incoming movement velocity;
this includes GetBaseVelocity (the QA SetVelocity push), just as the engine's mover does.
Idle panes have no polling. All hits record the native pane's last impact before crack filtering.
Deduplicated blast messages are deferred until after synchronous pane break messages.

The blast deferral also waits for one-turn native-removal/physics breaks, then sends the impulse.
Client readiness is the only initial push. nlglass_sync reads a uint32 pane ID (0 = initial list),
deduplicates per ID and permits at most 16 different requests in two seconds. A targeted request
sends only that snapshot, or removal for an absent ID. There is no PlayerInitialSpawn timer.

Captures map OnBreak keys via EntityKeyValue, mirrors their raw values to an unused OnUser1–4
output of the original surface and fires its FireUser input once. It never sends engine Shatter
or Break to the hidden original. Missing keys (e.g. Lua hot reload) or four occupied user channels
cannot be bridged; see ADR 0074. No engine sound/shard effects are requested by the bridge.

Authoritative pane registry, map glass adapters, network state and admin settings.

Server-only bootstrap include. Registers damage/input/entity/map/cleanup/movement hooks and network handlers. Inputs are engine callbacks and validated definitions; outputs are compact impacts, bounded state, blasts and removals. Builds frozen remaining-cell collision, hides original surface brushes as output bridges, and removes fully broken panes. Native glass remains engine-owned. No per-tick pane polling, per-piece server entities or direct filesystem writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
