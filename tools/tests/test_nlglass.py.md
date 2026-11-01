# test_nlglass.py

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
