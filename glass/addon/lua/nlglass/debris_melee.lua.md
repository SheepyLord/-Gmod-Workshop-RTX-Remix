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
