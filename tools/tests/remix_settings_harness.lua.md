# remix_settings_harness.lua

The bounce_defaults case covers the new default twelve, upper bound fifteen and saved-override
precedence, alongside the existing no-write-on-open and restart behavior.

Runs the Common Remix settings panel with mocked GMod ConVars, widgets, queued console commands,
hooks and the write-only Remix API. Arguments: menu Lua path, scenario (`fresh`, `legacy`, `replay`,
`edit`, `restart`, `invalid`, `reset`). Asserts that construction never writes, stale values do not
override native saves, explicit zero persists, invalid settings are rejected, and reset is safe.
No disk or game changes. Prints PASS and exits 0, or LuaJIT exits nonzero on an assertion.
