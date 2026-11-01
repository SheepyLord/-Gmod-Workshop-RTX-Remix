# glass_interaction_harness.lua

MIT LuaJIT harness for the actual `debris_scene.lua` and `debris_bullets.lua`. Run through
`test_glass_interaction.py`, or `luajit tools/tests/glass_interaction_harness.lua glass/addon/lua CASE`.
Cases: `scene_kinds`, `scene_caps`, `scene_fallback`, `bullets_filter`, `bullets_rate`, `bullets_client`.

Source doubles forbid all position, velocity, force and damage writes and whole-map scans. Checks
living/shadow classification, per-bone ragdolls, stale physics identity, fallback shapes, spatial/body/
shape caps, removals, final trace/PVS forwarding, unchanged weapon callbacks, ammo metadata, token
buckets, expired/cleaned interest and receive-only clients. No game, native module, installed assets,
network or files are changed. Exit 0 prints an assertion count; assertion/Lua errors exit nonzero.
