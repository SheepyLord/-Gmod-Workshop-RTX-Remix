# test_companion_qol.py

Runs [companion_qol_harness.lua](companion_qol_harness.lua.md) against the production R20-B Lua files
under LuaJIT. From the worktree root:

```powershell
python -I -m unittest discover -s tools/tests -p test_companion_qol.py -v
```

Six unittest methods cover the hint decisions, capabilities, timing, preferences, map/process
lifetime, silent failure and sky-default migration. Included by `tools/test.ps1`; skips only if
LuaJIT is unavailable. Inputs are repository Lua sources and the installed LuaJIT executable.
Writes no file; captures subprocess output with a 20-second timeout. No game/Steam/network side
effects. Exit 0 when tests pass (or LuaJIT is absent and they skip); otherwise unittest's nonzero exit.
