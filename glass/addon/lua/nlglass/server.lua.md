# server.lua

R7-C: after an authoritative impact actually releases pieces, register its bounded recent-break
region with `NLGlass.Bullets` (when present). Cracking hits register nothing. This supplies the
server's bounded final-pellet forwarding without any moving-piece server state.

The pre-movement player sweep uses the shared 250-unit/s default/fallback contact-speed gate.

Player contact also uses a pre-movement hull trace in SetupMove, with incoming movement velocity;
this includes GetBaseVelocity (the QA SetVelocity push), just as the engine's mover does.
R14 (the user's item 41): `S.Ghost` is true for a player in noclip (`MOVETYPE_NOCLIP`, flying through
walls) or spectating (`MOVETYPE_OBSERVER`). Touch, physics contact and the SetupMove sweep all go through
`S.Body`, which ignores such a player, so passing through a pane never cracks or breaks it.
On load it resets, once, the two settings Glass-Rewrite-Remix archived under the same names with
other meanings (`rtx_glass_player_break_speed` 100, `rtx_glass_velocity_transfer` 2): GMod restores
archived values, so with them a 200-unit/s walk broke glass (G1 QA run 08, an 80 left in the PoC's
`server.vdf`). The archived `rtx_glass_settings_version` 1 records it; later choices are kept.
A physics collision whose hitter is a player or NPC (their physics shadow) goes through the same
body rule and its speed gate, never the prop energy rule: 85 kg at a 200-unit/s walk is several
times the breaking energy, so in game a walk broke out part of a pane before this (G1 QA run 07).
Idle panes have no polling. All hits record the native pane's last impact before crack filtering.
Deduplicated blast messages are deferred until after synchronous pane break messages.

The blast deferral also waits for one-turn native-removal/physics breaks, then sends the impulse.
Client readiness is the only initial push. nlglass_sync reads a uint32 pane ID (0 = initial list).
There is no PlayerInitialSpawn timer.

R19 (glass F-02): nothing is written inside the request handler. A player gets **one full initial
sync per connection** (`ply.NLGlassFullSync`; the player entity lives exactly one connection, so a
later 0 is ignored); it queues every current pane ID, sorted. Targeted requests keep their limit (at
most 16 different IDs in two seconds, each once) and go to the front of the same per-player queue
(`S.syncQueues`). A `timer.Simple(0)` chain, alive only while a queue holds something, sends each
waiting player at least one pane per tick, then more while that tick's bytes for the player stay under
`S.SYNC_BYTES` (16,000; `net.BytesWritten`, or one pane per tick without it). A near-cap snapshot is
about 10 KiB in game, so a tick sends at most the budget plus the pane that crossed it. A pane gone by
its turn is sent as `nlglass_remove`; a player who left is dropped; `PreCleanupMap` clears every queue
(each pane registered after cleanup is broadcast). `S.Snapshot` returns the bytes it wrote.

Captures map OnBreak keys via EntityKeyValue, mirrors their raw values to an unused OnUser1–4
output of the original surface and fires its FireUser input once. It never sends engine Shatter
or Break to the hidden original. Missing keys (e.g. Lua hot reload) or four occupied user channels
cannot be bridged; see ADR 0074. No engine sound/shard effects are requested by the bridge.

Authoritative pane registry, map glass adapters, network state and admin settings.

Server-only bootstrap include. Registers damage/input/entity/map/cleanup/movement hooks and network handlers. Inputs are engine callbacks and validated definitions; outputs are compact impacts, bounded state, blasts and removals. Builds frozen remaining-cell collision, hides original surface brushes as output bridges, and removes fully broken panes. Native glass remains engine-owned. No per-tick pane polling, per-piece server entities or direct filesystem writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.


R9-G owns a bounded blast observer, which observes exact Lua API calls and native
signals independently of damage victims, with bounded duplicate/rate handling and original OnBreak
ordering. Optional Observe callbacks report damage and sent times. The validated nlglass_clear_debris
admin route broadcasts debris-only cleanup, limited to once per second and refused on dedicated
servers. Panes, Source damage and trusted package policy remain authoritative and unchanged.

The embedded InstallBlastObserver observes exact Lua APIs, native env_explosion/env_physexplosion
inputs and BaseGrenade.Explode without changing arguments/returns or Source damage. Refresh
disables old observers even below another wrapper and restores only owned wrappers. Nearby
signals coalesce over 32 units/0.1 seconds; pending 32, 32/s burst 16, radius 2048, speed 1800.
Two turns preserve OnBreak order and epochs cancel cleanup work. A global replicated listen-server
boolean advertises menu availability for remote admins; the server still validates every request.
