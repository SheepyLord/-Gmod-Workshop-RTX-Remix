# remix_settings_harness.lua

The bounce_defaults case covers the new default twelve, upper bound fifteen and saved-override
precedence, alongside the existing no-write-on-open and restart behavior.

Runs the Common Remix settings panel with mocked GMod ConVars, widgets, queued console commands,
hooks and the write-only Remix API. Arguments: menu Lua path, scenario (`fresh`, `legacy`, `replay`,
`edit`, `restart`, `invalid`, `reset`, `bounce_defaults`, `player_shadow`), and the RTX fixes' own
default for `rtx_pseudoplayer`. Before the menu loads, the harness creates `rtx_pseudoplayer` with
that default, as `cl_rtx_misc.lua` does in the game (the fixes' autorun runs before the companion's
`autorun/client`), so every scenario runs with the body proxy on.

Asserts that construction never writes, stale values do not override native saves, explicit zero
persists, invalid settings are rejected, and reset is safe. `player_shadow` starts from a player
shadow saved off in Alt+X: map start and a new session leave it off, turning the body off writes
nothing, and only turning it on requests `rtx.playerModel.enablePrimaryShadows = True`; `replay`
(startup replay on) requests it at map start. No disk or game changes. Prints PASS and exits 0, or
LuaJIT exits nonzero on an assertion.
