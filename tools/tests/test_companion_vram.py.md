# test_companion_vram.py

Runs the real client VRAM sampler under LuaJIT with the
[`companion_vram_harness.lua`](companion_vram_harness.lua.md) mocks. Checks all 14 binding fields,
UTC timestamps, API absence and late availability, disabling and reenabling, invalid values and
exceptions, hourly rotation, the 240-row bound, map/restart continuity and untouched incompatible
files. Also checks file errors and the server no-op.

Run `python -m unittest discover -s tools/tests -p test_companion_vram.py -v` from the repository,
or the complete `tools/test.ps1 -Config Release`. Requires an existing LuaJIT installation; skips
when unavailable. Reads the sampler and harness only; mocked files stay in memory. No game,
network, installed-game files, or GPU is used. Exit 0 passes/skips; a failing assertion exits nonzero.
