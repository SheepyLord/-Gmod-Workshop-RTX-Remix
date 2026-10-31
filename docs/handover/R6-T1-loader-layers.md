# R6 T1: layer order, performance tiers, GPU crash dump switch (loader)

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. Background in
[R5-stability-proposal.md](R5-stability-proposal.md) proposals 1, 2 and 4 (section 5) and sections 2
and 3. Branch `r6-t1-layers`, worktree `out\worktrees\r6-t1-layers`. ADR number 0062.

## 1. Loader layers first (proposal 1)

- `DXVK_CONFIG_FILE` lists files strongest first for `rtx.*` keys (the runtime names them `00_DXVK
  Config`, `01_...`, sorts by name, first layer holding a key wins: `rtx_option_layer.cpp:51-61, 671`,
  `rtx_option.cpp:1156-1186` in the fork at the commit in `runtime/base.json`), while for `dxvk.*` and
  `d3d9.*` keys the merged config lets the last file win. Today `loader/core/src/activate.cpp`
  (`layer_list`, `add_layers`, about lines 34-43 and 276) appends the loader's own layers after the
  package's copies, so `non-nvidia.conf` (ADR 0030) loses to the package layer.
- Change the order to: loader layers that set `rtx.*` keys (the tier layer of section 2, then
  `non-nvidia.conf`), then the package's layer copies (`native-loader/remix/dxvk-N.conf`), then loader
  layers that set `dxvk.*` keys only (section 3's `diagnostics.conf`), then the game root's
  `dxvk.conf` last, as now. Keep the two kinds of loader layer in separate files.
- Keep the short copies (ADR 0036) and the 259-character budget; a tier layer is copied to
  `native-loader/remix/tier.conf`.
- Record the measured order in `status.json` `activation.layers` as today.

## 2. Performance tiers (proposal 2, generalised; plan section "Performance tiers")

- Detect at activation, through DXGI as `graphics_adapters()` already does (`activate.cpp:172-196`;
  `loader/proxy/diagnostics.cpp:45-63` reads adapter memory for the menu panel): the NVIDIA adapter
  with the most `DedicatedVideoMemory` and its description.
- Tier = the lower of the VRAM tier and the class tier, exactly as the plan defines them (8.5 GiB and
  12.5 GiB bounds; `RTX <g><c>0` class digit 9/8 high, 7 medium, 6/5 low; `Laptop` one step down; an
  unmatched name uses the VRAM tier alone). Put the classification in a pure function in `nl_core` with
  unit tests for at least: RTX 5090 32 GB, 4090 24 GB, 4080 16 GB, 4070 Ti Super 16 GB, 4070 12 GB,
  3080 10 GB, 4060 Ti 16 GB, 4060 Ti 8 GB, 4060 Laptop 8 GB, 4090 Laptop 16 GB, 3060 12 GB, 2060 6 GB,
  RTX A4000 16 GB, an unknown name, no NVIDIA adapter.
- `native-loader/config.json` key `remix.performance_tier`: `auto` (default), `high`, `medium`, `low`;
  invalid values are reported in `status.json` notes and treated as `auto`. Update the config schema,
  its docs ([ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md), the shipped `dist/native-loader/config.json` if
  it lists keys, `docs/PACKAGE_FORMAT.md` only if needed) and `nlctl`'s config checks.
- `medium`/`low`: copy the runtime package's `config/dxvk-tiers/<tier>.conf` (interface I1) to
  `native-loader/remix/tier.conf` and list it first. If the file does not exist (a package before R6):
  for `low` write the built-in fallback text below as `tier.conf` (source `fallback`); for `medium`
  list nothing. `high`: no tier layer. A non-NVIDIA machine keeps today's `non-nvidia.conf` path and
  gets no tier layer.
- Built-in `low` fallback (only used without the package file):

  ```
  rtx.lowMemoryGpu = True
  rtx.opacityMicromap.cache.maxBudgetSizeMB = 512
  rtx.skyProbeSide = 1024
  rtx.volumetrics.froxelGridResolutionScale = 8
  rtx.terrainBaker.cascadeMap.levelResolution = 2048
  ```

- Report interface I2 (`activation.performance_tier`) in `status.json`; print it in `nlctl activation`
  (or the existing status command), in the bootstrap's log, and as one line in the main menu panel
  (ADR 0050; its strings follow the panel's existing localisation, all seven languages, agent-written
  translations marked as such in the catalogs' comments if the format allows).

## 3. One-start GPU crash dumps (proposal 4)

- `config.json` key `diagnostics.gpu_crash_dumps`: `off` (default), `next_start`, `always`.
- When on, write `native-loader/remix/diagnostics.conf`:

  ```
  dxvk.enableAftermath = True
  dxvk.enableAftermathResourceTracking = True
  rtx.enableGpuCrashState = True
  ```

  listed after the package's copies (these keys are read from the merged config, where the last file
  wins; `rtx.enableGpuCrashState` is read at start through the same path, `src/dxvk/dxvk_options.cpp:36-39`;
  verify which layer kind applies and split the file if the two key families need different slots).
  Set `DXVK_AFTERMATH_DUMP_PATH` for the game process to the absolute path of `native-loader\logs\gpu\`
  (created; the runtime prefixes the file name with the path as given, `dxvk_instance.cpp:353-359`) and
  report it in `status.json` `activation.environment` like the other variables.
- `next_start` applies once: after applying it, the loader records that it was used (in
  `native-loader/state.json` or a small file the loader owns; never by rewriting the player's
  `config.json`) so the following start is normal; document how a player asks again.

## Tests, docs, limits

- Unit tests in `loader/tests` (the order of the list for each combination, tier classification,
  config parsing, the fallback, `next_start` once), and the activation integration test in
  `loader/proxy/tests` if it checks the variable.
- ADR 0062 (amends ADR 0030's placement; records the tiers and the switch); CHANGELOG; RESEARCH facts you
  had to dig for; `docs/ON_DISK_LAYOUT.md`; `docs/TESTING.md`.
- Do not create the tier layer files (T6 does) and do not touch `packages/`, `companion/`, `runtime/` or
  `tools/package_runtime.py`. Do not change the loader version.
- You may not launch the game. Report what an in-game check should look for (the effective option values
  the runtime prints in `remix-dxvk.log`).
