# debris_melee.lua

MIT server-only helper included after `debris_bullets.lua`. Observes stock crowbar/stunstick swings
through successful primary-fire cooldown advances after a ready attack command, plus attack animation
events. Clips a 75-unit segment using Source and forwards a six-unit melee radius. No input, weapon
cooldown, animation return, damage callback or Source object is modified.

For trace-based SWEPs with melee/melee2/knife/fist hold type or `Primary.Melee`, observes actual
`util.TraceLine`/`util.TraceHull` results. The original function runs once with identical arguments;
the same result object is returned. Accepts only segments 1–160 units long, within 96 units of the
owner's shoot position, with the owner in a direct filter or first eight table entries, during a
0.6-second attack window. The forwarded endpoint is Source's actual hit position; hull radius caps
at 16. Coalesces accepted observations for 0.1 seconds. Uses the shared server forwarding buckets.

Reads active weapon class/hold type, `Primary.Damage` (default 25), commands, animation events and
trace tables. `sent` and `observed` are diagnostic counters. `Stop()` disables old wrappers and
restores them only if still owned; reload does not stack active observers. Cleanup drops actor state.
No files, client hit claims or networked shards. Client-only weapons, functional filters and unusual
weapons without a recognizable melee type need an adapter; saturated cosmetic events can be dropped.
No exit code; errors propagate to the Lua console.

R8-G follow-up: defer SWEP observations to a zero-delay timer and retain the widest actual trace
from the call. Stock fists use a line followed by a hull, so the first observation must not consume
the swing before the hull is available. Read HitDamage as a mean when Primary.Damage is absent.
Stock cooldown detection also accepts the player's processed attack button, independent of other
StartCommand hook ordering. StartSolid/AllSolid observations are ignored.

An animation arriving before the first command initializes the weapon cooldown field too. Deferred SWEP work also checks state identity, so cleanup cannot forward an old timer through a fresh actor state.

Forwarded volumes are re-clipped with a containing Source TraceHull box, independently of the weapon's untouched actual trace. This also protects line-only SWEPs from pushing pieces behind an endpoint wall. These extra queries have a 64/s global token bucket, burst 32; limited counts rejected queries. Native sphere casts fit within the clipping box. Cleanup resets this bucket.

Deferred observations copy both endpoints, so a SWEP can reuse/mutate its input/output vectors after returning without changing the queued cosmetic hit.
