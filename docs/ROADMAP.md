# Roadmap

R10-H implementation and PoC QA are **complete** on `r10-hotloader` (2026-11-02):
original PMX expression binding, geometry-checked meanings, overflow playback,
truthful mapping and cache rebuilding; stale-mount/per-map NPC readiness.
Release passes 26 CTests and 520 Python tests (two existing skips). Stock-menu
and library requests pass both map changes, fresh flatgrass and a listen server;
Guinaifen/Robin expression weights and screenshots pass. The exact field
missing-model error remains unreproduced; even the Workshop-baseline cold
ragdoll→map→first-NPC test passes. Claude retains merged integration and field
confirmation ([report](handover/R10-H-report.md)).

R10-H (items 33 and 34) is **in progress** on `r10-hotloader`: original PMX
expression identities, geometry-checked fallback, overflow playback and truthful
mapping/caches; ready carrier registration across maps. Offline regressions and
the Release native build pass; PoC QA shares the R10-E lock. Decisions are
[0089](decisions/0089-pmx-identities-and-geometry-checked-vmd-expressions.md) and
[0090](decisions/0090-ready-carriers-before-actor-publication.md).

R9 (the user's glass report of 2026-11-02) is **done**: CI is green again (the glass mirrors' dropped steps
and the exit observer's clock race), `v0.12.1` is released and only `main` remains. Glass breaks
realistically down to tiny pieces, without visible delay, with sounds, in water and under every kind of
explosion, without pieces flying backwards, and the settings can clear broken glass. Each was checked on
the PoC. See [the report](handover/R9-report.md).

R9-G implementation, offline validation and PoC measurements are **complete** on `r9-glass`
(2026-11-02): irregular tiny shards, immediate visible breaks, sounds, water, native/empty blasts,
stable transfer and local/admin clearing. Release passes 26 CTests and 515 Python tests (two
existing skips); the measured 50-pane falling mean/p99 are 12.999/45.023 ms. Claude retains review,
module import, two clients and repeated fully sleeping performance acceptance
([report](handover/R9-G-report.md), [ADR 0087](decisions/0087-glass-shards-and-environment.md)).

R9-G is **in progress** on `r9-glass`: irregular one-unit shards, receipt-frame break visibility,
local contact sounds, BSP buoyancy, empty-space explosions, overlap-safe velocity transfer and
local/admin debris clearing ([brief](handover/R9-G-glass.md),
[ADR 0087](decisions/0087-glass-shards-and-environment.md)). Claude owns integration and field QA.

R8 (the user's report after R7, 2026-11-01) is **done**: the character noise R7's runtime patch caused
is gone (patch 0018); vanilla characters stay out of bind pose (the Backrooms add-on no longer forces
`r_forcehwlight 1`, and the guard pins it); graphics add-ons such as GShader Library get safe fallbacks
instead of guard-made Lua errors, with their screen-space effects inert under RTX; falling glass costs
11-12 ms instead of 26-29 ms; glass has collision levels with living entities off; bullets and melee break
fractured glass at any time; the Backrooms work's native fixes are in the fixes DLL. Each was checked on
the PoC. See [the report](handover/R8-report.md). Afterwards, loader 0.12.1 stops Windows from marking
the game window "Not Responding" during long loads (the user's report from the field).

R8-C's pre-QA review corrections are **complete offline** (2026-11-01):
native material loads/readers, exact bundled-caller exemptions and binding-only shader checks replace
the earlier material preflight. The 1,200-path harness proves zero added VMT reads, including icons
and repeated misses. The [updated report](handover/R8-C-report.md) records modeled costs and source
collision limits. Release passes 26 CTests and 495 Python tests (two existing skips), including
47 guard test methods/49 LuaJIT invocations and a static inventory check. Claude retains game QA;
no game or install is touched here.

R8-C implementation and offline acceptance are **complete** on `r8-compat` (2026-11-01):
non-throwing guard fallbacks, inert screen-space shaders, eight exact archive source inventories,
ADR 0086 and eighteen add-on replay cases. Release passes 26 CTests and 488 Python tests (two
existing symlink skips); the guard has 40 methods/43 LuaJIT scenario invocations. Claude retains
PoC/two-client/tester-machine acceptance; see [the report](handover/R8-C-report.md).

R8-C is **in progress** on `r8-compat` (2026-11-01): reinvestigate GShader and the named graphics
add-ons, replace guard-created errors with safe fallbacks, and document inert effects under RTX.
Eight exact source archives are indexed in [the second audit](audits/R8-C-addon-compat.md); Claude
retains GPU and two-client acceptance. No game or install is changed by this task.

R8-G implementation and offline validation are complete on `r8-glass` (2026-11-01): bounded construction/GPU retirement, exact distant rigid groups, collision categories with living actors off, and renewable bullet/melee routing. The full Release gate passes; Claude's PoC half-cost/real-weapon/two-client acceptance remains pending. See [the R8-G report](handover/R8-G-report.md).

R8-G is in progress on `r8-glass`: falling-load mitigation, client Source collision flags and persistent follow-up bullet/melee hits; offline regression/measurement and Claude's PoC QA are required ([brief](handover/R8-G-glass.md)).

R7 (the user's report of 2026-11-01) is **done** (2026-11-01, loader 0.12.0):

- **Mask.** Columbina's mask renders as in MMD under RTX: runtime patch 0017 adds a texture category
  for Model Hotloader textures, and the companion fills it, soft copies included.
- **Exit report.** An observer outside the game reports why it ended (out of memory, device lost,
  crash), with the evidence folder.
- **Diagnostics.** The memory warning needs a real shortage of map headroom, and the panel counts
  the content add-ons.
- **Glass.** Players, NPCs, props, ragdolls, bullets, blasts and landings push and break broken glass,
  one way.

Each point was checked on the PoC. Integration fixed four things the game found: soft-copy tracking,
the dialog's path style, the body search's frame cost and the boxes of client physics bodies. See
[the report](handover/R7-report.md).

R7-C's fast-body fix is implemented on `r7-glass-fix` from `7b49de9` (2026-11-01): bounded swept
discovery, immediate/prioritized fast boxes, and capped one-way mirror sweeps. The real Lua-to-Jolt
sleeping-pile regression fails before and passes after at 650/3600 units/s and 60/30 Hz. All 31
native glass and 70 glass Python cases pass. The broader run passes 26 CTests/470 Python tests,
but the top-level gate still flags three pre-existing links to the missing R7-A brief; scope
clarification is pending for a minimal redirect. Claude retains PoC drum/frame-parity acceptance.
See [the fix report](handover/R7-C-report.md#r7-c-fast-body-fix-pass-r7-glass-fix).

R7-B implementation and offline acceptance are **complete** on `r7-crash-diag` (2026-11-01):
the embedded external exit observer, seven-language reports/previews, revised commit warning
and content add-on count. Release passes 26 CTests and 455 Python tests (two expected skips);
23 observer scenarios and a real, automatically acknowledged French dialog use synthetic hosts.
Claude retains actual PoC acceptance and integration; see [the report](handover/R7-B-report.md).

R7-B is **in progress** on `r7-crash-diag` (2026-11-01): a post-exit crash report from an
external observer, a map-headroom memory warning and a compact content add-on count. This task
does offline checks only; Claude retains PoC acceptance ([brief](handover/R7-B-crash-diagnostics.md)).

R7-C implementation and offline acceptance are **complete** on `r7-glass-interact` (2026-11-01):
bounded one-way Source mirrors, follow-up damage/fracture, Source-clipped pellet rays, original
descendant expiry, a seven-language per-player switch and the 19-step interaction QA sequence.
Release passes 25 CTests (29 native glass cases) and 468 Python tests (two existing skips), with
68 glass Python cases. Claude retains module import and real contact/two-client/RTX frame-parity
acceptance; no game or install was touched. See [the report](handover/R7-C-report.md).

R7-C is **in progress** on `r7-glass-interact` (2026-11-01): one-way Source mirrors, bounded local
follow-up damage/fracture and bullet rays, a per-player setting and offline tests. Claude owns
package import, integration and PoC contact/performance acceptance; no game is run by this task.

R7-A started 2026-11-01 on `r7-alpha`: scoped MMD alpha texture semantics and transient Model
Hotloader registration ([brief](handover/R7-A-mmd-alpha.md), [ADR 0081](decisions/0081-mmd-alpha-texture-category.md)).
Claude owns runtime import, integration and the mask/ramp/map-glass game acceptance; this worktree
does not launch or deploy to the game.

R7-A implementation and the isolated runtime build finished 2026-11-01: 29 fork unit tests and
16 companion scenarios pass. Release native/Python checks pass; the packaged-runtime provenance
gate remains pending the prohibited import or approval of separate unimported-build validation.
Claude's import/integration and GPU acceptance remain open; see the [R7-A report](handover/R7-A-report.md).

G1 (a glass overhaul) is **done** (2026-11-01): the MIT glass system and the Jolt module replace
Glass-Rewrite-Remix as the package's eleventh part. Game QA on the PoC passed every cause, walking
(whole) and running (broken), map glass on modern_house and the 50-pane scene; integration fixed
walking breaking glass (archived settings of the old add-on, reset once; shadow contact) and made
breaks irregular at the user's request. See [the report](handover/G1-report.md).

G1-A second-pass implementation and offline validation are complete on `g1-lua-fix2`: all four
items are implemented, with 200/300-piece bounds, lit cracks, walking below the 250-unit/s default
and deferred/coalesced client builds. Release passes 25 CTests and 453 Python tests (two existing
skips), including 50 glass cases. Mocked total client break CPU drops from 13.59 to 2.88 ms mean;
the density change lowers prepared topology from 502 to 164 cells. Real crack lighting, body
contact, prediction and the 50-pane comparison with G1-B remain Claude's game acceptance work.

G1-B's second fix pass is **complete offline** on `g1-native-fix2` (2026-11-01): consolidated
settled material areas, pooled/timed rebuilds and staged resource retirement, grouped/cached
individual drawing, current-view/distance/subpixel culling, and per-frame manager timings/calls.
Release passes 25 CTests/448 Python tests (two existing skips), with the documented local guard
output-path workaround; the final Lua harness passes 14,576 assertions. Mocked 2,000-piece piles
draw in four batches, and mixed-visibility individual draws fall from 2,000 to 500. Claude retains
all real-game frame targets and integrated visual acceptance; see [the second-pass report](handover/G1-B-fix2-report.md).

G1-A's integration fix pass is **complete offline** on `g1-lua-fix` (2026-11-01): all eleven
items in [the brief](handover/G1-fix-pass.md) are implemented, with 45 glass tests and before-failing
regressions. Release passes 25 CTests and 448 Python tests (two existing skips). Near-cap fracture
means are 0.84 ms new hit, 0.10 ms repeat, 0.67 ms break; real frame-time acceptance remains open.
Claude still combines G1-B's fixes and checks player contact, map outputs/effects, weak-hit and
tempered visuals, two clients/prediction and the 40/50-pane scene in game. No game was launched,
no install changed, no G1-B file edited and no package, upload, push, merge or tag was made.

G1-B fix-pass implementation and offline checks are **done** on `g1-native-fix` (2026-11-01):
gm_construct imports despite isolated bad hulls, terrain indexing/tags are corrected, preparation
and stepping run on polled workers, active/changed pose queues and staged pile chunks reduce client
work, and cache saturation stays nonfatal. Release passes 25 CTests and 426 Python tests with the
documented local guard-output path workaround. Real map/prop contacts, responsive first breaks and
Remix frame-time acceptance stay with Claude; see [the fix report](handover/G1-B-fix-report.md).

G1-A is **implemented and passes offline acceptance** on `g1-lua` (2026-11-01): original MIT panes,
unified impacts/strength, bounded deterministic annealed/tempered fracture, synchronized growing
cracks, remaining frozen collision/prediction, map input bridging, late join, cleanup, property-only
save/dupe, tool/presets and seven-language settings. The existing companion settings destination is
retained. All 23 new G1 cases pass; Release passes 24 CTests and 425 Python tests (two existing skips).
G1-B integration, package assembly, real engine outputs/weapon tuning/material/prediction checks and
the old/new 50-window/pile performance measurements remain with Claude. No game was launched and no
game install, Steam settings, user.conf or Workshop item was changed. See [implementation](../glass/README.md)
and [the G1 brief](handover/G1-A-lua.md).

G1-B implementation and offline acceptance are **done** on `g1-native` (2026-10-31): Jolt 5.3.0,
the native glass world/module, bounded BSP import, debris rendering/batching and Source fallback,
with generated-fixture native tests and a LuaJIT manager/probe harness. Release passes 25 CTests
and 402 Python tests (two expected fixture skips). Four thousand colliding shards sleep in 11.02
simulated seconds; settled core step/pose cost is 0.091 ms on this machine. Packaging, real-map
collision/material checks and Remix frame-time acceptance remain with Claude; see
[the module README](../glass/native/README.md) and [testing](TESTING.md).

R6 harness failure handling is **done with offline validation** on `r6-harness` (2026-10-31): whole-run crash-prompt
watchdog, device-loss/continuous-hang detection, bounded capture and exit, retained evidence and
explicit release-QA reasons. Validation uses fake games/windows only; game acceptance stays with
the project manager ([testing note](TESTING.md#r6-unattended-harness-failures)).

R6 T3 implementation (companion telemetry, tier display, translated stability guide and 2048 px
publishing guidance) was committed as `a28d6b6` on `r6-t3-companion`; see
[the task brief](handover/R6-T3-companion-docs.md). Its independent-review fix pass covers older-loader
guidance, missing tier layers/hardware, recoverable CSV segments, API back-off and documentation.
The fix pass is complete on that branch: all 37 companion tests, both i18n checks,
skill validation and the full Release gate pass with the user's access (288 tools Python tests,
23 CTests; the unchanged guard passes from a shorter executable path). Integration, human
translation review and game acceptance remain with the project manager; this task started no game.

R6 T6 is **done** (2026-10-31, branch `r6-t6-tiers`, measured in the R6 integration): optional
medium/low runtime payloads, lossless mip removal and 4096-wide sky inputs are implemented.
Tier options have source-pinned validation and the DDS fixtures cover every accepted format.
On the PoC at 4K on an RTX 5090, medium and low run 5-9 % faster than high and use 170-750 MiB
less VRAM; low takes medium's 8 bounces, since 4 measured no faster. An 8 GB card, a zoomed sky
and the class-limited low-memory trade-off remain unmeasured;
[ADR 0064](decisions/0064-performance-tier-defaults.md) records the source-verified consequences
and why medium retains the original skies.

R6 T5 is **implemented and passes offline acceptance** on `r6-t5-fixes`: the fixes DLL drops
unsupported memory-limit writes while keeping its Lua compatibility API
([ADR 0066](decisions/0066-fixes-memory-limits-compatibility.md)); all 83 ToPBR textures use
linear BC7, reducing DDS size from 136.25 to 34.07 MiB. Controlled rebuild/source checks,
compatibility and oversized-skinning regressions, deep input verification, the full Release
suite (23 CTests, 333 Python tests with 2 skips), and the nlctl-validated combined package pass.
Game acceptance belongs to R6 integration: no resource-limit rejections at map load and
unchanged ToPBR appearance. See [T5 validation](TESTING.md#r6-t5-topbr-compression).

R6 T2 implementation and automated validation are **done** on `r6-t2-evidence`: bounded previous-session
evidence, startup/CLI reporting, bootstrap memory history, and seven-language failure/RAM notices.
Release passes 24 CTests and 334 Python tests (two expected skips), with the pre-existing long-worktree
guard-test path workaround documented in [TESTING](TESTING.md#r6-t2-local-evidence-and-telemetry).
No game was launched; integration and game QA remain with Claude ([T2 brief](handover/R6-T2-evidence-telemetry.md)).

C13 graphics-add-on/map-load hardening is **done and published** in loader 0.10.0.
The verified early guard, scoped later multiplayer installation, D3D9 backend normalization and
required-protection vanilla fallback pass Release, actual-package and secure dedicated tests.
Release: 22 CTests/294 Python tests (7 skips); 17 guard cases execute 18 LuaJIT scenarios.
The actual 998-file GMA passes mixed-add-on/fault, toolgun/menu and corrupt-cache controls.
Steam files, user.conf, launch settings and native trust remain unchanged. Distribution item 3829070317 carries `0.0.0-dev.20261031102150+eb483442`; main includes `6e427e52`. Receipts are in [the QoL report](handover/QoL-report.md#c13-graphics-add-ons-and-map-loading-2026-10-31).

The durable audit covers 17 API families, 43 primary URLs (41 wiki), 25 indexed call-site files
(12 stock/13 add-on) and a broader 228-file inventory. Eight snapshots are available: three exact
archives and five author-linked repositories. Seventeen selected sources remain unavailable,
including QuickBloom plus sixteen collection members. The user crash remains unreproduced;
bounded fallback does not establish full graphics-effect compatibility or native-fault recovery.
Multiplayer protection starts after native client readiness, not before remote autoruns.
See [ADR 0054](decisions/0054-rtx-rendering-startup-boundaries.md) and
[TESTING.md](TESTING.md#c13-graphics-add-ons-and-map-loading).

QoL item 24 is **done and published**. Airi's clothing fur,
hair and shoes exceed the 32,768-vertex software-group limit. The final GPL native fix protects
both dynamic and direct hardware entries; a shared scope also preserves smaller weighted meshes
under the existing user-forced hardware mode. Default ordinary draws, rigid props, flex/eyes and
cvars retain their behavior. Oversized groups require complete strip certificates and matching
runtime fingerprints; unsafe static-fallback state fails closed. The earlier dynamic-only and
static-only prototypes are superseded. Final DLL 5e626e34 passes cold default NPC/two-skin and
arms checks; the actual final GMA passes force1 PM skins 0/8 with full body/arms visible, no errors
and exit zero. Final Release passes 20 CTests/277 Python tests (7 skips), including the standalone
GPL policy test. The reviewed 998-file GMA matches final source/DLL, with 28 changes and no
removals. Final client 18232 also passes secure dedicated multiplayer, with Airi and first-person
hands visible, unchanged cslua/cheat restrictions and successful debug rendering/deny probes.
GitHub main includes release 4d9257c; hidden Workshop 3829070317 carries
0.0.0-dev.20261031090927+39890cf1. The published archive matches all 998 tested payload files.
Policy and measured acceptance are in
[ADR 0053](decisions/0053-oversized-hardware-skinning.md) and
[TESTING.md](TESTING.md#oversized-hardware-skinning-item-24).

The requested multiplayer change is **done**: loader 0.9.0 implements a verified RTX-owner
script bootstrap without changing `sv_allowcslua`, removes the shipment's `-insecure` request and
keeps other community scripts under engine permissions. RTXDebug separates local rendering
configuration from commands requiring single-player, cheats and insecure mode. Offline validation
passes 16 catalog cases, 7 config cases, 6 Lua tests covering 14 scenarios and 2 player-body cases.
Prototype 7 joins a genuine 64-bit dedicated server with VAC secure mode active, `sv_allowcslua 0`,
cheats off and no `-insecure`; reconnect and a gm_construct/gm_flatgrass round trip pass. RTXDebug
rendering apply/restore works, unsafe evaluation/cvar changes are denied and unrelated local Lua
remains blocked. Full Release checks pass (19 CTests, 277 Python tests), and the reviewed GMA passes
the same dedicated-server probes and a normal single-player launch. Main 64e9913 and both CI jobs
are green; hidden Workshop 3829070317 carries 0.0.0-dev.20261031074244+74044194. No universal
VAC/server-policy guarantee follows from this controlled session. The helper-bearing shipment
requires loader >=0.9.0; a Workshop-only update cannot replace the installed bootstrap. Policy and acceptance
criteria are in [ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md) and
[TESTING.md](TESTING.md#multiplayer-bootstrap-and-rtxdebug).

QoL requests 15 and 23 are **done**: project startup text and loader 0.8.1 main-menu diagnostics.
The source/edit locations and bootstrap requirement are in [ADR 0050](decisions/0050-startup-text-and-main-menu-diagnostics.md).
The latest bounce-default request uses maximum 12/minimum 1 across all default sources
([ADR 0051](decisions/0051-path-bounce-defaults.md)).

QoL requests 17, 19/19.1 and 20 are **done**: optional geometry normals for imported world models, AME original
material labels and workspace selection handoff, and a dedicated motion-importer tab. Offline
behavior checks cover the changes; the user explicitly waived in-game validation for this batch.

Milestones with their acceptance criteria. Mark items here as they start and finish, and log the
change in [CHANGELOG.md](../CHANGELOG.md).

| # | Status | Scope | Done when |
|---|---|---|---|
| M0 | **done** (2026-10-27) | Repo on top of `origin/main`; AGENTS.md, docs, decision records, CHANGELOG; CMake presets + `build.ps1`; `test.ps1` + convention check; Steam depot tools (from the prep scripts); vendored gmapack | `tools\test.ps1` passes: conventions, Python tests, C++ build + CTest |
| M1 | **done** (2026-10-27, Codex, `m1-bootstrap`); [report](handover/M1-report.md), [brief](handover/M1-handover.md) | Inert bootstrap `loader/proxy`: complete System32 forwarding, main-game/Chromium host gate, off switches, EXE entry hook, guarded log; installer and smoke comparison | Debug/Release CTest 4/4, 16 proxy cases, 23 installer checks; all five PoC launches reach gm_construct with matching normalized output; tools unchanged; 2,877 depot files match after install and uninstall; PoC restored/uninstalled |
| M2 | **done** (2026-10-27, Claude, `m2-core`; merged into `main` with M1) | `nl_core`: GMA v1-v3 + LZMA reader (LZMA SDK, public domain), manifest schema 1, path rules, discovery (Workshop folder, `appworkshop_4000.acf`, `addonnomount.txt`, allowlist, local and dev sources), planner; `nlctl` CLI | Unit tests pass: 62 cases, and Debug/Release CTest 6/6 with M1 merged; outputs match `gmapack.py` on the same archives (`nlctl_crosscheck_gmapack`); read-only parse of all installed Workshop archives reports no errors: 753/753 (672 plain, 81 LZMA-wrapped; 104,847 entries); a full `nlctl verify` of the 81 legacy items matches every CRC and footer, one item having 4 bytes of padding after its trailer ([RESEARCH.md](RESEARCH.md) section 5) |
| M3 | **done** (2026-10-27, Claude, `m3-deployer`; merged into `main`); [ADR 0007](decisions/0007-transactional-deployment.md) | Deployer: staging, CRC32 + SHA-256 checks, atomic swap, journal, backups, rollback, `uninstall-loader.ps1` | Fault-injection tests (killed mid-deploy) leave a consistent state: the deployer killed by `TerminateProcess` before each of the 54 + 59 + 26 + 35 changes of a first deployment, an upgrade, a rollback and an uninstall, and the same failed or interrupted in process (with interrupted recoveries), always ends in the old or the new state. Re-runs are no-ops: 0 file-system changes, journal untouched. Uninstall leaves the PoC verifying as vanilla: `poc_deploy_check.ps1` found all 3,113 files and folders identical and 2,877 depot files OK. Debug/Release CTest 12/12, 94 `nl_tests` cases; an independent review's nine findings fixed before the merge |
| M4 | **done** (2026-10-28, Codex with Claude's parts 1-2 and review, `m4-activation`; merged into `main`); [report](handover/M4-report.md), [review](handover/M4-review.md), [brief](handover/M4-handover.md), [ADR 0008](decisions/0008-activation-at-startup.md), [ADR 0009](decisions/0009-startup-deployment-last-good.md) | `package_runtime.py` builds a runtime package from the user's fork build; start-up deployment with keep-last-good; activation: preload, config layers, env vars, launch arguments; status report | On the PoC with local packages: start-up deployed runtime A in 4.8 s and Remix initialised (runtime log, 34 runtime DLLs from the package folder); a config switch deployed and activated B; `nlctl rollback` brought A back and the hold kept it; RTX off used System32's `d3d9.dll` at `mat_dxlevel 95` (`-dxlevel` does not persist). Debug/Release CTest 15/15, 120 core cases. The path-traced frame needs the fixes' fixed-function shader DLL and moved to M5's acceptance |
| M5 | **done** (2026-10-28, Claude, `m5-rtx-fixes`; merged into `main` with M6); [plan](handover/M5-plan.md), [report](handover/M5-report.md), [ADR 0010](decisions/0010-rtx-session-extras.md), [ADR 0011](decisions/0011-lua-addon-folders.md), [ADR 0013](decisions/0013-rtx-only-addons-hidden-without-rtx.md) | RTX fixes on vanilla: `gmcl_RTXFixesBinary` / `gmcl_rtxwater` as `lua-binary-module`, `rtx-remix/mods` as root files, session-scoped console variables, the engine patch sets (`patches64`) applied in memory at module load, `stdshader_dx6` override; Lua companion | On the PoC with two local packages: gm_construct path-traced like `GarrysMod_RTX_c` at a pinned camera (block_diff 0.90, inside capture noise); the user's gm_csgosafehouse save at their camera: 3.18-3.24 against 0.83 between two reference frames, with runtime, fixes, configs and mods byte-identical and the rest on the woven chair backs under a different GMod build (2026.09.15 vs 2026.10.26; [RESEARCH.md](RESEARCH.md) section 13). RTX off: System32 `d3d9.dll`, no patches, override or session variables, and the fixes' add-ons hidden in memory (ADR 0013). Debug/Release CTest 16/16 |
| M6 | **done** (2026-10-28, Claude, on `m5-rtx-fixes` with M5; merged into `main`); [report](handover/M6-report.md), [ADR 0012](decisions/0012-distribution-route.md) | Workshop route: private-visibility upload test of a runtime package, LZMA-wrapped downloads, two-phase update with restart prompt | Route chosen with evidence ([ADR 0012](decisions/0012-distribution-route.md) answers ADR 0002's open question): GMod's `gmad.exe` refuses `native/manifest.json` and DLLs ("Not allowed by whitelist"), so native packages are released as downloads and allowlisted as local sources; the Workshop stays a supported source (LZMA-wrapped items deploy since M3). Two-phase update: `status.json` lists each package's source and Workshop update time, and the Lua companion asks for a restart once when Steam has a newer version (LuaJIT tests). Private upload test run on 2026-10-28 with the user's approval ([ADR 0015](decisions/0015-workshop-route-for-native-packages.md), superseding part of 0012). GMod's `gmpublish` accepted a native package packed with `gmapack`, as hidden item 3829070317. Steam served it back byte for byte, start-up deployed it from the Workshop folder, and an update deployed at the next start. GMod itself will not mount such an item, so its Lua comes through the loader's add-on folders (ADR 0011) |
| M7 | **done** (2026-10-28, Claude, `m7-field`; merged into `main`); [plan](handover/M7-plan.md), [report](handover/M7-report.md) | Field test on the user's install: snapshot and rollback scripts; coexistence with DXVK `d3d9.dll`, GModPatchTool's `vulkan-1.dll`, MMD Hotloader, Jolt | In the field install with the user's 44 add-ons: RTX on loaded the package's `d3d9.dll` (not the user's DXVK) and System32's `vulkan-1.dll` (not `bin\win64`'s), path-traced, with every M5 extra and the MMD Hot Loader; RTX off loaded the user's DXVK, mounted the same 44 add-ons (the fixes' hidden) and matched the no-loader baseline frame (block_diff 0.015); Jolt is not loaded either way. `field_snapshot.py rollback`, one command: clean, 76 kept files and the registry as before, 2,877 depot files OK |
| R1 | **done** (2026-10-28: review by Codex on `r1-review`, triage and fixes by Claude on `r1-fixes`; merged into `main`); [brief](handover/R1-handover.md), [prompt](handover/R1-codex-prompt.md), [report](handover/R1-report.md), [triage](handover/R1-triage.md), [ADR 0014](decisions/0014-r1-hardening.md). Result: 29 findings (12 P0), all triaged; every accepted one fixed with a regression test; one answered by the user (R1-025); in-game RTX on/off checks on the PoC passed | Independent review of the whole repository before the loader goes into the field install for good: the code that runs in `gmod.exe`, deployment and its inputs, the tools that touch real installs, tests, docs and licences | Codex's report gives every finding a severity (P0-P3) and a failure scenario, and covers every file in scope. Claude's triage accepts or rejects each finding with a reason. Accepted P0 and P1 findings are fixed, tested and merged |
| R3 | **done** (2026-10-29: review by Codex on `r3-review`, triage and fixes by Claude on `r3-fixes` and `r3-001`); [brief](handover/R3-handover.md), [prompt](handover/R3-codex-prompt.md), [report](handover/R3-report.md), [triage](handover/R3-triage.md), [ADR 0034](decisions/0034-the-runtimes-build-inputs-recorded.md), [ADR 0035](decisions/0035-restore-automatically.md). Result: 14 findings and the user's R3-015 (the sky's update interval) and R3-016 (limbs in bind pose on Modern House); 13 fixed with tests, R3-010 rejected, R3-002 kept as designed. R3-001 fixed as the user decided: the package's files are put back, what was in their place kept (loader 0.6.0). R3-016 traced in the live game to Modern House RTX's `r_forcehwlight 1`, fixed in that item and confirmed in the field install; R3-017 (a `DXVK_CONFIG_FILE` over 259 characters drops every layer, as the published package's did without an NVIDIA GPU) fixed with short copies of the layers ([ADR 0036](decisions/0036-remix-layers-as-short-copies.md)). The runtime check found the shipped `d3d9.dll` built from more than `runtime/patches`, now recorded | Robustness, stability and bug review of everything since R1: the code in `gmod.exe`, the runtime's sky patch, the build and publish toolchain with `packages/` and Git LFS, the companion, licences, the tools that touch installs | Every finding triaged with a reason; accepted ones fixed and tested; the package differs from the published one only by the fixes |
| R2 | **in progress** (2026-10-29, Claude, field rounds on the user's install) | Behaviour and rendering parity with `GarrysMod_RTX_c` in the field install. Next (the user, 2026-10-31): map the classic layer's 15 options the current runtime no longer has (old exposure, local tonemap and bloom options, `occluderTextures`, `finalizeWithACES`; [R6 report](handover/R6-report.md)) to their current options. Done: the start-up crash (ADR 0018), settings that reset (ADR 0021), the classic settings as defaults (ADR 0020), the session guard, one RTX menu tab, the guide (ADR 0022), the debug module; round 3: the pseudo player fixed again (classic defaults v3), the Emissives mod shipped (Water has no effect, Poolday stays out), Modern House RTX as its own hidden Workshop item 3829275998, played in the field (ADR 0023); round 4: Model Hotloader 2.3.1 with its natives and the other four add-ons bundled, rebuilt from their sources at every publish, and loader 0.3.0's module dependencies load its runtime from `lua\bin` (ADR 0024); round 5: unsubscribing from the Workshop item uninstalls its package, with no rollback copy left (loader 0.3.1, ADR 0025). Round 6: Model Hotloader's install check accepts the runtime the loader loads from `lua\bin`, fixed in its repository and taken into the RTX package with `package_content.py --addon-file` (ADR 0026). Round 7: content packages from any subscribed Workshop item load without the allowlist, native code still only from it (loader 0.4.0, ADR 0027); Draconic Base's motion-blur line no longer repeats; `poc_session.py --workshop` waits for the Workshop mount before the map. Round 8: ReShade in RTX sessions, a Vulkan layer from the RTX package with settings of its own, the Direct3D 9 ReShade kept out and never written (loader 0.5.0, ADR 0028); the companion in six languages from reviewable gettext files (ADR 0029), and the Remix menus (Alt+X) in the same six from the runtime fork (runtime-b5); FSR and the Neural Radiance Cache load again, and without an NVIDIA GPU Remix picks its own preset (ADR 0030); `poc_session.py --fps`. Sky and weather (branch `sky`): the runtime's physical sky with a time of day from the map's own sun, a clock, a moon and stars, and the runtime's twelve weather presets scaled for GMod's maps, in the RTX Remix tab (ADR 0031); `poc_session.py --lua`/`--lua-shots`. Then the real Moon (NASA maps, lit as a sphere, eight phases), a night sky image (Night Sky HD LE's sharp stars, galaxy and nebulae, or the procedural sky), lunar and solar eclipses by stage, and Remix's fog presets under Remix settings (runtime-b6, ADR 0032). Then one repository builds everything: every part's inputs in `packages/` (Git LFS), the runtime fork's changes as patches in `runtime/`, `build_package.py` and the CI package workflow, no hooks in other repositories (ADR 0033). Open: a public release of the loader for other players (the user's call) | The pool rooms render like the classic install at a pinned camera; settings persist; the requested add-ons ship |
| QoL | **in progress** (from 2026-10-29: Codex Astra; [brief](handover/QoL-handover.md)) | Translation batch **done** (2026-10-30; [report](handover/QoL-report.md)): audit and localization of every bundled add-on interface ([ADR 0038](decisions/0038-complete-bundled-interface-translations.md)); quality-of-life changes the user asks for, on the state the brief describes (loader 0.6.0, the RTX package `+8beef27e`) | Each change tested (`tools\test.ps1`, the PoC for in-game behaviour), documented, merged and pushed; a report in `docs/handover/QoL-report.md` |
| R4 | **done** (2026-10-31, Claude; loader 0.10.1, [review](handover/R4-review.md), field release run there) | Review of Codex Astra's QoL batch (loader 0.6.0 to 0.10.0, runtime patches 0005-0013, the GPL native changes, the companion and add-on Lua, tools and CI), fixes with tests, a field QA run on the user's install, the agent skills in [skills/](../skills/README.md), a GitHub release | Every finding triaged with a reason, accepted ones fixed and tested; the field install runs the release; `main`, the Workshop item and the release agree |
| R5 | **done** (2026-10-31, Claude, `r5-qol` with `r5-glass` and `r5-stability`, merged into `main` as `cff3c67`; [handover](handover/R5-qol.md), [stability proposal](handover/R5-stability-proposal.md); field QA passed on the published package) | The user's QoL report: the night sky line on modern_house, broken glass that is inert, never breaks again and never goes, Workshop model packs that must always provide their models, the RTX normals checkbox, the content pack skill's checks, and a proposal (not implemented) for stability on machines with little memory | Each item fixed and tested, checked in the game; the stability proposal handed to the user |
| R6 | **done** (2026-10-31, Codex through the Claude Code plugin, Claude as project manager; [plan](handover/R6-plan.md), [report](handover/R6-report.md); loader 0.11.0; PoC release QA, tier measurements and the field map-load check passed) | The stability proposal's 1-6, 8, 9 and 11, and performance tiers for the Remix defaults (the user's request: defaults for performance and stability, not the best consumer GPU) | Each task merged with tests; checked in the game; published |
| C-16 | **done** (2026-10-31, Codex through the Claude Code plugin, Claude as project manager; [plan](handover/C16-plan.md), [report](handover/C16-report.md); measured and tuned on the PoC, [ADR 0069](decisions/0069-tuned-adaptive-eye-emission.md)) | Anime characters' eye whites keep a steady brightness when the light changes: scene-adaptive emission in the runtime, written by the PBR tool | Measured on the PoC across bright, dim and dark scenes; packs updated; published |
| G1 | **done** (2026-11-01, Codex through the Claude Code plugin, Claude as project manager; [plan](handover/G1-plan.md), [report](handover/G1-report.md), [ADR 0070](decisions/0070-glass-overhaul.md); every cause, walking and running, map glass and the 50-pane scene checked on the PoC, the old system measured as the baseline; irregular breaks at the user's request) | A glass overhaul: every cause of a break scatters glass, breaks follow the impact, damage shows cracks, many broken panes and piles cost nothing visible (a dedicated Jolt world for broken glass) | Each case checked on the PoC against the old system; published |
| R7 | **done** (2026-11-01, Codex through the Claude Code plugin, Claude as project manager; [plan](handover/R7-plan.md), [report](handover/R7-report.md); loader 0.12.0, ADRs 0081-0084; each point checked on the PoC) | The user's report of 2026-11-01: transparent materials that render black (Columbina's mask), a report when a crash ends the game, broken glass pushed and broken by players, props, ragdolls, bullets, blasts and falls (one way), and the diagnostics' memory warning and add-on list | Each point checked on the PoC; published |
| R8 | **done** (2026-11-01, Codex through the Claude Code plugin, Claude as project manager; [plan](handover/R8-plan.md), [report](handover/R8-report.md); runtime patch 0018, ADRs 0085-0086; each point checked on the PoC) | The user's report after R7: character noise from the alpha fix, vanilla graphics add-ons under RTX (GShader Library), the falling-glass cost, glass collision levels, follow-up hits on fractured glass, the Backrooms work's fixes, vanilla characters in bind pose again | Each point checked on the PoC; published |
| Later | — | Signed manifests (authenticity), bootstrap self-update, URL + SHA-256 sources, more package kinds | — |

C-16 (2026-10-31): the runtime's scene-adaptive emission (C16-A) and the PBR writer, staged-pack
migration and package preservation (C16-B) are integrated. Measured on the PoC with Robin, the eye
white over the cheek went from 0.52-0.88 by day and 46 at night (fixed emission) to 0.77-1.38 by day,
0.70 at night and 1.04 in a lamp-lit room, with the ratio tuned to 25
([ADR 0069](decisions/0069-tuned-adaptive-eye-emission.md), superseding
[ADR 0068](decisions/0068-adaptive-eye-emission-publishing.md)'s provisional `1/0.18`). The packs:
[report](handover/C16-report.md#packs).

## Risks being watched

QoL requests 21–22 and 3–4 are implemented and validated: explicit diagnostic opt-in and welcome
dismissal, a live toolgun screen after upscaling, and layered model cutouts/outline suppression.
The complete package passes GPU acceptance and repository checks; see the QoL report for evidence.

| Risk | Plan |
|---|---|
| Workshop items with native files | `gmad.exe` will not pack them, but a `gmapack` archive uploaded with `gmpublish` is accepted and served intact, tested privately ([ADR 0015](decisions/0015-workshop-route-for-native-packages.md)). GMod's [Workshop rules](https://wiki.facepunch.com/gmod/Steam_Workshop_Rules) have no rule about file types. GMod itself cannot mount such an item, so its description must say it needs the loader, or it may be flagged as broken. Downloads stay a fallback ([ADR 0012](decisions/0012-distribution-route.md)) |
| VAC and in-memory patches | General patch sets require `-insecure`. Since loader 0.9.0 RTX sessions launch without it so they can join secure servers, and the RTX package's seven reviewed render-only recipes apply there ([ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md)); the RTX fixes module patches and hooks the engine in those sessions too. The user's decision (2026-10-31): multiplayer is a must-have, upstream garrys-mod-rtx-remixed runs without `-insecure` as well, and no ban has been recorded. `"patch_sets": {"allow_rtx_render_patches": false}` turns the recipe exception off (RTX then stays off without `-insecure`, R4) |
| Launch arguments cannot be added from inside the process | Fall back to documented Steam launch options |
| `stdshader_dx6.dll` loaded by full path | Redirect hook, else journaled on-disk override with hash checks |
| Remix bound to a non-system `vulkan-1.dll` in the field install | `prefer_system_vulkan_loader` preloads System32's; confirmed in the field install (M7) |
| The Remix runtime crashes on exclusive-fullscreen mode switches | RTX sessions run in a borderless window ([ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md)); the runtime fix belongs in the `dxvk-remix-gmod` fork |
| Redistributing NVIDIA binaries (DLSS, NRC, ...) publicly | Check licences before any public package |

## Native package addon cards (2026-10-30)

Loader 0.7.0 adds the requested warning suppression and blue addon cards for deployed native
Workshop packages ([ADR 0039](decisions/0039-native-package-addon-presentation.md)). The implementation
and PoC evidence are in [the QoL report](handover/QoL-report.md#native-package-addon-cards-2026-10-30).

## Native map glass (2026-10-30)

The Modern House glass batch adds persistent debris for native breakable brush panes, with native
map behavior preserved and bounded mesh synchronization ([ADR 0040](decisions/0040-native-map-glass-debris.md)).
See the [QoL report](handover/QoL-report.md#modern-house-map-glass-2026-10-30) for validation and delivery.

## Hotloader shader compatibility (2026-10-30)

The DepthWrite batch routes material registration and depth views according to the active shader
family ([ADR 0041](decisions/0041-hotloader-remix-depth-materials.md)). See the
[QoL report](handover/QoL-report.md#hotloader-depthwrite-shader-errors-2026-10-30).

## Existing Remix installation migration (2026-10-30)

Loader 0.8.0 archives recognized RTXLauncher leftovers and restores known edited depot files from
verified stock sources in the same transaction as deployment ([ADR 0042](decisions/0042-legacy-remix-migration.md)).
Validation uses a fresh pinned Xenthio install under out; RTX_c is now our implementation.

## Player body, arms and shadows (2026-10-30)

Separate first-person view models from primary-space player bodies, remove captured shared-player
categories from the defaults, and scope self-shadow materials to a private body proxy. The RTX tab
adds translated shadow and render-height controls ([ADR 0043](decisions/0043-player-body-viewmodel-and-shadows.md)).

## Remix settings persistence (2026-10-30)

Prevent unset Common Remix sliders from becoming startup zeros, make GMod startup replay explicit,
and preserve native settings on failed Save or Reload ([ADR 0044](decisions/0044-remix-settings-persistence.md)).
The panel's six translations include the ownership and save guidance. Validation and delivery are
recorded in the [QoL report](handover/QoL-report.md#remix-settings-persistence-2026-10-30).

## R6 T1: loader layers and GPU policy (2026-10-31)

In progress on `r6-t1-layers`: fix loader Remix layer precedence, select performance tiers from
the GPU, and add the opt-in GPU crash-dump switch ([brief](handover/R6-T1-loader-layers.md)).

Implementation finished in this worktree: all R6 T1 tier/layer/diagnostic code and documentation
are ready for review, uncommitted at the project manager's instruction. Release native CTests
pass (23/23); the full Release gate is blocked only by 21 existing field-snapshot tests whose
throwaway HKCU fixture creation is denied by this sandbox. Integration and real-runtime QA remain
with the project manager; see the R6 T1 validation record in TESTING.md.

## R6 T4: runtime memory diagnostics (2026-10-31)

Proposal 8 is implemented on `r6-t4-runtime` as runtime patch 0015: shared VRAM collection, snapshots
at cuts/five-minute intervals/device loss, a local schema-1 crash marker before Sentry and
device-lifetime OMM warning limits ([ADR 0065](decisions/0065-runtime-memory-diagnostics.md)).
Build/import and offline validation are recorded with the runtime in [runtime/README.md](../runtime/README.md).
Camera-cut/driver sampling and induced device loss remain for the project manager's game QA;
T4 does not launch Garry's Mod or modify an install.

The runtime rebuild/import, all 22 runtime unit tests, deep input verification and the combined
package check are done. Repository Release checks pass 333 Python tests (two skips) and 22/23
CTests; the remaining guard-cache long-path failure reproduces on unchanged `7759c43`, while all
22 guard cases pass from a shorter executable path ([TESTING.md](TESTING.md#r6-t4-runtime-memory-diagnostics)).

T1 independent-review fix pass (2026-10-31): all seven findings addressed on `r6-t1-layers`, with
regressions for fallback write failures, forgiving diagnostic config, off-mode rearm, unknown-GPU
overrides, effective menu tiers, malformed adapter descriptions and the combined user-list budget.
The earlier sandbox/HKCU validation limitation above belongs to the initial pass; the fix-pass
validation record below in TESTING.md records the current full-access run. Integration, actual
runtime option checks and GPU fault capture remain with the project manager.

T4's independent-review fix pass is complete on its branch: missing or unsafe runtime build
configurations stop before import; patch 0015 records all six omitted staged test sources, adds
heap locality/driver totals/pending OMM counts and flushes an early crash marker under the existing
single-handler gate. The Release rebuild imports only the changed `d3d9.dll`; all 27 runtime unit
tests and the 1,008-file package check pass. Repository Release checks pass all 23 CTests and 333
Python tests (two skips) with the unchanged guard executable relocated under `out/tmp` for its
known long-path limitation. No game session was run; runtime GPU acceptance remains with Claude.

T4's second-review fix pass is complete: budget-drop logs retain free VRAM, the previous budget,
use and thresholds; crash markers/logs preserve the escaped queue reason, use PID-specific
temporaries and two short replacement retries, and bound heap snapshots. Fresh setup invokes
Python/Meson after the repository's MSVC environment; a configure-only scratch build matches all
95 Release options and was removed. The single Release rebuild imports only `d3d9.dll`.
All 27 runtime unit tests, deep input verification, the 1,008-file package check and repository
Release checks pass (23 CTests, 333 Python tests, two skips; the same short guard-test path).
T2's integration reader ignores the additional I7 fields; loader code remains unchanged.

## C-16 A: scene-adaptive emission runtime (2026-10-31)

Completed on `c16-runtime` as patch 0016: optional opaque `emissive_adaptive_intensity`, the actual
auto-exposure scene Yf through a nonblocking readback ring and shared raytracing constants, unchanged
64-byte material records, fixed fallback, five options, cut/interval observations and the shipped
MDL declaration ([ADR 0067](decisions/0067-scene-adaptive-emission.md)).
The Release runtime is rebuilt/imported; all 28 runtime unit tests, deep input verification, the
1,023-file package check and repository Release checks pass (24 CTests, 376 Python tests, two skips).
Integration, actual GPU readback/log acceptance and Robin eye-white brightness measurements/tuning
remain with Claude under the [C-16 plan](handover/C16-plan.md). C16-A runs no game and touches no
install, user configuration or upstream fork; see [TESTING.md](TESTING.md#c-16-scene-adaptive-emission).
