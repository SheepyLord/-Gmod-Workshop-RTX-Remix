# bench_render_guard.py

Offline comparison of the complete production render guard with an optional older guard. Runs
the authored `r8_material_bench` scenario through [the LuaJIT harness](render_guard_harness.lua.md).
No game, install, third-party Lua or graphics driver is loaded.

```powershell
python tools/tests/bench_render_guard.py --out out/r8-compat/material-cost.json
python tools/tests/bench_render_guard.py --baseline-guard out/r8-compat/review-before-guard.lua --lookup-ms 1 --repeats 3
```

Inputs: guard path (default: this checkout's companion), optional baseline path, number of fresh
process runs (default 3), minimum failed-lookup delay in milliseconds (default 1; range 0-10).
LuaJIT must be installed. Each case uses 1,200 distinct paths, or repeats the same 1,200 paths.
The mixed browser workload has 400 PNG, 400 JPG and 400 extensionless material names; the image
case has 600 PNG/600 JPG, including uppercase extensions. Trusted reads use the PBR-reader path;
trusted entity bindings use the hotloader path. Fresh render bindings use 1,200 separate materials.

The file.Read double represents each missing VMT as one complete failed search through 761
mounts, with a configurable minimum delay. Mount probes are a modeled counter (reads times 761),
not actual archive operations. Native Material is a cached in-memory double, independent of
file.Read, to isolate added guard work. Missing root VMTs were not cached by the older guard.
Windows QueryPerformanceCounter supplies high-resolution elapsed batch time through LuaJIT FFI;
other hosts use os.clock. This is a harness timing measurement, not an in-game CPU/GPU benchmark.
The first native case warms the native cache before plain/repeated loads; image/trusted cases
create new fake materials. Entity binding uses previously loaded objects but fresh binding
decisions. Trusted entity binding adds no native material resolution. Repeat bindings must need
no new native lookup or shader/string query while the cached objects remain live.

Output: per-case console summary and a JSON receipt (default `out/r8-compat/material-cost.json`)
containing every run, medians, reads, modeled mount probes, native resolutions and metadata-query
counts. Only the requested receipt and its parent folders are written; keep them under the
repository's ignored `out/`. No network, config, Steam, Workshop or package changes occur.

Exit 0 means all subprocesses and counters completed consistently; malformed options/missing
LuaJIT exit 2, and a subprocess failure/timeout or inconsistent counters exits nonzero. Unittest
separately runs `r8_material_cost` without delay and asserts the zero-I/O/repeated-path bounds;
wall-time thresholds are deliberately excluded from regression assertions.
