# test_nlglass.py

Includes G1-A fix-pass regressions for oriented body contact, pre-movement player collision,
independent client convars, engine-effect-free map output routing, weak native last impacts,
blast ordering and the matching debris-budget bound.

Fracture regressions cover local hits beyond the old cap, weak energy/floor, revision caches,
tempered spiderwebs, 1/256 edge merging, perimeter omission, complete-group coarsening with holes,
bounded topology snapshots and repeatable near-cap timing output.

Client cases count per-message builds and stationary drawing calls, test distance/eye-plane
culling, one readiness sync and targeted pane repair, and record 40-sample server/client handler
timings. The full module currently runs 45 tests, including catalog/compilation checks.

G1-A unit/integration acceptance under LuaJIT, invoked by `tools/test.ps1`:

```powershell
cd tools
python -m unittest tests.test_nlglass -v
```

Runs [the fracture harness](nlglass_fracture_harness.lua.md) and
[the engine harness](nlglass_engine_harness.lua.md) against the actual MIT add-on. Determinism is
also compared across fresh processes. Checks all Lua compiles without GLua conversion, all six
non-English catalogs are complete and MIT, and committed generated shipping data matches the
catalog build exactly. LuaJIT comes from PATH or the existing LOCALAPPDATA installation; missing
LuaJIT skips executable cases, never downloads it. Python catalog checks still execute.

Inputs are repository source and generated in-memory fixtures. Lua subprocesses have timeouts.
Output is unittest diagnostics. No game, game files, user.conf, native module, network or temporary
files outside this repo are used. Exit is unittest's (0 all pass, nonzero otherwise).
