# Components

The companion's `nativeloader_imported_normals.lua` collects active imported-model hashes for an
optional additive NoSave smooth-normal category. `nativeloader_motion_tab.lua` opens the existing
motion manager from its own creation tab. These modules and AME's original-name/current-selection
behavior are checked offline by [test_addon_workflow.py](../tools/tests/test_addon_workflow.py.md)
and its Lua harness.

Every component of the project: where it lives, what it does, and its status. Keep this file in
sync when you add, rename or finish something ([`tools/check_repo.py`](../tools/check_repo.py.md)
fails if a folder under `loader/` or `tools/` is missing here).

Status: **done** (usable), **skeleton** (builds, little function), **planned** (milestone in
[ROADMAP.md](ROADMAP.md)).

## Runs inside the game

The player-body fix adds a private local-shadow proxy and RTX-tab shadow/height controls, with
independent first-person view models in runtime patch 0007. Details and tests are in
[ADR 0043](decisions/0043-player-body-viewmodel-and-shadows.md).

Loader 0.8.0 adds prior-install migration in nl_core: static PE recognition, a bounded upstream
path catalog, hash-verified stock recovery, and a permanent legacy archive committed with normal
package deployment ([ADR 0042](decisions/0042-legacy-remix-migration.md)). No GPU or execution of the
old runtime is needed for planning or its generated regression tests.

| Component | Path | Status | What it does |
|---|---|---|---|
| Bootstrap | [`loader/proxy`](../loader/proxy/README.md) → `bin\win64\winmm.dll` | M1 done (inert) | Loaded by `gmod.exe` at process start. Forwards every `winmm` export to the system DLL, checks it is inside `bin\win64\gmod.exe` and that no off switch is set, then runs the start-up step at the EXE entry point: discover packages, deploy, activate the runtime, write the status file. Any error is logged and the game continues vanilla. M1 built the inert part (forwarding, host gate, off switches, entry hook, log); the start-up step comes with M3 (deploy) and M4 (activate). |
| Core library | [`loader/core`](../loader/core/README.md) (`nl_core`) | M3 done | Logic shared by the bootstrap, the CLI and the tests. M2: GMA reader (GMAD v1-v3, plain and LZMA-wrapped with GMod's footer, verify, single-file reads, one-pass extraction), strict JSON, path rules, manifest schema 1, packages from archives or dev folders, `config.json`, KeyValues, discovery without the Steam API, planner. M3: SHA-256 (CNG), the file-system layer, the journal and the transactional deployer (apply, rollback, uninstall, recovery; [ADR 0007](decisions/0007-transactional-deployment.md)). M4: activation planning (`activate::plan`) and the in-memory command-line patch (`nl::cmdline`; [ADR 0008](decisions/0008-activation-at-startup.md)). |
| Lua companion | [`companion/`](../companion/README.md) | done (M5, M6) | Normal GMod Lua addon, shipped in the RTX fixes package. Reads `garrysmod/data/native-loader/status.json` and `session.json`, shows runtime state and errors, and tells the user to restart when Steam has a newer version of a deployed Workshop package. Details in the M5 section below. |
| Remix runtime package | built by [`tools/package_runtime.py`](../tools/package_runtime.py.md) | done (M4) | The package that carries the user's Remix fork build: its runtime files, a manifest with SHA-256 per file, `rtx.conf`/`dxvk.conf` layers, environment and launch arguments. There is no `packages/` recipe folder; the packager builds it from the fork's output. |

## Runs outside the game

| Component | Path | Status | What it does |
|---|---|---|---|
| CLI | [`loader/cli`](../loader/cli/README.md) → `nlctl.exe` | M3 done | Same core as the bootstrap, so packages and installs can be examined and deployed without starting GMod: `inspect`, `verify`, `scan`, `manifest`, `plan`, `status`, `activation` (read-only), and `apply`, `rollback`, `uninstall` (with `--dry-run`). Four CTests on `gmapack.py`-built archives: cross-check, end-to-end plan, end-to-end deploy, and `uninstall-loader.ps1` in synthetic game folders. |
| Unit tests (C++) | [`loader/tests`](../loader/tests/README.md) | done (harness), grows with each milestone | `nl_tests`, run by CTest: over CRC-32, GMA, LZMA, JSON, paths, manifests, packages, KeyValues, config, discovery, planner, SHA-256, `nl::fs`, journal, deployer, activation, command line, start-up policy, status and the M5 session extras (the count is in the CTest output), 3 of them exhaustive fault injection (their own CTests). `nl_fault_host` and [`deploy_faults.py`](../loader/tests/deploy_faults.py.md): the deployer killed before every change. |
| Build | [`tools/build.ps1`](../tools/build.ps1.md) | done | Configure, build and test with MSVC x64, CMake presets and Ninja. |
| MSVC environment | [`tools/lib`](../tools/lib/VsDevEnv.psm1.md) (`VsDevEnv.psm1`) | done | Finds VS / Build Tools (even when `vswhere` cannot) and imports `vcvars64`. |
| Test runner | [`tools/test.ps1`](../tools/test.ps1.md) | done | Runs the convention check, all Python tests and the C++ build + tests. |
| Convention check | [`tools/check_repo.py`](../tools/check_repo.py.md), tests in [`tools/tests`](../tools/tests/test_check_repo.py.md) | done | Enforces script docs, module READMEs, links, changelog, this component map. |
| Steam depot tools | [`tools/steam`](../tools/steam/steam_manifest.py.md) | done | Parse depot manifests; [`verify_install.py`](../tools/steam/verify_install.py.md) proves an install is vanilla and lists extras; [`make_vanilla_copy.py`](../tools/steam/make_vanilla_copy.py.md) builds the PoC install from verified local files; [`vdf.py`](../tools/steam/vdf.py.md) reads `.acf`/`.vdf`. |
| PE diagnostics | [`tools/diag`](../tools/diag/pe_imports.py.md) (`pe_imports.py`) | done | Lists imports and exports of EXEs and DLLs (hook points, runtime dependencies). |
| GMA packer | [`tools/gmapack`](../tools/gmapack/gmapack.py.md) | vendored | Python `.gma` reader and writer; reference for the C++ reader and the packer for test and runtime packages. |
| Runtime packager | [`tools/package_runtime.py`](../tools/package_runtime.py.md) | done (M4) | Turns the fork's runtime build folder into a runtime package folder and/or `.gma`, with a manifest and SHA-256 per file; tests in [`tools/tests`](../tools/tests/test_package_runtime.py.md). |
| Install / uninstall | [`tools/install-loader.ps1`](../tools/install-loader.ps1.md), [`tools/uninstall-loader.ps1`](../tools/uninstall-loader.ps1.md) | done (M1, M3) | Copy the bootstrap into an install (PoC by default); remove everything the journal lists (`nlctl uninstall`), then the bootstrap, keeping `config.json` unless `-RemoveConfig`. |
| PoC deployment check | [`tools/poc_deploy_check.ps1`](../tools/poc_deploy_check.ps1.md) | done (M3) | The deployer's whole life cycle on the PoC without starting the game; proves the install is identical afterwards. |
| In-game smoke test | [`tools/smoke_test.ps1`](../tools/smoke_test.ps1.md) | done (M1) | Launches the PoC with the bootstrap and checks the logs. |

### M1 implementation additions

The bootstrap, install and smoke rows above in detail, as M1 built them (merged into `main` on 2026-10-27):
Debug/Release tests, all five real PoC runs, tool comparisons and depot integrity checks pass.
See the [M1 report](handover/M1-report.md) for evidence and the user-selected build/worktree location.

| Component | Path | Implementation |
|---|---|---|
| Inert bootstrap | [`loader/proxy`](../loader/proxy/README.md) | `winmm.dll`; full System32 export forwarding, host/off-switch gate, entry-point hook and guarded log only. Package activation remains M2–M4. |
| Bootstrap tests | [`loader/proxy/tests`](../loader/proxy/tests/README.md) | `nl_proxy_tests`, static-import host, export-generation and installer CTests. |
| Bootstrap install/uninstall | [`tools/install-loader.ps1`](../tools/install-loader.ps1.md) | Copies DLL/PDB, records SHA-256, refuses foreign/edited files and Steam-managed roots by default; `-Uninstall` retains state. Journal-based package removal came with M3 (`uninstall-loader.ps1`). |
| PoC smoke comparison | [`tools/smoke_test.ps1`](../tools/smoke_test.ps1.md) | Five map loads, two tool comparisons, evidence and loader-state restoration. |

## M4 activation additions (implemented, in review)

The M1/M3 component descriptions above are the foundation. M4 now connects deployment and
activation inside the bootstrap; real-game visual acceptance remains open as recorded in the
[M4 report](handover/M4-report.md).

| Component | Path | M4 behavior |
|---|---|---|
| Startup policy and reporting | `loader/core` (`startup`, `status`) | Keep-last-good, current-PID exclusion, contention/pending handling, atomic status and cleanup |
| Process activation | `loader/proxy/runtime.cpp`, `loader/proxy/startup.cpp` | Validated file/cwd/path preconditions; reversible environment, full command-line descriptors, System32 Vulkan, DLL search and absolute d3d9 preload |
| Activation preview | `loader/cli/nlctl.cpp` | Same config-layer/user-value plan; missing config and pending state inactive; uninstall removes generated status |
| M4 tests | `loader/tests`, `loader/proxy/tests` | 120 core cases total, real command-line round trip, KERNEL32-only import check and 17 synthetic activation scenario groups |
| PoC acceptance | [`tools/poc_activation_check.ps1`](../tools/poc_activation_check.ps1.md) | A/B packaging, individually approved launches, module/log evidence, dxlevel/off checks, user visual confirmation and cleanup |

## M5 RTX fixes additions

| Component | Path | Status | What it does |
|---|---|---|---|
| Fixes packager | [`tools/package_fixes.py`](../tools/package_fixes.py.md) | done (M5) | Turns the fixes repo (read only) into the RTX fixes package folder and/or `.gma`: every add-on folder (kind `lua-addon`), the Remix mods, the built `gmcl_` modules, `stdshader_dx6.dll` as a module override, the seven `patches64` patch sets, the RTX section of `autoexec.cfg` as session console variables, and the Lua companion; leaves out the Steam files the fixes overwrite. Tests in [`tools/tests`](../tools/tests/test_package_fixes.py.md). |
| Frame comparison | [`tools/compare_frames.py`](../tools/compare_frames.py.md) | done (M5) | The user's block-difference measure for two screenshots (mean absolute difference of 32x32 block means, 0-255) with masks and a threshold exit code, plus mean RGB and luminance percentiles per image; needs Pillow. Tests in [`tools/tests`](../tools/tests/test_compare_frames.py.md). |
| Lua companion | [`companion/`](../companion/README.md) (`companion/nativeloader`) | done (M5, M6) | The Lua companion planned above, at `companion/nativeloader` instead of `addon/`: prints `status.json` and `session.json` to the console at client start and on `nativeloader_status`, marking reports older than the session as stale; M6: says when a Workshop package has a newer version that the next start deploys. Shipped in the fixes package as `garrysmod/addons/nativeloader`. Tested under LuaJIT ([`tools/tests`](../tools/tests/test_companion.py.md)). |
| RTX-session hooks | [`loader/proxy/modules.cpp`](../loader/proxy/README.md), [`nl::patch`, `nl::session`](../loader/core/README.md) | done (M5) | The DLL-load watcher that applies patch sets and redirects overridden module loads, and the session console variables with their restore ([ADR 0010](decisions/0010-rtx-session-extras.md)); without RTX, the search hooks on `filesystem_stdio.dll` that keep `requires_remix` packages' add-ons out of the session ([ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md)) |
| PoC session driver | [`tools/poc_session.py`](../tools/poc_session.py.md) | done (M4 review, M5) | Installs, launches, screenshots, quits and uninstalls without anyone at the keyboard; console text through `WM_COPYDATA`; `--reference` for an install that is only read |
| Parity content | [`tools/poc_parity.py`](../tools/poc_parity.py.md) | done (M5) | Copies the reference install's user content (user.conf, saved Lua settings, mounts, Remix mods, a save and its map) into the PoC and restores it exactly |
| Package combiner | [`tools/package_workshop.py`](../tools/package_workshop.py.md) | done (2026-10-28) | Merges native packages (folders or `.gma`) into one: kinds and session extras united, one runtime, no file from two parts, every file checked; a content digest says whether two builds differ ([ADR 0016](decisions/0016-one-workshop-item-kept-current.md)). Tests in [`tools/tests`](../tools/tests/test_package_workshop.py.md) |
| Loader bundle | [`tools/package_loader.py`](../tools/package_loader.py.md), files in [`dist/`](../dist/native-loader/config.json) | done (2026-10-28) | The end-user zip, extracted into the Garry's Mod folder: `bin\win64\winmm.dll`, the default `native-loader\config.json` (allows item 3829070317) and a README; the PDB in a symbols zip ([ADR 0017](decisions/0017-release-bundle-and-ci.md)). Tests in [`tools/tests`](../tools/tests/test_package_loader.py.md) |
| Classic RTX defaults | [`tools/remix_defaults.py`](../tools/remix_defaults.py.md), [`tools/classic_defaults.py`](../tools/classic_defaults.py.md) | done (2026-10-29) | The classic RTX install's settings as the package's defaults: Remix's merged into one low `DXVK_CONFIG_FILE` layer of the runtime package ([ADR 0021](decisions/0021-remix-defaults-in-one-low-layer.md)), the RTX add-ons' as the companion's first-run table ([ADR 0020](decisions/0020-classic-rtx-settings-as-defaults.md)) |
| Companion: guard, menu, guide | [`companion/nativeloader`](../companion/README.md) | done (2026-10-29) | In RTX sessions: keeps add-ons from undoing the session or drawing post-processing over the image; one "RTX Remix" spawn-menu tab with common Remix settings; the in-game guide ([ADR 0022](decisions/0022-companion-rtx-session-guard.md)) |
| Companion translations | [`companion/i18n`](../companion/i18n/README.md), [`tools/companion_i18n.py`](../tools/companion_i18n.py.md), [`companion/nativeloader/lua/nativeloader/i18n.lua`](../companion/nativeloader/lua/nativeloader/i18n.lua.md) | done (2026-10-29) | The RTX Remix tab, the guide and the update notice in Simplified and Traditional Chinese, Japanese, Korean, French and Russian: gettext `.po` files people review and edit, built into the add-on when the RTX package is made; the language follows `gmod_language`, or `nativeloader_language` ([ADR 0029](decisions/0029-companion-translations.md)). Tests in [`tools/tests`](../tools/tests/test_companion_i18n.py.md) |
| Companion: sky and weather | [`nativeloader_sky.lua`](../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md), [`sky_model.lua`](../companion/nativeloader/lua/nativeloader/sky_model.lua.md), presets from [`tools/weather_presets.py`](../tools/weather_presets.py.md) | done (2026-10-29) | In RTX sessions the runtime's physical sky: the sun, moon and stars for a time of day (by default the map's own sun), a clock that can run, and the runtime's twelve weather presets blended into each other, scaled for GMod's maps; the "Sky and weather" panel ([ADR 0031](decisions/0031-physical-sky-time-and-weather.md)). Then the real Moon's face and phases, a night sky image (stars, galaxy, nebulae) or the procedural sky, lunar and solar eclipses by stage (the runtime draws them, runtime-b6), and Remix's fog presets under Remix settings ([ADR 0032](decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)). Tests in [`tools/tests`](../tools/tests/test_companion_sky.py.md) |
| Content packager | [`tools/package_content.py`](../tools/package_content.py.md) | done (2026-10-29) | Turns Lua add-on folders (filtered as gmad publishes them), Remix mod folders and binary modules (`--lua-bin`, with `--load-first` runtimes) into a package: Modern House RTX (Workshop test item 3829275998), and the Emissives, Remove_halo and five add-on parts of the RTX package ([ADR 0023](decisions/0023-content-packages-and-modern-house-item.md), [0024](decisions/0024-bundled-addons-and-module-dependencies.md)). Tests in [`tools/tests`](../tools/tests/test_package_content.py.md) |
| ReShade in RTX sessions | [`loader/core/src/reshade.cpp`](../loader/core/README.md), [`loader/proxy/runtime.cpp`](../loader/proxy/README.md), packager [`tools/package_reshade.py`](../tools/package_reshade.py.md), licence [`third_party/reshade`](../third_party/reshade/README.md) | done (2026-10-29, loader 0.5.0) | The RTX package carries ReShade 6.8.0 unchanged as a Vulkan layer; in an RTX session the bootstrap enables it (`remix.reshade`: auto, on, off) with its own settings folder `native-loader\reshade`, made once from the game's `bin\win64\ReShade.ini`. A Direct3D 9 ReShade is never loaded into an RTX session and its files are never written ([ADR 0028](decisions/0028-reshade-in-rtx-sessions.md)). Tests in [`test_reshade.cpp`](../loader/tests/README.md) and [`tools/tests`](../tools/tests/test_package_reshade.py.md) |
| Module dependencies | [`loader/proxy/modules.cpp`](../loader/proxy/README.md), `nl::session::module_dependencies` | done (2026-10-29, loader 0.3.0) | A manifest's `module_dependencies`: the bootstrap loads a binary module's runtime DLL from `garrysmod\lua\bin` by absolute path just before the game loads the module, in every session ([ADR 0024](decisions/0024-bundled-addons-and-module-dependencies.md)). Tested in [`test_dependencies.cpp`](../loader/tests/README.md) and the synthetic [session test](../loader/proxy/tests/session_integration.py.md) |
| Local build workflow | [`tools/workflow.ps1`](../tools/workflow.ps1.md) | done (2026-10-28) | CI's build job on this machine: `tools\test.ps1 -Config Release` (or a build without tests), the bundle in `out\dist`, and with `-Install` the build in a game through `install-loader.ps1` (`-ReplaceUntracked` over a bundle extracted by hand) |
| CI build | [`.github/workflows/build.yml`](../.github/workflows/build.yml) | done (2026-10-28) | GitHub Actions on `windows-2022`: `tools\test.ps1 -Config Release` (conventions, build, CTest, Python tests), then the loader bundle as a run artifact; a `v*` tag makes a GitHub release with it ([ADR 0017](decisions/0017-release-bundle-and-ci.md)) |
| Workshop publisher | [`tools/publish_workshop.py`](../tools/publish_workshop.py.md), config [`tools/workshop.json`](../tools/workshop.json) | done (2026-10-28) | Builds the combined RTX package for item 3829070317 and uploads it with `gmpublish` when its content changed; its git hooks run it after commits and merges on `main` and before pushes of `main` ([ADR 0016](decisions/0016-one-workshop-item-kept-current.md)). Tests in [`tools/tests`](../tools/tests/test_publish_workshop.py.md) |
| Field snapshot and rollback | [`tools/field_snapshot.py`](../tools/field_snapshot.py.md) | done (M7) | Snapshot before the loader goes into a real install; one-command rollback (uninstall, remove what is new, restore files and registry, compare, verify depot files) |
| Package inputs | [`packages/`](../packages/README.md), [`tools/inputs.py`](../tools/inputs.py.md), tests in [`tools/tests`](../tools/tests/test_inputs.py.md) | done (2026-10-30) | Every input of the RTX package's ten parts, so this repository alone builds it ([ADR 0033](decisions/0033-one-repository-package-inputs-in-git-lfs.md)): text as it is, binaries xz-compressed in Git LFS, each part indexed (`files.json`: sizes, SHA-256s, times, LFS oids, origins); `inputs.py` imports from a packager's inventory, unpacks into `out\inputs` for the packagers and verifies (LFS pointers by oid) |
| Package build | [`tools/build_package.py`](../tools/build_package.py.md), [`tools/workflow.ps1`](../tools/workflow.ps1.md) `-Package` | done (2026-10-30) | The combined RTX package from `packages/` into `out\dist`, checked with the built `nlctl.exe`, compared with an upload's digest on request; the publisher's build without the upload |
| CI package build | [`.github/workflows/package.yml`](../.github/workflows/package.yml) | done (2026-10-30) | GitHub Actions on `windows-2022`, on changes to the package's inputs and by hand: cached Git LFS objects, `inputs.py verify`, a Release build of the loader, `build_package.py --require-nlctl`; keeps the summary (the `.gma` when asked for) |
| Runtime patches | [`runtime/`](../runtime/README.md), [`runtime/build_runtime.ps1`](../runtime/build_runtime.ps1.md) | done (2026-10-30) | This project's changes to the Remix runtime fork as a `format-patch` series against the fork commit in `base.json`; the script applies them in a fork worktree, builds twice (the shader stamp) and imports `d3d9.dll` into `packages/runtime` |
| Sky texture tools | [`tools/sky`](../tools/sky/make_moon_textures.py.md) | done (2026-10-30) | Make the runtime's sky textures: the Moon's from NASA's CGI Moon Kit ([`make_moon_textures.py`](../tools/sky/make_moon_textures.py.md)), the night sky's from Night Sky HD LE ([`bake_nightsky.py`](../tools/sky/bake_nightsky.py.md), [`nif_read.py`](../tools/sky/nif_read.py.md)), and check the shader's mappings against the mod's mesh ([`nightsky_mapping.py`](../tools/sky/nightsky_mapping.py.md)) |

## Outside this repo (used, not owned here)

None of these is needed to build the loader or the RTX package ([ADR 0033](decisions/0033-one-repository-package-inputs-in-git-lfs.md)):
what ships from them is in `packages/`. They are where a part's new version comes from, imported by hand
([packages/README.md](../packages/README.md)).

| Thing | Where | Role |
|---|---|---|
| Remix runtime fork | `sambow23/dxvk-remix-gmod` (`gmod-numos3` at `c6b48ed1`, [runtime/base.json](../runtime/base.json)), local clone `H:\BACKUP_20260815\Modding\dxvk-remix-gmod` | The runtime the package carries (Remix API 0.1000.1); this project's changes are [runtime/patches](../runtime/README.md) |
| RTX fixes | `SheepyLord/garrys-mod-rtx-remixed` (GPL-2.0), local clone beside this repo | `gmcl_RTXFixesBinary`, Lua add-ons, `rtx-remix/mods`: vendored unmodified as `packages/fixes` with their licence; code not copied into this repo's MIT code |
| The user's add-ons | `SheepyLord/Gmod-Model-Hotloader-with-Vulkan`, `-advanced_material_editor`, `-gmod_bullet_break_simulator`, `Gmod-Mmd-Motion-Importer`; `ipg\Remove_halo`, `ipg\!advanced_bodygroup_tool` | The sources of six parts in `packages/` |
| RTXLauncher | `SheepyLord/RTXLauncher` | The old separate-copy workflow this project replaces |

The translation checks are [`tools/companion_i18n.py`](../tools/companion_i18n.py.md) for the companion and new bundled interfaces, and [`tools/check_addon_i18n.py`](../tools/check_addon_i18n.py.md) for the add-ons’ existing catalogs and real language selectors.

The bootstrap also provides native package presentation (loader 0.7.0,
[ADR 0039](decisions/0039-native-package-addon-presentation.md)): derived inert GMAs and an addon-menu
script overlay under `native-loader/presentation`, served through exact read-only filesystem import
redirects. The payload journal and the actual Workshop archives keep their existing roles. The
proxy's `presentation.cpp` and fixture tests are listed in its component READMEs.

Native map glass is supplied by the indexed Glass-Rewrite-Remix part. Its server controller and
geometry helper preserve native brush behavior and create persistent networked debris; regression
coverage lives in tools/tests/test_glass_map.py and glass_map_harness.lua
([ADR 0040](decisions/0040-native-map-glass-debris.md)).

The bundled Model Hotloader renderer now routes depth behavior by native shader-family detection.
Coverage is in tools/tests/test_hotloader_depth.py and hotloader_depth_harness.lua; see
[ADR 0041](decisions/0041-hotloader-remix-depth-materials.md).

Remix persistence regressions use [`tools/tests/test_remix_settings.py`](../tools/tests/test_remix_settings.py.md)
and its Lua widget/lifecycle harness. Common Remix numeric controls are unbound and selected
explicitly; startup replay is opt-in. Runtime patch 0008 adds atomic checked Save and non-destructive
failed Reload ([ADR 0044](decisions/0044-remix-settings-persistence.md)).

The companion's `nativeloader_toolgun.lua` redraws the live toolgun screen after upscaling with a
private viewmodel depth mask. Its LuaJIT regression harness is
[tools/tests/test_toolgun_screen.py](../tools/tests/test_toolgun_screen.py.md).
Runtime diagnostic policy and welcome behavior are recorded in
[ADR 0045](decisions/0045-diagnostic-consent-and-welcome.md).

`nativeloader_model_layers.lua` controls only owned transient outline suppression, with collision
protection and late-hash/proxy tracking. Native cutout traversal and acceleration-cache fixes are
recorded in [ADR 0048](decisions/0048-layered-alpha-cutouts.md); outline behavior is in
[ADR 0047](decisions/0047-ignore-incompatible-model-outlines.md). Client lifecycle coverage is
[tools/tests/test_model_layers.py](../tools/tests/test_model_layers.py.md).
