# runtime/

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

- [`build_runtime.ps1`](build_runtime.ps1.md): applies them in a worktree of a fork clone, builds, and
  stores the new `d3d9.dll` in [`packages/runtime`](../packages/README.md).

The built runtime itself, `d3d9.dll` and NVIDIA's DLLs, lives in `packages\runtime\files` (Git LFS), so
building the RTX package needs neither the fork nor its SDKs. Only a change to the runtime does.

## Changing the runtime

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
