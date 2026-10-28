# M4 handover: activation (start-up deployment, preload, config layers, environment, launch arguments)

- From: Claude (author of the M4 plan; reviews this branch before it is merged), 2026-10-27
- To: Codex
- Branch: `m4-activation`, in the main checkout `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix` (no extra worktree)
- Baseline: `m4-activation` at `3679fdf` (M4 parts 1 and 2, written by another Claude session before
  this handover) plus the handover commit, on top of `main` at `28adc14` (M0-M3)
- In parallel: nothing else runs in this repository

This brief is your task specification. [AGENTS.md](../../AGENTS.md) applies in full and wins if
anything here seems to conflict with it; if so, stop and report the conflict.

## 1. Read first

1. [AGENTS.md](../../AGENTS.md): rules, build and test commands, documentation duties.
2. [docs/ROADMAP.md](../ROADMAP.md), the M4 row: the acceptance criteria you are working towards.
3. [docs/ARCHITECTURE.md](../ARCHITECTURE.md): "Boot sequence" (you finish step 2) and "Deployment (M3)".
4. Decision records: [0001](../decisions/0001-bootstrap-winmm-proxy.md) (entry-point hook),
   [0003](../decisions/0003-native-trust-allowlist.md) (allowlist),
   [0004](../decisions/0004-runtime-in-versioned-folder.md) (runtime in a versioned folder),
   [0007](../decisions/0007-transactional-deployment.md) (transactional deployment, holds, recovery),
   [0008](../decisions/0008-activation-at-startup.md) (activation; written in part 2, you revise it: 4.1).
5. [docs/PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md) (the `remix` section) and
   [docs/ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md) (`native-loader\`, `state.json`, off switches, `status.json`).
6. [docs/RESEARCH.md](../RESEARCH.md) sections 1, 2, 4, 9 and **10** (M4 facts: who reads the
   command line and when, kernelbase's getters, how the runtime takes config layers, the fork's
   build folders).
7. [docs/TESTING.md](../TESTING.md): the PoC, launching it, `smoke_test.ps1`, `poc_deploy_check.ps1`.
8. The code you build on: `loader/proxy/` (`bootstrap.cpp`: entry hook; `startup.cpp`: the start-up
   step, today only `loader.log`; `activation.cpp`: M1's host gate and off switches),
   `loader/core/include/nl/` (`activate.h`, `cmdline.h`, `deploy.h`, `planner.h`, `discovery.h`,
   `journal.h`, `config.h`), `loader/cli/nlctl.cpp`, [tools/package_runtime.py.md](../../tools/package_runtime.py.md).

## 2. State at handover

- On `m4-activation`:
  - Part 1 (`951a71e`): [`tools/package_runtime.py`](../../tools/package_runtime.py.md) and its tests
    build a runtime package (folder and/or `.gma`) from the fork's `_output`, with `--d3d9-from`,
    `--rtx-conf`, `--dxvk-conf`, `--env`, `--with-pdbs`. The default version comes from `d3d9.dll`'s
    build time and hash, so two builds never share a version.
  - Part 2 (`3679fdf`): `nl::activate::plan` (pure: what to preload, set and add), `nl::cmdline`
    (tokeniser, `has_arg`, the getter decoder and `append_arguments`, which repoints kernelbase's
    command-line caches and the PEB), `nlctl activation <root>`, ADR 0008, 12 new `nl_tests` cases
    (106 in all).
- Not built yet: the bootstrap neither deploys nor activates (it only writes `loader.log`); no
  `status.json`; no tests with a synthetic game; no PoC acceptance.
- `tools\test.ps1` passed on `3679fdf` (Debug: conventions, Python tests, CTest 12/12), run by
  Claude on 2026-10-27. Release has not been built since part 2.
- The PoC `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` is vanilla: no `bin\win64\winmm.dll`, no
  `native-loader\`, no `rtx-remix\` (M3's acceptance uninstalled everything).
- Nothing checks automatically that `winmm.dll` imports only KERNEL32; it was checked by hand with
  [`tools\diag\pe_imports.py`](../../tools/diag/pe_imports.py.md) in M3.

## 3. Goal

The M4 row of the roadmap: on the PoC with a local package, Remix initialises (runtime log) and
gm_construct is path-traced; RTX off gives vanilla rendering; switching versions and rolling back
work. All from inside the process: the user installs only `winmm.dll` and allowlists the package. No
launch options to set, nothing of ours in `bin\win64` but `winmm.dll`, Steam's files untouched.

## 4. Deliverables

### 4.1 Corrections to parts 1-2 (first, in their own commit)

1. `nl::cmdline::append_arguments`:
   - Each slot is the `Buffer` of a `UNICODE_STRING` / `ANSI_STRING` (RESEARCH §10: the 8 bytes
     before it hold `Length` = the string's bytes and `MaximumLength` = `Length` + one terminator).
     Check those lengths before writing anything and refuse if they do not match.
   - Update `Length` and `MaximumLength` together with `Buffer`; refuse if the new length does not fit
     a `USHORT`.
   - All or nothing: if a write fails after an earlier one succeeded, put back what was written.
   - Give the caller a way to undo a successful swap later (for example a `restore()`), because a
     later activation step can still fail (4.3).
   - Tests: synthetic slots with right and wrong lengths; on the real kernelbase, swap then restore
     in a separate test process, and check its command line is back exactly as it was.
2. `nl::activate::plan`, config layers: when the user has set `DXVK_RTX_CONFIG_FILE` or
   `DXVK_CONFIG_FILE`, put the package's layers in front of the user's list
   (`<package layers>,<user's value>`) instead of dropping them. This is what the approved plan says:
   the user's list stays on top, and its last entry is still the one the Remix menu saves to. The plan
   then needs the variable's value, not only whether it is set; change `EnvHas` accordingly. Other
   package variables keep the existing rule: a variable the user set is left alone. Tests.
3. ADR 0008 was written on this branch and is not merged. Revise it in place for 4.1.2 and for the
   activation order and failure rule of 4.3, and say so in its status line ("Revised before merge on
   <date>: ..."), as ADR 0007 did. Do not edit ADRs 0001-0007.

### 4.2 Deployment at start-up (record these rules in a new ADR 0009)

The bootstrap's start-up step runs, after the M1 log set-up and before the original entry point:
`config.json` → discovery → consider → plan → `nl::deploy::apply`, then activation (4.3), then the
report (4.4). Rules:

- No `config.json`, `enabled: false`, or an invalid config or journal: no deployment, no activation,
  nothing removed; the reason is logged.
- This process is the game, so it must not count as a running game. Another `gmod.exe` running
  from this game folder (a second instance) means no deployment this launch, and activation of what
  is deployed. `deploy::Options::allow_running_game` skips the check entirely today; add a way to
  exclude only the current process.
- The lock held by another deployer (`nlctl`): no deployment; activate the current generation only
  if the journal has no pending transaction.
- **Keep the last good version.** If deploying would remove or replace a deployed package because
  its allowlisted source is missing, unreadable or invalid (a Workshop item mid-update, a dev folder
  mid-rebuild, an archive that fails its checks while being staged, which `apply` re-plans as broken
  today), deploy nothing this launch, activate what is deployed, and report why. A source removed
  from `config.json`, or a Workshop item disabled in GMod's addon list (`addonnomount.txt`), still
  removes the package: that is the user's choice. `nlctl apply` keeps M3's behaviour. Discovery
  reports problems only as text today; give candidates a way to tell "disabled" from "missing".
- A held rollback (ADR 0007) is respected exactly as `nlctl apply` respects it.
- An exception or SEH fault anywhere in this step is caught (`startup_guarded`); the game continues
  vanilla, and the next run recovers the journal's pending transaction (M3).
- Log the deployment: outcome, generation, number of changes, elapsed time, skipped packages with
  reasons. The first deployment of the full runtime (about 1.04 GiB without PDBs) will hold up the
  game window for several seconds (RESEARCH §9 measured 1.75 s for 323 MiB); measure it on the PoC
  and record it in RESEARCH.md.

### 4.3 Activation (bootstrap; ADR 0008)

Apply `nl::activate::plan` for the journal's current generation when it says to activate (a runtime
deployed and `remix.enabled` true). Preconditions; if one fails, stay vanilla and log why:

- the working directory is the game root (the layer paths are relative to it, and so are Remix's own
  `user.conf` and `rtx-remix\`);
- the runtime's `d3d9.dll` and every layer file exist with the sizes the journal recorded;
- the absolute `d3d9.dll` path fits in `MAX_PATH` (`gmod.exe` is not long-path aware).

Steps, in this order and all or nothing: when one fails, undo the earlier ones and continue vanilla.

1. Environment variables (remember each variable's previous state, which is "absent").
2. Launch arguments through `append_arguments`. If the swap is refused, do not activate. The log and
   `status.json` then give the exact Steam launch options that would work; adding them is the user's
   call (AGENTS.md rule 5). With them present, the plan has no arguments to add and activation goes
   ahead.
3. If `prefer_system_vulkan`: load `%SystemRoot%\System32\vulkan-1.dll` by full path.
4. `SetDllDirectoryW(<absolute runtime folder>)`, for the bare-name delay load of
   `amd_fidelityfx_vk.dll`.
5. `LoadLibraryExW(<absolute ...\runtime\d3d9.dll>, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH)`. The path
   must be absolute: with a relative path that flag's behaviour is undefined.

If step 5 fails: log the Windows error and which of `msvcp140.dll`, `vcruntime140.dll`,
`vcruntime140_1.dll` and `vulkan-1.dll` System32 lacks (the VC++ 2015-2022 x64 redistributable is the
user's to install), then undo 1-4: `SetDllDirectoryW(nullptr)`, free the Vulkan loader you loaded,
restore the command line and the environment.

With RTX off (`remix.enabled: false`), an off switch, or no runtime deployed, none of this happens
and the engine sees a vanilla process. `winmm.dll` must still import only KERNEL32 once it links
`nl_core`: add a CTest that checks it.

### 4.4 Report

- `garrysmod\data\native-loader\status.json`, written atomically at every start, also when the game
  stays vanilla. It holds the loader version, time and process id (so a reader can tell a stale
  file, for example from before an off switch was used), the deployment result, the activation
  outcome and reason, the runtime's id, version and folder, the environment set and the user values
  kept, the layer lists, the launch arguments added or already present, the fallback launch options
  when the swap was refused, and any errors. Define the schema in ON_DISK_LAYOUT.md; M5's Lua
  companion will read it.
- `loader.log`: the same, as more `key=value` lines.
- Uninstall (`nlctl uninstall` and/or `tools/uninstall-loader.ps1`) removes `status.json` and the
  `garrysmod\data\native-loader` folder when that leaves it empty.
- `nlctl activation` must agree with what start-up does (extend it for 4.1.2).

### 4.5 Tests (CTest, run by `tools\build.ps1`)

- `nl_tests`: the corrections of 4.1, the start-up decisions of 4.2 (as pure functions where you
  can), and the `status.json` content.
- A synthetic game, extending M1's set-up (`loader/proxy/tests/host.cpp` copied to
  `<scratch>\bin\win64\gmod.exe` beside the built `winmm.dll`, scratch under `out\tmp`), with a local
  test package built by `package_runtime.py` from test-built DLLs: a fake `d3d9.dll` that statically
  imports one test DLL from its own folder and delay-loads another. After its `main` starts, the host
  records the path `LoadLibraryW(L"d3d9.dll")` returns, whether the delay load resolves,
  `GetCommandLineA/W` and the PEB's command line, and the environment. Cases:
  - RTX on: the first launch deploys and activates; the second makes no file-system changes and
    activates;
  - RTX off: nothing loaded or set, command line unchanged, `LoadLibraryW(L"d3d9.dll")` gives System32's;
  - each M1 off switch: still a pure pass-through;
  - the user's own `DXVK_RTX_CONFIG_FILE` and `-dxlevel 95`: kept, with the package layers in front;
  - a deployed package's source deleted (kept) versus its source removed from `config.json` (removed);
  - the lock held by the test, a pending transaction in the journal, an invalid journal;
  - a runtime with a missing dependency: the load fails, and the environment, command line and DLL
    folder are all back to what they were; vanilla, logged;
  - `status.json` as expected in each case.
- Python tests for any change to `package_runtime.py`.
- Timing: start-up overhead with nothing to deploy (synthetic game, Release), recorded in RESEARCH.md.

### 4.6 PoC acceptance (with the user; ask before every game launch)

Write `tools/poc_activation_check.ps1` (and its `.md`), in the spirit of `poc_deploy_check.ps1`:

- builds two local packages under `out\packages\` with `package_runtime.py`:
  - A: `H:\BACKUP_20260815\Modding\dxvk-remix-gmod\_output`, with copies of `GarrysMod_RTX_c`'s root
    `rtx.conf` and `dxvk.conf` as layers (read those two files and nothing else there);
  - B: the same with `--d3d9-from ...\dxvk-remix-gmod\built-A8E39D93-lockfree-options`;
- installs the bootstrap with `install-loader.ps1` and writes the PoC's `native-loader\config.json`;
- per run, saves to `out\poc-activation\<stamp>\`: `loader.log`, `status.json`, the Remix log
  (`rtx-remix\logs\` in the PoC), the PoC's `garrysmod\console.log` (`-condebug`), and the modules
  loaded in the running `gmod.exe` with their paths: every runtime DLL, `d3d9.dll` included, must
  come from the package folder;
- launches the game only when told to; the user approves every launch.

Runs, each only after the user says go, and never while any GMod is running (check for `gmod.exe`
first and ask):

1. RTX on with A: start-up deploys A; the Remix log shows it initialised; the user confirms on screen
   that gm_construct is path-traced.
2. RTX off (`remix.enabled: false`): no runtime loaded; the `smoke_test.ps1`-style comparison with
   vanilla matches. Also check whether `-dxlevel 90` from run 1 persisted: launch with `+mat_dxlevel`
   so the console prints the value, and compare with a vanilla run. If it persisted, stop and report:
   ADR 0008 then needs a mitigation, and the user decides which.
3. Switch to B by changing `config.json`: start-up deploys B and the logs show B. Then
   `nlctl rollback`: the next launch runs A, and the hold keeps start-up from redeploying B.

Afterwards: `tools\uninstall-loader.ps1 -RemoveConfig`; `tools\steam\verify_install.py` reports
every depot file of the PoC OK; the report lists the files the game and Remix created in the PoC
(logs, caches, configs). Do not delete those without asking.

### 4.7 Documentation (part of done)

- ADR 0008 revised (4.1.3), ADR 0009 new (4.2), [decisions/README.md](../decisions/README.md).
- ARCHITECTURE.md: boot-sequence step 2 as built; replace the launch-arguments open question with
  the answer.
- ON_DISK_LAYOUT.md: the `status.json` schema, the new `loader.log` keys, `garrysmod\data\native-loader\`.
- PACKAGE_FORMAT.md: one short paragraph on how each `remix` field is applied, linking ADR 0008.
- TESTING.md: the M4 checks (synthetic game, `poc_activation_check.ps1`).
- RESEARCH.md: measured numbers (start-up overhead, the first deployment of the runtime at start-up),
  the Remix log lines that show initialisation, the `-dxlevel` finding.
- COMPONENTS.md, `loader/proxy/README.md`, `loader/proxy/tests/README.md`, `loader/core/README.md`,
  CHANGELOG.md (`### Added (M4 ...)` / `### Changed` lines under `## [Unreleased]`), and the ROADMAP
  M4 row (evidence, status "implemented, in review").
- `docs/handover/M4-report.md` (section 8).

## 5. Definition of done

- [ ] `tools\test.ps1` passes (Debug) and `tools\build.ps1 -Config Release` passes.
- [ ] A CTest proves `winmm.dll` imports only KERNEL32.
- [ ] The corrections of 4.1 are in, with tests; ADR 0008 is revised and ADR 0009 written.
- [ ] The synthetic-game tests of 4.5 exist and pass.
- [ ] PoC runs 1-3 are done with the user, with evidence in `out\poc-activation\`, or the report
      says exactly which are still open and why.
- [ ] Afterwards the loader is uninstalled from the PoC and `verify_install.py` reports every depot
      file OK.
- [ ] Docs updated as in 4.7; report written.

## 6. Boundaries

| You may change | Do not change |
|---|---|
| `loader/proxy/**`, `loader/core/**`, `loader/cli/**`, `loader/tests/**`; M3's deployer behaviour for `nlctl` stays as it is, and its tests keep passing | `third_party/**`, `tools/steam/**`, `tools/gmapack/**`, `tools/check_repo.py`: report bugs instead |
| `tools/package_runtime.py`, `tools/tests/test_package_runtime.py` and their `.md`; `tools/poc_activation_check.ps1` (new) and its `.md`; `tools/install-loader.ps1`, `tools/uninstall-loader.ps1`, `tools/smoke_test.ps1` only as far as 4.4 and 4.6 need | ADRs 0001-0007 (accepted; supersede with a new record if needed) |
| ADR 0008 (revise before merge), ADR 0009 (new), `docs/decisions/README.md` | `AGENTS.md` (Claude updates its status line when merging); `docs/handover/M1-*` and this brief |
| Shared docs (CHANGELOG, ROADMAP M4 row, COMPONENTS, TESTING, RESEARCH, ARCHITECTURE, ON_DISK_LAYOUT, PACKAGE_FORMAT): additive or M4-specific edits | Docs about other milestones' rows and sections |
| The PoC: `bin\win64\winmm.dll` (+ `.pdb`), `native-loader\`, `garrysmod\data\native-loader\`, what the loader deploys there, and files the game and Remix write themselves | The field install `...\common\GarrysMod`; `GarrysMod_RTX_c` (read only its root `rtx.conf` and `dxvk.conf`) and its backups; the fork `H:\BACKUP_20260815\Modding\dxvk-remix-gmod` (read only); Steam settings and launch options |
| Files under `out\` (packages, evidence, scratch) | Anything outside these paths |

Git:

- Work on `m4-activation` in the main checkout. Commit in logical steps; `tools\test.ps1` passes
  before each commit.
- Never push, never merge into `main`, never rewrite history: fix parts 1-2 with new commits.
- If the sandbox stops you writing to git, ask the user for approval. If approval is not possible,
  leave the work uncommitted and say so in the report.

## 7. Practical notes

- A runtime package without PDBs is about 1 GB, and the PoC holds a deployed copy of each version
  the journal keeps. Build packages under `out\packages\` (git-ignored, AGENTS.md rule 6); expect
  about 4 GB on `H:` during acceptance.
- The fork's `_output` and `built-*` folders are the user's build outputs: read them, never write.
- In-game runs need the user's desktop session, Steam running and logged in, and no other GMod
  running. At handover the user had `GarrysMod_RTX_c` running.
- Keep everything under `out\` (AGENTS.md rule 9; in M1 Windows Defender blocked builds elsewhere).
- No network access is needed. Do not download anything.
- Launch the PoC as `smoke_test.ps1` does (`bin\win64\gmod.exe`, working directory = game root,
  `-noworkshop -noaddons`, `-condebug`); the root `gmod.exe` is a 32-bit launcher.
- Known Windows quirks (RESEARCH §9): an exited process's image file stays locked for a moment
  (retry), and short-lived synthetic `gmod.exe` processes from parallel tests can confuse a
  running-game check.

## 8. Report (`docs/handover/M4-report.md`)

1. Summary: what works, what does not.
2. Files added and changed.
3. Design choices, with the ADR 0008 revision and ADR 0009.
4. Evidence: each command you ran for the definition of done, with the lines that show success
   (test counts, `loader.log` and `status.json` excerpts, the Remix log lines, the module list, the
   `verify_install` summary, timings).
5. Deviations from this brief and why.
6. Open issues and risks; facts added to RESEARCH.md.
7. Questions for the user.
8. Where the reviewer should look first.

## 9. Stop and ask instead of guessing

- Every game launch.
- Anything that would write a Steam depot file, the field install, `GarrysMod_RTX_c`, the fork,
  Steam settings or launch options.
- Activation behaviour that differs from 4.3 (for example keeping Remix loaded when the command-line
  swap is refused), or a change to the start-up rules of 4.2.
- `-dxlevel` persisting after run 1, or RTX-off output that differs from vanilla in a way you cannot
  explain.
- Remix failing to initialise for a reason outside the loader (driver, GPU, runtime build).
- Any need for network access or new third-party code.
