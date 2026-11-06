# test_companion_effect_categories.py

Re-exports companion/tests/test_effect_categories.py's unittest class so tools/test.ps1 includes
the nine real Lua observer scenarios. Run `python -I -m unittest discover -s tools/tests -p test_companion_effect_categories.py`.
Needs LuaJIT; otherwise skips. No files/game/config/network changes. Exit zero on success,
nonzero on failure; the companion harness's per-subprocess timeout is thirty seconds.
