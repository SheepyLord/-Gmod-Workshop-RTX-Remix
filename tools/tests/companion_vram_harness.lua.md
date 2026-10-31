# companion_vram_harness.lua

LuaJIT harness for the shipped client sampler. Arguments are the sampler's absolute path and a
scenario, as supplied by [`test_companion_vram.py`](test_companion_vram.py.md). Mocks the archived
client setting, 30-second repeating timer, UTC clock, DATA file operations and the fixes' VRAM API.
Eleven scenarios cover every field and the lifecycle/retention contract. The rotation scenarios
sample five hours and optionally reload the module to represent map changes and process restarts.

Reads only its source argument. All simulated files and settings remain in memory; no game, GPU,
network or filesystem writes. Prints `PASS <scenario>` and exits 0, or fails with a Lua assertion
and nonzero exit code.
