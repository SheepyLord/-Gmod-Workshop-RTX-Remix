# Testing

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
overrides, props, preview/hand exclusions, toggles, removed models, API retry, translations and
opening the existing motion manager. The runtime's dedicated test_model_layers checks NoSave
routing and draw invalidation. No game is started, as the user explicitly waived that validation.
Full Release checks, input verification and a reviewed package comparison remain required.

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
