# test_toolgun_screen.py

Runs ten GPU-free LuaJIT scenarios in [toolgun_screen_harness.lua](toolgun_screen_harness.lua.md),
including the screen as the first HUD draw and after another UI draw.
Included in tools/test.ps1's discovery; skips if LuaJIT is absent. No game, files or network changes.
Exit 0 on success, nonzero on failure.
