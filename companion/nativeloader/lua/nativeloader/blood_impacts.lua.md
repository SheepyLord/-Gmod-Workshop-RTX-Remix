# blood_impacts.lua

PoC tuning uses droplet drag .9–3.5, mist drag 20 and reverse-cone mist, with longer droplet flight.
World collision traces are accepted through HitWorld even when their entity fails IsValid.
Diagnostics also retain landing/trace-miss and ragdoll-impact counts.

Ragdolls use existing Impact/Impact_GMOD/RagdollImpact dispatches, preserving native physics,
sounds/decals and previously registered Lua effects. Known ragdolls use the event's surface property;
world rays can hit cached client ragdolls (`hitclientonly`), with at most 160 extra traces/checks/s.
Living NPC/player events are left to BloodImpact, mechanical/bloodless/non-flesh bodies stay dry,
and only bullet/buckshot damage qualifies. A weak client ragdoll map retains its source's blood
colour; otherwise flesh/alien/chitin surface types choose red/yellow. Cross-name duplicate events
are suppressed in a bounded 64-entry window; separate shotgun pellets still count. Impact supplies
no blood amount, so a missing/unit scale uses 12. Off forwards the original dispatch without extras.

Client `BloodImpact` override, with the engine's normal observer dispatch (no new networking).
Off/master off/amount 0 forwards the same CEffectData using `allowOverride=false`; mechanical/unknown
colours also use the engine. No PCFs, shared effects materials or bullet/damage hooks are changed.
The documented stock red/yellow/green/antlion/zombie/worker colours use the chosen blood scheme.

`nativeloader_blood_impacts` defaults on. `nativeloader_blood_amount` is 0–2, default 1. Effect scale
(stock blood amount, clamped .5–255 and square-root normalized around 12, gain bounded .4–2.8)
is a damage proxy, not a damage measurement. This preserves differing pistol/rifle amounts even
when the engine scales multiplayer blood amount up. Detail reduces after 768/2048 units,
and effects beyond 4096 units are culled. The impact direction comes from the event, never the
observer's camera. A wider, slower reverse cone and narrower forward cone approximate spatter; the
event cannot identify an exit wound. Every fifth particle is low-opacity mist lasting .10–.22 s;
other droplets last .75–1.8 s, with several sizes, gravity, size-dependent drag and one collision
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
