# r20_blood_harness.lua

LuaJIT harness for the real R20-C bootstrap, core, impact and menu files. Invoked by
`test_r20_blood.py <repo> <scenario>`: rolling budgets, exact stock forwarding, palette/quality
choices, cone directions, collision storms/map cap/toggle resistance, menu relocation and duplicate
include protection with optional parts present/absent. API doubles model particles, material tint,
time and normal effect data; no game is launched. Exit 0/PASS on success, nonzero assertion on failure.
