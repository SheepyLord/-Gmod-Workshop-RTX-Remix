# Components

Every component of the project: where it lives, what it does, and its status. Keep this file in
sync when you add, rename or finish something ([`tools/check_repo.py`](../tools/check_repo.py.md)
fails if a folder under `loader/` or `tools/` is missing here).

Status: **done** (usable), **skeleton** (builds, little function), **planned** (milestone in
[ROADMAP.md](ROADMAP.md)).

## Runs inside the game

| Component | Path | Status | What it does |
|---|---|---|---|
| Bootstrap | [`loader/proxy`](../loader/proxy/README.md) → `bin\win64\winmm.dll` | M1 done (inert) | Loaded by `gmod.exe` at process start. Forwards every `winmm` export to the system DLL, checks it is inside `bin\win64\gmod.exe` and that no off switch is set, then runs the start-up step at the EXE entry point: discover packages, deploy, activate the runtime, write the status file. Any error is logged and the game continues vanilla. M1 built the inert part (forwarding, host gate, off switches, entry hook, log); the start-up step comes with M3 (deploy) and M4 (activate). |
| Core library | [`loader/core`](../loader/core/README.md) (`nl_core`) | M3 done | Logic shared by the bootstrap, the CLI and the tests. M2: GMA reader (GMAD v1-v3, plain and LZMA-wrapped with GMod's footer, verify, single-file reads, one-pass extraction), strict JSON, path rules, manifest schema 1, packages from archives or dev folders, `config.json`, KeyValues, discovery without the Steam API, planner. M3: SHA-256 (CNG), the file-system layer, the journal and the transactional deployer (apply, rollback, uninstall, recovery; [ADR 0007](decisions/0007-transactional-deployment.md)). M4: activation planning (`activate::plan`) and the in-memory command-line patch (`nl::cmdline`; [ADR 0008](decisions/0008-activation-at-startup.md)). |
| Lua companion | `addon/` | planned (M5/M6) | Normal GMod Lua addon. Reads `garrysmod/data/native-loader/status.json`, shows runtime state and errors, and tells the user to restart when a package update has been downloaded. |
| Remix runtime package | `packages/remix-runtime/` | planned (M4) | Recipe for the package that carries the user's Remix fork build: manifest template, `rtx.conf`/`dxvk.conf` layers, launch arguments, later patch sets. |

## Runs outside the game

| Component | Path | Status | What it does |
|---|---|---|---|
| CLI | [`loader/cli`](../loader/cli/README.md) → `nlctl.exe` | M3 done | Same core as the bootstrap, so packages and installs can be examined and deployed without starting GMod: `inspect`, `verify`, `scan`, `manifest`, `plan`, `status`, `activation` (read-only), and `apply`, `rollback`, `uninstall` (with `--dry-run`). Four CTests on `gmapack.py`-built archives: cross-check, end-to-end plan, end-to-end deploy, and `uninstall-loader.ps1` in synthetic game folders. |
| Unit tests (C++) | [`loader/tests`](../loader/tests/README.md) | done (harness), grows with each milestone | `nl_tests`, run by CTest: 106 cases over CRC-32, GMA, LZMA, JSON, paths, manifests, packages, KeyValues, config, discovery, planner, SHA-256, `nl::fs`, journal, deployer, activation and command line, 3 of them exhaustive fault injection (their own CTests). `nl_fault_host` and [`deploy_faults.py`](../loader/tests/deploy_faults.py.md): the deployer killed before every change. |
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

## Outside this repo (used, not owned here)

| Thing | Where | Role |
|---|---|---|
| Remix runtime fork | `SheepyLord/dxvk-remix-gmod` (`gmod-1.6.1`), local checkout `H:\BACKUP_20260815\Modding\dxvk-remix-gmod` | The runtime the packages carry (Remix API 0.1000.1) |
| RTX fixes | `garrys-mod-rtx-remixed` (GPL-2.0), local checkout beside this repo | `gmcl_RTXFixesBinary`, Lua addons, `rtx-remix/mods`; packaged by us later, code not copied |
| RTXLauncher | `SheepyLord/RTXLauncher` | The old separate-copy workflow this project replaces |
