# Testing

## G1-A glass (offline)

Validation on `g1-lua` (2026-11-01): `tools\test.ps1 -Config Release` exits 0, conventions pass,
24/24 CTests pass and 425 Python tests pass with two pre-existing skips (372 tools, 28 gmapack,
25 Steam). All 23 new G1 tests execute under the existing LuaJIT installation. Both full runs pass;
the final receipt is `out/g1-a/release-final.log`. The latest focused suite also passes after the
join-hook/resynchronization assertions. Only this worktree and its `out/` were written.

[`test_nlglass.py`](../tools/tests/test_nlglass.py.md) adds 23 cases: a pure LuaJIT fracture harness
and actual server/client add-on modules under mocked GMod APIs, with only NLGlassDebris stubbed.
It covers bullets/buckshot/melee/crush, blast dedup and impulses, real prop/ragdoll PhysObj mass and
relative velocity, moving players/NPCs/vehicles, scripted break, native recorded/breaker/nominal
fallbacks, duplicate event/removal suppression and cleanup epochs. State tests check typed wire
fields (including real float32 conversion), two-client replay, late join before and after breakout,
a break with no create packet, delayed entity networking and unrelated entity-index reuse.

Fracture cases compare identical states and fresh processes with global RNG/trigonometry/sqrt
disabled, corner/centre location, near/far cell area and velocity, accumulated crack growth and
old cracks becoming final cell edges, uniform tempered shatter, bounded/merged impacts, area
conservation, supported frame cells and falling islands. Integration checks remaining server/client
collision, collision failure becoming a full break, rotated triangular brush geometry/material,
surface input bridging, property-only save/dupe and output ownership, tool limits/CPPI, companion
settings relocation, admin setting authorization/injection refusal/reset, every Lua file compiling
without GLua conversion and all six non-English MIT catalogs matching generated data.

The fixes packager adds a separate fixture-backed exclusion test: only the retired glass add-on and
its exclusive catalog phrases/references disappear; other translations and the glass VMT/Remix
replacement stay. Full original catalog validation remains enabled. No test launches Garry's Mod,
loads the native debris module or writes either game install. Claude owns package/native integration,
real map outputs, two-client visual/prediction acceptance, actual weapon/body tuning, materials under
Remix and the original/new 50-window/pile performance measurements.

G1-B final fixture refinement (2026-11-01): the benchmark uses the manager's 8192-body reserve
while dropping 4000 shards; the same 11 native cases additionally verify compressed `sprp` with
both packed/original directory lengths and displacement holes. The LuaJIT manager/probe harness
passes 523 assertions. Latest reserve-matched measurements and retained earlier figures are in
the G1-B RESEARCH entry below; none establishes game frame-time acceptance.

G1-B offline validation (2026-10-31, `g1-native`): `tools/test.ps1 -Config Release` includes
`nl_glass_tests` (11 cases in one CTest target) and `tools/tests/test_glass_debris.py` (the real
Lua manager, map-import glue and new QA probe under LuaJIT engine doubles). The native fixtures
generate a room, displacement, LZMA leaf, scaled solid prop and non-solid prop; malformed input,
degenerate hulls, bounds, actual binding calls, interpolation, sleep/wake and contact overflow are
covered. The 4,000-piece collision/settling test enforces 15 simulated seconds, 30 wall seconds and
120 process CPU seconds; measured values are in [RESEARCH](RESEARCH.md#g1-b-dedicated-glass-world-and-offline-measurements-2026-10-31).
The gate passes 25 CTests and 402 Python tests (two expected fixture skips). No game was started.
Claude's acceptance uses [the Jolt probe](../tools/qa/glass_debris_jolt_probe.lua.md); the older
`glass_debris_probe.lua` remains unchanged for the legacy loose-glass baseline. Actual Workshop
BSP/model coverage, glass materials under Remix and frame-time parity need that game acceptance.

## C16-B adaptive eye emission (offline, 2026-10-31)

`tools/tests/test_adaptive_emission.py` adds 17 standard-library tests for the USD writer,
publish-time eye-class selection (including tiny regions rounded to zero coverage), settings and
CLI validation, exposure-1 normalisation, explicit opt-out, legacy tuple compatibility, staged
layer edits and package preservation. Edits cover insertion once, numeric updates, unchanged
non-emissive shaders, BOM/CRLF/comments, dry-run byte/timestamp equality, idempotence, malformed
layer preflight and range errors. Synthetic DDS encoding is mocked; scratch stays in `out/tmp`.

`tools\test.ps1 -Config Release` passes: conventions, 24/24 CTests and 393 Python tests
(340 tools, 28 gmapack, 25 Steam; two existing skips). No path workaround was needed. The focused
17-test suite also passes after the rounded-coverage review fix. Log: `out/c16-b/release-tests.log`.
The local pack demonstration in `out/c16-b/demonstration.json` records seven inserted inputs
across four layers in copies of Robin, Evernight/March 7th and Guinaifen, verifies all 157 source
files unchanged, and checks dry runs, repeat runs and preservation of every other copied byte.
The copied packs and per-pack command logs are under `out/c16-b/` in this worktree. No game was
launched, installed config edited or pack published. In-game brightness acceptance remains with
Claude; the [default](decisions/0068-adaptive-eye-emission-publishing.md) is provisional.

## R6 unattended harness failures

[`poc_session.py`](../tools/poc_session.py.md) now declines crash prompts on a background watchdog
throughout a run, preserves live crash dumps before answering, and aborts in-game work on a new Remix
device-loss marker or a window continuously hung for 120 s. Short load stalls may recover; captures
have a 5 s timeout. After failure Remix gets 60 s to exit before only this run's game/helpers are
stopped. Evidence records `failed`, `device_lost`/`hung_seconds`, numeric/hex/named exits and any forced
termination; release QA prints those causes and retains them in `qa-summary.json`. Focused tests are
`cd tools; python -m unittest tests.test_poc_session tests.test_release_qa -v`: fake processes/windows
and log files cover the watchdog, stale-log exclusion, hang recovery, capture races, bounded exit
and `0x60D0DEAD` / `0xCFFFFFFF` names. No game launch is needed.

Validation on `r6-harness`: all 54 focused tests pass. `tools\test.ps1 -Config Release` exits 0:
repository conventions, 24/24 CTests and 375 Python tests (322 tools, 28 gmapack and 25 steam;
two expected skips). No render-guard path workaround was needed. Receipts are this worktree's
`out/r6-harness/focused-tests.log` and `release-tests.log`. No game was launched, and neither game
install was modified; live device-loss acceptance remains with the project manager.

## R6 companion VRAM sampler

[`test_companion_vram.py`](../tools/tests/test_companion_vram.py.md) exercises the actual companion
sampler under LuaJIT, with no game or GPU. Twenty scenarios check all 14 fields and byte/count
units, 30-second timing, the default-on client switch, missing/late APIs, invalid values and errors,
hourly rotation over five sampled hours, the 240-row bound and continuity across module reloads.
Changed headers, truncated/NUL tails, CRLF, malformed/excess rows and oversized files must be
preserved byte-for-byte as `vram.previous.csv` while sampling resumes. An oversized segment may
not be read into memory. Rename failures keep the source and retry. Three consecutive nil/error
calls stop sampling; valid results reset that count and off/on permits an immediate retry.
These checks run in `tools/test.ps1`.

[`test_companion_stability.py`](../tools/tests/test_companion_stability.py.md) runs 131 UI scenarios
against the real menu, guide, i18n module and generated shipping catalogs: high/medium/low and all
selection sources, T1's real non-NVIDIA/query-failed/no-layer data, fresh status on reopening,
absent/malformed/unsupported reports, plus direct/default guide navigation in all seven languages.
Older loaders must see update/manual-log-copy advice without R6 config keys or collection promises;
R6 guide and docs examples must parse as complete JSON with the shipped allowlist intact. Six
integration cases actually parse full schema-1 JSON documents for the menu and guide using Python
as the native `util.JSONToTable` replacement. UI construction must write
no configuration or Remix options. The guide controls wrap/stretch; visual font/layout acceptance
still belongs to an authorized game session.

The nested T3 worktree makes the guard test's default cache filename 262 characters long. On this
machine its raw `std::filesystem::last_write_time` call fails despite the cache being written with
an extended-length path. T3 uses an **ignored CMake-cache-only**
`CMAKE_RUNTIME_OUTPUT_DIRECTORY=<absolute worktree>/out/build/win64-release/bin` override, then the
unchanged `tools/test.ps1 -Config Release`; the guard suite passes from that shorter executable
directory. Source, presets, test assertions and permissions remain unchanged.

The fix pass also copied the default-layout guard executable to
`out/r6-t3-fix/guard-short/nl_render_guard_tests.exe`. The **byte-identical executable** (matching
SHA-256 recorded in `out/r6-t3-fix/guard-comparison.txt`) fails its repeated-preparation case at the
long path and passes all **22 guard cases** at the shorter path.

Full-access Release receipt (2026-10-31): `tools/test.ps1 -Config Release` exits **0**, with repo
conventions, the build, all **23 CTests**, **288 tools Python tests**, **28 gmapack tests** and
**25 Steam tests** passing (one existing skip in each of the latter two groups). The **37 companion
tests**, companion/add-on i18n checks and skill validator pass separately. The earlier sandbox-only
registry/Git errors do not recur. Logs are under `out/r6-t3-fix/` (`release-test.log`,
`companion-tests.log`, `guard-long-path.log`, `guard-identical-short.log`). No native test assertions
were changed, and no game was started.

## R6 testers: reading memory

The player checklist and crash handoff are in [STABILITY.md](STABILITY.md), also available through
RTX Remix > Start here > Memory and stability guide. Record UTC/local time, map, models/mods,
the action being tested and frame rate alongside each reading. Compare the same scene and camera,
with the same settings and elapsed time after loading; change one setting per comparison.

| Reading | Where / how | What to compare |
|---|---|---|
| Immediate Remix VRAM | Console `rtx_vram_stats` (RTX fixes module) | Driver allocation/budget, DXVK allocation/use, retained pools, replacement textures/geometry, buffers, acceleration structures, micromaps, render targets and D3D9 app resources. Run before and after an expensive action or map change. |
| Loader memory history (R6 loader only) | `native-loader\logs\memory.csv` and rotated `memory.1.csv`, every 10 s | Process private bytes and working set, system commit/limit and available RAM, process GPU local/non-local usage and budgets. Only after `status.json` reports `activation.performance_tier`, `diagnostics.memory_telemetry` is `on` by default; `off` disables it. Older loaders reject this config key. |
| Remix category history | `garrysmod\data\native-loader\vram.csv` and `vram.previous.csv`, every 30 s | Same API totals/categories, at most 120 samples per segment. Archived client setting `nativeloader_vram_telemetry` defaults to 1; 0 stops it. No API means no samples. Read the previous segment first, then the current one. |
| Runtime HUD | Add `dxvk.hud = memory` to the game root's **dxvk.conf**, preserving its other lines, then restart | Watch DXVK memory during the same action. Restore the previous line after the comparison. This HUD does not account for every driver-owned allocation. |
| Broader health snapshot | Console `rtx_agent_health`, when the bundled `rtx_agent` add-on is available | Its `health.json` includes Remix VRAM, Lua memory, model/entity counts and loaded components; correlate with the CSV times. |
| Windows commit | Task Manager > Performance > Memory > **Committed** | Used versus limit for the whole system, not just GMod. Compare with the loader's system commit counters; inspect process private bytes separately. |

CSV values are bytes unless the column says otherwise. In `vram*.csv`, **only**
`forkTextureCacheCount` is an entry count; divide byte values by 1,048,576 for MiB. Timestamps are
ISO 8601 UTC. A blank cell means unavailable/invalid, not zero. Each append is local; do not infer
a crash cause from a final sample up to 10/30 seconds before the fault.

`driverAllocatedBytes` includes allocations outside DXVK's allocator (for example DLSS/NGX and
NRC CUDA); `totalAllocatedBytes` is DXVK's own allocation. Their difference is a useful overhead
estimate, not another category to add to the totals. `totalUsedBytes` and the `used*Bytes` columns
describe use within those allocations; do not sum totals and categories. The driver budget is
dynamic and can be smaller than the adapter's physical VRAM. Growing non-local use can indicate
memory pressure but does not establish why a device was lost. Working set is resident process RAM,
private bytes is process commit, and system commit covers all processes; none is interchangeable.

Telemetry is bounded by sample count; long gaps between sessions do not count as sampled time.
Copy both segments promptly after a fault. The bootstrap session folder keeps its own memory tail;
copy companion `vram*.csv` separately. Copy `garrysmod/data/native-loader/status.json` and
`session.json` **before restarting**: the next start rewrites them and the evidence collector does
not copy them. The R6 project manager must verify actual API readings, HUD
visibility and Task Manager agreement in an authorized game session; offline harnesses test the
sampler/UI contract without starting a game.

## R6 T6 performance-tier payloads

`tools\test.ps1 -Config Release` includes `tools/tests/test_package_runtime.py`: optional
medium/low tiers are hashed, copied, archived and inventoried at fixed `config/dxvk-tiers/` paths,
without changing the manifest schema/requirement or its unconditional layer lists. Invalid tier
names, repeated tiers, non-rtx keys, malformed/empty/duplicate assignments, bad UTF-8 and missing or
non-conf files are refused before output. Existing runtime packager behavior remains covered.

`tools/tests/test_runtime_tiers.py` parses every `packages/runtime/layers/*.conf`. Low/medium and
new layers must match a pinned table of real option names, C++ types and inclusive ranges/enums,
cited to declarations in the fully patched R6 T4 runtime source. Typos, wrong types and invalid
values fail, including numeric/enum boundary fixtures. Classic/compiler are pinned byte-identical;
classic's 15 obsolete ignored keys are not falsely listed as real options. Refresh the table from
the patched source when updating the runtime. No external checkout is required to run the test.

`tools/tests/test_drop_top_mip.py` uses independently generated compressed DDS fixtures: legacy
DXT1/3/5, ATI1/2, BC4U/S, BC5U/S and every accepted DX10 BC1/2/3/4/5/6H/7 variant. Each checks
8/16-byte block sizes, original/result linear sizes and refusal of a wrong linear size. Covers
rectangular images, minimum block sizes, exact mip 1 and lower-mip bytes, header preservation,
single remaining mip flags, corrupt headers/lengths/shapes/formats and refused overwrites. All
scratch stays under `out/tmp`. Run these alone from the worktree root with:

```powershell
python -c "import sys,unittest; sys.path.insert(0,'tools'); unittest.main(module=None,argv=['unittest','tests.test_package_runtime','tests.test_drop_top_mip','tests.test_runtime_tiers','-v'])"
python tools/inputs.py verify --deep
python tools/build_package.py --require-nlctl --keep-work
```

Real-asset verification: regenerate the three `_4096.dds` files with
[`drop_top_mip.py`](../tools/sky/drop_top_mip.py.md), compare the output hashes to
`packages/runtime/files.json` and verify the retained bytes against source mip 1 onward. The
combined package's generated manifest/inventory must contain both tier payloads and all three
smaller skies, while its default DXVK layer list still contains only classic/compiler layers.

The PoC measurements (2026-10-31: both maps, each tier, unpinned and pinned cameras, 4K) and how
they were taken are in ADR 0064. Repeat them with `poc_session.py config --performance-tier <tier>`
and `run --fps 30 --camera <view> --width 3840 --height 2160`, checking the runtime log's
"Effective RtxOption values". Still open: a zoomed sky, an 8 GB card, and class-limited low on a
card above 8 GiB with `lowMemoryGpu` and an Automatic-preset flip. Run-specific evidence belongs in the
[handover status](handover/R6-T6-performance-tiers.md#status).

The review-fix validation passes 23 focused T6 tests, deep verification of all ten input parts,
the combined package build with `--require-nlctl` and `tools\test.ps1 -Config Release`: repo
conventions, 23/23 CTests and Python groups 28/25/291 (two expected skips). The handover status
records the run logs.

## R6 T2 local evidence and telemetry

2026-10-31: `tools/test.ps1 -Config Release` passed all 24 CTests and 334 Python tests (28 gmapack,
25 Steam, 281 tools; two expected fixture/environment skips). The final log is
`out/r6-t2-evidence/release-tests-final-verified.log`. Nine evidence cases, eight memory cases, strict
config tests, Node/LuaJIT notices and real-worker synthetic integration all passed. No GMod launch,
in-game warning/soak comparison or real device-loss reproduction was performed by T2.

On the long `r6-t2-evidence` worktree, the pre-existing guard idempotence check reaches a 261-character
cache path and plain `std::filesystem::last_write_time` fails (`loader/guard/tests/test_early.cpp:198`).
An archived rebuild of original commit `7759c43` reproduces it; that exact executable passes from a
shorter `out` path. Local validation keeps all tests and sources intact, with an ignored CMake
include at `out/r6-t2-evidence/short-guard-output.cmake`: deferred `set_target_properties` sets only
`nl_render_guard_tests`'s `RUNTIME_OUTPUT_DIRECTORY` to `${CMAKE_BINARY_DIR}/g`. It is loaded through
the local cache variable `CMAKE_PROJECT_native_loader_INCLUDE`; no tracked CMake or guard test edit,
drive mapping or system setting change. Logs and the baseline rebuild are in `out/r6-t2-evidence`.

`tools/tests/test_presentation_ui.py` runs the actual menu JavaScript in Node and the embedded local
notice reader in LuaJIT, without a game/browser: five failure classes and RAM text in all seven
languages, evidence-folder copy, stale/other-process snapshots including PID reuse, bounded reads/
retries, once-per-start acknowledgement, language changes, hidden/home/map transitions and no
automatic outbound action. The C++ presentation tests verify current-process metadata, embedding,
ASCII output for the game's decoder and unchanged stock menu sources.

`nl_tests "memory:"` checks byte/UTC CSV fields, unavailable counters, row/byte rotation,
foreign/edited/locked history preservation, interrupted receipt/rotation recovery, actual kernel
queries, latest-only commit snapshots and strict warning thresholds (below 32 GiB, above 70 percent,
unknown/zero limit and overflow boundaries). The config test rejects invalid telemetry modes/types.
`nl_telemetry_integration` uses the real DLL in generated synthetic host roots: two flushed samples
ten seconds apart, previous history saved before new sampling, `nlctl` text/JSON, history off and
loader disabled. `nl_proxy_kernel32_imports` checks static and delay import directories.

`nl_tests "evidence:"` uses only generated game roots in the worktree's build tree. It covers every
classification, optional/malformed structured GPU data, whole-log preservation before a simulated
runtime truncation, ASCII/UTF-16 OOM strings crossing streaming chunks, stale/future file filtering,
pre-R6 loader record fallback, empty/clean sessions, locked dumps, byte/file limits, five-session
retention and preservation of edited archives. It prints mean/max collection time for 30 empty starts.
`nlctl status <fixture> [--json]` reports previous-session data even without a journal.
No game launch or source dump modification is involved.

## Release QA protocol (field install, R4)

What review R4 used to test a release on the user's own install quickly and without guesswork. One
scripted session per question, each about two minutes, all with the user's own settings, so a field
problem shows up the way the user meets it.

1. **Gate.** `tools\test.ps1 -Config Release` passes on the branch.
   - **Before the publish, the package on the PoC.** A merge into `main` uploads the package the user's
     install then downloads, so the branch's own package goes through the PoC first, with no Workshop
     mount (each session about 80 s from launch to quit instead of several minutes):
     `python tools\build_package.py --require-nlctl --out out\qa-poc\package` (about 3 minutes, 1.84 GB),
     then `python tools\poc_session.py --evidence out\qa-poc\<round> install --allow-local <absolute .gma>
     --remix on --replace-config`, then `python tools\qa\release_qa.py --root <PoC> --evidence
     out\qa-poc\<round> --extra=-insecure`: the sessions of step 4 with no Workshop mount, the modern_house
     map mounted from the user's subscription alone (`--mount-workshop 3495468649 --change-map
     modern_house`) and `mat_queue_mode 2` standing in for the field's queued rendering (U1 crashed only
     with it). Put the PoC's `config.json` back from the `config.json.before-*` copy the install step kept.
2. **Back up and record.** Copy the field's `bin\win64\winmm.dll`, `winmm.pdb`,
   `native-loader\bootstrap-install.json` and `config.json` with their SHA-256 into
   `out\field-backups\<date>-<purpose>`; record the hashes of `user.conf`, `rtx.conf` and
   `garrysmod\cfg\client.vdf`, copy `config.cfg`, and `reg export HKCU\Software\Valve\Source\garrysmod`.
   A user's game that is running is closed with a console `quit` (it saves normally), never killed.
3. **Install** with `tools\install-loader.ps1 -GameRoot <field> -AllowSteamManaged`. A bundle the user
   extracted by hand leaves a receipt that names another build: the refusal says so; move the receipt
   to the backup folder and add `-ReplaceUntracked`.
4. **Sessions**, all four in one command that also applies the pass rules of step 5 and records the
   watched files and the registry key before and after
   ([`release_qa.py`](../tools/qa/release_qa.py.md), about 10 minutes on the field):
   `python tools\qa\release_qa.py --field --root <field> --evidence out\qa-field\<run> --extra=-insecure
   --extra=-tickrate --extra=120` (the user's own launch options). One at a time, each is
   `python tools\poc_session.py --root <field> --allow-steam-managed --evidence
   out\qa-field\<run> run --name <step> --workshop --addons --no-window --extra=-insecure
   --extra=-tickrate --extra=120` plus:
   - `--menu-shot --map gm_construct --lua tools\qa\rtx_session_probe.lua --lua-shots 90`: the menu
     (diagnostics panel, add-on cards), the session state, the toolgun screen;
   - `--map modern_house --console "sv_cheats 1" --lua tools\qa\map_glass_probe.lua --lua-shots 180`;
   - `--map gm_construct --console "sv_cheats 1" --lua tools\qa\spawned_glass_probe.lua --lua-shots 120`;
   - `--map gm_construct --lua tools\qa\spawnmenu_probe.lua --lua-shots 60`: the spawn menu's External
     Models and Motion importer tabs (labels translated, the importer laid out in place).
5. **Pass** when every record has `map_loaded`, `normal_quit` and `lua_errors: 0`, the activation is
   `active` with no status errors, the probe lines show the guard installed and no guard errors, the
   toolgun crop is sharp, glass breaks into shards, and after the runs `user.conf`, `rtx.conf`,
   `client.vdf`, the loader files and the registry export are unchanged (`config.cfg` is rewritten by
   the game at every normal quit: diff it against the copy; the probes change nothing archived).
6. **A crash** leaves `rtx-remix\logs\.sentry-native\reports\*.dmp`, which `poc_session.py` copies into
   the session's `crash-reports\` (Remix deletes it once the next start's prompt is declined): read the faulting module and the
   module frames on the faulting thread's stack (a crash on the material system's thread with no
   project module on it points at what was drawn, not at the module that draws). The next start's
   crash-report prompts are declined by `poc_session.py` (No, then OK); never set
   `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES`, which grants upload consent. Bisect with
   `--console "lua_run ..."` / `lua_run_cl` switches in the same scripted session rather than by editing
   deployed files.
## R4 start-up, guard and bootstrap fallbacks (loader 0.10.1)

[ADR 0056](decisions/0056-guard-and-startup-fallbacks.md) is covered without a game: 25 LuaJIT
guard scenarios (autorun install, served-initializer and RTX-off counterexamples, error reports and
three-failure quarantine, gamemode methods never quarantined, per-category report caps, leaked-scope
resynchronization at FrameNumber/PreRender boundaries, fractional sizes, MRT clears, hot paths,
owned-only multiplayer wrapping), 20 bootstrap scenarios (normal-load marker read from the actual
cl_rtx.lua, listen-host and per-add-on skips, server-delivered entities, missing APIs, the
loading-event replay order), the main-menu trigger cases in the Node harness (skipped where Node is
absent; in R4 they ran through a browser shim, see RESEARCH.md), the early-view CTests (local proof,
input-named cache, kept-aside cache file and folder, junction refusal), the render-recipe refusal
and module contract cases, and
two integration runs: the crashing opt-out stays vanilla with its reason (with `-insecure` it starts),
and a catalog-verified package whose early view cannot be prepared still activates with a note.

Not yet accepted in a game session; suggested live checks on the PoC install:

- Change only the owned `native-loader/presentation/render-guard-*.lua` cache: the next RTX start
  keeps it under `native-loader/backup/render-guard/`, writes the view again and installs early.
- `patch_sets.allow_rtx_render_patches: false` without `-insecure`: a vanilla start whose status.json
  activation reason names the key; with `-insecure`, RTX.
- A listen server from an RTX session with a vanilla client: no `NativeLoaderRenderGuard` on the
  client; the host's bootstrap status reads "normal loading already ran the RTX payload".
- A tool whose DrawToolScreen errors, held for more than 32 frames: no "tracked stack limit"; one
  failing HUD hook is reported with its stack and quarantined after three frames; hands still draw.

## C13 graphics add-ons and map loading

Release passes **22 CTests and 294 Python tests (7 skips)**, including 20 early-policy cases,
6 backend cases, 11 targeted command-line cases and 17 unittest cases running 18 actual-source
LuaJIT scenarios. CI builds pinned official LuaJIT and requires it, rather than skipping these
scenarios. CPU tests are separate from the real NVIDIA GPU sessions below.

The actual 998-file GMA reads back against every manifest SHA and matches all preview payloads.
Its construct session passes ten failure/positive controls: reserved RTs, invalid dimensions,
unsupported shader/MRT/depth work, pinned HDR writes, valid normal/R32F targets, one quarantined
HUD failure and restored RT state. Toolgun rendering and spawn-menu open controls pass. Corrupting only its owned
startup cache gives a clean vanilla map load/exit, no RTX patches or executable init redirect,
and preserves the changed cache; the fixture restores its original bytes afterward.

Secure dedicated multiplayer passes with no -insecure, sv_allowcslua 0 and cheats 0. The trusted
RTX payload, RTXDebug and guard load; unrelated local Lua remains excluded and the temporary
catalog API is absent. A normal server-delivered test verifies an unsupported-shader rejection,
one failing HUD callback, continuing healthy callbacks and restored RT state with zero cleanup
errors. It records installation="verified multiplayer bootstrap", with the early flag false.
This is a later readiness boundary, not protection before the remote server's autoruns.

Earlier controlled baselines load LifeMod defaults, CSM depth24/one controller and GShader/FXAA.
The guarded combined construct-to-flatgrass transition and explicit DX11-to-D3D9 process choice
pass. RTX-off loads/exits normally with the guard absent. Steam depot verification passes.

Loader 0.10.0 normalizes explicit shader-backend choices to stock D3D9 only for an RTX process,
preserving raw unrelated arguments and exact W/A/PEB rollback. It installs the catalog-verified V2
guard through a hash-supported stock initializer view without editing Steam files. A verified
V2 stock/cache preparation failure for the selected RTX owner disables RTX with a clear reason
and vanilla/hide-RTX fallback; foreign-runtime and legacy-V1 behavior stay scoped.

When a remote server supplies its own initializer, the existing native verified-payload path can
install the guard later. It accepts only that path's raw marker in a private chunk environment,
uses the real global hook dispatcher and reports its installation timing. It does not expand
native allowlists, local Lua permissions, debug mutation permissions or the native bridge.
The saved guard off switch remains. All guard checkouts use LF for stable package/cache hashes.

The original user crash was not reproduced with fresh defaults. Exact QuickBloom/HDR source and
sixteen collection members were unavailable; author-linked repositories are distinguished from
exact Workshop archives. Unsupported shader effects can be disabled or quarantined while the
map loads; this does not promise their original appearance or recovery from native/GPU faults.
Earlier aliases, later API replacements, unknown native state and already-completed camera/clip/
matrix pops remain explicit limits. Multiplayer installation is later than server autoruns.

Tested loader SHA-256: `95303c8648686d8f155549cf85fba42d6b06dde2f422bad680dc08c8fd18f269`.
Guard SHA-256: `0e57e92fae2dae6783c195f79d032a3f8fd79e41ee94be0637f0512d416a1040`.
Tested archive: `0.0.0-dev.20261031101734+c1874c95`, SHA-256 `c5cb4f4ec0baf6e8b9a6b8a13d7ff931932f2e34d12a77fe66bdf6c3e85f7304`.
It requires loader >=0.10.0; a Workshop update cannot replace an older bootstrap.
The Remix runtime `f9827b35b533caa38c08caa117fb264fb8d18012e3682694e1c92e1faf67a26e` and accepted native fixes `5e626e34` are unchanged.
Evidence: `out/c13-evidence`, including release-test, package-readback, final-accepted,
required-guard-fallback-final and dedicated-final-accepted. Distribution 3829070317 carries `0.0.0-dev.20261031102150+eb483442` with all 998 published payloads matched. Delivery and CI tracking are in the [QoL report](handover/QoL-report.md#c13-distribution-and-cleanup).

Keep these counterexamples in regressions: full-frame -1 sizing, raw R32F27 without a Lua enum,
two sequential stereo views, caller-owned RT/camera/matrix layers, deliberate Pre/Post balancing,
NUL strings before C-string dispatch, nested successful/failed callback cleanup, hook registry
identity/object self/first-non-nil returns, private-versus-global multiplayer markers and inactive
server/menu/vanilla contexts. Do not use mesh.End as an abort or reset unknown native state.
Follow poc_session.py, own-process/log privacy and runtime rebuild rules for future changes.
Scope/provenance: [ADR 0054](decisions/0054-rtx-rendering-startup-boundaries.md) and
[API audit](audits/C13-render-api.md).

## Oversized hardware skinning (item 24)

Current evidence includes **completed asset/engine investigation, final-policy CPU tests and a
final-DLL cold default NPC/two-skin plus arms pass, and final-GMA force1 PM/two-skin rendering pass**.
The Airi archive's MDL/VVD/VTX CRCs/checksums, mesh/group vertex ranges, bone references and weight
normalization pass. Evidence is under the main checkout's `out/oversized-skinning-evidence`.
The final DLL is built from native local commit `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`, with
SHA-256 `5e626e34f412cd55e93a485cd1d777794b339a0cb7a5082935454b72fbc72db7`.

```powershell
cmake --build --preset win64-release --target rtx_oversized_skinning_policy
ctest --test-dir out/build/win64-release -R '^rtx_oversized_skinning_policy$' --output-on-failure
```

The standalone GPL policy CTest passes with /UNDEBUG confirmed after Release's default NDEBUG
in the actual compile command. It exercises threshold/hardware/flex eligibility, complete strip
slots and stale-cache rejection, borrowed palette/blend restoration, failed capture, user-forced
small-group eligibility, supported/unsupported diagnostic modes and unsafe static fallback. It
links no MIT loader code and needs no Source SDK or GPU. Final Release (`final-tests.log`) passes
20 CTests/277 Python tests (7 skips).

Acceptance must distinguish the 32,767/32,768 per-group boundary, oversized compiled hardware
groups and normal/flex-dependent/software-only groups. Check the wrapper's eligibility and original
fallback, weighted bone/palette remaps, missing or invalid data, and restoration of affected render
state on success and every refusal path. Check dynamic and direct hardware entries separately,
including same-group re-entry and unsafe config38 bit 0x08. Small normal force0 groups retain their
path; small user-forced hardware groups must share the scope only inside RenderFinal with a valid
multi-bone pose and the existing mode 1/matching-bone-count upload predicate. Rigid single-bone,
flex and eye controls remain on their original paths. Complete strip certificates apply only to
oversized groups. Do not widen the software limit or silence warnings from unsupported groups.

For live A/B, use the same camera, animation and cvars in the PoC. Capture the existing warning and
missing oversized geometry with the old module, then compare the rebuilt module with the same deployed
assets. Exercise both player/NPC variants and all four oversized groups: clothing Fuzz/Fuzz_B,
three-palette hair and both shoes. Check alternate skins/bodygroups, animation/poses and weighted
deformation, then a normal face-flex model, the Airi arms control and an unrelated model drawn
after it. Verify unchanged skinning cvars and no leaked bone/render state; include first spawn,
repeated spawn, removal and map reload. Repeat the relevant normal single-player and secure
multiplayer regressions from [ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md).

Measured progression: baseline PM without insecure at force0/softwareskin1 reproduces four size
warnings and missing hair/shoes. Dynamic-only 0d4 and static-only 034 are superseded: they missed,
respectively, the direct fallback fatal and smaller force1 body visibility. Preview 357 passes
force1 PM skins 0/8 with body, hair, boots and arms visible, no fatal and exit zero. Final 5e626e34
passes cold default NPC skins 0/8 plus arms in `complete-default`. The actual final GMA passes
force1 PM skins 0/8 with full body and arms visible, no errors and exit zero (`complete-packaged`).
Its reviewed 998-file GMA readback matches final DLL/source, 28 changes and no removals. Both the
software warning and later direct-fallback fatal are fixed in these final build checks.

Final client 18232 passes secure dedicated server 37728 with the final DLL: Airi has 233 bones,
the full model and first-person hands render, cslua/cheats stay off, unsafe commands remain denied,
and rendering config/restore succeeds without config-file changes. Model content is mounted by
the server-approved fixed probe; unrelated local Lua remains blocked. Records and the Source JPEG
are under multiplayer-5e. The hidden Workshop update completed; published readback matches all
998 tested payload files and the final DLL (published-review.json). Preserve exact source/DLL,
package and CI receipts. See
[ADR 0053](decisions/0053-oversized-hardware-skinning.md) for scope and provenance.

## Multiplayer bootstrap and RTXDebug

Loader 0.9.0's targeted offline checks require no game or GPU:

```powershell
cmake --build --preset win64-release --target nl_client_catalog_tests nl_tests
ctest --test-dir out/build/win64-release -R '^nl_client_catalog_tests$' --output-on-failure
out/build/win64-release/loader/tests/nl_tests.exe 'config:'
python -m unittest discover -s tools/tests -p test_mp_bootstrap.py -q
```

The current result is **16 catalog cases, 7 config cases and 6 Lua tests covering 14 scenarios,
all passing**. Catalog checks use generated local/dev/Workshop fixtures and enforce exact owner
and module/script hashes, safe paths, changed/missing/link rejection and excluded automation.
The independent recipe fixtures cover the seven approved rendering patches, all proper subsets,
extra/reordered patches and owner/module/name/find/offset/replace mutations. Config checks retain
the general insecure default, strict booleans and exact opt-out key. The
[Lua harness](../tools/tests/mp_bootstrap_harness.lua.md) executes the complete production
initializer, checks scoped includes/requires and cached results, engine-approved fallbacks,
unmodified global helpers, client entity ordering and replay of only its newly tracked hooks.
Cross-script absent-channel suppression, registered-channel recovery, genuine engine network
errors/returns and environment-only markers are covered. The actual cl_rtx.lua reload section
retains normal early timers/retries and performs no late verified model-cache flush. Two separate
player-body cases check source-bone snapshots, invalid destinations and non-accumulating offsets.
Single-player, wrong realms and unavailable readiness/API execute no forced owner scripts.

For live acceptance, use disposable client and genuine dedicated-server fixtures under
`out`, with the 0.9.0 loader and updated payload, no `-insecure`, server `sv_allowcslua 0` and cheats
off. Verify a completed RTX catalog, visible rendered gameplay, reconnect/map transitions and
absence of duplicate initialization. Verify an unrelated community Lua fixture remains rejected,
while server-approved Lua still works. Check runtime/loader off switches and patch-exception
opt-out. Exercise RTXDebug's local rendering queries/configuration in multiplayer, and verify
Lua evaluation, memory writes, detours and gameplay/replicated cheat mutations remain refused;
their development path requires single-player, `sv_cheats 1` and `-insecure` together.

RTXDebug 0.2.1 decides single-player from the engine (connected, loopback net channel, one player
slot, no demo), never from Lua. Its offline checks are `tests/session_policy_test.cpp` and
`tests/render_policy_test.cpp` in the module's tree (see
`packages/fixes/licenses/rtxdebug/Source.md`). Live, still to run: on the dedicated fixture with
client `-insecure` and server `sv_cheats 1`, `RTXDebug.Status()` reports `single_player` and
`can_mutate` false, also after a client script replaces `game.SinglePlayer`, and Lua.Eval,
Memory, Engine.SetConVar and Detours.Enable are refused; rendering SetConfig/restore still works.
In local single-player with `-insecure` and `sv_cheats 1`, both are true and Lua.Eval works.
0.2.1 also gates the read-only information leaks: on that multiplayer fixture, verify
`Interfaces.Resolve`, `Interfaces.FileExists` and `Engine.ListConsole` are refused,
`Engine.GetConVar` returns `mat_queue_mode` but refuses `sv_allowcslua`, and `Lua.Global`/`Lua.Hooks`
work for `client` but refuse `menu`; in single-player all of these work.

Prototype 7 **passes** the secure dedicated join, reconnect and gm_construct -> gm_flatgrass ->
gm_construct round trip in client PID 8544 against genuine 64-bit server PID 78088. The server
reported VAC secure mode active, `sv_lan 0`, `sv_allowcslua 0` and cheats off; the password-protected
loopback client had no `-insecure`. The payload completed 44 autoruns with errors empty, six absent
channels recorded, temporary API absent and the unrelated local Lua fixture blocked. RTXDebug 0.2
confirmed connected/in-game client/menu states, no server realm, successful rendering SetConfig
and restore with config-file hashes unchanged, and denial of Lua.Eval and an Engine.SetConVar
attempt to enable client Lua. Source JPEG confirms rendered world/hands. Records are under
`out/multiplayer-evidence/probe7*`, with the JPEG at
`out/mpc/garrysmod/screenshots/nl_mp_construct.jpg`; crash A/B findings are in
`out/debug-crash-analysis/findings.md`.

Do not count a listen server or mocked Lua as dedicated-server acceptance. This controlled result
does not establish a universal VAC/server-policy guarantee. Full Release checks pass: 19 CTests
and 277 Python tests (28 + 25 + 224; seven environment skips). The reviewed 970-file GMA passes
the dedicated-server debug/boundary probes in PID 80444; single-player PID 39532 loads normally
without insecure or a forced client payload. Archive readback verifies seven critical files,
44 changed payload files and no removals. Evidence is under out/multiplayer-evidence/packaged,
singleplayer and package-review.json. Both push CI workflows passed for main 64e9913. The published
archive preserves every executable payload byte from the reviewed archive; its only difference
from the final branch build is LF normalization of the MIT notice (published-review.json).
The root licence now has an explicit LF attribute so future checkouts reproduce those notice bytes.
Policy
and install requirements are in [ADR 0052](decisions/0052-scoped-rtx-multiplayer-bootstrap.md).

Requests 15 and 23 use [test_presentation_ui.py](../tools/tests/test_presentation_ui.py.md) for seven
template/catalog checks and the actual menu JavaScript in a Node DOM fixture. The proxy C++ suite
checks private-path exclusion, JSON validation, generated read redirection and unchanged stock
bytes. Runtime test_splash_message runs in the dedicated unit build and covers locale/path
allowlisting, BOM/CRLF, repeated tokens, percent signs, missing/oversized/NUL/empty files and fallback.
Hardware reads are best-effort and do not require an NVIDIA GPU. No real game or user config is
changed by these checks. Full Release tests, input verification and the package comparison still run.

Requests 17, 19/19.1 and 20 use [test_addon_workflow.py](../tools/tests/test_addon_workflow.py.md):
actual AME methods check original names, path identity, current-row handoff, canonical return and
independent working stores. Complete companion modules check late hashes/APIs, shared hashes,
overrides, props, preview/hand exclusions, toggles, removed models and API retry. The runtime's
dedicated test_model_layers checks NoSave routing and draw invalidation. No game is started, as
the user explicitly waived that validation. Full Release checks, input verification and a reviewed
package comparison remain required.

The Motion importer tab ([ADR 0060](decisions/0060-motion-tab-hosts-the-importer.md)) uses
[test_motion_tab.py](../tools/tests/test_motion_tab.py.md): under LuaJIT and mocked Derma it loads
the companion's tab and the shipped motion importer files (`sh_core.lua`'s catalogs, `cl_menu.lua`,
`cl_import_data.lua`, `cl_import_bake.lua`, `cl_importer.lua`). It checks the tab waiting for the
add-on, the importer's inputs in the desktop importer's order and its bake side, a file picked
through a mocked Model Hotloader, the library's columns and actions, Open in window, the file-access
notice, inputs shared between the tab and a window, the windows' old layout and console commands,
and the fallback for an add-on without the builders. Pixels and the light theme's colours on real
Derma need a look in the game.

Player body regression: test_player_body.py executes the real entity, category registrar and menu
using LuaJIT. It checks proxy-only offsets, white-texture isolation, legacy settings, model state,
render cleanup and shared-material rejection. test_remix_defaults.py rejects captured player hash
lists in the shipped layer. Real acceptance compares the old/new runtime with primary-space off/on,
shared-texture world models and ragdolls, shadow enable/disable and a 16-unit height change. Do not
use poc_session --hide-hud for this test, because that intentionally disables first-person arms.

Legacy migration (loader 0.8.0): generated PE fixtures cover detection, malformed bounds and links;
planner tests cover protected paths and unknown edits. The dedicated nl_tests_faults_legacy CTest
interrupts and fails every deployment filesystem operation, including interrupted recovery.
Real acceptance uses a fresh depot-verified Xenthio installation under out/legacy-game, never the
user's now-migrated RTX_c. Compare every legacy backup hash, all ten restored depot files and
preservation sentinels; run RTX on/off with poc_session.py, then verify uninstall keeps the archive.
See [ADR 0042](decisions/0042-legacy-remix-migration.md) for recovery-source limits.

## Levels

| Level | What | How | Since |
|---|---|---|---|
| Conventions | Script docs, module READMEs, links, changelog, component map | `python tools\check_repo.py` | M0 |
| Python unit tests | `tools/**/tests` | `tools\test.ps1 -SkipNative` | M0 |
| C++ unit tests | `nl_tests` (CTest) | `tools\build.ps1` | M0 |
| CLI integration | `nlctl` and `uninstall-loader.ps1` against synthetic packages and scratch game folders | CTest (`nlctl_crosscheck_gmapack`, `nlctl_e2e_plan`, `nlctl_e2e_deploy`, `nlctl_uninstall_loader`) | M2 |
| Fault injection | Every file-system change of a deployment interrupted or failed, in process and by killing a real process | CTest (`nl_tests_faults_*`, `nl_deploy_faults`) | M3 |
| Real-data parse | Read-only parse of every installed Workshop archive (header and index only) | `nlctl scan`, by hand | M2 |
| PoC deployment | The deployer's whole life cycle on the PoC, without starting the game | `tools\poc_deploy_check.ps1`, by hand | M3 |
| PoC in-game | Launch `GarrysMod_PoC` with the bootstrap, check logs and behaviour | `tools\smoke_test.ps1` | M1 |
| Field test | The user's real install, with backups and a tested rollback | manual, with the user | M7 |
| CI | What `tools\test.ps1 -Config Release` runs, on a clean GitHub `windows-2022` runner | `.github/workflows/build.yml`, every push and pull request | ADR 0017 |

`tools\test.ps1` runs the first five (the CLI and fault-injection tests are CTests) and must pass
before any change is finished. CTest runs six tests at a time (`CMakePresets.json`); the longest,
the real-process kill test, takes about 20-35 s.

CI's code page is 1252, not this machine's UTF-8 (65001). A test that reads `nlctl` or a C++ test
host must decode with `encoding='utf-8'`, and files must be opened with an explicit encoding.
Otherwise, non-ASCII text passes here and fails there (see section 17 of [RESEARCH.md](RESEARCH.md)).

### M3 deployer checks

**Unit tests.** `nl_tests` covers:

- SHA-256 (FIPS 180-4 values), `nl::fs` (long paths, atomic writes, links refused) and the journal
  (round trip; 17 invalid or out-of-bounds journals refused).
- The deployer: first deployment and the no-op re-run, upgrade, rollback with hold and the second
  rollback back, retirement of the oldest generation, foreign and adopted files, changed files,
  create-only, the fallback past a package that fails its SHA-256, junctions, dry run, the lock,
  an invalid journal, uninstall back to the original folder.
- Restoring automatically (loader 0.6.0, [ADR 0035](decisions/0035-restore-automatically.md)): a
  changed file put back with its change kept (and a rollback over that), a foreign file taken over and
  put back at uninstall, a new version over an adopted file, an original put back once no generation
  names its path, at once after an unsubscribe, or kept while another file is there; the journal's
  `originals`; `load_first` files loaded only as deployed (`test_dependencies.cpp`).

**Fault injection.** Each fault test builds the state before a command, runs the command
uninterrupted to get the state after it, then interrupts or fails it before each of its changes,
every time on a fresh copy. After the next run's recovery the folder must be exactly the before or
the after state, with nothing pending and no staging left. The tests:

| CTest | What | Where |
|---|---|---|
| `nl_tests_faults_upgrade` | an upgrade interrupted before every change; twice, recovery itself is interrupted before every one of its changes | in process; the "crash" is an exception nothing catches |
| `nl_tests_faults_other` | the same for a first deployment, a rollback (once with interrupted recovery) and an uninstall | in process |
| `nl_tests_faults_errors` | every change of those four made to fail with an error instead: the run must undo itself, or, after the commit, leave the new state | in process |
| `nl_tests_faults_unsubscribe` | the removal of two packages whose Workshop items were unsubscribed, which deletes their payload folders and rollback copies (ADR 0025): interrupted before every change (twice with interrupted recovery), then failed at every change | in process |
| `nl_deploy_faults` | [`loader/tests/deploy_faults.py`](../loader/tests/deploy_faults.py.md): `nl_fault_host` killed with `TerminateProcess` before every change of the same four, on the real file system (2026-10-27: 54, 59, 26 and 35 changes) | real processes |

The in-process tests use a file system without flushes, for speed; they test the deployer's logic.
The kill test goes through the real, durable `fs::win32()`.

**End to end.** `nlctl_e2e_deploy` ([`e2e_deploy.py`](../loader/cli/tests/e2e_deploy.py.md)) runs
`apply`, `status`, `rollback` and `uninstall` through `nlctl`:

- sources: a development folder, an LZMA-wrapped Workshop item and local archives;
- deploy, re-run, dry run, upgrade, drift found by `status`, rollback twice;
- refusals: while the lock is held, while the folder's `gmod.exe` runs (a copy of `ping.exe`
  stands in for the game), with a broken journal;
- uninstall back to the original folder.

`nlctl_uninstall_loader` ([`uninstall_tests.ps1`](../loader/cli/tests/uninstall_tests.ps1.md)) runs
`tools\uninstall-loader.ps1` in synthetic game folders, with a deployment and the bootstrap
installed:

- `-WhatIf` removes nothing;
- an edited bootstrap stops it before any deployed file is removed;
- `config.json` stays by default and goes with `-RemoveConfig`, leaving the folder exactly as before;
- a folder Steam manages needs `-AllowSteamManaged`.

**On the PoC, by hand** (writes to the PoC, never starts the game):

```powershell
tools\build.ps1 -Config Release
tools\poc_deploy_check.ps1
```

[`poc_deploy_check.ps1`](../tools/poc_deploy_check.ps1.md) runs the bootstrap install, a deployment
and a re-run, then uninstalls with `-RemoveConfig`. Every file must then be back as it was (sizes
and times) and `verify_install.py` must pass. On 2026-10-27 it passed: 58 changes deployed, 0 on
the re-run, 3,113 entries identical afterwards, 2,877 depot files OK.

### M2 core and CLI checks

CTest runs `nl_tests` (62 cases: CRC-32, GMA, LZMA, JSON, paths, manifests, packages, KeyValues,
config, discovery, planner), `nlctl_crosscheck_gmapack` (`nlctl` against `tools/gmapack/gmapack.py`
on generated archives, damaged and LZMA-wrapped ones included) and `nlctl_e2e_plan` (the whole chain
on gmapack-built packages in a fake Steam library). Fixtures are generated; no test reads a game
install.

After changing the GMA or LZMA reader, repeat the read-only real-data parse:

```powershell
out\build\win64-release\loader\cli\nlctl.exe scan "H:\SteamLibrary\steamapps\workshop\content\4000"
```

On 2026-10-27 all 753 archives parsed (672 plain, 81 LZMA-wrapped; 104,847 entries; 19 without the
optional CRC trailer, 1 with trailing bytes). `nlctl verify <archive>` decodes one archive completely
and checks every CRC and, for LZMA, GMod's footer; see [RESEARCH.md](RESEARCH.md) section 5.

### M1 bootstrap checks

`tools/build.ps1` also runs `nl_proxy_tests` (16 pure/export/forwarding/child-host cases),
`nl_proxy_generated_exports` and `nl_proxy_installer` (synthetic roots only; since ADR 0035 also a
foreign `winmm.dll` kept in `native-loader\original` and put back by `-Uninstall`). Since ADR 0036,
`nl_activation_integration` also checks that every active start hands the runtime short copies equal
to the package's layers, writes a copy changed by hand again, and falls back to the source when a copy
cannot be written. Both configurations
use static CRT. Generate/update committed exports with `python loader/proxy/generate_exports.py`.
Before installation check runtime dependencies with `py -3.12 tools/diag/pe_imports.py
out/build/win64-release/loader/proxy/winmm.dll` on this machine (the Python with `pefile`).

With Steam running and GMod closed:

```powershell
tools\build.ps1 -Config Release
tools\smoke_test.ps1 -Config Release
```

The smoke script performs baseline/enabled/three off-switch map loads and compares two console
tools. Only thumbnail allocation counters and formatting are normalised. Evidence, a machine-readable
summary and original loader/log backups go to `out/smoke/<UTC timestamp>/`; original DLL/PDB, receipt,
disable flag, loader logs and console log are restored even on failure. See
[smoke_test.ps1.md](../tools/smoke_test.ps1.md) for exact side effects and failure behavior.
The script checks actual module absence and complete export resolution in the enabled log.
Antivirus blocking a local build is a test failure requiring review; scripts do not change security
settings or suppress it.

Until the merge into `main` (2026-10-27), M1 was built and tested in its branch worktree
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap`. Since then the main
checkout builds the proxy into its own `out\build\<preset>`, which is where `install-loader.ps1` (and
through it `smoke_test.ps1`) takes it from (AGENTS.md rule 9). Chromium helper roles stay inert, and
the real-game smoke check verifies the enabled log's PID against the game process it launched.

## M4 checks and PoC acceptance

`tools/test.ps1` runs 66 Python tests (one existing skip) and 15 CTest entries. Native checks include
120 core cases across the normal/fault groups, 16 proxy cases, 23 installer assertions, a separate
kernelbase W/A/PEB swap-and-restore process, and an automated KERNEL32-only PE import check.
`nl_activation_integration` packages a fake runtime with one static and one delay dependency and
checks 17 scenario groups in synthetic game roots below `out/tmp`; no real game is started by CTest.
It writes status/probe/log evidence and ten unchanged-startup timing samples under `out/m4-synthetic`.

The real PoC uses [poc_activation_check.ps1](../tools/poc_activation_check.ps1.md). Prepare builds
two runtime archives and snapshots the reference root configs without starting a game. Every run
needs its own user approval and explicit `-Launch`. Preview is read-only. The user-approved
`-Multirun` override permits another install to remain open, while a second PoC instance still blocks.
The baseline records System32 d3d9 and mat_dxlevel; subsequent stages cover A, RTX off, B and rollback.
Rendering confirmation is a user observation, separate from a successful preload/status report.

Codex's real evidence is in [M4-report.md](handover/M4-report.md): the copied classic shaderModel=0
layer failed with vanilla shaders; a test-only shaderModel=3 layer reached the map without path
tracing. The checks still open after that were run in Claude's review ([M4-review.md](handover/M4-review.md))
with [poc_session.py](../tools/poc_session.py.md), which needs nobody at the keyboard: it launches the
PoC, waits for the map, takes screenshots through `PrintWindow`, lists the loaded modules, and quits
through a local remote console (`quit` is refused from Lua). With the shaderModel=3 packages A and B:
A deployed and active, a config switch deployed and activated B, `nlctl rollback` brought A back and
the hold kept it at the next start, and RTX off (`remix.enabled: false`) used System32's `d3d9.dll` at
`mat_dxlevel 95`; every run quit normally; uninstall left 2,877 depot files OK. Evidence:
`out/poc-sessions/m4-real-20261028T041725`. Whether `-dxlevel` persists was settled separately
([RESEARCH.md](RESEARCH.md) section 11: it does not).

## Installs

| Install | Path | Use |
|---|---|---|
| PoC | `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` | All development and in-game tests |
| Field | `H:\SteamLibrary\steamapps\common\GarrysMod` | Only with the user's explicit go-ahead (AGENTS.md rule 1) |
| RTX_c | `H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c` | Reference for the expected look and file set; read-only |
| ReShade client | `H:\SteamLibrary\steamapps\common\GarrysMod_ReShade` | A second vanilla copy (2026-10-29, `make_vanilla_copy.py`) with ReShade 6.8.0 set up for Direct3D 9 in `bin\win64` and two test effects of ours: ReShade compatibility and frame-rate runs ([ADR 0028](decisions/0028-reshade-in-rtx-sessions.md), [RESEARCH.md](RESEARCH.md) section 26) |

### Frame-rate runs

`poc_session.py run --fps 30 --camera <pinned view> --console "engine_no_focus_sleep 0" --console
"fps_max 0"` times every frame in the game. Frame rates are only comparable on a quiet machine: in
round 8 a build and `.gma` packing by another session made ReShade's layer look 35 % slower than it
is, while runs without the layer lost 3 %. So check, before and during each run, that no game of
another install runs and that the processor is idle, and alternate the cases (with, without).
Another session's runs on the PoC share the one GPU too.

### An AMD GPU on this machine

The Ryzen 9 9950X3D has an integrated Radeon. Setting `VK_DRIVER_FILES` to AMD's Vulkan driver
manifest (`C:\WINDOWS\System32\DriverStore\FileRepository\u0200157.inf_amd64_*\B025930\amd-vulkan64.json`)
for the one `poc_session.py run` makes Vulkan, and so Remix, see only that GPU; nothing on the system
changes. DXGI still lists the RTX 5090, so the loader's non-NVIDIA layer stays off. The integrated GPU
loses its device about a minute into the session and the game then hangs (RESEARCH.md section 27):
stop it with a watchdog, the session timeout does not.

### The PoC install

Built on 2026-10-27 from the field install: the 2,877 files that GMod's depots 4001 and 4002 list
for build 26229091 (x86-64 branch), each copied only after its SHA-1 matched Steam's cached manifest.
That makes it byte-identical to a fresh download. Missing on purpose: `garrysmod\cfg\autoexec.cfg`
(a user-config file the field install has customised; GMod runs without it). Added:
`steam_appid.txt` (`4000`), needed to launch a copy Steam does not manage.

Check that it is still vanilla (everything we deploy is extra, so this stays green until a GMod update):

```powershell
python tools\steam\verify_install.py "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" `
  --manifests-from "H:\SteamLibrary\steamapps\common\GarrysMod"
```

After a GMod update (Steam updates only the field install) the check lists what changed. To rebuild,
delete the PoC folder deliberately, then:

```powershell
python tools\steam\make_vanilla_copy.py "H:\SteamLibrary\steamapps\common\GarrysMod" `
  "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" --report out\poc_copy.json
```

### Launching the PoC (Steam must be running)

```powershell
& "H:\SteamLibrary\steamapps\common\GarrysMod_PoC\bin\win64\gmod.exe" -game garrysmod -console -windowed -w 1280 -h 720 -condebug
```

Start it with the working directory set to the PoC root (Remix reads its configs from there).
The PoC sees the same Workshop subscriptions as the field install; add `-noworkshop` (and
`-noaddons`) to keep GMod from mounting them during loader tests. The loader's own discovery does not
depend on GMod mounting anything.

## Field test protocol (M7, summary)

1. Snapshot `bin\win64` file list and hashes, root configs, `garrysmod\lua\bin`.
2. Install the bootstrap; launch with RTX off first: the existing DXVK `d3d9.dll` must still load.
3. Enable the runtime package; compare against `GarrysMod_RTX_c` on the user's test save.
4. Roll back with `uninstall-loader.ps1`; `verify_install.py` must report the depot files unchanged.

Automated sessions pass `-windowed -w W -h H` and `-noworkshop`. A start from Steam carries only the
player's own launch options, so it differs in two ways. It runs the game's window mode, which crashed
the Remix runtime in exclusive fullscreen until [ADR 0018](decisions/0018-rtx-sessions-in-a-borderless-window.md).
It also mounts the player's subscriptions: a PoC start without `-noworkshop` first extracts every
legacy Workshop item into the PoC's own `garrysmod\cache\workshop` (several GB, over several starts,
[RESEARCH.md](RESEARCH.md) section 18).

For a quick round, `tools\workflow.ps1 -SkipTests -Install <game root>` builds the Release loader,
makes the bundle CI would make, and installs the build into the game ([workflow.ps1](../tools/workflow.ps1.md)).

## Translation completeness and interface behavior

`python tools/companion_i18n.py check` checks both gettext namespaces. Shipping catalogs must contain
every extracted message, with no blank, fuzzy, duplicate, stale, or unreviewed English entries.
`package_fixes.py` uses the same strict build. `--allow-incomplete` is only for translation drafts.

`python tools/check_addon_i18n.py` exercises the native add-on catalogs under LuaJIT: required
languages, key coverage, placeholders, intended unchanged names, Traditional Chinese routing,
Korean Destruction, ambiguous material-label lookup and context-bound language changes.
`test_companion_ui_i18n.py` checks the generated table, metadata phrases, long labels and
server-to-client localized notices. These are in `tools/test.ps1`; LuaJIT tests explicitly skip on
a machine without LuaJIT. The catalog validator's synthetic regression needs only Python.

The runtime's patched `i18n/tools/embed.py` rejects incomplete release catalogs, checks printf
conversions and font coverage, and has `i18n/tools/test_embed.py` regressions. Run its extractor
with `--check` after a source change. Use the PoC for final menu, font and layout checks.

For UI tours, use the project Python 3.12 environment with Pillow and absolute `--allow-local` paths. Protected commands such as `gmod_language` must go through the test console transport, not `RunConsoleCommand` from Lua. Inspect Remix with its window in the foreground; background captures can retain old overlay pixels. A native crash-report prompt may block startup indefinitely; follow the applicable user-consent flow and never enable the automation flag that grants upload permission.

### Native package presentation (loader 0.7.0)

`nl_proxy_tests` includes display-archive CRC/index/metadata and cache/source identity tests. Its
real `filesystem_stdio.dll` fixture exercises A/W open and attribute imports, read-only restrictions,
unrelated files, edited caches, uninstall and traversal refusal. The game-facing acceptance test
uses the PoC at the main menu with Workshop enabled and RTX disabled: confirm no native manifest or
mount warnings, normal mount totals, blue native-package cards and the actual Workshop description.
Inspect `session.json.package_presentation` to prove both archive and menu reads reached the hooks.
A missing expected source marker must leave the ordinary menu untouched and report a note.

The publisher tests mock upload processes. They verify that only the exact reviewed early Steam
presence failure can retry, real API initialization is required, unknown hashes/bytes fail closed,
and a successful ordinary publish does not use the fallback. Tests never upload to Workshop.

### Native map glass

`tools/tests/test_glass_map.py` runs the actual shipped geometry, map-break controller and packet
writer under LuaJIT using generated physics fixtures. It checks fracture count and volume for thin,
horizontal and rotated panes, invalid shapes, native event ordering and return values, duplicate
breaks, unrelated entities, ordinary removal, cleanup cancellation, the debris budget, and bounded
late-join packets. It never launches a game or needs a GPU.

PoC acceptance uses the installed Modern House map: compare the baseline, damage a native pane,
check valid independent fragments and client meshes, wait for settled persistent debris, exercise
scripted breaks, resync a full pile, and clean up/rebreak. Read only that session's console log.
The RTX run uses a fresh process-only DXVK_LOG_PATH under repository out/ for its logs and crash
cache; it does not set the flag that grants automatic upload consent or edit Remix user.conf.

### Loose broken glass (R5, ADR 0061)

`test_glass_map.py` also runs the real `procedural_shard.lua` (converted from GLua by the runner's
`glua_to_lua`, with `world_functions.lua`), the debris registry `glass_debris.lua` and the map
controller over a mocked entity system whose VPhysics builds each convex hull from the points the
entity passes, with timers on a mocked clock. Eight scenarios, each reported on its own: map debris
and the add-on's fragments are moving `COLLISION_GROUP_WEAPON` physics (`DEBRIS` with
`rtx_glass_expensive_shards 0`) that bullets push; map debris breaks again for two or more generations
until only dust is left and no placeholder remains; fragments count in the 256-piece budget, oldest
first; 450 units/s and another loose piece leave a piece whole, 700 units/s breaks it;
`rtx_glass_debris_lifetime` (archived, replicated, default 120) fades pieces within a second of their
time, younger fragments keep theirs, 0 keeps pieces for an hour; and the client's `Draw` shrinks an
expired piece by its transform without building or freeing a mesh. Against the add-on before ADR 0061
the map section's new collision-group check fails, and with it skipped all eight scenarios fail. In
game: [`tools/qa/glass_debris_probe.lua`](../tools/qa/glass_debris_probe.lua.md) breaks a modern_house
window, reads the pieces' collision group, shoots the pile (pieces move or break) and waits out a 6 s
lifetime (no piece left). Not scripted: punting and picking up debris, players and NPCs passing
through while props collide, an explosion in a full pile, a second player on a listen server.

### The night sky on a map whose add-on sets the sky (R5)

[`tools/qa/night_sky_probe.lua`](../tools/qa/night_sky_probe.lua.md) on modern_house in the field
install, in the map's first minute (Modern House RTX re-applies its settings at 23, 43 and 63 s): a
clear midnight, ten views of the sky from a place under open sky. Pass: every view a night sky, no
daylight, no haze with a straight edge. `test_companion_sky.py` checks that the player's sky comes
back in the same tick when Modern House RTX's `ApplySettings` runs.

### Hotloader shader-family routing

`tools/tests/test_hotloader_depth.py` runs the actual shipped builders and DrawCarrier under LuaJIT,
with no game/GPU. The Remix fixture rejects DepthWrite creation and Source depth submissions; the
Source fixture checks delayed texture recovery and the unchanged alpha/cull/depth behavior.
Both verify native initialization before cached backend detection and preserved draw state.

The PoC acceptance probe loads the specific reported asset from the existing cache, records shader
requests and actual draws, checks both depth-view flags from a render hook, and inspects its own
console and screenshots. No user model is copied into the repository or release. Use a fresh
process-only DXVK_LOG_PATH for the RTX test, leaving upload permissions and user.conf unchanged.

### Remix settings persistence

`tools/tests/test_remix_settings.py` runs seven Lua lifecycle scenarios: fresh controls, archived
legacy zeros, explicit startup replay, deliberate zero edits, native Save followed by restart,
invalid values, and clearing overrides. Repeated panel construction and programmatic synchronization
must send no values. The existing sky tests cover actually applied fog ownership.

Runtime patch 0008 extends test_option_layer_export in its dedicated _CompUnitTest_x64 build. It
locks the destination against replacement, verifies failed Save leaves the original and unsaved
state intact, unlocks and retries, checks zero and unknown-key round trips, denies reads during
Reload, and proves live edits survive that failure. Missing directories fail cleanly and no staging
files remain. Do not run runtime unit tests from the game build directory.

PoC acceptance builds the real DForm/DNumSlider controls with the existing archived zeros, captures
Remix API writes while opening and reopening them, exercises an explicit zero and startup replay,
and checks another launch without replay. Snapshot client.vdf/server.vdf along with the usual
bootstrap/config/video settings. Hash user.conf without editing it. Keep only own-session logs.

### Welcome privacy and toolgun screen

The dedicated runtime option-layer export suite also tests explicit diagnostic policy migration,
unique archival of legacy SDK state, saved opt-in/opt-out across restart, failed-write rollback,
stale SDK consent and the twelve-second timer including interaction and reopening. Use disposable
LOCALAPPDATA and DXVK_LOG_PATH directories for live acceptance. Do not grant reporting consent or
use the automation environment switch that does so implicitly. Confirm unattended timeout, an
interaction lasting beyond twelve seconds, permanent dismissal and a restart with both grants off.

`tools/tests/test_toolgun_screen.py` runs the shipped module under LuaJIT. It covers live texture
replacement, inverse-bind skinning including bone zero, viewmodel FOV, third-person/auxiliary view
exclusion, stale frames, render-target allocation and retry, resize and exception cleanup. Live
comparison uses native resolution, DLSS, and DLSS with frame generation, with the redraw off/on.
Record the resolved backend enable flag rather than inferring activation from the dropdown alone.

### Layered model materials and outline shells

`tools/tests/test_model_layers.py` runs the shipped outline module under LuaJIT. Cases cover
late hashes without revision changes, ordinary-image collisions, source suffixes, skin/submaterial
changes, clientside entities, native-registry and proxy bindings, toggles and retries. The native
test_model_layers suite verifies owned controls are NoSave/derived and invalidate cached draws.

Native shader builds compile and validate every ray-query and any-hit variant. Live acceptance
uses the three user-specified cached model archives in separate fresh processes: capture the
first spawn, two seconds and fourteen seconds with micromaps off, then test normal micromaps and
GBuffer ray modes. Sequential actors at one position can retain old cached meshes briefly and
are not a valid cold-spawn comparison. Raw albedo and interaction views distinguish geometry
selection from lighting. Ganyu has two skins; Lynette and March 7th expose one in the current cache.
Exercise Ganyu's outline skin, suppression off/on and return to the transparent skin. A separate
stock-model fixture verifies front-culled outline suppression and retained body/ground shadows.

### R4 companion review: outline work per frame, player shadow, glass resync

`test_model_layers.py` also runs the separate opt-in shell rule (`nativeloader_ignore_outline_shells`,
[ADR 0059](decisions/0059-outline-shell-rule-opt-in.md)), map textures named `*_outline` (never
hidden; the cached-material registry is not scanned), 2001 entities with bounded engine and hash
calls per frame, a missing or changed hash revision, removed entities and the growing delay after a
refused write. `test_remix_settings.py` loads the menu with the RTX fixes' real `rtx_pseudoplayer`
default (1) and checks that map start never writes the player shadow unless startup replay is on.
`test_glass_map.py` paces a 256-shard late join at one batch of at most 16,000 bytes per tick and
checks the resync rate limit and the single-shard cap; `test_player_body.py` covers a slot without a
private copy, draw-time reuse and the shared-material backoff. In game (not run in R4): after a
late join on a map with many broken windows, every pane's debris is visible within a few seconds
and the console shows no reliable-buffer overflow.

## R6 T1 loader layers

`loader/tests/test_activate.cpp` checks that the non-NVIDIA Remix layer precedes the package's
short DXVK copies, including long payload paths and packages with no DXVK layers. The synthetic
proxy activation integration checks the same order without starting Garry's Mod.

### R6 T1 tier and diagnostic checks

- `test_performance.cpp`: all 15 required GPU/no-NVIDIA examples plus class/laptop/name-boundary
  cases, inclusive byte-exact 8.5/12.5 GiB thresholds, multi-adapter maximum, config overrides and I2.
- `test_activate.cpp`: all high/medium/low/auto x off/next_start/always x NVIDIA/non-NVIDIA lists,
  package tier records, old-package low fallback and medium omission, config notes and diagnostics
  disable behavior. Default combined lists stay below the runtime's 259-character budget.
- `test_gpu_diagnostics.cpp`: read-only probe, unchanged preparation, next_start once and explicit
  re-arm, empty interrupted marker, concurrent claims, blocked paths and byte-identical config.
- `test_config.cpp`, `test_status.cpp`: new config schema keys, recoverable invalid tier values,
  strict dump modes, I2 and notes in JSON/bootstrap log.
- Proxy presentation tests check tier data/localized-row embedding; the existing seven-language
  catalog and Node menu checks cover label completeness and text-only rendering.
- `nl_activation_integration`: a generated fake runtime/package checks diagnostic layer contents
  and order, the absolute created dump folder/environment at host entry, next_start once, re-arm,
  read-only preview, always/off, config preservation, tier fallback and generated package tiers.
  It launches only the synthetic host under this worktree's out, never Garry's Mod.

Run `tools/test.ps1 -Config Release`. On machines where PowerShell's script policy blocks direct
invocation, a process-only `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
-Config Release` runs the same suite without changing the machine's policy.

Integration still needs a real session by the project manager: force low/medium, confirm the
selected tier file precedes classic defaults in remix-dxvk.log and that its effective RtxOption
values (lowMemoryGpu, OMM cap, skyProbeSide, froxel scale, terrain resolution) match. Compare high
against the existing classic look. On a non-NVIDIA GPU check Auto (graphicsPreset 5). With
next_start, check `Aftermath enabled` and the requested crash-state option in startup config;
confirm the following start omits diagnostics. A real GPU fault/dump was not induced by T1.

### R6 T1 validation result (2026-10-31)

Final `tools/test.ps1 -Config Release` run: native build and all 23 CTests passed, including
26 synthetic activation scenario groups, the tier/config/state unit cases and KERNEL32 imports.
The Python gmapack group passed (28 tests, one skipped) and steam group passed (25 tests, one
skipped). The tools group ran 280 tests: its only failures were the 21 existing
`test_field_snapshot.FieldSnapshotTests` cases, all in setUp at `tools/tests/test_field_snapshot.py:136`:
`reg add HKCU\Software\NativeLoaderTest_<random> ...` returned 1, `ERROR: Access is denied.`
A single-case diagnostic rerun captured that exact stderr. No tests were skipped or weakened to
hide this sandbox restriction; the project manager must run the complete gate with fixture-key
access before integration. The two documented skips belong to the existing Python suite.

Direct script invocation needed a process-only PowerShell ExecutionPolicy Bypass. Git-reading
Python tests used GIT_CONFIG_GLOBAL pointing to this worktree's `out/r6-t1/test.gitconfig`, with
only this worktree in safe.directory; no user/global Git file or permissions were changed.
The shipped config remains its original minimal allowlist: the optional new values default to
auto/off in nl_core, so existing installs need no config rewrite. No tools script changed.

Evidence: `out/r6-t1/release-tests-final.log`, `registry-blocker.log`, CTest's
`out/build/win64-release/Testing/Temporary/LastTest.log`, and `out/m4-synthetic/release-*`.
The Node harness variant under `out/r6-t1/menu-tier-harness.js` also passed, explicitly rendering
the low/fallback line in all seven languages with the real menu script/catalog. No real Garry's
Mod launch, field-install write, runtime payload import, software install or public action occurred.

### R6 T4: runtime memory diagnostics

Patch 0015 registers `test_memory_diagnostics` in the runtime's `unit_tests` target. Use its
dedicated `_CompUnitTest_x64` build, as described by the fork's `.agents/skills/run-unit-tests`.
The test needs no GPU: it checks first/one-minute warning timing, independent and pending suppressed counts,
cut/present deduplication, a five-minute deadline unaffected by cuts, all heap/category fields,
64-bit byte precision, heap locality and device-local driver totals, nonzero free-VRAM/previous-budget/
use/hard-limit/soft-limit warning values, identical marker/log timestamps and escaped reasons,
per-process temporary files, replacement of an earlier crash marker, bounded sharing retries,
temporary-file cleanup and preservation on write/replacement failure. It clears a stale
`memory-fixture` at startup, including files left by an interrupted test.
Patch 0015 also records the five previously omitted unit sources (GPU profile, GPU overrides,
hot reload, dynamic options and particle schema) and the medium API app from the user's staged fork
index. All six build without source guards; the five unit tests are registered in the 27-test suite.
The medium API app is a separate GPU rendering executable, not a registered CPU unit test.

For the runtime build, apply all fifteen patches and run
`runtime\build_runtime.ps1 -Fork <own clone> -Worktree <verified tree>`. `-Verify` checks the tree
and SDK/submodule identities without building. T4 uses only preinstalled SDKs; APIC downloads are
disabled and an offline resolver validates local Packman package/link identities before every
dependency step. Run `python tools\inputs.py verify --part runtime --deep`,
`python tools\build_package.py --require-nlctl` and `tools\test.ps1 -Config Release` after import.
The build wrapper rejects a missing/empty build directory (no `meson-private/coredata.dat`) and
saved configurations with Debug build type, Debug DLL CRT or APIC downloads enabled, before any
setup/compile/import. The review exercised all five rejection cases and verified unchanged hashes
for `base.json`, `packages/runtime/files.json` and the packaged DLL. First-time source setup is
configure-only through `python -m mesonbuild.mesonmain setup` after `Enter-VsDevEnv`, without the
fork helper's separate vswhere/PATH lookup; the two shader passes run once through the common build path.

The project manager's later authorized PoC acceptance (not performed by T4):

1. At a map/camera cut, find one `[RTX Memory]` JSON line with `event:"camera_cut"`, the current
   frame, every driver heap's budget/use and `device_local` flag, device-local `driver` budget/use,
   and DXVK's device-local totals/eight categories. Cut samples describe the outgoing scene before
   its delayed teardown. Compare
   nearby values with `rtx_vram_stats`; they are sampled at different instants. Stay on the map for
   five minutes after device creation and find `event:"periodic"` even if intervening cuts occurred.
2. Under repeated OMM pressure, each warning kind logs immediately and then at most once every
   sixty seconds, including `suppressed repeats: N`. A cut that recreates OMM must not reset its
   limit. Counts are emitted with the next eligible occurrence, not on an idle timer. A budget-drop
   line includes free VRAM, the previous budget, OMM use and the hard/soft free-VRAM thresholds in
   bytes; those values are captured before free VRAM is invalidated. A loss snapshot includes pending
   `omm_suppressed` counts.
3. In a development build only, arm the crash hotkeys with process-local
   `RTX_ENABLE_CRASH_HOTKEY=1` (or the Development tab), then Ctrl+Shift+Alt+G invokes the runtime's
   GPU-crash shader. This ends the process. Check for `[RTX Memory]` with `event:"device_lost"`
   before the GPU crash-state recorder, either Aftermath wait and Sentry handling, and a complete
   schema-1 `last_gpu_crash.json` beside the runtime log, with identical UTC time, memory fields and
   optional escaped queue `reason`. The bridge is notified before diagnostics; the log is attempted
   before the marker write and its short file-replacement retries.
   The default folder is `rtx-remix/logs`; a process-local
   `DXVK_LOG_PATH` relocates both. Repeat with an unwritable marker path: the original exit behavior
   must remain. No Remix `user.conf` edit is needed.

These diagnostics do not determine the cause of a GPU fault. Aftermath tests and real device-loss
handling still need a game session; the CPU test covers serialization and best-effort file writes.

T4's initial dedicated unit build passed 22/22 tests; the review build passes 27/27 after restoring
the five omitted unit tests. Its unit install helper mishandles `!` in paths;
stage `d3d9.dll` and the two compiled USD plugins/resources into the unit test directory using
literal-path PowerShell copies instead of the affected batch helpers. The runtime rebuild and
`-Verify` pass, input verification reports zero problems, and the 1,008-file combined GMA passes
the worktree's `nlctl` checks. Build identities and exact import commands are in
[runtime/README.md](../runtime/README.md#r6-t4-rebuild-2026-10-31).

Before this review fix, `tools\test.ps1 -Config Release` was run both at the unchanged `7759c43`
checkout and after T4.
Both runs pass repository conventions, 333 Python tests (two skips), and 22 of 23 CTests, with the
same sole failure: `nl_render_guard_tests`, `test_early.cpp:198`, calls `last_write_time` on its
260-character generated cache path without an extended-length path. Copying the unchanged guard
test executable to `out/tmp/nl_render_guard_tests.exe` passes all 22 guard cases. T4 leaves
`loader/` unchanged. Receipts: `out/tmp/release-baseline.log`, `release-final.log` and
`guard-short-path.log`.

### R6 T5 fixes memory-limit compatibility

The GPL source bundle's
[`test_memory_limits.py`](../packages/fixes/licenses/oversized-skinning/memory-limits/tests/test_memory_limits.py.md)
compiles the actual production method and Lua wrapper bodies in a fake SDK harness. Run from a
VS 2022 x64 developer shell, with TEMP/TMP below this worktree's `out/tmp`:

```powershell
python packages/fixes/licenses/oversized-skinning/memory-limits/tests/test_memory_limits.py --out out/tmp/memory-limits-test
```

It checks 8,000 concurrent calls, an absent runtime, the retained Lua `true` result, both invalid
argument cases, a single explanatory log and zero configuration writes. It rejects a module-open
call or unsupported key strings in the resource source. The native branch's existing
`oversized_skinning_test.cpp` also passes C++17 `/W4 /WX`, with assertions enabled. Build both
the base and changed module using the recorded projects and dependencies; compare PE architecture,
imports/exports and unsupported-option strings, then `inputs.py verify --part fixes --deep`.
See [source and rebuild pins](../packages/fixes/licenses/oversized-skinning/memory-limits/Source.md).

Integration acceptance (not run by T5): enter maps repeatedly and confirm no
`rtx.resourceLimits` rejection in `remix-dxvk.log`. Explicitly call
`RemixResource.SetMemoryLimits(256, 1024)` twice: both return `true`, one compatibility notice
appears per loaded module lifetime, and no limit-setting API writes occur. No game is launched by
the offline checks.

### R6 T5 ToPBR compression

The [conversion record](../packages/fixes/licenses/topbr-bc7/conversion.json) pins the encoder,
its arguments and every original/converted DDS hash. The offline audit checks all 83 files:
DXGI 98 (BC7_UNORM, linear), single 2D image, unchanged name/dimensions/mip count, exact block
payload size, and successful independent Pillow decoding of all 816 mip levels. Compare the
decoded raw channels against the pre-conversion aggregate commit in that record; RGB errors
are measured in 8-bit units, and alpha must match. All 113 USD references resolve to the same
83 raw normal/roughness files. The [package notes](../packages/fixes/licenses/topbr-bc7/README.md)
record measured errors and the before/after sizes; local evidence is in `out/topbr-bc7`.

```powershell
python tools/inputs.py verify --part fixes --deep
tools/test.ps1 -Config Release
python tools/build_package.py --require-nlctl
```

Integration acceptance (not run by T5): compare Construct brick/concrete/water, arms and
weapons, and Kleiner in matched lighting and camera positions, near and distant. Their normal
direction, seams and roughness should retain the preceding look. BC7 is lossy; matching metadata
and low decoded-channel error do not replace this renderer check.

T5's 2026-10-31 package build with `--require-nlctl --json` passes: the combined GMA is
1,730,986,849 bytes with 1,017 payload files. A separate archive read matches all 83 texture
hashes to the conversion record, the native DLL hash to its build pins, and `materials.usda`
byte-for-byte to the unchanged input. Receipt and logs are under this task's `out/dist` and
`out/tmp/t5-package-build.log`; nothing was uploaded or installed.

`tools/test.ps1 -Config Release` also passes on 2026-10-31: 23 CTests and 333 Python tests
(2 skips), plus repo conventions. The native compatibility harness and unchanged oversized-
skinning test pass separately; `inputs.py verify --part fixes --deep` reports zero problems.
The full Release log is `out/tmp/t5-release-tests.log` in this task's worktree.

### R6 T1 review regressions (2026-10-31)

The independent-review fix pass adds these checks, superseding the initial pass's strict dump-mode
and manual-only rearm descriptions above:

- `loader/proxy/tests/test_runtime.cpp` links the real activation implementation and loads the
  existing fake runtime. A directory and a read-only stale file at tier.conf both preserve active
  RTX, omit the tier from the effective list/environment, clear I2's layer, report the failure and
  generate a menu with no tier. A blocked marker reset preserves RTX and the blocker with a note.
  These tests supply no GPU reader, so unknown-GPU overrides and write failures run on every host.
- `test_config.cpp` accepts invalid dump strings/types as off with a note. `test_activate.cpp`
  checks empty/missing GPU readers, source config for overrides, stale-tier removal including a
  user duplicate, malformed UTF-16 descriptions retaining vendor/VRAM, and combined package/tier/
  diagnostic/user DXVK lists at exactly 259 and 260 characters. The new loader layers add 67.
- `test_performance.cpp` includes RTX 5090 D, GTX 1080 Ti and RTX A2000 Laptop GPU; the professional
  laptop case proves an unrecognized class does not get the consumer Laptop adjustment.
- `test_gpu_diagnostics.cpp` exercises marker reset and re-consumption without config writes,
  no writes for an absent marker, and preservation of a directory at the marker path.
- `test_presentation.cpp` checks listed layers, empty/classic layers, inactive plans and the ADR
  0056 recipe refusal, including the -insecure exception. The real Node menu harness checks all
  seven languages with a tier, without its layer and without its adapter description.
- Synthetic `nl_activation_integration` verifies off-mode rearm followed by a single new capture,
  invalid diagnostics preserving activation, and a leftover low/medium tier.conf omitted from
  both layers.dxvk and DXVK_CONFIG_FILE on the following high run.

Fix-pass validation: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 -Config
Release` exited 0, with repository conventions, 23/23 CTests and all three Python groups passing:
gmapack 28 tests (one skip), steam 25 (one skip), tools 280 (no skips). Native cases include 223
non-fault core cases, 34 proxy cases, 22 guard cases and 26 synthetic activation scenario groups.
The initial pass's HKCU fixture restriction did not recur with this run's full user access.

The reported long-path guard failure did not reproduce: the pre-rebuild baseline guard executable
and the final Release CTest each passed 22/22 cases in the original build path. The identical final
executable (SHA-256 compared) also passed 22/22 after copying it to `out/g/nl_render_guard_tests.exe`;
its fixture root stays under this worktree's out and the executable path is 37 characters shorter.
No guard code, fixtures or test exclusions were changed. The shorter-path check is:

```powershell
New-Item -ItemType Directory -Force out/g | Out-Null
Copy-Item out/build/win64-release/loader/guard/tests/nl_render_guard_tests.exe out/g/
& out/g/nl_render_guard_tests.exe
```

Evidence is `out/r6-t1-fix/release-tests.log`, `guard-baseline-long.log`, `guard-short.log` and
`guard-paths.json`, plus CTest's `out/build/win64-release/Testing/Temporary/LastTest.log` and
`out/m4-synthetic/release-68168-20261031T160751`. Only synthetic hosts/fake DLLs ran. Real Remix
effective options, actual GPU fault capture/upload and in-game behavior remain for the project
manager; this pass never launched Garry's Mod or touched the field/PoC installs, Steam files or
any player's user.conf, and performed no push, merge, tag or publication.

The review fix passes all 27 runtime unit tests and all six recovered sources compile without
guards. Five rejected build configurations leave the runtime inputs unchanged; the verified
Release rebuild imports only `d3d9.dll` (the two USD plugin hashes are unchanged), and the 1,008-file
GMA passes `--require-nlctl`. The user's fork index hash and staged/working status remain unchanged.

`tools\test.ps1 -Config Release` now passes repository conventions, all 23 CTests and 333 Python
tests (two skips) using a session-local `ctest` wrapper for the known guard-path limitation. It
copies the unchanged guard executable to `out/tmp/nl_render_guard_tests.exe`, verifies identical
SHA-256, temporarily points that one generated CTest command at the copy, executes every registered
test, and restores the generated command in `finally`. No loader or test source is changed. The
plain long-path guard defect remains outside T4's allowed paths. A whole-worktree `subst` alias
was unsuitable: `QueryFullProcessImageNameW` returns the real `H:` image path, so the deployment
test's running-process comparison fails against an `R:` target. The alias was removed and the
final suite ran under the real path. Receipts and the local wrapper are in `out/tmp`, prefixed
`runtime-review-`: `release-tests.log`, `release-tests-drive-alias.log`, `test-short-guard.ps1`,
`build-guards.log`, `unit-tests.log`, `inputs-verify.log`, `package-build.log` and `fork-unchanged.log`.
The standalone medium API GPU app and an actual game/device-loss trigger were not launched.

The second review configured `out/tmp/runtime-review2-setup` offline with the wrapper's direct
Python/Meson setup command, without compiling runtime targets. All 95 saved build options match
`_CompRelease_x64`; the scratch folder was then removed. The comparison receipt retains the
Release/Ninja/optimization/CRT/Tracy/shim/APIC values and Meson's three compiler-probe objects
(`out/tmp/runtime-review2-setup-comparison.json`). The focused diagnostics test also exercises a
locked destination: two 10 ms replacement retries preserve the old marker, remove this process's
temporary file and leave a foreign process's temporary file intact.

The second-review rebuild uses `remix-main+024a9866` and passes all 27 runtime unit tests, including
the stale-fixture rerun. The existing config-save test's symbolic-link subcase is skipped by Windows
error 1314 (the process lacks that privilege); the other subcases pass. Runtime source verification,
deep input verification (zero problems), and the 1,008-file package's `--require-nlctl` check pass.
Only `d3d9.dll` was imported; the two USD plugin hashes and the six recorded test-source blobs are
unchanged. Second-review receipts use the `out/tmp/runtime-review2-` prefix; `unit-summary.json`
retains only names, results, exit codes and timings.

Second-review repository validation also passes `tools\test.ps1 -Config Release`: conventions,
all 23 CTests and 333 Python tests (two skips). It uses the same session-local CTest wrapper for
the known guard-cache path limitation; the copy's hash matches and the generated CTest command
is restored afterward. No loader/test source changed. `runtime-review2-release-summary.json`
records those checks beside `runtime-review2-release-tests.log` and the local wrapper.

## C-16: scene-adaptive emission

Task C16-A implements [ADR 0067](decisions/0067-scene-adaptive-emission.md) as runtime patch 0016.
The isolated source is `8a5df5d8ef2e4529f20f7c07c195cb6dc3588afe`; its Release DLL is
`remix-main+8a5df5d8`, 396,802,048 bytes, SHA-256
`9906eec639b8768baf468daebb2f281c45f04754eaaf6cd60c0c5f7c883cc543`.
The build and exact import commands are in [runtime/README.md](../runtime/README.md#c-16-rebuild-2026-10-31).

The dedicated `_CompUnitTest_x64` build passes **28/28 runtime unit tests**, including the new
`test_adaptive_emission`. It tests absent/authored USD inputs, default zero and 0..65504 clamping,
CPU material identities, 64-byte GPU record size, half-float round trips with emission on/off,
four subsurface indices including the invalid sentinel, unchanged preceding fields and restored
DLSS RGB/alpha. Formula coverage includes feature off, input zero, fixed intensity zero, scale
zero, both clamps, fallback and fallback clamping, inverted clamp bounds, approximate settled
display brightness below the exposure cap and fading at the cap. The option documentation test
passes after regenerating its five new option rows. Final receipts are
`out/tmp/c16-unit-final-build.log` and `out/tmp/c16-unit-tests-final.log`.
The existing config-save test's symbolic-link subcase is skipped by Windows error 1314; its other
subcases pass. `out/tmp/c16-validation-summary.json` keeps test names/results/timings without
Meson's inherited environment dump.

The configured Release/Ninja build retains optimization 3 and the release DLL CRT, Tracy/shim off
and `download_apics=false`; the wrapper performs both passes and imports one changed runtime file.
No SDK or source downloads were needed. The prepared R6 tree was copied, including its configured
builds, and only the local copy was changed. Relocating its Meson state was insufficient alone:
694 shader dependency files per configuration also pointed at the old tree. The stale attempt was
stopped before import. The real shader compile then exposed an unnecessary compatibility-header
include/name collision; the final shared helper needs no such include. Failed attempts imported
nothing. Final receipts use `c16-runtime-build.log`, `c16-verify-final.log` and
`c16-shader-relocation.json` under `out/tmp`.

Disassembled auto-exposure SPIR-V exposes the new output at binding 4 with stride 8; an opaque
G-buffer variant exposes both new raytracing constants. Both newly compiled binaries appear
byte-for-byte in the final DLL (`out/tmp/c16-embedded-shaders.json`), guarding against stale shader
embedding. The fixes part's one MDL declaration was reimported as plain text, preserving its
existing CRLF bytes outside the nine added lines. No other fixes asset changed.

### Project manager GPU acceptance (not run by C16-A)

- With Robin's opted-in pack, use fixed eye-white/cheek patches in the bright outdoor, dim interior
  and night scenes from the [C-16 plan](handover/C16-plan.md): ratio about 0.85..1.05 after settling;
  dark eye white must not exceed the cheek. Compare captures with identical cameras/settings.
- Correlate `[RTX Adaptive Emission]` with those captures: source/sample frame and age, raw
  `adapted_yf`, paired `exposure`, effective `luminance`, `scale` and `enabled`. A camera-cut record
  intentionally describes the delayed sample used for that frame; allow exposure to settle too.
  Check a five-minute interval record and disabled-auto-exposure fallback.
- A material with no input or input zero retains fixed emission; feature off restores the fixed
  fallback even with a positive input. Check zero fixed intensity plus positive adaptive input,
  `enable_emission=false`, an emissive-blend material, Source eyes, decals and an SSS material with
  adaptive emission. DLSS control masks must retain their prior RGB and alpha 1.
- With auto exposure off, confirm fallback 0.18 by default and both clamp overrides. At the exposure
  cap confirm emission fades with the logged scene Yf. Tune the default scale/clamps using that
  evidence; the raw geometric mean is distinct from temporally smoothed exposure during cuts.

C16-A never launches Garry's Mod, changes the user's fork, an install, Steam files/settings or a
user configuration, or publishes anything. Actual GPU readback timing, cut/interval log sampling
and visual brightness acceptance remain with Claude.

### Project manager GPU acceptance (2026-10-31, Claude, PoC)

The integration branch `c16-int` (C16-A and C16-B merged) built into the PoC: runtime
`remix-main+8a5df5d8`, Robin's pack copied as the test mod `c16_robin` (it sorts before `pbr_robin`,
so its materials win). [`eye_white_probe.lua`](../tools/qa/eye_white_probe.lua.md) on gm_construct,
the player placed on one spawn point so every run frames Robin in the same pose and light,
1920x1080, then [`eye_white_patches.py`](../tools/qa/eye_white_patches.py.md) (the eye white's linear
luminance over the cheek's). "Fixed" is the same runtime with `rtx.adaptiveEmission.enable = False`
in a temporary root `rtx.conf`, removed after each run.

| run | noon | golden hour | dusk | night |
|---|---|---|---|---|
| `A-fixed-r1` (fixed 0.6) | 0.69 | 0.52 | 0.88 | 46.4 |
| `B-adaptive-r1` (input 3.33, the provisional `1/0.18`) | 0.62 | 0.61 | 0.48 | 0.31 |
| `B-adaptive-p4` (input 3.33, `rtx.adaptiveEmission.scale = 4`) | 0.94 | 1.28 | 0.73 | 0.64 |
| `B-adaptive-v15` (input 15, ratio 25: the shipped default) | 0.98 | 1.38 | 0.77 | 0.70 |

The interior, a lamp-lit room of the building east of the spawn (the player placed on
(1227, -1669, -144) at angles (50, 45, 0), `NL_EYE_CONDITIONS` noon and night, boxes for that pose:
`--patch sclera_ur=822,490,834,500 --patch sclera_lo=745,588,775,597 --patch skin=850,600,875,618`):
fixed 0.79 by day and 0.84 at night (`A-fixed-room`), input 15 1.04 and 1.04 (`B-adaptive-room`). The
lamps make day and night alike, and the room is not dark enough for the fixed glow.

- Result against the plan's acceptance: the night glow is gone and the eye white stays below the
  cheek in the dark (0.70; fixed 46); the interior is inside the band (1.04). Outdoors by day the
  band is 0.77-1.38, not 0.85-1.05: the emission
  follows the frame's average light while the cheek follows its own, so shade on the face (golden
  hour) lifts the ratio and a low sun on the cheek (dusk) lowers it. Why one ratio cannot close that,
  and why 25: [ADR 0069](decisions/0069-tuned-adaptive-eye-emission.md).
- The runtime log's `[RTX Adaptive Emission]` lines: an `interval` record at start-up with
  `source=fallback` (no readback yet), then `camera_cut` records with `source=auto_exposure`,
  `age_frames=2`, `adapted_yf` 0.00046-0.00069 and `exposure` 16 (night, the cap), `enabled=0` in
  the fixed runs and `enabled=1` in the others. The sky changes inside a run are not cuts, so the log
  has no record per condition.
- Placement matters: runs that started on other spawn points (`B-adaptive-s3`, `B-adaptive-s6`)
  framed Robin differently and lit her differently (half the cheek luminance at night), so they are
  not compared. The probe's `--console` placement reproduced the head position to 0.01 units.
- Not covered: Source eyes, decals, an emissive-blend and an SSS material with the input (no such
  asset on the PoC); auto exposure off. C16-A's unit tests cover the formula, fallback and packing for
  those paths.

Evidence: `out/qa-poc/c16/` (each run's shots, `console.log` and `remix-dxvk.log`; contact sheets
`sheet-fixed-vs-v15.png`, `crops-r1-p4.png`).

### Final offline gates

- `runtime/build_runtime.ps1 -Fork <own source> -Worktree <own source> -Verify` matches all sixteen
  patches, tree `1a6009a44590fe673282b7ceecf759548df646b8`, both submodule settings and both clones;
  the built DLL hash matches the packaged record.
- `python tools/inputs.py verify --part runtime --part fixes --deep` reports zero problems. Input
  index comparison against the branch base confirms only `files/d3d9.dll` and the one MDL changed.
  The DLL adds one 58,495,348-byte xz LFS object; no dependency/plugin binary was reimported.
- `python tools/build_package.py --require-nlctl --json` passes this worktree's validator:
  **1,023 files**, content digest
  `b136a9d079ac48a76b3a9f9a8abbdedd07fda458e9530d9ec29a6766ccfccbce`.
- Plain `tools/test.ps1 -Config Release` passes repository conventions, **24/24 CTests** and
  **376 Python tests (two skips)**. The guard test passes at this worktree's actual path; the R6
  relocation wrapper is unnecessary and was not used. No loader or loader-test source changed.

Receipts: `out/tmp/c16-verify-final.log`, `c16-inputs-verify.log`, `c16-package-build.log`,
`c16-release-tests-plain.log` and `c16-validation-summary.json`.

## G1-B fix pass: offline map probe

`out/build/win64-release/glass/native/nl_glass_import_probe.exe <map.bsp>` opens only the named
file for reading, validates the same 256 MiB bound, and prints considered/clipped/skipped/refused
brushes, displacement triangles, prop metadata, static bodies and parse/build timings. It does not
extract client model collision, write fixtures or start a game. Exit 0 means a usable finished world;
1 means refusal/read failure; 2 means missing argument. CTest never reads an installed map.
Generated regressions cover 62-sided clipping, Jolt-refused brush/prop convexes, ordinary triangle
tags without SURFACE, explicit REMOVE holes and asymmetric displacement indexing.

### G1-B fix-pass checks

Generated native cases now also cover asymmetric displacements with ordinary tags 0/2/6,
Jolt-refused brush and prop convexes, active-only pose queues, safe contact saturation, background
import/finish/step polling and joining at teardown. A separate 4,000-body async probe prints dispatch,
poll and worker timings and measured catch-up limiting. The import probe also prints asynchronous
copy/enqueue, poll and total cooking time without extracting client model collision.

The Lua harness checks changed-ID consumption (including poisoned unused rows), zero worker
requests for an unchanged sleeping world, refused model isolation, bounded queued spawning and
safe deferred removal/impulse, retained old pile chunks through multi-frame rebuilds, failed mesh
build retention/retry, per-frame work limits, affected-chunk wakes and in-flight cleanup. Its optional
`skip perf` arguments run the original/corrected manager against identical mocked physics.
Claude still owns real-map terrain/prop contacts, late-frame behavior during import, pile wake /
expiry / cleanup visibility, and empty/falling/settled Remix frame-time acceptance with thousands
of pieces. No game is started by any of these tests.

### G1-B final import receipt and local gate environment

After moving the owned BSP buffer's release onto the import worker, the final read-only probe
reports the same geometry counts, standalone parse 14.50 ms, Init 1.13 ms, parse/cook/finish
46.60 ms. Async enqueue/copy is 3.79 ms, maximum poll .0069 ms, total preparation 76.12 ms;
Init scratch remains zero. Evidence: `out/g1-native-fix/import-delivery.log`. These timings exclude
Lua's engine VFS read and client prop collision extraction.

The full Release gate's sole initial failure was the existing guard fixture's MAX_PATH limit:
`loader/guard/tests/test_early.cpp:198` uses `std::filesystem::last_write_time` on a long generated
cache path. This worktree uses the already documented local-only CMake output relocation:
`out/g1-native-fix/short-guard-output.cmake`, loaded by the ignored build cache's
`CMAKE_PROJECT_native_loader_INCLUDE`, defers only the guard test output to `${CMAKE_BINARY_DIR}/g`.
No loader/guard source, assertion, registered test, tracked build setting, drive mapping or system
setting changed. With that local setup, `tools/test.ps1 -Config Release` passes 25 CTests and 426
Python tests (373 tools, 28 gmapack, 25 steam; two expected skips). The glass native target has 19
cases and the actual Lua manager/probe harness passes 3,264 assertions. Receipt:
`out/g1-native-fix/test-release-final.log`.
