# smoke_test.ps1

Runs the x64 PoC with Steam running: baseline (bootstrap absent), enabled, and each of the three
off switches. Every run must reach `Map: gm_construct` followed by `Clientside Lua startup!` in a
fresh `garrysmod/console.log`; then waits three seconds for post-map output and stops only the
spawned game process tree. Refuses to start while any `gmod` process exists.

```powershell
tools\build.ps1 -Config Release
tools\smoke_test.ps1
tools\smoke_test.ps1 -Config Debug -TimeoutSeconds 240
```

Inputs: `-GameRoot` (PoC default), `-Config Release|Debug`, `-TimeoutSeconds` (180, range 15–600).

M4 also snapshots/restores `garrysmod/data/native-loader` so an inert smoke run does not leave a
new status report behind. Use a config with activation disabled for a vanilla comparison. This
multi-launch M1 script is not used for M4's individually approved runs; use poc_activation_check.ps1.
Uses [install-loader.ps1](install-loader.ps1.md), with its ownership/hash checks and Steam-managed
protection; there is no Steam-managed bypass in the smoke test. Does not change Steam settings or
launch options. Child-only environment removes inherited `NATIVE_LOADER_DISABLE` except in the
environment-off case. Launch arguments are those in the M1 handover; cwd is the game root.

Also compares no-argument `vpk.exe` and `bspzip.exe` output and exit code with/without the bootstrap;
each must exit within 15 seconds and create no loader log. Enabled logging must prove all exports
resolved, match the launched game's PID, and prove engine/shader API/D3D9 modules were absent at
the entry point. Chromium helper processes must not replace that log. Disabled runs must
create no log. Console comparison preserves order and all nonempty content, except CRLF/trailing
whitespace/blank lines and the numeric `Thumbs: N => N` thumbnail allocation counters. Any other
difference fails and writes a diff for investigation; no generic warning/error suppression.

Outputs: raw and normalised console logs for five runs, enabled loader log, console-tool JSON,
summary JSON, and backups in `out/smoke/<UTC timestamp>/`. On exit (including failure), restores
original bootstrap DLL/PDB, receipt, disable flag, log directory and console log from those backups;
newly generated versions are removed. Reparse points in touched paths are refused and recursive
targets are checked inside the game root before removal. The game may update its own normal
config/cache files, as on any launch. Does not restore those game-authored files.

Exit 0 when all comparisons pass and restoration completes. A terminating error/nonzero separate
PowerShell exit on missing Steam, existing game, timeout, installation failure, missing proof,
unexplained output differences or restoration failure. Inspect `summary.json` and `before/` if
interrupted forcibly (a killed PowerShell cannot execute `finally`).
