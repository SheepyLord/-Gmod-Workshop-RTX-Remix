# blood_impacts.lua

Client `BloodImpact` override, with the engine's normal observer dispatch (no new networking).
Off/master off/amount 0 forwards the same CEffectData using `allowOverride=false`; mechanical/unknown
colours also use the engine. No PCFs, shared effects materials or bullet/damage hooks are changed.
The documented stock red/yellow/green/antlion/zombie/worker colours use the chosen blood scheme.

`nativeloader_blood_impacts` defaults on. `nativeloader_blood_amount` is 0–2, default 1. Effect scale
(clamped .25–8) is a damage proxy, not a damage measurement. Detail reduces after 768/2048 units,
and effects beyond 4096 units are culled. The impact direction comes from the event, never the
observer's camera. A wider, slower reverse cone and narrower forward cone approximate spatter; the
event cannot identify an exit wound. Every fifth particle is low-opacity mist lasting .10–.22 s;
other droplets last .5–1.35 s, with several sizes, gravity, size-dependent drag and one collision
stamp each. Collision traces reject sky/solid starts; all stains use `util.DecalEx` and owned maps.

Hard limits: 80 accepted events/rolling second; 640 particle admissions/rolling second, 512 live
(conservative expiry count), 42 per impact; 48 stains/rolling second, 384 per map/explicit-clear
epoch. A saturated budget suppresses extra work. Engine decals have no individual retirement API,
so the total stops growing until map cleanup or `bloodoverhaul_clear` (which explicitly clears all
engine decals). Toggles do not reset budgets. Turning the effect off also kills its live particles;
stains already on walls stay until cleared. External add-ons retain their own budgets.

`nativeloader_blood_status` prints dispatch, stock/cull, particle, stain and denied counts. Reads
client settings, event data and world collision traces; writes in-memory materials/particles/decals.
No disk writes or exit code. Missing emitters fall back to stock. See ADR 0119 and the Lua harness.
