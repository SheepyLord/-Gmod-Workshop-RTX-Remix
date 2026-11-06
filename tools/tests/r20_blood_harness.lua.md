# r20_blood_harness.lua

The server-delivery scenario checks that both the private screen marker and panel adapter are sent
before a multiplayer client tests their presence. This prevents a second Utilities shortcut.

An independent reference flight check requires at least half of the configured droplets to clear
a 12-unit body radius and fall 48 units within their lifetime. Engine motion is measured separately
in the PoC; the reference model is a conservative transport check, not an engine-equivalence claim.

Ragdoll scenarios preserve native forwarding and previous Lua effects, retain source blood colour,
infer flesh/alien surfaces, reject metal/bloodless bodies, handle client-only rays and deduplicate
cross-name events while retaining pellets. A world-landing case uses HitWorld with an invalid entity.

LuaJIT harness for the real R20-C bootstrap, core, impact and menu files. Invoked by
`test_r20_blood.py <repo> <scenario>`: rolling budgets, exact stock forwarding, palette/quality
choices, cone directions, collision storms/map cap/toggle resistance, menu relocation and duplicate
include protection with optional parts present/absent. API doubles model particles, material tint,
time and normal effect data; no game is launched. Exit 0/PASS on success, nonzero assertion on failure.

Additional scenarios cover an already-loaded screen on both realms and a server-preloaded legacy
blood wrapper/hook set. External Lua blood droplets retain their recolour control, extra arguments
and disabled pass-through. Stock SP/MP blood amounts remain distinct after bounded scaling.
