# nlglass_fracture_harness.lua

G1 integration `irregular` (the user: breaks were always an octagon): over 24 seeds, breaks must use
at least four ray counts and at least 18 must have uneven first-ring radii (max/min above 1.1); each
break repeats exactly for its seed, every piece and remaining cell is convex and their areas add up
to the pane's. It fails on 8536d87 (always eight rays, one radius per ring).

Second-pass `density` covers centre/corner hits on 96x64, 256x128 and 128x256 panes, plus
8192x1, 1x8192 and 8192x8192 extremes, both kinds and piece sizes 4/8/64. It checks the live
200/300-cell bounds after 24 spatial hits, full-break counts and area conservation; prints fresh
and pre-damaged counts at default spacing. The regression fails on ad3ed46. The coarsen/timing
probes now use the kind's lower active topology cap; 512 remains the snapshot wire ceiling.

Fix-pass modes `cap_local`, `weak`, `incremental`, `tempered_spider`, `tiny_edges`, `border` fail
against the original 3096b2e modules. `coarsen` drives 100 separated impacts to the 512-cell cap;
`hole_coarsen` proves complete-group coarsening cannot refill an existing opening. `tiny_edges`
also checks generated edges over 180 seeds. `timings` prepares a near-cap pane and reports 80
new hits, repeats and breaks (mean/p99 milliseconds, QueryPerformanceCounter on Windows).
Preparation is outside the timed section; this is pure fracture CPU cost, not engine/Remix cost.
The coarsen case also drives 200 dense visual-only hits, ensuring engine-owned glass never
generates an early cosmetic shatter under geometry pressure.

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
