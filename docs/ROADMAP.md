# Roadmap

Milestones with their acceptance criteria. Mark items here as they start and finish, and log the
change in [CHANGELOG.md](../CHANGELOG.md).

| # | Status | Scope | Done when |
|---|---|---|---|
| M0 | **done** (2026-10-27) | Repo on top of `origin/main`; AGENTS.md, docs, decision records, CHANGELOG; CMake presets + `build.ps1`; `test.ps1` + convention check; Steam depot tools (from the prep scripts); vendored gmapack | `tools\test.ps1` passes: conventions, Python tests, C++ build + CTest |
| M1 | **done** (2026-10-27, Codex, `m1-bootstrap`); [report](handover/M1-report.md), [brief](handover/M1-handover.md) | Inert bootstrap `loader/proxy`: complete System32 forwarding, main-game/Chromium host gate, off switches, EXE entry hook, guarded log; installer and smoke comparison | Debug/Release CTest 4/4, 16 proxy cases, 23 installer checks; all five PoC launches reach gm_construct with matching normalized output; tools unchanged; 2,877 depot files match after install and uninstall; PoC restored/uninstalled |
| M2 | **done** (2026-10-27, Claude, `m2-core`; merged into `main` with M1) | `nl_core`: GMA v1-v3 + LZMA reader (LZMA SDK, public domain), manifest schema 1, path rules, discovery (Workshop folder, `appworkshop_4000.acf`, `addonnomount.txt`, allowlist, local and dev sources), planner; `nlctl` CLI | Unit tests pass: 62 cases, and Debug/Release CTest 6/6 with M1 merged; outputs match `gmapack.py` on the same archives (`nlctl_crosscheck_gmapack`); read-only parse of all installed Workshop archives reports no errors: 753/753 (672 plain, 81 LZMA-wrapped; 104,847 entries); a full `nlctl verify` of the 81 legacy items matches every CRC and footer, one item having 4 bytes of padding after its trailer ([RESEARCH.md](RESEARCH.md) section 5) |
| M3 | **done** (2026-10-27, Claude, `m3-deployer`; merged into `main`); [ADR 0007](decisions/0007-transactional-deployment.md) | Deployer: staging, CRC32 + SHA-256 checks, atomic swap, journal, backups, rollback, `uninstall-loader.ps1` | Fault-injection tests (killed mid-deploy) leave a consistent state: the deployer killed by `TerminateProcess` before each of the 54 + 59 + 26 + 35 changes of a first deployment, an upgrade, a rollback and an uninstall, and the same failed or interrupted in process (with interrupted recoveries), always ends in the old or the new state. Re-runs are no-ops: 0 file-system changes, journal untouched. Uninstall leaves the PoC verifying as vanilla: `poc_deploy_check.ps1` found all 3,113 files and folders identical and 2,877 depot files OK. Debug/Release CTest 12/12, 94 `nl_tests` cases; an independent review's nine findings fixed before the merge |
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
