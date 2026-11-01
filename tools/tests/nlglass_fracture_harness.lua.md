# nlglass_fracture_harness.lua

Fix-pass modes `cap_local`, `weak`, `incremental`, `tempered_spider`, `tiny_edges`, `border` fail
against the original 3096b2e modules. `coarsen` drives 100 separated impacts to the 512-cell cap;
`hole_coarsen` proves complete-group coarsening cannot refill an existing opening. `tiny_edges`
also checks generated edges over 180 seeds. `timings` prepares a near-cap pane and reports 80
new hits, repeats and breaks (mean/p99 milliseconds, QueryPerformanceCounter on Windows).
Preparation is outside the timed section; this is pure fracture CPU cost, not engine/Remix cost.

Runs the actual MIT fracture module under plain LuaJIT, without GMod globals. Invoked by
[test_nlglass.py](test_nlglass.py.md), or directly:

```powershell
luajit tools/tests/nlglass_fracture_harness.lua glass/addon/lua determinism
```

Arguments: Lua root and scenario (`determinism`, `strength`, `pattern`, `tempered`, `bounded`,
`connectivity`, `forced`). Assertions cover seeded equality and snapshot replay, disabled global
random/trigonometry/sqrt, game thresholds and crack growth, corner/centre breakout, near/far cell
area and velocity, retained-cell rebreaking, area conservation, uniform full tempered shatter,
large-pane cell bounds, merged impact energy, shared-edge support and forced nominal breaks.
The deterministic scenario emits a canonical state/piece serialization for fresh-process comparison.

Inputs are generated in memory. Outputs are assertion diagnostics and an OK marker on stdout;
there are no files, network calls, engine entities or native debris. Exit 0 passes; Lua assertions
give a nonzero exit. The Python wrapper runs all scenarios and compares independent processes.
