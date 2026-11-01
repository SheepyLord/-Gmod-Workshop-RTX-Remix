# debris_bullets.lua

MIT shared hit routing, included by the bootstrap. The client receives `nlglass_debris_hit` and
passes Source-clipped endpoints, damage and radius (0 bullet, 1–16 melee) to `NLGlassDebris.Ray`.
It advertises live-piece interest through `Update(api, wanted)` every two seconds, including settled
pieces and infinite lifetime; stopping sends an empty update. Up to 32 native regions become numeric
spheres (radius ≤2048). No client damage, piece IDs or gameplay claims are accepted.

The server accepts ≤32 regions/≤4200 bits per message, at most one update/second/player, and at most
128 clients. Finite coordinates and radii are checked before replacing an entire snapshot. Leases
expire in six seconds. Numeric ray/region tests route each hit to clients whose own pieces overlap,
without depending on the shooter's PVS or the age/location of an old pane. `Mark(origin, radius)`
retains a 32-region, two-second PVS bridge for the first interest update after a real break.

`PostEntityFireBullets` reads final pellet endpoints/damage, with ammo-metadata damage fallback.
`Forward(entity, from, to, damage, radius, attacker)` is shared with melee observations. Inspection
caps at 256/s (burst 64), delivery at 64/s (burst 32) globally and 16/s (burst 8) per firing entity.
One unreliable payload is 28 bytes plus five bits before headers. Region tests use numbers, retaining
the R7 engine-vector cost fix. `HasInterest()` prunes leases at 4 Hz; no world entity scan. `Clear()`
resets leases, recent breaks, buckets and counters on map cleanup. `sent`/`limited` report saturation.

Never modifies bullets, callbacks or other hooks' return values. No Source force/damage or file access.
Lost/late leases, >32 separated regions or saturated buckets may miss cosmetic hits. Runtime module:
no exit code; errors appear in the console.

StartSolid/AllSolid pellet traces are ignored; no endpoint behind a solid start becomes a glass hit.
