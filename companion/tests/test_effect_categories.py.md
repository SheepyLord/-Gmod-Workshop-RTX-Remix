# test_effect_categories.py

Runs twelve scenarios of effect_categories_harness.lua against the production companion observer.
Usage from the repository root: `python -I -m unittest discover -s companion/tests -p test_effect_categories.py`.
Needs LuaJIT (same discovery as test_mmd_alpha.py); skips when unavailable. Each subprocess has
a thirty-second timeout. No game/files/network changes. unittest exits zero on success, nonzero
on failure. Repository companion checks discover this test automatically.

R20-D bounds animated/hash-heavy materials to 64 input hashes each and each published category
to 4,096 hashes. `hash_budget` checks a 10,000-hash response; no unbounded CSV reaches the API.

Live DX7 coverage: normalize shader _DX suffixes, read packed $flags, recognize standard white
aliases and clear stale observer bindings on both color-material helpers. The packed_flags and
color_helper scenarios supplement the hash budgets and normal classifications.
