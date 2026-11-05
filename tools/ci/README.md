# tools/ci

What GitHub's package workflow ([`.github/workflows/package.yml`](../../.github/workflows/package.yml))
builds the RTX package's native binaries from, and the scripts it runs (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)). Every native binary in the
package comes from the run: compiled from a pinned source, or downloaded from its publisher and checked
against a pinned SHA-256. None comes from `packages/`: the Model Hotloader's natives are built from the
source copy in `packages/model-hotloader/source` ([ADR 0107](../../docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)).

| File | What |
|---|---|
| [`pins.json`](pins.json) | The sources and tools: garrysmod_common and its submodules, premake 5.0.0-beta2 (archive SHA-256), the RTX fixes' public base commit with the four GPL patches from `packages/fixes/licenses` (they give the native tree of `913bb6b`), RTX Water's commit (native Version 4), the debug module's and the bridge's source copies in `packages/`, this repository's own modules (`repository_builds`), and the files that are fetched (`fetched`: URL, size, SHA-256, a member of an archive, files a packager takes out of them) |
| [`build_hotloader.ps1`](build_hotloader.ps1.md) | Builds the Model Hotloader's four natives from its source copy in `packages/` with the add-on's own recipe, and regenerates its hash records (`native_policy.lua`, `mmdhl-native-release.json`), with `provenance-hotloader.json` |
| [`build_modules.ps1`](build_modules.ps1.md) | Builds `gmcl_RTXFixesBinary`, `gmcl_rtxwater`, `gmcl_rtxdebug` and the material editor's bridge from those pins into `out\ci\built\<part>\<path>`, with `provenance-modules.json` |
| [`collect_runtime.py`](collect_runtime.py.md) | Lays out the runtime build's install folder (`runtime\build_runtime.ps1 -Install`) as the runtime part's files, with `provenance-runtime.json` |
| [`collect_repo_build.py`](collect_repo_build.py.md) | Takes this repository's client and glass modules from its Release build, with `provenance-repository.json` |
| [`fetch_prebuilt.py`](fetch_prebuilt.py.md) | Downloads ReShade's setup, the fixes' `stdshader_dx6.dll` and CoACD's `lib_coacd.dll` and checks their pins, with `provenance-fetched.json` |
| [`cache_key.py`](cache_key.py.md) | The cache keys of the runtime, module and Hotloader builds: a SHA-256 of exactly the sources each reads |

## How the workflow uses them

1. Job `runtime` (cached by `cache_key.py runtime`): clones the fork, runs
   `runtime\build_runtime.ps1 -NoImport -Install -Jobs 2` on the runner's larger drive, then
   `collect_runtime.py`.
2. Job `modules` (cached by `cache_key.py modules`): `build_modules.ps1`. Job `hotloader` (cached by
   `cache_key.py hotloader`): `build_hotloader.ps1` in a short folder on the runner.
3. Job `package`: Git LFS content except the binaries the run makes, the three jobs' caches,
   `tools\build.ps1 -Config Release`, `collect_repo_build.py`, `fetch_prebuilt.py`, then
   [`tools/build_package.py`](../build_package.py.md) `--built out/ci/built` and
   [`tools/package_report.py`](../package_report.py.md) into the run's summary. The older `rtx-package`
   artifacts are deleted before the new `.gma` is uploaded; `rtx-package-report` keeps the report.
4. On the developer's machine, [`tools/publish_workshop.py`](../publish_workshop.py.md) `--from-ci`
   (the pre-push hook) uploads that `.gma` after checking it against the report.

The provenance records are keyed by each binary's SHA-256, so the report finds a binary wherever a
packager puts it in the `.gma`. A record says where the binary came from (`repository`, `commit`), how
(`how`, starting with `compiled:` or `fetched:`) and which run made it (`run`).

## Locally

Every script runs on this machine too, without network where local copies are given:

```powershell
tools\ci\build_modules.ps1 -FixesClone H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed -GmodCommon H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\garrysmod_common -Premake <premake5.exe 5.0.0-beta2>
python tools\ci\collect_runtime.py <fork>\_output
python tools\ci\collect_repo_build.py
python tools\ci\fetch_prebuilt.py --from out\inputs
tools\ci\build_hotloader.ps1 -Vendor <the add-on's bootstrapped vendor folder>
python tools\build_package.py --built out\ci\built --out out\r16\ci-package
```

Tested by [test_ci_tools.py](../tests/test_ci_tools.py.md).
