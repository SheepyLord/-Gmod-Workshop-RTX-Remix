# M4 review (Claude)

- Reviewer: Claude, 2026-10-28
- Branch reviewed: `m4-activation` at `ffe287a` (Codex's corrections, start-up policy and activation,
  on top of Claude's parts 1-2), against the [brief](M4-handover.md) and the [report](M4-report.md)
- Verdict: **accept with fixes**, made on the branch before the merge. M4's loader mechanics meet the
  definition of done; the path-traced frame moves to M5's acceptance, because it needs the RTX fixes'
  fixed-function shader DLL (below). Merged into `main` on 2026-10-28; the user asked for M5-M7 to
  follow without further approvals.

## How I checked

- Read the code that runs inside `gmod.exe` (`loader/proxy/startup.cpp`, `runtime.cpp`) and
  `nl::startup`, and had an independent reviewer (a separate agent, no shared context) read
  `389755c..ffe287a` in full. Its findings and mine are below, with what was done about each.
- `tools\test.ps1` on `ffe287a` before any change: CTest 15/15 (Debug), as the report says.
- Ran the real PoC checks the report left open, with a new driver that needs nobody at the
  keyboard ([poc_session.py](../../tools/poc_session.py.md)), on the M4 packages with the
  `d3d9.shaderModel = 3` test layer (evidence `out/poc-sessions/m4-real-20261028T041725`):

  | Step | Result |
  |---|---|
  | RTX on, package A | start-up deployed A (generation 1), activation `active`, `d3d9.dll` from A's payload folder, `mat_dxlevel 90`, normal quit |
  | config switched to B | deployed B (generation 2), `d3d9.dll` from B's folder |
  | `nlctl rollback` | generation 3 = A |
  | next start | deployment `held`, A active: the hold keeps start-up from redeploying B |
  | `remix.enabled: false` | activation `inactive`, System32 `d3d9.dll`, `mat_dxlevel 95` |
  | uninstall | 2,877 depot files OK |

- Settled the `-dxlevel` question with three vanilla PoC sessions (vanilla, `-dxlevel 90`,
  vanilla: 95, 90, 95) and found what does persist: `+mat_disable_d3d9ex 1`, through `config.cfg`
  ([RESEARCH.md](../RESEARCH.md) section 11). GMod's registry settings, which every install of the
  user shares, were backed up first and restored afterwards.

## Path tracing

With the classic `dxvk.conf` (`d3d9.shaderModel = 0`) the stock shaders are rejected and the engine
faults before the map (Codex's run 2). With `shaderModel = 3` the map loads with the runtime active,
but the frame is raster-looking: Remix passes the stock shader draws through. The classic install
gets its path-traced frame from the fixes' fixed-function `stdshader_dx6.dll` together with
`shaderModel = 0`, which is M5's scope, so M5's acceptance now includes the path-traced frame.

## Findings and fixes

| # | Finding | Severity | Done |
|---|---|---|---|
| 1 | A report (status or log) that could not be written after a successful preload unloaded the initialised runtime, and was retried, stalling start-up about 5 s with a reader holding `status.json`; a `loader.log` that could not be rotated kept start-up from running at all | medium | Activation is committed before reporting; reporting is attempted once and only logged on failure; `loader.log` is best-effort. ADR 0008 revised |
| 2 | A deployment that failed (and was undone by M3) left the game vanilla instead of activating the intact committed generation, for example an unreadable Workshop archive during staging or too little disk space for an update | medium | `startup::after_deployment`: only a pending transaction blocks activation; unit-tested. ADR 0009 revised. I/O errors during staging still fail the transaction rather than re-planning the package as broken; the result is the same at start-up |
| 3 | Keep-last-good matched local and dev sources by the stored path, which was relative when `nlctl` was given a relative root | medium | Discovery resolves every local and dev location to an absolute, normalised path; test with a relative root |
| 4 | Command-line buffers were freed on rollback although DLL start-up code had run since they were published; restore wrote the old descriptor without checking the slot was still ours | medium (unlikely) | Published buffers are never freed; a later restore leaves a slot alone that something else replaced; test added |
| 5 | Nothing checked that the base name `d3d9.dll` resolves to the preloaded runtime | low | Activation fails (and undoes) unless `GetModuleHandleW(L"d3d9.dll")` is the runtime |
| 6 | The running-game check could see the 32-bit launcher (`root\gmod.exe`) that started this game | low | The current process's parent is excluded when it is that launcher |
| 7 | `status.json.tmp-<pid>` files from crashed launches accumulated | low | Removed after each successful write when their process is gone |
| 8 | `+mat_disable_d3d9ex 1` in the default launch arguments is archived into `config.cfg` and so reaches RTX-off sessions; it only takes effect from the next session anyway | medium | `package_runtime.py` leaves it out; `-nod3d9ex` covers the session |

Not changed, noted: the SEH boundary is not exercised by a test (the fixture's DllMain exception
becomes Windows error 1114 on the normal path); the real command-line swap was exercised through the
PoC driver, which starts `bin\win64\gmod.exe` directly, not through Steam's root launcher.

## Evidence after the fixes

`tools\test.ps1` (Debug: conventions, 66 Python tests, CTest 15/15) and `tools\build.ps1 -Config
Release` (CTest 15/15): 120 core cases plus the three exhaustive fault cases, 16 proxy cases, the
synthetic activation scenarios and the KERNEL32-only import check. The real PoC checks above ran on
Codex's build; the fixes change failure paths only, which the unit and synthetic tests cover.
