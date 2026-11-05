# R16 report: the sky at a map's start, and the RTX package built on GitHub

The user's items (2026-11-04), in the [plan](R16-plan.md): 44, the chosen weather and daytime were not
applied on entering a map until the settings panel was opened; 45, the RTX package's workflow should
report the SHA-256 of every file in the `.gma` and of the `.gma` uploaded to the Workshop, build every
binary freshly on GitHub, pack the `.gma` there, and keep only the newest package within the 2 GB of
artifact storage.

Claude did the work in the main session on `r16`; Codex only translated. Decisions:
[ADR 0105](../decisions/0105-the-players-sky-applies-from-a-maps-start.md) (item 44) and
[ADR 0106](../decisions/0106-the-rtx-package-built-on-github.md) (item 45).

## Item 44: the sky at a map's start

On every map but one the companion's sky already applied at the start (traced option by option in the
PoC: a new game, a map change, a listen server, the field's `rtx.conf`; in the field on gm_construct).
The one was `modern_house`: Modern House RTX sets its own afternoon 5.8 s after the map starts, and ADR
0031 let such an add-on keep its sky until a setting was changed. Now, with "Follow the map's sun"
unticked (the player chose a time), the player's time and weather are in charge from the start and the
add-on's later settings are put back at once; following the map still keeps the add-on's sky. Merged as
`9343e6e`, published as 0.0.0-dev.20261105022609+1afcd9aa, and checked in the field on `modern_house`:
taken over, the player's clock running, their clear noon sky in the pictures.

## Item 45: the package built on GitHub

**What GitHub builds now.** `package.yml` has three jobs. `runtime` builds the Remix runtime from the
fork commit in `runtime/base.json` with `runtime/patches` (`runtime/build_runtime.ps1 -Install`) and
lays out the runtime part's 189 files from its install folder (`tools/ci/collect_runtime.py`). `modules`
builds the RTX fixes' module from the public fixes commit `f28bd5a9` with the four GPL patches already in
`packages/fixes/licenses` (they give exactly the native tree of the unpushed `913bb6b` the shipped module
was built from), RTX Water from `b5c194ec` (native Version 4, as shipped), the debug module from its
complete source copy in `packages/`, and the material editor's bridge from its source, now vendored in
`packages/advanced-material-editor/source` (`tools/ci/build_modules.ps1`, sources and commits in
`tools/ci/pins.json`). `package` builds this repository's client and glass modules, downloads ReShade's
setup, the fixes' `stdshader_dx6.dll` and CoACD's `lib_coacd.dll` from their publishers against pinned
SHA-256 hashes, and packs the `.gma` with every native binary from the run (`build_package.py --built`;
any `.dll`/`.exe` missing from the run fails it).

**The report.** The run's summary shows the `.gma`'s size and SHA-256, every file's path, size and
SHA-256, and each native binary's origin: compiled in the run, downloaded by it against a pin, or taken
from `packages/`, with its repository, commit and recipe (`tools/package_report.py`). The artifact
`rtx-package-report` keeps the same as JSON, as `SHA256SUMS.txt` and with the provenance records.

**One package.** The `.gma` is the artifact `rtx-package` (zip level 6). Each run deletes the older
`rtx-package` artifacts before uploading its own, so one is kept.

**The Workshop gets exactly that file.** The pre-push hook of `main` runs `publish_workshop.py
--from-ci`: it waits for the package run of the pushed commit, downloads both artifacts, checks the `.gma`
against the report (name, size, SHA-256) and uploads that file; the change note and
`out/workshop/published.json` name the run and the SHA-256. Commits and merges no longer publish, and a
package built on this machine is not uploaded unless the user asks (`--local-upload`).

**Still from `packages/`.** The Model Hotloader's four natives (`gmcl_mmdhl`, `gmsv_mmdhl`,
`mmdhl_runtime`, `mmdhl_worker`): the shipped files were built from 41 staged, uncommitted changes in the
author's worktree `ipg\!GMHLVK\wt-full-textures-props` (branch `feat/gravity-buoyancy-settings`;
`SetSecondaryWater`, `SetSecondaryBuoyancy`), which no commit has. The report lists them under "taken from
packages/". The rest of the content (Lua, materials, the emissives part's `.gma`) comes from `packages/`
as before; it is not compiled.

**Fetched, not compiled.** The runtime's 38 vendor binaries (DLSS, NRC, XeSS, OpenUSD and the like) come
with the same Meson build, from packman, submodules and clones; ReShade is its author's signed setup;
`stdshader_dx6.dll` was built by sambow23 from source never pushed; `lib_coacd.dll` is CoACD's own
wheel build. Each must match its pin, or the run fails.

## Proven

**Locally** (this worktree, no network): `build_modules.ps1` with the local fixes clone, garrysmod_common
and premake built all four modules at the shipped sizes (5,491,712; 274,944; 428,032; 316,416 bytes),
and the patched native tree equals `913bb6b`; `collect_runtime.py` found all 189 runtime files in the
fork's `_output`; `build_package.py --built` packed 1,124 files (1,736,040,838 bytes) whose report counts
9 compiled, 41 fetched and 4 `packages/` binaries. `tools\test.ps1 -Config Release` passed (26/26 CTest,
the Python suites).

**On GitHub:** see "The runs" below.

## The runs

| Run | Commit | Result |
|---|---|---|
| [41962240202](https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix/actions/runs/41962240202) | `f44f510` (the merge of item 45) | Both build jobs failed in two minutes, each on something only a runner shows: `build_runtime.ps1` restored `GIT_OBJECT_DIRECTORY` as an empty variable (PowerShell 7.5 on .NET 9 keeps it; Windows PowerShell removes it), so git took the new worktree for an invalid repository; and `git restore --source` did not fetch RTX Water's blob in the blob-filtered fixes clone. Fixed in `dac2b8a` |
| [41962824677](https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix/actions/runs/41962824677) | `a141826` | **Success in 64 minutes.** `modules` 4 min (the four modules; the bridge's test passed), `runtime` 53 min (445 build steps on two cores; `d3d9.dll` 397,908,480 bytes, 512 fewer than this machine's build; 189 files, 41 binaries collected), `package` 12 min |

The runner had 2 cores, 8 GB, 79-81 GB free on C: and 73-96 GB on D:, git 2.56.0. Both builds were
cached by their sources, so the next run that leaves them unchanged takes only the `package` job.

**The package of run 41962824677:** `gmod-rtx-remix-0.0.0-dev.20261105043959_133af7c6.gma`, 1,795,374,781
bytes, SHA-256 `65c6a7c6b73a7a2d918616076163cd2e402cffcb5a1d84bf1c3eb06fb39a5a9d`, 1,124 files. Native
binaries: 54, 9 compiled in the run (the runtime's `d3d9.dll` and two USD plugins, the fixes' three
modules, the bridge, the client and glass modules), 41 downloaded by it against pins (38 runtime vendor
binaries, ReShade, `stdshader_dx6.dll`, CoACD), 4 from `packages/` (the Model Hotloader's). The artifact
`rtx-package` is 841,295,455 bytes (zip level 6), `rtx-package-report` 121,472 bytes. The run's summary
lists every file with its SHA-256; `SHA256SUMS.txt` has 1,125 lines.

**The publisher's check.** `publish_workshop.py --from-ci --commit a141826 --dry-run` downloaded both
artifacts (one minute) and found the `.gma`'s name, size and SHA-256 equal to the report's.

**In the PoC** (that `.gma` through `allow.local`, gm_construct with Remix; `out/r16/ci1` in the main
checkout): the loader deployed and activated runtime 0.0.0-dev.20261105043959+133af7c6
(`DXVK_Remix: remix-main+ade6c1df`, the commit `git am` made on the runner); the Remix API answered; the
fixes' module, RTX Water (native Version 4: `ClearRipples` and `Stats`, no `SetCameraInWater`), the
bridge, the glass and debug modules and the Model Hotloader all loaded. All 54 deployed native binaries
equal the report's hashes, and 1,121 of the 1,123 deployed files; the other two are the auto-PBR mod's
`materials.usda` and `topbr_generation.txt`, which the game rewrites. The scene was path traced as
before; normal quit, no Lua error, and the Remix log's 29 `err:` lines (`GetShaderModule: Out of range of
supported shader model`) are as many as with the locally built package. The PoC's loader config was put
back byte for byte.

## Publication and the field check

After the PoC check, the main checkout's hooks were reinstalled (`--install-hooks`: pre-push runs
`--from-ci`; post-commit and post-merge only run Git LFS), and `publish_workshop.py --from-ci --commit
a141826` uploaded run 41962824677's `.gma` to item 3829070317 as 0.0.0-dev.20261105043959+133af7c6
(`published.json`: `source: github`, the run, SHA-256 `65c6a7c6...`, 9 compiled, 41 fetched, 4 from
`packages/`). Until then the old hooks' local builds had found the same content as the item and uploaded
nothing.

Before the field starts no other lab or game was running, and `tools\steam\verify_install.py` found the
field install intact (only the user's `autoexec.cfg` differs). Evidence: `out\r16\field-ci\` in the main
checkout.

| Start | Result |
|---|---|
| 01-download | Steam downloaded the new item: `workshop\content\4000\3829070317\gmod-rtx-remix-0.0.0-dev.20261105043959_133af7c6.gma`, SHA-256 `65c6a7c6...`, the run's file. The game still ran 1afcd9aa (the first start only downloads); normal quit |
| 02-ci-package | Deployed and active: 0.0.0-dev.20261105043959+133af7c6, `DXVK_Remix: remix-main+ade6c1df`. All 54 deployed native binaries equal the run's report. Every module loaded (the fixes, RTX Water Version 4, the bridge, glass, the debug module, the Model Hotloader); gm_construct path traced under the user's own settings; no Lua error, normal quit |

## Cost

A run that rebuilds everything took 64 minutes: 53 for the runtime on two cores, 4 for the modules, 12
for the package. A run whose runtime and module sources are unchanged takes the cached builds and only
the package job's 12 minutes plus the two jobs' lookups. Windows minutes count double for a private
repository's plan. Artifacts: one `rtx-package` of 0.84 GB at a time, plus the 121 KB reports (90 days)
and `build.yml`'s bundles (about 270 MB in all before this round).

## The Model Hotloader's natives, built here too

Asked how the Hotloader's four natives should get a source GitHub can build, the user chose to copy it
here ([ADR 0107](../decisions/0107-the-model-hotloaders-natives-built-from-a-source-copy.md)).

**The source.** The worktree `ipg\!GMHLVK\wt-full-textures-props` (branch
`feat/gravity-buoyancy-settings` at the public `ecd7c426`, "Version 2.3.1") had all 41 of its changes
staged and none unstaged, and no source file newer than the shipped DLLs (2026-10-26 16:21): its index
is their source. What the native build reads, 320 files (8.6 MB), was copied from that index with
`git cat-file` into `packages/model-hotloader/source/mmdhl` (`tools/inputs.py import`; 66 binary or
large files, the 4.5 MB generated `native/shape_atlas.hpp` among them, went to Git LFS), with
`provenance.json`, `Source.md` and `staged-changes.patch` (the ten copied files that differ from the
commit: `CMakeLists.txt`, `native/module.cpp`, `physics.cpp`, `runtime.hpp`, `secondary.cpp/.hpp`,
`spring_bones.cpp/.hpp`, two C++ tests). The Lua add-on stays in `mmd_hotloader/`; the part ships no
source.

**The build.** `tools/ci/build_hotloader.ps1` runs the add-on's own recipe: `scripts/bootstrap.py` (its
pinned dependencies: nanoem, glm, Bullet, garrysmod_common, sourcesdk-minimal, json, stb, assimp,
meshoptimizer, Vulkan-Headers, glslang from codeload.github.com, and CoACD's wheel), its Bullet patches,
CMake with Visual Studio 2022 x64 Release of `mmdhl_client`, `mmdhl_server` and `mmdhl_worker`. The
worker must report release 2.3.1. Then the add-on's `scripts/native_manifest.py` rewrites the 2.3.1
entry of a copy of the shipped `native_policy.lua` and writes `native-release.json` from the files just
built: the add-on's installation check accepts exactly the natives it ships with. The workflow's new
`hotloader` job runs it in a short folder on the runner (assimp's folders are deep), cached by its
sources; `KEEP_PACKAGED` is gone, and `tools/inputs.py extract` writes the source tree for the build.

**Local proof** (this worktree, the worktree's already fetched dependencies copied in, no network; 5
minutes on 8 jobs): client 2,843,648 bytes, server 1,862,144 and worker 4,148,224, the shipped sizes;
runtime 10,736,640 (512 more). The client has `SetSecondaryWater`, `SetSecondaryBuoyancy`,
`secondaryGravity` and "Invalid water height", as the shipped one. The regenerated policy differs from
the shipped one only in the 2.3.1 entry's build (`f2e32f99f0a5-...`, this repository's commit and the
configure time) and the four hashes.

**On GitHub** ([run 41977506299](https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix/actions/runs/41977506299),
commit `f83d7ad`): the runtime and modules came from their caches in seconds; the `hotloader` job
fetched every pinned dependency and built the four natives in 17 minutes, all four exactly the shipped
sizes (the runtime too, 10,736,128 bytes); the package job took 12. On the runner the source is built
outside any git checkout, so the add-on's CMake names the build `source-20261105T060107Z`; the run's
report and provenance tie it to the commit. The package `gmod-rtx-remix-0.0.0-dev.20261105062645_fbce366a.gma`
(1,795,374,769 bytes, SHA-256 `d850040f0ea61051b9e78fefae23969995cc9266756b2815c144fa2f6159daba`, 1,124
files) has 54 native binaries: **13 compiled in the run, 41 downloaded by it against pins, none from
`packages/`**. The run deleted the previous `rtx-package` artifact, so one is kept.

**In the PoC** (`out/r16/ci2` in the main checkout): the add-on's own check accepted the GitHub-built
natives against the regenerated policy: installed 2.3.1, recommended 2.3.1, core and imports available;
its only issue is the warning `game_unverified` (the module's compiled-in profiles do not describe this
Garry's Mod build's libraries; it disables nothing). All 54 deployed binaries equal the report's hashes;
every module loaded; no Lua error, normal quit, the loader config put back byte for byte.

**Published and checked in the field.** The push hook's background publisher was stopped before the run
finished (the PoC check came first); then `publish_workshop.py --from-ci --commit f83d7ad` uploaded the
run's `.gma` to item 3829070317 as 0.0.0-dev.20261105062645+fbce366a. The field install was intact
(only `autoexec.cfg` differs). Evidence: `out\r16\field-hl\` in the main checkout.

| Start | Result |
|---|---|
| 01-download | Steam downloaded the run's file (SHA-256 `d850040f...`); the game still ran 133af7c6, the previous upload with the old Hotloader natives: the add-on reported installed 2.3.1, core on, and the same `game_unverified` warning, so that warning is the game build's, not the new natives' |
| 02-all-built | Deployed and active: 0.0.0-dev.20261105062645+fbce366a. All 54 native binaries and the two regenerated Hotloader records equal the run's report; every module loaded; the add-on accepted its natives (installed 2.3.1, core and imports on, only `game_unverified`); no Lua error, normal quit |

## Open items

- **`packages/model-hotloader/source/Source.md`** says the build identity names this repository's commit;
  on the runner it is `source-<time>` (ADR 0107 says both). Correct it with the next change of the source
  copy: any change there rebuilds the natives and republishes the package.
- **Debug-only glass tests.** `tools\test.ps1` (Debug) fails two glass tests that only a Release build
  can pass: one deliberately overfills Jolt's contact tables, which Jolt's Debug build asserts on
  (`0x80000003`), and the 4,000-piece benchmark's time limits. CI and the rounds' gate run Release; the
  tests could be marked Release-only.
- **The material editor bridge's long-path limit.** Its writer test fails once `%TEMP%` is longer than
  about 75 characters (a material with every texture role passes MAX_PATH): a game root up to about 115
  characters is safe. CI runs the test with the runner's short `TEMP`.
