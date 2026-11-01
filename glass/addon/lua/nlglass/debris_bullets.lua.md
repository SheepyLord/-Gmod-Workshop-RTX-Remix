# debris_bullets.lua

MIT shared helper included by the autorun bootstrap; served by the `debris*.lua` download rule.
Server `NLGlass.Bullets.Mark(origin, radius)` records a region where a pane actually released pieces.
`Clear` resets interest and token buckets. No per-piece entities/state or client requests exist.

The read-only `PostEntityFireBullets` hook observes final spread/damage/Source-clipped trace endpoints;
it returns nothing and never changes callbacks, damage or firing tables. Zero damage uses ammo metadata.
Only rays intersecting one of 32 recent-break spheres (120 seconds, radius 768–2048) are sent, to that
region's PVS plus a player shooter. Global bucket: 64/s, burst 32; each firing entity: 16/s, burst 8.
Region inspection itself caps at 256 pellets/s, burst 64, including rejected distant shots.
The unreliable message contains two Vectors and one damage float (28 bytes before engine headers).
Counters `sent`/`limited` and bounded `regions` are available to QA. Cleanup clears all interest.

Client receive calls `NLGlassDebris.Ray`; it does not run predicted bullet hooks or send messages.
The manager validates, queues and raycasts against its own Jolt pieces. Missing/off interaction drops
cosmetic work. No file writes; no process exit code. Engine/network errors propagate normally.
