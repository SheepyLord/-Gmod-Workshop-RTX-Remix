# Components

Every component of the project: where it lives, what it does, and its status. Keep this file in
sync when you add, rename or finish something ([`tools/check_repo.py`](../tools/check_repo.py.md)
fails if a folder under `loader/` or `tools/` is missing here).

Status: **done** (usable), **skeleton** (builds, little function), **planned** (milestone in
[ROADMAP.md](ROADMAP.md)).

## Runs inside the game

| Component | Path | Status | What it does |
|---|---|---|---|
| Bootstrap | `loader/proxy` → `bin\win64\winmm.dll` | planned (M1) | Loaded by `gmod.exe` at process start. Forwards every `winmm` export to the system DLL, checks it is inside `bin\win64\gmod.exe` and that no off switch is set, then runs the start-up step at the EXE entry point: discover packages, deploy, activate the runtime, write the status file. Any error is logged and the game continues vanilla. |
| Core library | `loader/core` (`nl_core`) | skeleton (M0) | Logic shared by the bootstrap, the CLI and the tests: GMA reading (incl. LZMA-wrapped), manifest parsing, path rules, discovery, planning, transactional deployment, journal (M2/M3). Today: version only. |
| Lua companion | `addon/` | planned (M5/M6) | Normal GMod Lua addon. Reads `garrysmod/data/native-loader/status.json`, shows runtime state and errors, and tells the user to restart when a package update has been downloaded. |
| Remix runtime package | `packages/remix-runtime/` | planned (M4) | Recipe for the package that carries the user's Remix fork build: manifest template, `rtx.conf`/`dxvk.conf` layers, launch arguments, later patch sets. |

## Runs outside the game

| Component | Path | Status | What it does |
|---|---|---|---|
| CLI | `loader/cli` → `nlctl.exe` | planned (M2) | Same core as the bootstrap: `list`, `inspect`, `plan`, `apply`, `rollback`, `verify` against an install, so deployment can be tested without starting GMod. |
| Unit tests (C++) | [`loader/tests`](../loader/tests/README.md) | done (M0 harness) | `nl_tests`, run by CTest. |
| Build | [`tools/build.ps1`](../tools/build.ps1.md) | done | Configure, build and test with MSVC x64, CMake presets and Ninja. |
| MSVC environment | [`tools/lib`](../tools/lib/VsDevEnv.psm1.md) (`VsDevEnv.psm1`) | done | Finds VS / Build Tools (even when `vswhere` cannot) and imports `vcvars64`. |
| Test runner | [`tools/test.ps1`](../tools/test.ps1.md) | done | Runs the convention check, all Python tests and the C++ build + tests. |
| Convention check | [`tools/check_repo.py`](../tools/check_repo.py.md), tests in [`tools/tests`](../tools/tests/test_check_repo.py.md) | done | Enforces script docs, module READMEs, links, changelog, this component map. |
| Steam depot tools | [`tools/steam`](../tools/steam/steam_manifest.py.md) | done | Parse depot manifests; [`verify_install.py`](../tools/steam/verify_install.py.md) proves an install is vanilla and lists extras; [`make_vanilla_copy.py`](../tools/steam/make_vanilla_copy.py.md) builds the PoC install from verified local files; [`vdf.py`](../tools/steam/vdf.py.md) reads `.acf`/`.vdf`. |
| PE diagnostics | [`tools/diag`](../tools/diag/pe_imports.py.md) (`pe_imports.py`) | done | Lists imports and exports of EXEs and DLLs (hook points, runtime dependencies). |
| GMA packer | [`tools/gmapack`](../tools/gmapack/gmapack.py.md) | vendored | Python `.gma` reader and writer; reference for the C++ reader and the packer for test and runtime packages. |
| Runtime packager | `tools/package_runtime.py` | planned (M4) | Turns a Remix build folder into a runtime package `.gma` with a manifest and SHA-256 per file. |
| Install / uninstall | `tools/install-loader.ps1`, `tools/uninstall-loader.ps1` | planned (M1/M3) | Copy the bootstrap into an install (PoC by default), and remove everything the journal lists. |
| In-game smoke test | `tools/smoke_test.ps1` | planned (M1) | Launches the PoC with the bootstrap and checks the logs. |

### M1 implementation additions

The planned bootstrap/install/smoke rows above now have M1 implementations (validation status and
evidence are in the M1 report when complete):

| Component | Path | Implementation |
|---|---|---|
| Inert bootstrap | [`loader/proxy`](../loader/proxy/README.md) | `winmm.dll`; full System32 export forwarding, host/off-switch gate, entry-point hook and guarded log only. Package activation remains M2–M4. |
| Bootstrap tests | [`loader/proxy/tests`](../loader/proxy/tests/README.md) | `nl_proxy_tests`, static-import host, export-generation and installer CTests. |
| Bootstrap install/uninstall | [`tools/install-loader.ps1`](../tools/install-loader.ps1.md) | Copies DLL/PDB, records SHA-256, refuses foreign/edited files and Steam-managed roots by default; `-Uninstall` retains state. Journal-based package removal remains M3. |
| PoC smoke comparison | [`tools/smoke_test.ps1`](../tools/smoke_test.ps1.md) | Five map loads, two tool comparisons, evidence and loader-state restoration. |

## Outside this repo (used, not owned here)

| Thing | Where | Role |
|---|---|---|
| Remix runtime fork | `SheepyLord/dxvk-remix-gmod` (`gmod-1.6.1`), local checkout `H:\BACKUP_20260815\Modding\dxvk-remix-gmod` | The runtime the packages carry (Remix API 0.1000.1) |
| RTX fixes | `garrys-mod-rtx-remixed` (GPL-2.0), local checkout beside this repo | `gmcl_RTXFixesBinary`, Lua addons, `rtx-remix/mods`; packaged by us later, code not copied |
| RTXLauncher | `SheepyLord/RTXLauncher` | The old separate-copy workflow this project replaces |
