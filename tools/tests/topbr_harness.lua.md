# topbr_harness.lua

Loads the packaged GPL ToPBR client driver under a fake GMod API. Checks syntax, diagnostics,
convar/command collisions, callbacks, independent game/world switches, hash retry and one-time
metadata submission. Usage: `luajit tools/tests/topbr_harness.lua <driver.lua>`. Reads only its driver;
no game, network or filesystem mutation. Exit 0 on success, nonzero on a failed assertion.
