# build_modules.ps1

Builds the RTX package's native modules that come from other repositories (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)), from the sources and commits in
[`pins.json`](pins.json): the RTX fixes' `gmcl_RTXFixesBinary_win64.dll` and `gmcl_rtxwater_win64.dll`,
the debug module `gmcl_rtxdebug_win64.dll`, and the Advanced Material Editor's
`gmcl_advmat_rtx_bridge_win64.dll`. GitHub's package workflow runs it in its `modules` job.

```powershell
tools\ci\build_modules.ps1 [-RunUrl <run>]
tools\ci\build_modules.ps1 -FixesClone <fixes clone> -GmodCommon <garrysmod_common checkout> -Premake <premake5.exe>
tools\ci\build_modules.ps1 -Only advmat -Out out\ci\built-advmat
```

| Parameter | Meaning |
|---|---|
| `-Out` | Where the modules go, as `<part>\<path in the part>` (default `out\ci\built`) |
| `-Work` | Checkouts and builds (default `out\ci\work`); `TEMP`/`TMP` point to its `tmp` |
| `-FixesClone` | A local clone of the fixes fork: borrowed with `git clone --shared` (that repository is only read). Default: cloned from GitHub |
| `-GmodCommon` | A garrysmod_common checkout at the pinned commit with its submodules. Default: cloned (blobs only for what is checked out) |
| `-Premake` | A premake5.exe 5.0.0-beta2. Default: the official archive, downloaded and checked against its SHA-256 |
| `-RunUrl` | Recorded with each module |
| `-Only` | `fixes`, `rtxwater`, `rtxdebug`, `advmat` (default all) |
| `-VCToolsVersion`, `-WindowsSdk` | MSVC toolset and Windows SDK of the recorded builds (14.44.35207, 10.0.26100.0) |

## What it does

1. Checks premake's version and that garrysmod_common and each of its submodules is at its pin.
2. **The fixes:** a sparse checkout (`/.gitattributes`, `/premake5.lua`, `/public/`, `/source/`) of the
   public base commit; the patches (`fixes.patches`, six since R20-E) are applied to the index
   (`git apply --cached`, limited to `source/*`, `premake5.lua` and `public/*`), and the files are written
   from it. The patched native tree must be the recorded one, everywhere: `git write-tree` stores the
   index as a tree (in that checkout only) and the object id of each path in `fixes.patched_tree`
   (`source`, `public`, `premake5.lua`) must match; no pushed commit is needed (R19; the first four
   patches give the tree of the unpushed `913bb6b`). premake (`--os=windows --gmcommon=<gmc> vs2022`), then
   MSBuild `gmcl_RTXFixesBinary.vcxproj` `ReleaseWithSymbols`/x64, the configuration the shipped module
   was built with.
3. **RTX Water:** `source/rtx_water` restored from its pinned commit (native Version 4; the base has
   Version 5), then its own patches (`fixes.rtxwater_patches`, index first, limited to
   `source/rtx_water/*`); `source/rtx_water` must have the object id in `fixes.rtxwater_tree`. premake
   again, MSBuild `gmcl_rtxwater.vcxproj` Release/x64.
4. **The debug module:** a copy of `packages/fixes/licenses/rtxdebug/checkout`, premake with
   `--remixinclude=<fixes>/public/include`, MSBuild of the solution's `gmcl_rtxdebug` Release/x64. Under a
   path with `!` (this machine's repository path) the pinned generator writes a wrong absolute IntDir: the
   helper libraries are built first, then the module with `BuildProjectReferences=false` and a relative
   `IntDir` (as `Source.md` there records).
5. **The bridge:** CMake (Visual Studio 17 2022, x64) of
   `packages/advanced-material-editor/source/rtx_bridge` with `ADVMAT_RTX_BUILD_GMOD_MODULE=ON` and its
   tests, Release build, then its tests. They run with a short `TEMP` (the runner's, or this
   repository's `out\t`):
   the writer test fails once `TEMP` is longer than about 75 characters (RESEARCH.md, R16).
6. Copies each module to `-Out` and writes `provenance-modules.json`: for each module's SHA-256 its part,
   path, repository, commit (and patches), how it was built and the run.

Native tools' stderr is passed on as text and only the exit code decides (Windows PowerShell would stop
at git's first warning). **Needs:** git, Visual Studio 2022 (MSBuild, MSVC 14.44, Windows SDK
10.0.26100.0, CMake), network unless local copies are given. **Writes:** `-Work` and `-Out`; and with
`-GmodCommon`, garrysmod_common's own helper projects (`helpers`, `helpers_extended`, `lua_shared`), which
premake generates and MSBuild builds inside that checkout's git-ignored `projects\` folder. To leave a
checkout untouched, omit `-GmodCommon`: the script then clones garrysmod_common into `-Work`.
`-FixesClone` is only read: a `--shared` clone keeps its new objects, the written trees too, to itself.
When it writes an object the clone it borrows from already has (`git write-tree` on the patched index
does), git refreshes the time of that clone's pack file instead; no content changes.
**Exit:** 0 when every asked module is built; a failed step stops it with an error.

Checked 2026-11-04 on this machine with the local fixes clone, garrysmod_common and premake: all four
built, each the size of the shipped file (5,491,712; 274,944; 428,032; 316,416 bytes); the patched
native tree equals `913bb6b`.

Checked 2026-11-05 (R19, `-Only fixes,rtxwater`, the local fixes clone and garrysmod_common, premake
downloaded and checked): both recorded trees matched; `gmcl_RTXFixesBinary_win64.dll` 5,512,192 bytes,
SHA-256 `ba3fb505...4a0da`; `gmcl_rtxwater_win64.dll` 281,088 bytes, SHA-256 `970f9dbd...fe5a9`.
