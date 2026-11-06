# build_runtime.ps1

Rebuilds the RTX Remix runtime's `d3d9.dll` from the fork's base commit and this repository's patches,
and stores it in `packages\runtime` ([runtime/README.md](README.md), [ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md),
[ADR 0034](../docs/decisions/0034-the-runtimes-build-inputs-recorded.md)).

```powershell
runtime\build_runtime.ps1 -Fork H:\BACKUP_20260815\Modding\dxvk-remix-gmod
runtime\build_runtime.ps1 -Fork <clone> -Worktree <existing patched tree> -NoImport
runtime\build_runtime.ps1 -Fork <clone> -Worktree <existing patched tree> -Verify
```

| Parameter | Meaning |
|---|---|
| `-Fork` | A clone of the fork named in [`base.json`](base.json). Only a worktree of it is created or built; its own checkouts are left alone |
| `-Worktree` | Where the patched tree is built. Default `<Fork>\.claude\worktrees\nl-runtime` |
| `-NoImport` | Build only; `packages\runtime` and `base.json` stay as they are |
| `-Jobs` | Maximum concurrent Ninja jobs (default 4), to bound C++ compiler memory use; the fork's shader helper retains its separate internal parallelism |
| `-Verify` | Only the checks of step 3, then the built `d3d9.dll`'s size and SHA-256; builds and writes nothing |
| `-Install` | R16: after compiling, `meson install --tags output` into `<Worktree>\_output` (`d3d9.dll`, the vendor DLLs, the USD plugins and their files), which the RTX package's workflow collects ([`tools/ci/collect_runtime.py`](../tools/ci/collect_runtime.py.md)) |

## What it does

1. Reads `base.json` and the patches in `runtime\patches` (name order), and checks that the clone has
   the base commit.
2. **No worktree yet:** `git worktree add --detach` at the base commit, `git am --3way --keep-cr` of
   every patch, `git submodule update --init --recursive --filter=blob:none` (network: the fork's submodules; since R16
   blobs only for the recorded commits, for the workflow's small disk), then what
   `base.json` adds: each `submodules` entry checked out at its `commit` and/or given its `patch`
   (`runtime\submodules\*.patch`, `git apply`), each of `clones` cloned from its `url`
   (`--filter=blob:none --no-checkout`) and checked out at its `commit` (network). After the source checks and `Enter-VsDevEnv`, first-time setup calls
   Meson directly through Python, without the fork helper's vswhere/PATH lookup:
   `python -m mesonbuild.mesonmain setup --buildtype release --backend ninja
   -Denable_tracy=false -Dremix_with_shim=false -Ddownload_apics=false <build> <tree>`.
3. **Checks, for a new worktree and an existing one alike:** what is checked out must be exactly what
   `base.json` and the patches describe (R3-014), or it stops and lists every difference:
   - the commit's tree is the tree the patches make, applied to the base commit in a scratch index
     (so a patch whose content changed under the same subject is noticed);
   - no uncommitted tracked change, and no untracked file or folder that is not one of `clones` (the
     build could read it);
   - every submodule at the commit the tree records, or at its `submodules` `commit`, without changes of
     its own; one with a `patch` holds exactly that patch (its files compared as a tree, again in a
     scratch index);
   - every clone at its `commit`, without changes.
   The scratch index and objects live under `out\tmp` and borrow the repository's objects, so the
   fork's repository is only read. Submodules inside submodules are left as the build has them: in a
   worktree some of their `.git` files point nowhere, which stops `git submodule status` itself.
4. An existing source tree must already have `_CompRelease_x64\meson-private\coredata.dat`;
   a missing or empty build folder stops before Meson can configure its Debug/download defaults.
   Enters the MSVC environment (`tools\lib\VsDevEnv.psm1`) and checks Meson's saved build options:
   Release, Ninja, optimization 3, `b_vscrt=from_buildtype` or `md`, Tracy/shim off and
   `download_apics=false`. Other settings stop the build before compilation or import. To configure
   a prepared tree explicitly, run `python -m mesonbuild.mesonmain setup --buildtype release
   --backend ninja -Denable_tracy=false -Dremix_with_shim=false -Ddownload_apics=false
   <tree>\_CompRelease_x64 <tree>` (dependencies must already be available for an offline build).
   Reconfigures an existing build so the fork's configure-time version string names the current
   source commit. A first-time setup needs no second configure or upstream build pass. Deletes the shader stamp
   `_CompRelease_x64\src\dxvk\_built_shaders.txt`, and runs `meson compile` **twice**: ninja rebuilds
   shaders only while the stamp is missing, and the C++ that embeds them notices the new headers only
   on the next run ([RESEARCH.md](../docs/RESEARCH.md) section 29).
5. Prints the size and SHA-256 of `_CompRelease_x64\src\d3d9\d3d9.dll` and, unless `-NoImport`, stores
   it as `files/d3d9.dll` of the runtime part (`tools\inputs.py import runtime --file`; an unchanged
   DLL is not stored again), and writes `packaged` in `base.json`: the DLL's SHA-256 and what it was
   built from (the commit, `submodules`, `clones` and every patch file's SHA-256).
   [`tools/check_repo.py`](../tools/check_repo.py.md) fails while `runtime\` differs from that record.

   R20-E permits explicitly hashed new `pending_patches` in `base.json` while integration waits for
   parallel runtime tasks. These are still included in the source verification and build above.
   An import clears `pending_patches` as it records every built patch; `-NoImport` leaves both the
   packaged and pending records intact. Existing packaged inputs cannot be exempted this way.

**Needs:** git, the fork's toolchain (Visual Studio 2022 Build Tools, Windows SDK, Meson, the Vulkan
SDK; see the fork's `.agents/skills/build-remix`), Python. **Writes:** the worktree and its build
folder in the fork clone; `packages\runtime\files\d3d9.dll.xz`, `packages\runtime\files.json` and
`runtime\base.json` here; scratch under `out\tmp`. **Exit:** 0 on success; a failed check, git
command or build stops it with an error.

Checked 2026-10-29 with `-Verify` against the fork worktree `remix-i18n` (branch `claude/sky-night`,
`f9937026`), which the packaged `d3d9.dll` (SHA-256 `d9cf79e6...`) was built in: it is what
`base.json` describes, and its built DLL is the packaged one. The check first found what the patches
alone left out (NVAPI R615, the RTXDI changes, the DLSS and SHARC clones; RESEARCH.md section 31),
which `base.json` now records. A build in a new worktree (step 2) needs the network and has not been
run since.

Checked again for R6 T4's second review (2026-10-31): the direct Python/Meson setup command above
configures a scratch folder under this worktree's `out/tmp` with all 95 saved build options equal
to the existing `_CompRelease_x64`. Only Meson's compiler probes run; no runtime target is compiled.
The scratch folder is deleted after comparison. The receipt is
`out/tmp/runtime-review2-setup-comparison.json`. Source worktree creation and dependency cloning
were not repeated; the check used the existing fully prepared clone and its offline SDK resolver.
