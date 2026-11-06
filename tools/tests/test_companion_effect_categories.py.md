# test_companion_effect_categories.py

Re-exports companion/tests/test_effect_categories.py's unittest class so tools/test.ps1 includes
the ten real Lua observer scenarios. Run `python -I -m unittest discover -s tools/tests -p test_companion_effect_categories.py`.
Needs LuaJIT; otherwise skips. No files/game/config/network changes. Exit zero on success,
nonzero on failure; the companion harness's per-subprocess timeout is thirty seconds.

R20-D bounds animated/hash-heavy materials to 64 input hashes each and each published category
to 4,096 hashes. `hash_budget` checks a 10,000-hash response; no unbounded CSV reaches the API.
