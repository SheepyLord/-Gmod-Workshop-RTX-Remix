# topbr_harness.lua

Loads the packaged GPL ToPBR client driver under a fake GMod API. Checks syntax, diagnostics,
convar/command collisions, callbacks, independent game/world switches, hash retry and one-time
metadata submission, source-less queueing, and clear/requeue while preserving the off switch.
Usage: `luajit tools/tests/topbr_harness.lua <driver.lua>`. Reads only its driver;
no game, network or filesystem mutation. Exit 0 on success, nonzero on a failed assertion.

The driver includes the R12 panel under its existing trusted path; registration is exercised here,
and `game_pbr_panel_harness.lua` separately executes that exact marked section with Derma stubs.
