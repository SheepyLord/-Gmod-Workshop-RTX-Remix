# build_runtime.ps1

Rebuilds the RTX Remix runtime's `d3d9.dll` from the fork's base commit and this repository's patches,
and stores it in `packages\runtime` ([runtime/README.md](README.md), [ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)).

```powershell
runtime\build_runtime.ps1 -Fork H:\BACKUP_20260815\Modding\dxvk-remix-gmod
runtime\build_runtime.ps1 -Fork <clone> -Worktree <existing patched tree> -NoImport
```

| Parameter | Meaning |
|---|---|
| `-Fork` | A clone of the fork named in [`base.json`](base.json). Only a worktree of it is created or built; its own checkouts are left alone |
| `-Worktree` | Where the patched tree is built. Default `<Fork>\.claude\worktrees\nl-runtime` |
| `-NoImport` | Build only; `packages\runtime` stays as it is |

## What it does

1. Reads `base.json` and the patches in `runtime\patches` (name order), and checks that the clone has
   the base commit.
2. **No worktree yet:** `git worktree add --detach` at the base commit, `git am --3way --keep-cr` of
   every patch, `git submodule update --init --recursive` (network: the fork's submodules), and the
   fork's first-time setup, `build_dxvk.ps1 -BuildFlavour release -BuildSubDir _CompRelease_x64
   -Backend ninja -EnableTracy false`.
3. **A worktree there:** it must be the base plus exactly these patches, compared by commit subject in
   order (a long subject's folded header line is unfolded), and have no uncommitted tracked changes.
   Otherwise it stops.
4. Enters the MSVC environment (`tools\lib\VsDevEnv.psm1`), deletes the shader stamp
   `_CompRelease_x64\src\dxvk\_built_shaders.txt`, and runs `meson compile` **twice**: ninja rebuilds
   shaders only while the stamp is missing, and the C++ that embeds them notices the new headers only
   on the next run ([RESEARCH.md](../docs/RESEARCH.md) section 29).
5. Prints the size and SHA-256 of `_CompRelease_x64\src\d3d9\d3d9.dll` and, unless `-NoImport`, stores
   it as `files/d3d9.dll` of the runtime part (`tools\inputs.py import runtime --file`). An unchanged
   build stores nothing: the build is deterministic, and the import skips a file whose size and time
   match.

**Needs:** git, the fork's toolchain (Visual Studio 2022 Build Tools, Windows SDK, Meson, the Vulkan
SDK; see the fork's `.agents/skills/build-remix`), Python. **Writes:** the worktree and its build
folder in the fork clone; `packages\runtime\files\d3d9.dll.xz` and `packages\runtime\files.json` here.
**Exit:** 0 on success; a failed check, git command or build stops it with an error.

Checked 2026-10-30 against the fork worktree `remix-i18n` (branch `claude/sky-night`): the build gave
the packaged `d3d9.dll` (SHA-256 `d9cf79e6...`), and the import stored nothing.
