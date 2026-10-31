# test_model_layers.py

Runs [model_layers_harness.lua](model_layers_harness.lua.md) under LuaJIT against the shipped module.
Use `python -m unittest tools.tests.test_model_layers`; tools/test.ps1 also discovers it. Seventeen
scenarios cover suffix normalization, late hashes, collisions, ordinary black materials, skin,
submaterials, proxies, clientside entities, the separate opt-in shell rule
(`nativeloader_ignore_outline_shells`), map textures named `*_outline` (never hidden), bounded work
per frame with 2001 entities, a missing or changed hash revision, removed entities, toggles, absent
APIs and the backoff after a refused write. LuaJIT lookup follows the toolgun harness and skips when
unavailable. No side effects; exit zero when tests pass.
