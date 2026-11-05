# build_hotloader.ps1

Builds the Model Hotloader's four native files from the source this repository keeps in
`packages/model-hotloader/source` (R16, [ADR 0107](../../docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)),
and regenerates the add-on's hash records for them. GitHub's package workflow runs it in its `hotloader`
job.

```powershell
tools\ci\build_hotloader.ps1 [-RunUrl <run>] [-Work <short folder>]
tools\ci\build_hotloader.ps1 -Source <a source tree> -Vendor <the add-on's bootstrapped vendor folder>   # without network
```

| Parameter | Meaning |
|---|---|
| `-Out` | Where the files go, as `<part>\<path in the part>` (default `out\ci\built`) |
| `-Work` | The source copy and its build (default `out\ci\work-hotloader`); `TEMP`/`TMP` point to its `tmp`. The workflow gives a short folder (`$RUNNER_TEMP\hl`): assimp's folders are deep |
| `-Source` | A source tree to build instead of `packages/model-hotloader/source/mmdhl` (a staged copy, before its import) |
| `-Vendor` | The add-on's `vendor` folder with its dependencies already fetched (each with `.mmdhl-revision`): copied in (robocopy, no links), so `bootstrap.py` downloads nothing |
| `-RunUrl` | Recorded with each file |
| `-Jobs` | Parallel MSBuild projects (default 2) |

Relative `-Out`, `-Work`, `-Source` and `-Vendor` folders are taken from where the script is started (R19: before,
they broke the build once it changed into the source copy).

## What it does

1. Writes the source to `<Work>\src`: `tools\inputs.py extract model-hotloader --prefix source/mmdhl/`
   (only those files are read), or a copy of `-Source`; then `-Vendor`, if given.
2. The add-on's own recipe (its `scripts/build.ps1`): `scripts/bootstrap.py` (the locked commits of
   `dependencies.lock.json`, each fetched with git from GitHub, which checks every object against the
   commit's hash, since R19; CoACD's wheel from PyPI against its SHA-256; the add-on's patches of Bullet and
   nanoem), `scripts/patch-bullet-threading.py`, then CMake with Visual Studio 17 2022, x64,
   and a Release build of the targets `mmdhl_client`, `mmdhl_server` and `mmdhl_worker` (with
   `mmd_runtime`). The test targets are not built.
3. `mmdhl_worker.exe --version` must report the release `pins.json` names (2.3.1).
4. A copy of the part's `mmd_hotloader/lua/mmdhl/native_policy.lua` is given to the add-on's
   `scripts/native_manifest.py`, which rewrites that release's entry with the files just built and
   writes `native-release.json` beside them.
5. Copies the four natives to `<Out>\model-hotloader\bin\`, `native-release.json` as
   `bin\mmdhl-native-release.json` and the policy to `mmd_hotloader\lua\mmdhl\native_policy.lua`, and
   writes `<Out>\provenance-hotloader.json`: for each file's SHA-256 its part and path, the add-on's
   repository and base commit, the source copy, how it was made (`compiled:` or `generated:`) and the
   run. `lib_coacd.dll` is not among them: [`fetch_prebuilt.py`](fetch_prebuilt.py.md) downloads it.

**Needs:** Python 3, git, Visual Studio 2022 (MSBuild, MSVC, CMake), network unless `-Vendor` is given.
**Writes:** `-Work` and `-Out` only. **Exit:** 0 when the four files and the records are written; a
failed step stops it with an error.
