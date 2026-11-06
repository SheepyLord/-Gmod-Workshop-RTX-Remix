# test_hotloader_installation.py

R21-B regression tests for the shipped Model Hotloader installation override and its unchanged UI.

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_installation.py -v
```

Runs [hotloader_installation_harness.lua](hotloader_installation_harness.lua.md) with LuaJIT for both
realms. Checks arbitrary current/future game libraries and native findings, exact matches, failed and
throwing checks, old modules, pending libraries and their retry limit, repeated refreshes and Recheck.
Game findings stay out of warnings, summaries, detailed UI text, notices and problem counts, without
writing a dismissal. Raw reports and feature behavior are retained; the console logs one plain line.
Outdated-release, policy, fallback, identity and missing-file warnings still reach the unchanged UI.

Needs LuaJIT on PATH or at `%LOCALAPPDATA%/Programs/LuaJIT/bin/luajit.exe`; skipped if absent. Reads
only this repository's packaged Lua. Writes no files and starts no game. Exit 0 when all tests pass.
