# measure_nlglass.py

Offline before/after CPU measurements for R8-G; never starts GMod, reads game assets, installs a
module or downloads anything. Requires local LuaJIT and a Release build of `nl_glass_tests.exe`.

```powershell
python tools/qa/measure_nlglass.py --before-lua out/r8-g/before/lua --before-native out/r8-g/before/nl_glass_tests.exe
```

The before arguments are preserved baseline Lua and the baseline generated-fixture native test
executable. The current LuaJIT harness is shared by both sides. Three interleaved runs (configurable
`--runs 1-10`) compare 50 real Lua fractures over 1.5 simulated seconds, warm Think/draw with
interaction off/on, empty/96-body/512-entry Source capture doubles, unchanged 4000-piece native stepping and 2000 quads as separate or eight-hull
rigid groups. Prints medians; preserves raw samples and each command's stdout/stderr.

`--out` defaults to `out/r8-g/measurements` and must resolve inside this worktree's `out`. Child
TEMP/TMP point to `out/tmp`. Creates/overwrites logs and `costs.json` there only. No game/RTX/GPU
timings: engine, renderer and physics doubles cannot prove frame-time acceptance. Native groups
also intentionally constrain motion within each group. Exit 0 on completion, 2 for invalid arguments,
nonzero if a workload fails or a process/file operation raises an error (logs retained).
