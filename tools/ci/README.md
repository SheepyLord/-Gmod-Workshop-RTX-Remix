# tools/ci

R20-A release announcement: after a GitHub loader release exists, its maintainer edits
`companion/nativeloader/resource/loader-release.json` to that released version and the exact
`https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v<version>` page, runs the
Release gate, commits and pushes main. The Workshop package then carries the reminder. Keep this
hand-edited record at 0.14.0 during 0.15.0 development; CMake is not its source. Publishing a new
bootstrap and updating this record are separate release steps. The record adds no manifest key
or minimum loader requirement ([ADR 0115](../../docs/decisions/0115-released-loader-record-and-reminders.md)).

What GitHub's package workflow ([`.github/workflows/package.yml`](../../.github/workflows/package.yml))
builds the RTX package's native binaries from, and the scripts it runs (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)). Every native binary in the
package comes from the run: compiled from a pinned source, or downloaded from its publisher and checked
against a pinned SHA-256. None comes from `packages/`: the Model Hotloader's natives are built from the
source copy in `packages/model-hotloader/source` ([ADR 0107](../../docs/decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)).

| File | What |
|---|---|
| [`pins.json`](pins.json) | The sources and tools: garrysmod_common and its submodules, premake 5.0.0-beta2 (archive SHA-256), the RTX fixes' public base commit with the GPL patches from `packages/fixes/licenses` and the object ids of the patched native tree they give (`patched_tree`; R19), RTX Water's commit (native Version 4) with its own GPL patch and recorded tree (`rtxwater_patches`, `rtxwater_tree`), the debug module's and the bridge's source copies in `packages/`, this repository's own modules (`repository_builds`: their sources and the record of what the copies in `packages/` were built from, `packaged`), and the files that are fetched (`fetched`: URL, size, SHA-256, a member of an archive, files a packager takes out of them) |
| [`repo_builds.py`](repo_builds.py.md) | The record of what this repository's own modules in `packages/` were built from, which [`check_repo.py`](../check_repo.py.md) checks; `refresh` builds a module, checks what the build read, and imports it only when it is another image ([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)) |
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
   [`tools/package_report.py`](../package_report.py.md) into the run's summary. `rtx-package-report`
   keeps the report. The older `rtx-package` artifacts are deleted, then the new `.gma` is uploaded as
   `rtx-package`. The order is deliberate (review R19, F-07): Actions storage (2 GB) may not hold two
   packages beside the other artifacts, so a failed upload leaves none; the last good package stays on
   the Workshop item and in `out\workshop\ci` on the developer's machine, and a new run builds it again.
   Both artifacts expire two days after the run, like every artifact
   ([ADR 0113](../../docs/decisions/0113-every-actions-artifact-expires-after-two-days.md)).
4. On the developer's machine, [`tools/publish_workshop.py`](../publish_workshop.py.md) `--from-ci
   --commit <sha>` uploads that `.gma` after checking it against the report, within those two days.
   Without a successful run of that commit, or once its artifacts are gone, it uploads nothing and exits 1.

**Permissions** (review R19, F-04): the workflow's token can only read the repository. Only the
`package` job, which deletes the older artifacts, may also write to Actions; the `runtime`, `modules`
and `hotloader` jobs, which run other people's build scripts and downloads, cannot. Values a run gets
from GitHub (the run's URL) reach the scripts as environment variables, never pasted into them.

Only a person starts the workflow, for a release
([ADR 0108](../../docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)); during
development the git hooks publish packages built on the developer's machine from `packages/`.

The provenance records are keyed by each binary's SHA-256, so the report finds a binary wherever a
packager puts it in the `.gma`. A record says where the binary came from (`repository`, `commit`), how
(`how`, starting with `compiled:` or `fetched:`) and which run made it (`run`).

## This repository's modules in `packages/`

The workflow compiles the client module and the glass module from source; development builds of the
package (the git hooks, [ADR 0108](../../docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md))
take the copies stored in `packages/fixes/modules` and `packages/glass/bin`. Each `repository_builds`
entry therefore declares the module's `sources` (`not_sources`: the tests inside them) and records in
`packaged` the SHA-256 of the stored copy and of each source when it was built
([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)).
`tools\check_repo.py` fails while a source differs from the record, naming it (R20-Q found that the
client module stored since R4 rejected R6's `remix.performance_tier`). After changing `loader/core`,
`loader/client`, `glass/native`, the root CMake files or the third-party code they link:

```powershell
python tools\ci\repo_builds.py status     # what differs
python tools\ci\repo_builds.py refresh    # tools\build.ps1 -Config Release, check, compare, import if needed, record
```

`refresh` refuses a build that read a file of the repository outside the module's sources (Ninja's
inputs and header log), and imports with `tools\inputs.py` only a build that is another image than the
stored copy, apart from what every MSVC link changes (time stamps, the PDB's identity, anonymous-namespace
names). Never import these modules with `inputs.py` directly: the check then fails until `refresh`
records them. Details: [repo_builds.py.md](repo_builds.py.md).

## Locally

R20-E adds the sixth `fixes.patches` entry, `upscaling-state/upscaling-state.patch`, and updates
`fixes.patched_tree.source`; the pins' shape and build procedure are unchanged. It supplies
`RemixConfig.GetUpscalingState()` and returns `nil` with older runtimes.

Every script runs on this machine too, without network where local copies are given:

```powershell
tools\ci\build_modules.ps1 -FixesClone H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed -GmodCommon H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\garrysmod_common -Premake <premake5.exe 5.0.0-beta2>
python tools\ci\collect_runtime.py <fork>\_output
python tools\ci\collect_repo_build.py
python tools\ci\fetch_prebuilt.py --from out\inputs
tools\ci\build_hotloader.ps1 -Vendor <the add-on's bootstrapped vendor folder>
python tools\build_package.py --built out\ci\built --out out\r16\ci-package
```

Tested by [test_ci_tools.py](../tests/test_ci_tools.py.md) and, for `repo_builds.py`,
[test_repo_builds.py](../tests/test_repo_builds.py.md).
