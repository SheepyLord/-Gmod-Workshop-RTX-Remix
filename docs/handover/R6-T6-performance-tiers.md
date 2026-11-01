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

## Status

### Earlier T6 sessions (2026-10-31)

The initial high/gm_construct baseline launched through `tools/poc_session.py` at 22:27:49 UTC.
It deployed generation 59 and initialized `remix-main+6f2dbd79` on the RTX 5090, then stopped at:

> Failed to initialize Steamworks API. Could not determine Steam client install directory.
> Make sure Steam is running and is up to date!

Evidence is in this worktree's ignored `out/t6-evidence/`: `startup-error-full.png`,
`sessions/session.json` and the copied Remix log. `session.json` has `map_loaded: false`, no
console/FPS/VRAM sample, exit 1. Steam discovery also needed an explicit client path for the
read-only depot verifier in that sandbox. All 2,877 depot files passed before the attempt;
`autoexec.cfg` was the one allowed user-config difference. This is session/environment evidence,
not a tier performance result. The owned blocked process was ended with the harness's
creation-time-checked `terminate` helper. No other process was ended, no Steam settings changed,
and the field install and every `user.conf` were untouched. Further launches stopped there.

Restoration: 2,808 files in the PoC's pre-existing loader/runtime, add-on, data and settings trees
were copied and hash-checked before the session, then restored and hash-checked afterwards.
The standard snapshot rollback restored bootstrap/root files/configs and shared settings:
`snapshot/rollback.json` reports `clean: true`, all 2,877 depot files matching. The prior allowlist,
generation and data were restored; changed trees were kept under `out/t6-evidence/trees-after/`.
No root `rtx.conf` was added for the high baseline.

On the earlier resumed attempt as the user, Steam was running and the sandbox limitation had
gone, but the field game was also running (reported PID 24620). It was left alone; the user was
asked to quit normally, and no PoC files changed. Probes/backups were prepared under `out/t6-live/`.
The earlier sandbox's registry/Git test failures were superseded by a successful user-account
`tools\test.ps1 -Config Release`: conventions, 23/23 CTests, Python groups 28/25/287 tests, two
expected skips, including 19 focused DDS/packager tests. No checks were skipped or altered to
pass, and no registry policy, ACL or global Git settings changed. Ten parts passed
`inputs.py verify --deep` and the actual combined package passed `--require-nlctl`. Logs:
`out/t6-release-resumed.log`, `out/t6-inputs-resumed.log`, `out/t6-package-resumed.log`;
the older failure log is `out/t6-release-tests.log`. That build had 1,013 payload files,
1,893,630,963 payload bytes and a 1,893,940,498-byte GMA.

The initial staged sources were under `out/t6-stage/`. Each sky was generated with
`python tools/sky/drop_top_mip.py out/inputs/runtime/files/atmosphere/<name>.dds
out/t6-stage/atmosphere/<name>_4096.dds`. The exact initial import was:

```powershell
python tools/inputs.py import runtime --file out/t6-stage/layers/medium.conf=layers/medium.conf --file out/t6-stage/layers/low.conf=layers/low.conf --file out/t6-stage/atmosphere/stars_4096.dds=files/atmosphere/stars_4096.dds --file out/t6-stage/atmosphere/galaxy_4096.dds=files/atmosphere/galaxy_4096.dds --file out/t6-stage/atmosphere/nebula_4096.dds=files/atmosphere/nebula_4096.dds
```

### Independent-review fix pass

The PM's fix-pass instruction supersedes the game-launch allowance above: **never launch GMod**;
the PM will run PoC measurements later. No game/install/user settings are touched in this pass.
Work stays on `r6-t6-tiers`, after `319bac3` and `84e0f1a`, with scratch under its own `out/`.

Rechecked findings 1-8 against the read-only T4 runtime snapshot
`29546f3566a676a1318b799fb8ddd01b2a110058`. Corrected the OMM/NRC/low-memory comments, credited
the smaller skies, pinned source option validation and expanded DDS format fixtures. The all-conf
scan parses classic/compiler too, but pins their bytes unchanged: classic has 15 obsolete keys
absent from this runtime. These are not claimed as valid options in the tier table, preserving
the brief's immutable high tier.

BLAS build-flag flips are guarded and rebuild safely; the source references and class-limited
low on cards above 8 GiB are recorded in ADR 0064 and RESEARCH. Medium keeps original skies:
at native 4K, horizontal FOV 90 degrees and zero bias, the nebula still samples original mip 0
(LOD 0.44), despite the stars/galaxy using retained levels. All tier values remain candidates.

Only these staged text inputs are re-imported; no DDS/DLL/xz input changes:

```powershell
python tools/inputs.py import runtime --file out/t6-fix-stage/layers/low.conf=layers/low.conf --file out/t6-fix-stage/layers/medium.conf=layers/medium.conf --file out/t6-fix-stage/atmosphere/CREDITS.txt=files/atmosphere/CREDITS.txt
```

Validation passed:

- The 23 focused packager/DDS/tier tests (`out/t6-fix-focused.log`). The DDS table exercises all
  30 accepted format variants, including correct 8/16-byte blocks and both linear sizes.
- `python tools/inputs.py verify --deep`: ten parts, zero problems (`out/t6-fix-inputs.log`).
- `python tools/build_package.py --require-nlctl --keep-work`: accepted by this worktree's Release
  `nlctl.exe` (`out/t6-fix-package.log`), 1,013 files, 1,893,941,161-byte GMA, content digest
  `68d5db6643e04392210dba8c9c5992862642bd6679d1c0ad3fd733e9625a5348`. Inspection of its runtime
  manifest confirms both conditional tiers, all three compact skies, updated credits and only
  classic/compiler unconditional layers.
- `tools\test.ps1 -Config Release`: conventions, 23/23 CTests and Python groups 28/25/291 pass
  (two expected skips; `out/t6-fix-release.log`). No tests disabled or altered to conceal failures.
- The input-index diff is exactly the three text files above, each stored plain; every binary
  entry and classic/compiler/sky hash is unchanged (`out/t6-fix-scope.log`). `git diff --check`
  and the final conventions check pass.

Not done: PoC frame-time/VRAM/visual measurements and tuning changes to class-limited low or
medium's skies, deferred to the PM as instructed. No pushes, merges, tags, main commits, Workshop
uploads, downloads, game launches, external-fork edits or game/install/user-setting writes.

### PM measurements (2026-10-31)

Claude measured the tiers in the R6 integration on the PoC (loader 0.11.0, 4K, RTX 5090): medium and
low run 5-9 % faster than high and use 170-750 MiB less VRAM; low's candidate 4 bounces measured no
faster than 8, so low now uses 8. Numbers and method are in
[ADR 0064](../decisions/0064-performance-tier-defaults.md#poc-measurements-2026-10-31); the evidence is
in the main checkout's `out/qa-poc/r6/tiers`, `tiers-pinned` and `shots`.
