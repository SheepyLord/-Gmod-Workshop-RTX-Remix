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
| `0015-Record-GPU-memory-...` | Share the VRAM API's collector with heap/category snapshots at camera cuts, five-minute intervals and device loss; write a best-effort atomic `last_gpu_crash.json` before Sentry; rate-limit each OMM budget warning to once a minute with suppressed counts; guard optional fork tests whose sources are absent from the recorded tree ([ADR 0065](../docs/decisions/0065-runtime-memory-diagnostics.md)) |

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

A new base (the fork moved on): rebase the series there, export it again, set `commit` in
`base.json`, and rebuild. NVIDIA's DLLs change only with the fork's SDKs; import those from the fork
build's `_output` folder with `tools\inputs.py import runtime --root "<_output>=files"` (without
`--prune`, which would drop `files\atmosphere`).

## R6 T4 rebuild (2026-10-31)

- Source: base `c6b48ed1` plus patches 0001-0015; commit `86ac49e9` in the isolated
  `out/runtime-src` clone; verified tree `823db03a8f9c88835364d2916e4a8cc529813bab`.
- Build: x64 Release, MSVC 19.44, Meson 1.12.1, Ninja with four jobs, Tracy/shim off and
  `download_apics=false`. `build_runtime.ps1 -Fork <own clone> -Worktree <own clone>` reconfigured
  and ran both compile passes. The DLL labels itself `remix-main+86ac49e9`.
- `d3d9.dll`: 395,537,408 bytes, SHA-256
  `86983b5b51d4d758714fcf5d280129fac17924e89f0439fd75471c1ac1937cad`.
  `base.json` records its source/patch hashes. The two rebuilt shipped USD plugin DLLs were also
  imported; `packages/runtime/files.json` records all three hashes and their local source origins.
- No downloads: the already prepared clone has the recorded submodules/clones. SDK junctions point
  only to the declared versions in `H:/packman-repo/chk`. A process-local
  `PM_MODULE_DIR_EXT=out/tmp/offline-packman` resolver validates every package/link instead of
  invoking Packman's network/bootstrap code. Its Python and the compiler were already installed.
- The dedicated `_CompUnitTest_x64` build passes all 22 available tests, including the new
  `test_memory_diagnostics`. Five optional fork unit sources and one medium API source are absent
  from the recorded tree and guarded by patch 0015. Unit dependency staging used literal-path
  PowerShell copies because the upstream install batch helpers strip `!` from paths.
- `inputs.py verify --part runtime --deep`: zero problems. The combined package passes this
  worktree's `nlctl` validation: 1,008 files, digest
  `acf1b18cf13fa76c07e7e0b663991dcbbdd132c40b2c570674e02722b8dd8e30`.
  No game session or GPU-loss trigger was run; see [TESTING.md](../docs/TESTING.md#r6-t4-runtime-memory-diagnostics).

Exact imports from this worktree (the first is also what `build_runtime.ps1` invokes):

```powershell
python tools/inputs.py import runtime --file 'out/runtime-src/_CompRelease_x64/src/d3d9/d3d9.dll=files/d3d9.dll'
python tools/inputs.py import runtime --file 'out/runtime-src/_CompRelease_x64/src/usd-plugins/RemixCategories/RemixCategories.dll=files/usd/plugins/RemixCategories/RemixCategories.dll' --file 'out/runtime-src/_CompRelease_x64/src/usd-plugins/RemixParticleSystem/RemixParticleSystem.dll=files/usd/plugins/RemixParticleSystem/RemixParticleSystem.dll'
```

Local receipts are under `out/tmp`: `runtime-build-final.log`, `runtime-verify.log`,
`runtime-unit-build.log`, `runtime-unit-plugins.log`, `runtime-unit-tests.log`,
`runtime-plugin-import.log`, `runtime-inputs-verify.log`, and `package-build.log`.
