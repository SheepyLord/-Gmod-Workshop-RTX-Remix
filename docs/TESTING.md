# Testing

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

`tools\test.ps1` runs the first five (the CLI and fault-injection tests are CTests) and must pass
before any change is finished. CTest runs six tests at a time (`CMakePresets.json`); the longest,
the real-process kill test, takes about 20-35 s.

### M3 deployer checks

**Unit tests.** `nl_tests` covers:

- SHA-256 (FIPS 180-4 values), `nl::fs` (long paths, atomic writes, links refused) and the journal
  (round trip; 17 invalid or out-of-bounds journals refused).
- The deployer: first deployment and the no-op re-run, upgrade, rollback with hold and the second
  rollback back, retirement of the oldest generation, foreign and adopted files, changed files,
  create-only, the fallback past a package that fails its SHA-256, junctions, dry run, the lock,
  an invalid journal, uninstall back to the original folder.

**Fault injection.** Each fault test builds the state before a command, runs the command
uninterrupted to get the state after it, then interrupts or fails it before each of its changes,
every time on a fresh copy. After the next run's recovery the folder must be exactly the before or
the after state, with nothing pending and no staging left. The tests:

| CTest | What | Where |
|---|---|---|
| `nl_tests_faults_upgrade` | an upgrade interrupted before every change; twice, recovery itself is interrupted before every one of its changes | in process; the "crash" is an exception nothing catches |
| `nl_tests_faults_other` | the same for a first deployment, a rollback (once with interrupted recovery) and an uninstall | in process |
| `nl_tests_faults_errors` | every change of those four made to fail with an error instead: the run must undo itself, or, after the commit, leave the new state | in process |
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
`nl_proxy_generated_exports` and `nl_proxy_installer` (synthetic roots only). Both configurations
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
