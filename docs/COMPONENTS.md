# Components

`loader/guard/` prepares the verified client rendering guard's early stock-initializer read redirect;
`loader/guard/tests/` exercises generated-file ownership, stock hashes, cache integrity and off switches.

C13 uses loader 0.10.0's [`loader/guard`](../loader/guard/README.md) to prepare an exact, client-only
read redirect for a hash-supported `includes/init.lua`. Its generated cache includes only the
catalog-SHA-verified RTX owner's V2 guard, after library setup and before third-party autoruns;
the Steam initializer stays unchanged. The owned cache is
`native-loader/presentation/render-guard-<sha>.lua`. The Lua guard requires verified native early proof or the existing verified multiplayer
bootstrap's raw private marker. An ordinary autorun/global marker cannot activate it; the later
multiplayer path uses _G.hook and reports its timing rather than claiming early protection. Activation fallback removes the executable
initializer redirect while ordinary presentation redirects may remain. Once a V2 owner guard is
catalog-verified for the selected `gmod-rtx-remix` runtime, stock-hash/cache preparation failure is
required-protection failure: RTX activation is refused with a clear reason and vanilla fallback.
Foreign runtimes do not read the stock initializer/cache through this path; legacy V1 marker
failure remains a nonfatal note. Inactive/server/menu contexts stay unchanged. The native early
suite has 20 passing cases, including foreign/legacy classifications; the latest native run passes
all 22 CTest entries. Controlled live runs record the stock initializer read hit.

R4 (loader 0.10.1, [ADR 0056](decisions/0056-guard-and-startup-fallbacks.md)) amends this: a guard
that cannot be prepared early no longer refuses RTX. Start-up notes why, and the companion's guard
installs from its autorun (installation "autorun") when this machine's status.json reports an active
start. The cache is named from its inputs and the generated block installs the guard only where that
file exists locally (`BASE_PATH`), so a listen host's served view does nothing on remote clients; a
changed cache file moves to `native-loader/backup/render-guard/`. With
`patch_sets.allow_rtx_render_patches: false` and no `-insecure`, start-up stays vanilla with a reason
(`client::render_recipes_refusal`), and `nlctl activation` says so. The multiplayer route protects
only owned callbacks and leaves `hook.Call` alone; `loader/client/poll.h` bounds the module's polling.

[`loader/proxy/backend.cpp`](../loader/proxy/backend.cpp) and the core command-line span/rewrite API
normalize explicit alternate shader backends to stock D3D9 only during active RTX startup. All
duplicates agree; unrelated raw arguments and RTX-off starts are preserved, and rollback restores
W/A/PEB descriptors. Six backend and eleven core command-line cases pass. The companion's broader
Lua guard passes seventeen unittest cases/eighteen LuaJIT scenarios and
actual-package mixed-add-on, map, callback-fault, UI and secure dedicated probes. Raw R32F27 is a
valid positive control. CI builds pinned official LuaJIT for these policies. See
[ADR 0054](decisions/0054-rtx-rendering-startup-boundaries.md) for timing/state/coverage limits.
No Remix or native fixes rebuild was needed; the accepted native fixes remain `5e626e34`.

Item 24's oversized-skinning correction belongs in the GPL RTX fixes native module
(`gmcl_RTXFixesBinary_win64.dll`), shipped by [`packages/fixes`](../packages/README.md). It extends
the existing wrapper across dynamic and direct hardware entries, with scoped bone uploads/palette
remaps and state restoration. Nine-argument re-entry and a thread-local same-group marker prevent
double wrapping. Automatic protection targets eligible oversized hardware groups. The same scope
also handles smaller non-flex, multi-bone groups already selected by the user's hardware mode,
inside RenderFinal and under the existing r_hwskin_setbones selection predicate. Ordinary default
draws, rigid props, flex and eye behavior retain their paths. Oversized-only creation certificates
prove every strip supplies all its used bone slots; fingerprints reject unknown/changed groups,
and unsafe config38 bit 0x08 fails closed. Smaller user-forced groups retain their remap behavior.
A DrawIndexedPrimitive-scoped declaration conversion preserves UBYTE4 blend-index ordering,
with a bounded 16-entry COM cache and original declaration restoration. The loader's permissions,
global cvars and Remix option files
are outside this change. [Corresponding source](../packages/fixes/licenses/oversized-skinning/Source.md),
COPYING, pins, generated projects and patches ship under the short add-on path `remixbinary/src/hw`
to stay within Windows staging path limits. Source/build provenance and final-DLL default NPC/arms
checks are complete. The actual final GMA also passes force1 PM/two-skin and visible-arms checks;
secure dedicated multiplayer, CI and publication also passed for that accepted shipment. Findings are in
[RESEARCH.md](RESEARCH.md#oversized-airi-skinning-groups-item-24) and
[ADR 0053](decisions/0053-oversized-hardware-skinning.md).

[`packages/fixes/licenses/oversized-skinning/tests`](../packages/fixes/licenses/oversized-skinning/tests/README.md)
adds the standalone GPL CTest `rtx_oversized_skinning_policy`. It compiles the shipped policy with
assertions enabled in Release and checks eligibility, complete strip palettes and borrowed-state
restoration using CPU fixtures. It needs no Source SDK or GPU and links no MIT loader code; the
root CMake build registers it as a separate executable for CI. The targeted Release build and
CTest pass with /UNDEBUG confirmed in the actual compile command.
The final policy also covers user-mode filtering and unsafe static fallback. The final Release
suite passes 20 CTests and 277 Python tests (7 skips).

Loader 0.9.0 adds [`loader/client`](../loader/client/README.md): an immutable, SHA-256-verified
catalog of Lua belonging to the allowlisted `gmod-rtx-remix` owner, a menu-realm native helper
(`gmsv_nlrtxclient_win64.dll`) and its private client initializer. It leaves `sv_allowcslua` and
global engine include/require/file/net functions unchanged. A shared scoped net adapter drops
owned messages for absent server channels and records them locally; registered channels keep the
engine API. The environment-only `NATIVELOADER_VERIFIED_MULTIPLAYER` marker lets packaged GPL
cl_rtx.lua avoid initial/final model-cache flushes after the world is active. The catalog classifies the exact
seven rendering recipes eligible for the secure-launch exception; other patches keep the general
gate. [`loader/client/tests`](../loader/client/tests/README.md) tests ownership, bytes, source
allowlists and recipe mutations. [test_mp_bootstrap.py](../tools/tests/test_mp_bootstrap.py.md)
executes the actual initializer and extracted actual cl_rtx.lua reload section in LuaJIT
(6 tests/14 scenarios). The public Lua SDK headers and BSD-3-Clause licence are
recorded in [`third_party/gmod`](../third_party/gmod/README.md). See
[ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md) for scope and completed dedicated-server checks.

Loader 0.8.1's `loader/proxy/diagnostics.cpp` supplies local system/package identity data to the
read-only main-menu presentation layer. `loader/proxy/ui/` holds the JavaScript, labels and CMake
embedding template. `companion/presentation/` holds editable, localized startup text copied as
create-only root files by package_fixes.py. [test_presentation_ui.py](../tools/tests/test_presentation_ui.py.md)
checks assets and the actual UI script alongside the proxy C++ tests and runtime text-policy test.

The companion's `nativeloader_imported_normals.lua` collects active imported-model hashes for an
optional additive NoSave smooth-normal category. It and AME's original-name/current-selection
behavior are checked offline by [test_addon_workflow.py](../tools/tests/test_addon_workflow.py.md)
and its Lua harness. `nativeloader_motion_tab.lua` is the Motion importer creation tab: the bundled
motion importer's in-game importer and Motion Manager, built into the tab by the add-on's own
builders (`MMDVMDNPC.BuildMotionImporter`, `MMDVMDNPC.BuildMotionManager`, which its windows use
too) in External Models' look ([ADR 0060](decisions/0060-motion-tab-hosts-the-importer.md));
[test_motion_tab.py](../tools/tests/test_motion_tab.py.md) checks the tab, the builders and the
windows under LuaJIT.

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
| Field QA probes | [`tools/qa`](../tools/qa/rtx_session_probe.lua.md) | done (2026-10-31, R4) | Client Lua probes for `poc_session.py --lua`: the RTX session's state and the toolgun screen, map glass on modern_house, spawned procedural glass, the spawn menu's External Models and Motion importer tabs; [`release_qa.py`](../tools/qa/release_qa.py.md) runs them all on the field or the PoC and applies the pass rules of the release QA protocol in [TESTING.md](TESTING.md#release-qa-protocol-field-install-r4) |

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

Broken glass is loose physics since R5 ([ADR 0061](decisions/0061-loose-glass-breaks-again-and-expires.md)):
the part's `glass_debris.lua` registers every piece that breaks off, from map windows and from the
add-on's own panes, gives it a collision group players pass through, counts it in one 256-piece
oldest-first budget and fades it out after `rtx_glass_debris_lifetime` seconds (default 120, 0 keeps
it); pieces break again until they are dust. The same harness runs the real entity code for it.

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

## R6 T1 loader GPU policy

`loader/core/include/nl/performance.h` / `src/performance.cpp` hold pure GPU tier classification
and I2 serialization. `gpu_diagnostics.h` / `src/gpu_diagnostics.cpp` probe/prepare local GPU dump
state and atomically consume one-start requests. `activate` composes the two layer-priority slots;
`loader/proxy/runtime.cpp` applies them, `status` and `loader/cli/nlctl.cpp` report them, and
`loader/proxy/diagnostics.cpp` / `ui/mainmenu.js` show a localized menu tier preview (ADR 0062).

T1 review separates `presentation::prepare_main_menu` so activation supplies its effective layer
plan after writes, and vanilla fallback supplies an inactive plan. Core GPU diagnostics can reset
the one-start marker on off-mode RTX starts. Proxy `test_runtime.cpp` applies the real activation
code to fake DLLs to verify failed tier writes/reset attempts preserve RTX without a GPU reader.
