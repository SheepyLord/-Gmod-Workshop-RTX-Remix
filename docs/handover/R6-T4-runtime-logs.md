# R6 T4: self-describing runtime logs (runtime patch 0015 and a rebuild)

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. Background in
[R5-stability-proposal.md](R5-stability-proposal.md) proposal 8 and sections 1.3, 1.4 and 3. Branch
`r6-t4-runtime`, worktree `out\worktrees\r6-t4-runtime`. ADR 0065 only if you make a design decision.

## The patch

A new patch `runtime/patches/0015-*.patch` against the fork commit in `runtime/base.json`, on top of
0001-0014, made the way [runtime/README.md](../../runtime/README.md) describes:

1. At device loss, before the Sentry step (`src/dxvk/dxvk_queue.cpp:143-171`, `:407-431`), log the
   driver's budget and use per memory heap and DXVK's allocation totals and categories (the numbers
   `remixapi_GetVramStats` returns; reuse that code path).
2. Log the same line at each camera cut and every five minutes.
3. The two opacity micromap budget lines (`rtx_opacity_micromap_manager.cpp:190`, `:199`) are logged at
   most once a minute with a count of the suppressed repeats, instead of `ONCE`.
4. Before `TerminateProcess` after a device loss, write `rtx-remix\logs\last_gpu_crash.json` (interface
   I7, schema 1) next to the log. Never let a failure to write it change the exit path.
5. Optional, only if small and safe: request `VK_EXT_device_fault` when the driver offers it and log
   `vkGetDeviceFaultInfoEXT`'s result after a loss.

## Build and import

- Rebuild `d3d9.dll` with the repository's runtime build script and inputs (runtime/README.md); do not
  disturb the user's fork checkout at `H:\BACKUP_20260815\Modding\dxvk-remix-gmod` beyond what the
  script itself does (if it builds in that checkout, check `git status` there first and stop and report
  if it has uncommitted work that the build would touch).
- Import the new `d3d9.dll` (and any other file the build changes) into `packages/runtime` with
  `python tools\inputs.py import runtime --file <staged>=<path>`, then `inputs.py verify`, and check
  that `python tools\build_package.py` builds the package. Mind the Git LFS quota: import only the files
  that changed.
- Update `runtime/README.md` (the patch list) and record the build's identity the way the README asks.

## Tests, docs, limits

- The runtime's own unit build/tests if the README names them; this repository's `tools\test.ps1`.
- CHANGELOG, RESEARCH (what you found about the device-loss path), `docs/TESTING.md` (how to check the
  new lines: a development build's GPU-crash trigger if the runtime has one).
- Do not touch `loader/`, `companion/`, `packages/` other than `packages/runtime`'s runtime files, and
  not `packages/runtime/layers/` or the tier files (T6). You may not launch the game.
