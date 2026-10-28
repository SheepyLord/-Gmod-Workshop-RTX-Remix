# Roadmap

Milestones with their acceptance criteria. Mark items here as they start and finish, and log the
change in [CHANGELOG.md](../CHANGELOG.md).

| # | Status | Scope | Done when |
|---|---|---|---|
| M0 | **done** (2026-10-27) | Repo on top of `origin/main`; AGENTS.md, docs, decision records, CHANGELOG; CMake presets + `build.ps1`; `test.ps1` + convention check; Steam depot tools (from the prep scripts); vendored gmapack | `tools\test.ps1` passes: conventions, Python tests, C++ build + CTest |
| M1 | assigned to Codex: branch `m1-bootstrap`, brief [handover/M1-handover.md](handover/M1-handover.md) | Inert bootstrap `loader/proxy`: `winmm.dll` with every export forwarded (generated from the System32 export list), host check, off switches, EXE entry-point hook, logging; `install-loader.ps1`, `smoke_test.ps1` | PoC reaches the menu and loads gm_construct with the bootstrap, with the same console output as without it; GMod tools in `bin\win64` (hlmv, studiomdl, ...) unaffected |
| M2 | assigned to Claude: branch `m2-core` (in parallel with M1) | `nl_core`: GMA v1-v3 + LZMA reader (LZMA SDK, public domain), manifest schema 1, path rules, discovery (Workshop folder, `appworkshop_4000.acf`, `addonnomount.txt`, allowlist, local and dev sources), planner; `nlctl` CLI | Unit tests pass; outputs match `gmapack.py` on the same archives; read-only parse of all installed Workshop `.gma` files reports no errors |
| M3 | planned | Deployer: staging, CRC32 + SHA-256 checks, atomic swap, journal, backups, rollback, `uninstall-loader.ps1` | Fault-injection tests (killed mid-deploy) leave a consistent state; re-runs are no-ops; uninstall leaves the PoC verifying as vanilla |
| M4 | planned | `package_runtime.py` builds a runtime package from the user's current fork build; activation: preload, config layers, env vars, launch arguments | On the PoC with a local package: Remix initialises (runtime log), gm_construct is path-traced; RTX off gives vanilla rendering; switching versions and rolling back work |
| M5 | planned | RTX fixes on vanilla: `gmcl_RTXFixesBinary` / `gmcl_rtxwater` as `lua-binary-module`, `rtx-remix/mods` as root files, required cvars, shaderapidx9 + materialsystem patch sets at module load, `stdshader_dx6` override; Lua companion | PoC matches `GarrysMod_RTX_c` on the user's gm_csgosafehouse test save (their block-difference measure) |
| M6 | planned | Workshop route: private-visibility upload test of a runtime package, LZMA-wrapped downloads, two-phase update with restart prompt | Distribution route chosen with evidence ([ADR 0002](decisions/0002-source-agnostic-payloads.md) updated or superseded) |
| M7 | planned | Field test on the user's install: snapshot and rollback scripts; coexistence with DXVK `d3d9.dll`, GModPatchTool's `vulkan-1.dll`, MMD Hotloader, Jolt | One-command rollback tested; RTX on and off both work in the field install |
| Later | — | Signed manifests (authenticity), bootstrap self-update, URL + SHA-256 sources, more package kinds | — |

## Risks being watched

| Risk | Plan |
|---|---|
| Workshop refuses or removes items with `.dll`/`.exe` | M6 tests a private upload before anything depends on it |
| VAC and in-memory patches | Patch sets require `-insecure` by default |
| Launch arguments cannot be added from inside the process | Fall back to documented Steam launch options |
| `stdshader_dx6.dll` loaded by full path | Redirect hook, else journaled on-disk override with hash checks |
| Remix bound to a non-system `vulkan-1.dll` in the field install | `prefer_system_vulkan_loader` preloads System32's |
| Redistributing NVIDIA binaries (DLSS, NRC, ...) publicly | Check licences before any public package |
