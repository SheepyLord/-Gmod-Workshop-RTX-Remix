# test_effect_categories.py

Runs nine scenarios of effect_categories_harness.lua against the production companion observer.
Usage from the repository root: `python -I -m unittest discover -s companion/tests -p test_effect_categories.py`.
Needs LuaJIT (same discovery as test_mmd_alpha.py); skips when unavailable. Each subprocess has
a thirty-second timeout. No game/files/network changes. unittest exits zero on success, nonzero
on failure. Repository companion checks discover this test automatically.
