# The Model Hotloader's native source, for the GitHub build

The add-on's four native files in this part's `bin/` (`gmcl_mmdhl_win64.dll`, `gmsv_mmdhl_win64.dll`,
`mmdhl_runtime_win64.dll`, `mmdhl_worker.exe`) are built from `mmdhl/` on GitHub by the RTX package's
workflow (R16, ADR 0107), with the add-on's hash records for them (`native_policy.lua`,
`mmdhl-native-release.json`) regenerated in the same run, so the package carries no native file made on
a local machine. `lib_coacd.dll` is CoACD's own wheel build, which the workflow downloads (ADR 0106).

## Source identity

- Origin: https://github.com/SheepyLord/Gmod-Model-Hotloader-with-Vulkan (MIT), commit
  `ecd7c426c0b50fa3b92cb882059ac46842912f3a` ("Version 2.3.1"), **with the staged, uncommitted changes**
  of its author's worktree `wt-full-textures-props` (branch `feat/gravity-buoyancy-settings`): the
  buoyancy and secondary-water work (`SetSecondaryWater`, `SetSecondaryBuoyancy`, `secondaryGravity`)
  that the shipped 2.3.1 natives export and the packaged add-on uses. No commit holds those changes.
- The worktree had every change staged and none unstaged, and no source file there was newer than the
  shipped `gmcl_mmdhl_win64.dll` (2026-10-26 16:21:10 -0700): the files here are that index's blobs, the
  source of the shipped build (whose five native files were byte-identical to that worktree's
  `build\bin\Release`).
- `mmdhl/` holds what the native build reads: `CMakeLists.txt`, `dependencies.lock.json`, `native/`,
  `shaders/`, the C++ tests and fixtures in `tests/` (CMake declares those targets), the scripts the
  build runs (`scripts/bootstrap.py`, `patch-bullet-threading.py`, `native_manifest.py` with
  `compatibility_profiles.py`, `shaders.py`, `fixtures.py`, and the origin's `build.ps1` for its recipe),
  the licences of the dependencies (`licenses/`, `THIRD_PARTY.md`), `LICENSE` and `README.md`. Left out:
  the Lua add-on (this part ships it in `mmd_hotloader/`), the add-on's Python and Lua tests, the DXVK
  renderer and its patches (the package's runtime is Remix), documentation.
- `staged-changes.patch` is `git diff --cached` of the ten vendored files that differ from the commit;
  `provenance.json` lists every file's size, SHA-256 and git blob, those ten paths, and the shipped
  release record.

## Build

```powershell
python scripts/bootstrap.py               # the pinned dependencies (codeload.github.com archives, CoACD's wheel)
python scripts/patch-bullet-threading.py  # the add-on's documented Bullet patches
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target mmdhl_client mmdhl_server mmdhl_worker
python scripts/native_manifest.py --bin build/bin/Release --output <a copy of native_policy.lua>
```

`tools/ci/build_hotloader.ps1` runs exactly this. The build identity is `<12 digits of git HEAD>-<UTC
configure time>`: in this repository, HEAD is the commit of this repository being built.
