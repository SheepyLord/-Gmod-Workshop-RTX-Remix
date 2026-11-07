# test_companion_qol.py

Runs [companion_qol_harness.lua](companion_qol_harness.lua.md) against the production R20-B Lua files
under LuaJIT. From the worktree root:

```powershell
python -I -m unittest discover -s tools/tests -p test_companion_qol.py -v
```

Nine unittest methods cover the hint decisions, capabilities, timing, preferences, map/process
lifetime, silent failure, sky-default migration and (R22) the hint's top-right notice at 1080p,
4K and 720p, with sandbox hints off, and with the RTX tab's checkbox off. Included by `tools/test.ps1`; skips only if
LuaJIT is unavailable. Inputs are repository Lua sources and the installed LuaJIT executable.
The first-run guide and other menus defer the decision; closing them reads the current settings.
Writes no file; captures subprocess output with a 20-second timeout. No game/Steam/network side
effects. Exit 0 when tests pass (or LuaJIT is absent and they skip); otherwise unittest's nonzero exit.
