# test_remix_settings.py

The bounce_defaults scenario also verifies twelve on explicit activation, rejection of an
unsupported sixteen-bounce value, and acceptance of a deliberate eight-bounce override.

Runs nine persistence scenarios in [remix_settings_harness.lua](remix_settings_harness.lua.md)
using LuaJIT. Each runs with the RTX fixes' real `rtx_pseudoplayer` default, read from
`packages/fixes/.../remixlua/cl/cl_rtx_misc.lua` (1: the body proxy on), so `fresh` fails if a map
start writes the player shadow over Remix's saved settings, and `player_shadow` checks that only
turning the body on (or the opt-in startup replay) writes it. A second test checks that the menu
does not create `rtx_pseudoplayer` itself (that default would be dead and misleading). Included in
tools/test.ps1's unittest discovery. Skips if LuaJIT is unavailable. No game, GPU, disk writes or
network access. Exit 0 on success; nonzero on test failure.
