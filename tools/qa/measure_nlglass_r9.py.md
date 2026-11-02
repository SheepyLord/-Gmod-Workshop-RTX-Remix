# measure_nlglass_r9.py

Offline paired R9 CPU measurement. Run after a Release build:

```powershell
python tools/qa/measure_nlglass_r9.py --before-lua out/qa-r9/before/glass/addon/lua --before-native out/qa-r9/before/nl_glass_tests.exe
```

Uses the same LuaJIT harness with saved/current production Lua for 80 near-cap pane impacts,
repeated impacts and breaks, plus 80 server/client wire replays. Three interleaved runs compare
native CanSplit+two-child replacement, records 2-6-child replacement costs and measure 1000 generated pieces with sound/buoyancy off/on
for 120 fixed steps. The baseline has no environment events or buoyancy: those feature deltas use
the current native feature-off control. Engine doubles are CPU costs, never RTX/GPU frame timings.

`--runs` accepts 1-10; `--out` defaults to `out/qa-r9/feature-costs` and must remain in this
worktree's `out`. Writes raw logs, all samples and median `costs.json`; subprocess TEMP/TMP use
`out/tmp`. No install reads, game launches, downloads or changes to inputs. Exit 0 completes,
2 rejects arguments, nonzero on a failed workload/OS error with raw logs retained.
