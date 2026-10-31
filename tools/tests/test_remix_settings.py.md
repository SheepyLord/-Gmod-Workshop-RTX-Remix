# test_remix_settings.py

The bounce_defaults scenario also verifies twelve on explicit activation, rejection of an
unsupported sixteen-bounce value, and acceptance of a deliberate eight-bounce override.

Runs seven persistence scenarios in [remix_settings_harness.lua](remix_settings_harness.lua.md)
using LuaJIT. Included in tools/test.ps1's unittest discovery. Skips if LuaJIT is unavailable.
No game, GPU, disk writes or network access. Exit 0 on success; nonzero on test failure.
