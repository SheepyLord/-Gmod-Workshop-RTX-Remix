# runtime/

R13-B adds six patches ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md),
[report](../docs/handover/R13-B-report.md)):

- `0023-Log-host-memory-by-memory-type-mapping-and-purpose-i.patch`: the opt-in census
  (`rtx.profiler.memory.requestSnapshot`) also writes `[RTX Host Memory]` rows, with or without the
  memory profiler: each memory type's chunks and dedicated allocations, the address range of each
  host-visible memory object, the process counters and the committed address space by protection with
  the part DXVK's mappings cover. Allocation groups gain the memory flags they received, whether the
  application released the image while the renderer holds it, and the allocation's name.
  [host_memory_census.py](../tools/qa/host_memory_census.py.md) reads them.
- `0024-Keep-one-copy-of-managed-GMod-textures-and-release-i.patch`: for patch 0022's class (static
  managed 2D textures), `d3d9.releaseManagedHostCopies` (`DXVK_RELEASE_MANAGED_HOST_COPIES`; Auto, the
  gmod.exe default, is on below 28 GiB of RAM or 15 GiB of VRAM) frees a texture's CPU copy once its
  image holds the data and it was not locked for 10 presented seconds; a later lock reads it back
  first. `d3d9.managedTextureBudgetMiB` (`DXVK_MANAGED_TEXTURE_BUDGET_MIB`; -1, the gmod.exe default,
  is VRAM / 4; 0 off) releases images not drawn for 60 presented seconds, least recently used first,
  while the class holds more than the budget; the data stays (read back first when needed), the next
  use uploads it again with the same hash, and Remix frees a released image once no instance samples it.
  Other games keep both off. The resolved values are logged at startup; `[RTX Managed Textures]` lines
  report the passes and the CPU copy bytes. Policy and unit test: `src/d3d9/d3d9_managed_memory.h`,
  `test_managed_texture_memory`. The texture copy buffers are named `d3d9 texture copy`.
- `0025-Let-replacement-textures-give-way-under-real-VRAM-pr.patch`: under real pressure (within 2 %,
  at least 256 MiB, of the driver's live budget, or over it) the replacement texture budget stops growing
  or gives back the overflow plus that margin, whatever the configured percentage or fixed budget; with
  the margin free nothing changes. `[RTX Texture Budget]` lines report it. Rule and unit test:
  `src/dxvk/rtx_render/rtx_texture_budget.h`, `test_texture_budget_pressure`.
- `0026-Let-undrawn-preloaded-material-textures-give-way-und.patch`: a USD material's
  `preload_textures` pins its textures at every mip from the moment the mod loads, and the budget (with
  patch 0025's cap) never touches pinned textures. Under the same real pressure, a preloaded texture no
  instance has drawn for 10 seconds now gives way and drops to its smallest mip; when an instance draws
  it again it is pinned and loaded whole again. Under pressure the streamed textures also get 0025's
  limit less what pinned ones hold. While memory is free nothing changes; dome lights, textures too
  large to stream and `rtx.texturemanager.neverDowngradeTextures` stay pinned. `[RTX Texture Budget]`
  lines report the pinned bytes and count the releases and restores. Rules and unit test:
  `preloadPinChange` and `streamedTextureLimitMib` in `rtx_texture_budget.h`,
  `test_texture_budget_pressure`. For tests, `DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB` caps the budget
  these rules see (a warning in the log when set); on a large card WDDM pages a background process's
  memory before it lowers the game's budget, so real pressure is hard to make there.
- `0027-Count-what-creates-deferred-managed-GMod-texture-ima.patch`: the `[RTX Managed Textures]` line
  counts the deferred images (and bytes) that sampling, a view, a flushed upload, `PreLoad` and a
  draw's upload created, so a burst shows which call made it. Diagnostics only.
- `0028-Fix-a-hash-race-baker-sources-and-unmarked-writes-of.patch`: the review's fixes. A
  memory-managed texture keeps its hash in an atomic that the hash API and `GetStableHash` read, so a
  caller on another thread (ToPBR from Lua) never races the image release; a texture tracked through
  `addTexture` in the last frames counts as in use, so the terrain baker's preloaded sources do not give
  way; a writable lock with `D3DLOCK_NO_DIRTY_UPDATE` keeps the CPU copy for good; and with neither
  option on (other games) the once-a-second pass and its log do not run. Unit checks in
  `test_managed_texture_memory` and `test_texture_budget_pressure`.

The [GPU probe](../tools/qa/build_managed_texture_probe.ps1.md)'s `r13` sequence proves exact pixels and
hashes through upload, released copies, read-back locks, a rewrite, image release, re-upload and a
device reset, against the original runtime.

R12-C patch `0022-Allocate-unused-managed-GMod-textures-only-on-GPU-us.patch` defers GPU backing
for unused static 2D managed GMod textures ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
The model catalog and CPU buffers remain ready; sampling, upload or `PreLoad` creates the original
image without changing its format/mips/hash. `d3d9.deferManagedTextures` defaults on for `gmod.exe`
only, with an explicit config or `DXVK_DEFER_MANAGED_TEXTURES` override. Other pools/types/usages,
conversion formats and `evictManagedOnUnlock` keep their existing paths. The shared initializer
preserves zero contents and queues a deferred clear before the upload on the same command stream.
The [GPU probe](../tools/qa/build_managed_texture_probe.ps1.md) compares allocation, exact pixels,
LOD, partial writes and original/new texture hashes. See the [R12-C report](../docs/handover/R12-C-report.md).

R12-C adds `0021-Log-opt-in-allocation-census-with-D3D9-size-format-a.patch`
([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
Enable the existing memory profiler at process launch with `RTX_PROFILER_MEMORY_ENABLE=1`, then
request `rtx.profiler.memory.requestSnapshot = True` through the Remix API. On the next present it
resets that NoSave request and logs `[RTX Allocation]` begin/group/end JSON rows, with actual live
allocation slices grouped by category/type/locality, dimensions, Vulkan format and D3D9
pool/format/mip count (primary and resolve images). Pool `-1` means unavailable. It keeps images
still held by the renderer visible after the application's D3D9 texture is released. The registry
copy/update lock protects diagnostic metadata; grouping and log I/O happen after releasing it.
No hashes, resource contents or allocation/eviction policy change. The ordinary profiler remains
disabled. See [the parser](../tools/vram_census.py.md) and [Source probe](../tools/qa/vram_probe.lua.md).

R10-E adds `0019-Keep-imported-eye-white-emission-on-isolated-surface.patch`
([ADR 0088](../docs/decisions/0088-imported-character-eye-whites.md)). NoSave proxy/original texture
aliases isolate automatic emission to named eye-white surfaces; original PBR replacements retain
precedence. A NoSave brightness multiplier scales automatic and C-16 authored adaptive emission
through the existing luminance helper, preserving the saved adaptive scale. Its runtime unit test
covers alias validation, isolation, material inputs, C-16 normalization, brightness and option
lifetime/invalidation. R10-E builds with `-NoImport`; the committed packaged record intentionally
remains at patches 0001–0018 until Claude imports the reviewed DLL.

The new source files in 0019 are `src/dxvk/rtx_render/rtx_eye_whites.h` (strict aliases,
revisioned snapshots and automatic material inputs) and `tests/rtx/unit/test_eye_whites.cpp`.
Existing D3D9/external category snapshots preserve original atlas alpha/normal tags for proxy draws.

This repository's changes to the RTX Remix runtime ([ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)).
The runtime is the GMod fork of NVIDIA's DXVK-Remix, `sambow23/dxvk-remix-gmod`. Its source, with
NVIDIA's SDKs, is about 3.6 GB and keeps its own history, so this repository holds:

- [`base.json`](base.json): the fork's commit the patches apply to (`gmod-numos3` at `c6b48ed1`); what
  else the build has that the fork's tree does not record ([ADR 0034](../docs/decisions/0034-the-runtimes-build-inputs-recorded.md),
  [RESEARCH.md](../docs/RESEARCH.md) section 31): `submodules` built at another commit or with a patch
  (NVAPI R615; RTXDI with the fork's uncommitted changes) and `clones` the build reads (the DLSS SDK,
  SHARC); and `packaged`, the SHA-256 of the `d3d9.dll` the RTX package ships with what it was built
  from, which [`tools/check_repo.py`](../tools/check_repo.py.md) holds `runtime/` to;
- [`submodules/`](submodules): patches of submodules (`git diff HEAD --binary --full-index` in the
  submodule), named by `base.json`;
- [`patches/`](patches): this project's commits on top of it, as `git format-patch` files, applied in
  name order:

| Patch | What |
|---|---|
| `0001-Snapshot-...` | The fork's `gmod-1.6.1` working tree during its remix-1.6.1 merge, which the rest was built on |
| `0002-Translate-the-Remix-menus-...` | The Remix menus (Alt+X) in zh-CN, zh-TW, ja, ko, fr and ru ([RESEARCH.md](../docs/RESEARCH.md) section 25) |
| `0003-i18n-the-translators-glossaries` | The translators' glossaries |
| `0004-Atmosphere-...` | The real Moon, the night sky image, lunar and solar eclipses, and `dxvk.numCompilerThreads < 0` ([ADR 0032](../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md), RESEARCH.md section 29) |
| `0005-i18n-...` | Complete weather display translations and formatted status, clearer cache names, strict catalog checks and tests; dependency setup tolerates `!` in paths |
| `0006-i18n-...` | Static translated migration buttons with separately formatted counts; regression coverage for both migration directions |
| `0007-Keep-view-models-...` | First-person arms/weapons remain enabled independently of primary-space player bodies ([ADR 0043](../docs/decisions/0043-player-body-viewmodel-and-shadows.md)) |
| `0008-Save-Remix-config-...` | Atomic checked config saves; failed saves retain their baseline/unsaved state and failed reloads retain live values ([ADR 0044](../docs/decisions/0044-remix-settings-persistence.md)) |
| `0009-Default-diagnostics-...` | Explicit saved diagnostic consent, legacy SDK archival, twelve-second welcome timeout and permanent dismissal ([ADR 0045](../docs/decisions/0045-diagnostic-consent-and-welcome.md)) |
| `0010-Resolve-layered-alpha-...` | Reject cutouts during ray traversal in query/trace/PSR/indirect paths, refresh cached opacity flags, and ignore incompatible outline meshes ([ADR 0047](../docs/decisions/0047-ignore-incompatible-model-outlines.md), [ADR 0048](../docs/decisions/0048-layered-alpha-cutouts.md)) |
| `0011-Keep-imported-model-...` | Join transient imported-model smooth-normal tags with the saved set on D3D9, cached-draw and external submission paths ([ADR 0049](../docs/decisions/0049-importer-normals-material-labels-and-motion-access.md)) |
| `0012-Read-localized-project-...` | Load bounded editable startup templates and their font glyphs; point launch text to this repository ([ADR 0050](../docs/decisions/0050-startup-text-and-main-menu-diagnostics.md)) |
| `0013-Default-to-minimum-...` | Default path bounces to 1/12 consistently across graphics presets and option metadata ([ADR 0051](../docs/decisions/0051-path-bounce-defaults.md)) |
| `0014-Never-save-over-unread-...` | A missing user.conf/rtx.conf reloads as empty, so Discard Changes works on a fresh profile; a file that exists but could not be read blocks Save, export and the diagnostic choices until it is read; saves retry briefly held files, rewrite links in place and show failures; the outline rule spares view models, mirrored geometry and replacements with their own culling ([ADR 0044](../docs/decisions/0044-remix-settings-persistence.md), [ADR 0047](../docs/decisions/0047-ignore-incompatible-model-outlines.md)) |
| `0015-Record-GPU-memory-...` | Share the bounded VRAM collector with heap locality, driver totals and category snapshots at cuts, five-minute intervals and device loss; log the escaped queue reason first, then flush/replace `last_gpu_crash.json` through a per-process temporary with two brief retries, before the crash recorder, Aftermath and Sentry; rate-limit OMM warnings, report free VRAM/previous budget/use/thresholds at a budget drop and preserve pending counts at loss; record the six test sources omitted from the fork snapshot, without silent guards ([ADR 0065](../docs/decisions/0065-runtime-memory-diagnostics.md)) |
| `0017-Apply-scoped-MMD-alpha-...` | Join saved and transient Model Hotloader texture tags, use an exact default-0.5 cutout reference, and promote blended coverage at the cutoff in shared ray/OMM evaluation; include cutoff/category in OMM identity and material-history invalidation ([ADR 0081](../docs/decisions/0081-mmd-alpha-texture-category.md)) |
| `0018-Keep-denoiser-history-...` | Mark an instance's material as changed for the MMD alpha rule only between the first draws of consecutive frames, never for a new instance; patch 0017 compared the merged in-frame state and discarded tagged characters' denoiser history every frame (R8) |
| `0020-Rank-generated-fallback-mods-...` | Mods named in `rtx.gmod.fallbackMods` (default `~gmod_topbr`, the fixes' ToPBR output) get priority 1: every authored mod wins over them for materials, meshes and lights whatever its folder name, also when it loads or reloads later, and their search paths come first ([ADR 0092](../docs/decisions/0092-generated-fallback-mods-rank-last.md)) |
| `0021-Log-opt-in-allocation-census-...` | The opt-in allocation census with D3D9 size, format and pool ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)) |
| `0022-Allocate-unused-managed-GMod-...` | Static managed GMod textures get GPU memory only on first use ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)) |
| `0023-Log-host-memory-by-memory-type-...` | The census also accounts host memory: memory types, host mappings, the process and its address space ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0024-Keep-one-copy-of-managed-GMod-...` | One copy of each static managed texture, and idle images released over a budget; automatic for gmod.exe ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0025-Let-replacement-textures-give-way-...` | Replacement textures stop growing near the driver's live budget and give back the overflow over it ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0026-Let-undrawn-preloaded-material-textures-...` | Under the same pressure, preloaded material textures no instance draws drop to their smallest mip, and are preloaded again when drawn ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0027-Count-what-creates-deferred-...` | The managed texture log counts what created each deferred image: sampling, a view, a flushed upload, `PreLoad`, a draw ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0028-Fix-a-hash-race-baker-sources-...` | The review's fixes of 0024 and 0026: an atomic stable hash for the API, the terrain baker's sources count as in use, `D3DLOCK_NO_DIRTY_UPDATE` keeps the CPU copy, no pass in other games ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |

- [`build_runtime.ps1`](build_runtime.ps1.md): applies them in a worktree of a fork clone, builds, and
  stores the new `d3d9.dll` in [`packages/runtime`](../packages/README.md).

Patch `0016-Add-scene-adaptive-opaque-emission` adds optional `emissive_adaptive_intensity`
([ADR 0067](../docs/decisions/0067-scene-adaptive-emission.md)). The geometric-mean scene Yf and
paired exposure use a three-slot, nonblocking readback ring (eligible after two frames), then the
shared raytracing constants. The half-float material input occupies the unused high subsurface-index
byte and constant DLSS-alpha byte; the 64-byte material record stays unchanged, and input zero
preserves its previous bytes. Both opaque and Source-eye evaluation use the new intensity helper;
already evaluated interactions keep their radiance. Texture preload preserves the new USD value;
public API materials and baked terrain retain a zero adaptive input.

The feature defaults on for positive inputs; `rtx.adaptiveEmission.scale` defaults to 1,
`minLuminance` to 0, `maxLuminance` to 64, and `fallbackLuminance` to 0.18. Fallback is used when
auto exposure is off or before a completed readback exists. The zero lower clamp permits fading
in darkness. `[RTX Adaptive Emission]` logs the raw Yf, paired exposure, effective luminance,
sample frame/age, scale and enablement at cuts and five-minute intervals. These are the real
geometric mean and smoothed exposure; transition brightness is still affected by exposure's
0.15/0.75-second integrator. The combined package's only `AperturePBR_Opacity.mdl` lives in the fixes
part's breakable-glass assets, and declares the input with default 0 and range 0..65504; the runtime
part itself has no MDL. Its MDL preview retains fixed emission.

The built runtime itself, `d3d9.dll` and NVIDIA's DLLs, lives in `packages\runtime\files` (Git LFS), so
building the RTX package needs neither the fork nor its SDKs. Only a change to the runtime does.

## Changing the runtime

R7-A's branch build is deliberately **not imported**: the task forbids package edits.
Its new DLL, source identity, additional USD schema resource and test/provenance gate status are
recorded in the [R7-A report](../docs/handover/R7-A-report.md). Until Claude imports it during
integration (or separately approves unimported-build validation), the existing repository
provenance convention rejects patch 0017 against the older `packaged` record.

1. Make the change in the fork worktree `build_runtime.ps1` uses (or any tree at `base.json`'s commit
   with the patches applied), and commit it there.
2. Export the series again into `patches\`, replacing the old files:
   `git -C <worktree> format-patch --binary --no-signature --zero-commit -o <this repo>\runtime\patches <base commit>..HEAD`
3. `runtime\build_runtime.ps1 -Fork <clone>`: it checks that the worktree is exactly what `base.json`
   and these patches describe, builds, imports `d3d9.dll` and writes `packaged` in `base.json`. Then
   build the package (`tools\build_package.py`), test it in the PoC, and commit on a branch. Until the
   DLL is built and stored again, `tools\test.ps1` fails on a changed patch.

An existing source tree needs a configured Release/Ninja build with optimization 3, the release DLL
CRT, Tracy/shim off and `download_apics=false`. A missing `meson-private/coredata.dat` or mismatched
saved options stop the wrapper before setup, compilation or import. A newly created source worktree
is configured once with those settings through `python -m mesonbuild.mesonmain setup`, after
`Enter-VsDevEnv`; its first setup does not compile runtime targets before the wrapper's two shader
passes. See [the build script's instructions](build_runtime.ps1.md) for explicit offline setup.

A new base (the fork moved on): rebase the series there, export it again, set `commit` in
`base.json`, and rebuild. NVIDIA's DLLs change only with the fork's SDKs; import those from the fork
build's `_output` folder with `tools\inputs.py import runtime --root "<_output>=files"` (without
`--prune`, which would drop `files\atmosphere`).

## R6 T4 rebuild (2026-10-31)

- Source: base `c6b48ed1` plus patches 0001-0015; second-review fix commit
  `024a98665149e628db827cd0f9ce142828c14701` in the isolated `out/runtime-src` clone;
  verified tree `d6516436af1cabf354059b1ba4a8841550236eee`.
- Build: x64 Release, MSVC 19.44.35228, Meson 1.12.1, Ninja with four jobs, Tracy/shim off and
  `download_apics=false`. `build_runtime.ps1 -Fork <own clone> -Worktree <own clone>` reconfigured
  and ran both compile passes once with all review fixes. Saved Meson options and the diagnostics
  compile command verify optimization 3 and `/MD /O2 /DNDEBUG`. The DLL labels itself
  `remix-main+024a9866`.
- `d3d9.dll`: 395,540,480 bytes, SHA-256
  `c40f28e4371f7525dce01afad7316ae3efeabb2099c7ec19fe1df5dc3706ac19`.
  `base.json` records its source/patch hashes. The two shipped USD plugin DLLs are byte-identical
  to the existing inputs and were not imported again; only the changed DLL consumes new LFS storage
  (58,336,968 bytes compressed).
- No downloads: the already prepared clone has the recorded submodules/clones. SDK junctions point
  only to the declared versions in `H:/packman-repo/chk`. A process-local
  `PM_MODULE_DIR_EXT=out/tmp/offline-packman` resolver validates every package/link instead of
  invoking Packman's network/bootstrap code. Its Python and the compiler were already installed.
- The dedicated `_CompUnitTest_x64` build passes all 27 tests, including `test_memory_diagnostics`
  with a stale fixture. Patch 0015 now records the five omitted unit sources and the medium API app
  byte-for-byte from the user's staged fork index, without guards. All six compile; the five unit
  sources run in the suite. The medium API app is a separate GPU app and was not launched.
  Unit dependency staging used literal-path
  PowerShell copies because the upstream install batch helpers strip `!` from paths.
- `inputs.py verify --part runtime --deep`: zero problems. The combined package passes this
  worktree's `nlctl` validation: 1,008 files, digest
  `90d6fa1ae7206eea8eb4a0170ce5ccd8a5c22df3d532701eb2faf151895f9961`.
  No game session or GPU-loss trigger was run; see [TESTING.md](../docs/TESTING.md#r6-t4-runtime-memory-diagnostics).
- Repository Release validation: 23/23 CTests and 333 Python tests (two skips). The known guard
  cache-path limitation needs only that unchanged test executable copied to `out/tmp`; the local
  wrapper temporarily redirects its generated CTest command and restores it after the run.
  No loader/test source changed. The whole-worktree drive alias was removed.

The second review's configure-only scratch setup matches all 95 saved Release options and was
deleted after comparison. Its dedicated diagnostics test checks the five nonzero OMM counters,
reason escaping, PID-specific temporary files, two 10 ms sharing retries, preservation of the old
marker and cleanup after replacement failure. T2's integration reader ignores the additional fields;
see [RESEARCH.md](../docs/RESEARCH.md#r6-t4-runtime-memory-snapshots-2026-10-31).

Exact second-review import from this worktree (invoked by `build_runtime.ps1`):

```powershell
python tools/inputs.py import runtime --file 'out/runtime-src/_CompRelease_x64/src/d3d9/d3d9.dll=files/d3d9.dll'
```

Local second-review receipts are under `out/tmp`, prefixed `runtime-review2-`: `build.log`,
`verify-before.log`, `setup.log`, `setup-comparison.json`, `release-config.json`,
`recorded-sources.json`, `diagnostics-build.log`, `diagnostics-tests.log`, `unit-build.log`,
`unit-tests.log`, `unit-summary.json`, `verify.log`, `import.json`, `inputs-verify.log`, `package-build.log`,
`release-tests.log`, `release-summary.json` and `test-short-guard.ps1`. The first review's receipts retain the
`runtime-review-` prefix.

## C-16 rebuild (2026-10-31)

The isolated source commit is `8a5df5d8ef2e4529f20f7c07c195cb6dc3588afe`, tree
`1a6009a44590fe673282b7ceecf759548df646b8`: base `c6b48ed1` plus patches 0001-0016.
The completed build uses x64 Release, MSVC 19.44.35228, Meson 1.12.1, Ninja with four jobs,
optimization 3, the release DLL CRT, Tracy/shim off and `download_apics=false`.
Build identity: `remix-main+8a5df5d8`. The DLL is 396,802,048 bytes, SHA-256
`9906eec639b8768baf468daebb2f281c45f04754eaaf6cd60c0c5f7c883cc543`.

The R6 source, git metadata, configured builds and local dependency bytes were copied under this
worktree's `out/runtime-src`; thirty SDK junctions resolve to the already installed Packman
versions. Both saved Meson configurations and 694 shader dependency files in each were relocated
to this copy. When reusing another configured tree, relocate the shader `.d` paths too: their
timestamp checks otherwise keep following the old includes even after the shader stamp is removed.
The process-local offline resolver from R6 validates existing SDK links and cannot download.

`build_runtime.ps1` runs its source/configuration checks, reconfigures the version, and completes
both compile passes. `out/tmp/c16-runtime-build.log` records real shader compilation.
`out/tmp/c16-embedded-shaders.json` confirms the newly compiled auto-exposure and opaque G-buffer
SPIR-V are embedded in the DLL. The dedicated unit configuration passes all 28 tests, including
`test_adaptive_emission` and the regenerated `RtxOptions.md` check. Game/GPU acceptance and
eye-white tuning remain with Claude; no game or install was touched.

Exact runtime import, invoked by `build_runtime.ps1` from this worktree:

```powershell
python tools/inputs.py import runtime --file 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\c16-runtime\out\runtime-src\_CompRelease_x64\src\d3d9\d3d9.dll=files/d3d9.dll'
```

The MDL declaration is the only other imported input (plain text):

```powershell
python tools/inputs.py import fixes --file 'out/c16-mdl/AperturePBR_Opacity.mdl=garrysmod/rtx-remix/mods/base_mod/breakable_glass/assets/remix_materials/AperturePBR_Opacity.mdl'
```

Local evidence is under `out/tmp/c16-*`: build/verification logs, saved Release options, shader
relocation and embedded-shader receipts, final runtime unit build/tests, MDL import, package and
repository checks. See [TESTING.md](../docs/TESTING.md#c-16-scene-adaptive-emission) for final gate
results and the project manager's GPU acceptance cases.

Final offline gates pass: exact source verification, deep input verification (zero problems),
the 1,023-file combined package's `--require-nlctl` validation, and plain
`tools/test.ps1 -Config Release` (24 CTests; 376 Python tests, two skips). The guard test needs no
path workaround here. Only the DLL's new 58,495,348-byte xz LFS object consumes binary storage.
