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
