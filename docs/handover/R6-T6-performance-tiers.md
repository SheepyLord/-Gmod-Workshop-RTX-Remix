# R6 T6: performance tier values and the low tier's night sky

Read [R6-plan.md](R6-plan.md) first: its rules, decisions and interfaces bind this task. This task
answers the user's request: "currently the remix default setting is for the best consumer GPU
available, please find a way to turn the default settings to enhance performance and stability".
Background in [R5-stability-proposal.md](R5-stability-proposal.md) proposals 2 and 6 and section 2.
Branch `r6-t6-tiers`, worktree `out\worktrees\r6-t6-tiers`. ADR number 0064.

**You alone may run game sessions, on the PoC install only** (`tools\poc_session.py`, never
`--root` of the field install). Put back anything you change in the PoC (its root `rtx.conf`, its
`native-loader\config.json`, its data) when you are done, and say so in the report.

## 1. The tier layers (interface I1)

- The package's classic layer (`packages/runtime/layers/classic_remix_defaults.conf`, made by
  `tools/remix_defaults.py`; ADR 0020, 0021, 0037) is the `high` tier and stays as it is unless you
  find a setting that hurts stability on every GPU with no visible benefit; any such change needs a
  measurement and its own line in ADR 0064.
- Write `medium.conf` and `low.conf`: `rtx.*` keys only, each with a comment saying why. Candidates to
  measure (the classic layer's values first): `rtx.pathMaxBounces` 12 (our patch 0013 made 12 the
  default), `rtx.neuralRadianceCache.qualityPreset` 2 and its training settings,
  `rtx.skyProbeSide` 2048, `rtx.volumetrics.froxelGridResolutionScale` 4 / `froxelDepthSlices` 48,
  `rtx.restirGI.biasCorrectionMode` 4, `rtx.denoiseDirectAndIndirectLightingSeparately`,
  `rtx.di.enableDenoiserGradient`/`Confidence`, the opacity micromap cache
  (`rtx.opacityMicromap.cache.maxBudgetSizeMB`, `minFreeVidmemMBToNotAllocate`), `rtx.lowMemoryGpu`,
  `rtx.terrainBaker.cascadeMap.levelResolution`, texture manager budgets. Leave DLSS's upscaler and
  quality mode, frame generation (off, ADR 0037) and anything that changes which surfaces render
  (texture categories, anti-culling) alone unless measured as a stability problem.
- `low` must include proposal 2's values (the plan's fallback) and the night sky of section 2.
- Make them inputs of the runtime part: text files in `packages/runtime/layers/` (imported with
  `tools\inputs.py import runtime`), and teach `tools/package_runtime.py` (with its tests and `.md`) and
  `tools/workshop.json` to place them at `config/dxvk-tiers/medium.conf` and `low.conf` in the runtime
  package. Regenerate the package's file list as the packager does. No new manifest key or kind.

## 2. The low tier's night sky (proposal 6 b, interface I3)

- A tool in `tools/sky/` (with its `.md`) that writes a copy of a DDS without its top mip (header
  width/height halved, mip count minus one, the first mip's bytes dropped; no re-encoding), checked
  against the source's mip 1.
- Make `atmosphere/stars_4096.dds`, `galaxy_4096.dds` and `nebula_4096.dds` from the runtime part's
  8192 px files and import them into `packages/runtime` beside the originals (about 53 MB resident,
  12 MB more in Git LFS by the proposal's estimate: check). `low.conf` sets
  `rtx.atmosphere.starMapTexture`, `starMapGalaxyTexture` and `starMapNebulaTexture` to them; check how
  the runtime resolves those paths (the current defaults point at `atmosphere\...` beside `d3d9.dll`).

## 3. Measure (PoC)

- Until T1's loader exists, apply a tier by putting its lines in the PoC's root `rtx.conf` (the layer
  above the package's) for the run, and restore the file afterwards.
- For `high`, `medium` and `low`: frame time (`poc_session.py run --fps`), VRAM (`rtx_vram_stats` in the
  console, from the fixes module), on gm_construct and on modern_house
  (`--mount-workshop 3495468649 --change-map modern_house`), the same camera each time. Screenshots for
  the look; a night sky shot for `low` against `high`. This machine's GPU is high end: report relative
  differences and VRAM, which carry over.
- Put the numbers in ADR 0064 and RESEARCH.

## Tests, docs, limits

- `tools\test.ps1`; the package build (`python tools\build_package.py`); `inputs.py verify`.
- ADR 0064 (the tier values, what each costs and saves, what was measured and how); CHANGELOG; TESTING.
- Do not touch `loader/`, `companion/`, `runtime/`, or `packages/runtime`'s runtime binaries (T4).
  Never the field install.
