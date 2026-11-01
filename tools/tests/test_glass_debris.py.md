# test_glass_debris.py

`python -m unittest discover -s tools/tests -p test_glass_debris.py` runs the LuaJIT debris harness
against this worktree's G1-B sources. The standard `tools/test.ps1` includes it. Requires LuaJIT at
PATH or the repository's documented local installation; skips explicitly if absent. No downloads,
game launches or install writes. Captures stdout/stderr and asserts success; exit 0 passes, 1 fails.
