# test_model_layers.py

Runs [model_layers_harness.lua](model_layers_harness.lua.md) under LuaJIT against the shipped module.
Use `python -m unittest tools.tests.test_model_layers`; tools/test.ps1 also discovers it. Twelve
scenarios cover suffix normalization, late hashes, collisions, ordinary black materials, skin,
submaterials, proxies, clientside and cached bindings, toggles, absent APIs and retry. LuaJIT lookup
follows the toolgun harness and skips when unavailable. No side effects; exit zero when tests pass.
