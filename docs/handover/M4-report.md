# M4 report: startup deployment and activation

- Assignee: Codex; report prepared 2026-10-28, America/Vancouver.
- Branch/workspace: `m4-activation` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`.
- Baseline: Claude's parts 1–2 at `3679fdf`, plus handover commit `389755c`.
- Status: **implemented, in review; real path-tracing acceptance blocked**. The user stopped
  further PoC tests after the diagnostic A run. No push, merge or history rewrite.

## 1. Summary

M4 startup deployment, activation, rollback of process changes and status reporting are implemented.
The required corrections were committed first as `e82684d`; startup policy/ADR 0009 followed in
`8b5b4a9`. Loader version is now 0.1.0 with the user's explicit approval, matching the packager's
minimum-loader contract.

Debug and Release each pass all 15 CTest entries. There are 120 core cases (117 normal plus three
exhaustive fault cases), 16 proxy cases, 23 installer assertions, the real command-line round trip,
KERNEL32-only import validation and 17 synthetic activation scenario groups. All 66 Python tests
pass apart from one pre-existing skip. The synthetic tests include missing dependencies, failed
DLL initialization, a native exception during initialization, user settings, contention, recovery,
source disappearance/removal, real static/delay dependency loading, version switching and rollback.

Real PoC results:

- Vanilla baseline: gm_construct loaded using System32 d3d9, `mat_dxlevel=95`.
- Original package A: startup deployed 977,303,948 payload bytes in 4.81 seconds and preloaded the
  runtime. Remix initialized its RTX 5090 Vulkan device and Reflex. The copied classic
  `d3d9.shaderModel=0` setting rejected vanilla shaders; the game exited before the map.
- The user approved an additional PoC-only `d3d9.shaderModel=3` layer and one A retry. It reached
  gm_construct with `mat_dxlevel=90`; all 34 loaded runtime DLLs matched the package folder,
  including d3d9, the delay-loaded FSR DLL and the DLSS DLLs.
- The user reported **“Not path-traced or rendering incorrectly”** and then explicitly chose
  **“Stop PoC tests and finalize the report.”** Visual acceptance did not pass.
- Real RTX-off comparison, `-dxlevel` persistence, real B activation and real rollback remain
  **unperformed**. Their synthetic equivalents pass; that does not resolve the real-game gap.

The PoC loader/payloads/status/config were uninstalled. All **2,877 depot files match**, with zero
missing, size or hash mismatches. No PoC game remains running. The other RTX_c instance was left
alone. Game/Remix logs, crash artifacts, caches and settings were preserved.

## 2. Files added and changed

- `loader/core/include/nl/cmdline.h`, `src/cmdline.cpp`: full cached-string descriptor validation,
  USHORT capacity checks, transactional writes, partial-failure rollback, explicit/scoped restore
  and process-lifetime commit. Tests include `loader/tests/cmdline_host.cpp` in a separate process.
- `loader/core/include/nl/activate.h`, `src/activate.cpp`: environment-value adapter, package-first
  config layering with user values retained, existing launch-argument values, reporting metadata.
- `loader/core/include/nl/startup.h`, `src/startup.cpp`: startup-specific preflight and keep-last-good
  policy, current-PID exclusion and safe contention/pending decisions.
- `loader/core/include/nl/status.h`, `src/status.cpp`: status schema 1, matching log fields,
  atomic per-PID temporary-file replacement, and selective status cleanup.
- `loader/core/include/nl/deploy.h`, `src/deploy.cpp`, `include/nl/discovery.h`, `src/discovery.cpp`:
  opt-in startup policy, structured contention, explicit addon-disable metadata and dynamic System32
  registry API lookup. Default `nlctl apply` behavior remains M3's.
- `loader/proxy/runtime.h/.cpp`, `startup.cpp`: validated activation order and rollback state outside
  the SEH frame; full startup orchestration and reporting.
- `loader/cli/nlctl.cpp`: matching environment/config-layer preview, missing-config/pending gating;
  uninstall reaches the new status cleanup through core.
- `loader/tests/test_activate.cpp`, `test_cmdline.cpp`, `test_startup.cpp`, `test_status.cpp`,
  `test_deploy.cpp`, `test_discovery.cpp`: corrections, startup decisions, status and late staging failure.
- `loader/proxy/tests/activation_probe.h/.cpp`, `fixture_runtime.cpp`, `fixture_static.cpp`,
  `fixture_delay.cpp`, `activation_integration.py` and `.md`, `check_imports.py` and `.md`, plus
  `host.cpp`: packaged fake-runtime acceptance, fault cases, metadata probes and import validation.
- Relevant component CMake/README files and root CMake project version.
- `tools/poc_activation_check.ps1` and `.md`: one approved launch per invocation, A/B preparation,
  log/module/status capture, off/dxlevel checks, visual recording and cleanup. `tools/smoke_test.ps1`
  and `.md` now restore M4 status data; uninstall documentation records status cleanup.
- ADR 0008 revised before merge; ADR 0009 new; decisions index, ARCHITECTURE, ON_DISK_LAYOUT,
  PACKAGE_FORMAT, TESTING, RESEARCH, COMPONENTS, CHANGELOG and the M4 ROADMAP row updated.

AGENTS.md, the M4 brief, M1 reports, accepted ADRs 0001–0007, third-party code, Steam tools and
gmapack were not edited. No binaries or runtime packages are committed.

## 3. Design choices

[ADR 0008](../decisions/0008-activation-at-startup.md) now specifies complete descriptor swaps and
reversible activation in the requested order: environment → launch arguments → optional System32
Vulkan → runtime DLL directory → absolute d3d9 preload. Working directory, journaled entry/layer
sizes and MAX_PATH are checked first. A refused swap prevents preload and reports exact fallback
options. Successful state is retained only after final reporting; failure restores prior environment,
command line and DLL directory and releases the loader's module references.

[ADR 0009](../decisions/0009-startup-deployment-last-good.md) defines startup deployment. Missing,
disabled or invalid config, or invalid journal, never reaches deployment/activation. Only the
current process is excluded from the game-running check. Contention permits activation only from
committed non-pending state. An unusable still-allowlisted source cannot discard the current package;
the check also runs after staging has exposed corrupt contents. Explicit source removal and addon
disable remain user choices. Rollback holds and explicit CLI apply keep M3 semantics.

Rollback state is owned by the caller of the SEH frame, not a destructible local inside it. The
status writer uses a per-PID temporary file and atomic rename, so simultaneous instances do not
share a temp filename. Off switches and Chromium roles remain pure pass-through; their old status
may be stale. `activation.outcome=active` describes startup completion, not later renderer health.

## 4. Evidence

### Baseline and non-game checks

The initial checkout was on main with the incoming handover uncommitted. Those files were backed
up and preserved while selecting m4-activation; the handover subsequently appeared as `389755c`.
The first baseline hit a cached Windows PowerShell choice that could not load Get-FileHash.
Selecting the available pwsh executable in the ignored CMake cache fixed that environment issue.
No source was changed before the passing baseline (66 Python tests; CTest 12/12).

Commands:

    tools/test.ps1
    tools/build.ps1 -Config Release

Results for both final configurations:

    100% tests passed, 0 tests failed out of 15

Detailed groups include:

    117 test case(s), 0 failed
    # Three separate exhaustive fault cases each report 1 case, 0 failed.
    16 test case(s), 0 failed
    Installer OK: 23 checks (synthetic roots only).
    kernelbase W/A and PEB swapped, lengths updated, exact original descriptors restored (explicit and scoped)
    winmm imports only KERNEL32.dll (static and delay-load directories checked)

Logs: `out/m4-baseline-tests.txt`, `out/m4-part1-corrections-tests.txt`,
`out/m4-startup-policy-tests.txt`, `out/m4-activation-debug-tests.txt`,
`out/m4-activation-release-tests.txt` and each build's `Testing/Temporary/LastTest.log`.

The isolated Release synthetic run is `out/m4-synthetic/release-62268/summary.json`:
17 scenario groups passed. Ten unchanged-deployment startup samples measured **25.8064 ms median**,
**19.8476–27.9013 ms** range, with zero deployment operations each time. This measures through
activation before final status/log I/O, not rendering performance. A thrown native exception in
the fake DLL's initializer is converted by Windows to error 1114; rollback and vanilla continuation
are verified. The outer startup SEH boundary remains in place for escaping native faults.

### Real acceptance session

All real evidence: `out/poc-activation/20261028T075336206Z/`.

| Stage | PID | Result |
|---|---|---|
| 01-Baseline | 6876 | gm_construct; System32 d3d9; mat_dxlevel 95 |
| 02-RunA, classic layers | 70300 | Loader activation succeeded; engine exited before map after shader errors |
| 03-RunA, approved shaderModel=3 layer | 31480 | gm_construct; mat_dxlevel 90; 34 runtime DLL paths verified; user rejected path-traced visual result |

Original package A: 191 files, 977,303,948 bytes, version
`0.0.0-dev.202610270636+e5c65136`. B: 191 files, 977,403,788 bytes, version
`0.0.0-dev.202610271832+a8e39d93`. The diagnostic packages add one 132-byte config layer and keep
the same runtime DLLs. Full hashes and manifest identities are in package/proposed-package JSON.

Original A loader excerpt:

    deployment.outcome=deployed
    deployment.generation=1
    deployment.elapsed_ms=4808.77
    activation.outcome=active
    activation.runtime.version=0.0.0-dev.202610270636+e5c65136
    activation.arguments.added=["-dxlevel","90","-nod3d9ex","+mat_disable_d3d9ex","1"]
    activation.elapsed_ms=36.5178
    startup.elapsed_ms=4846.04

Remix log evidence includes NVIDIA GeForce RTX 5090 device creation, “Reflex initialized
successfully”, Neural Radiance Cache support and swapchain creation. It then reported
“GetShaderModule: Out of range of supported shader model”. The copied layer sets shaderModel=0;
the fork's `src/d3d9/d3d9_shader.cpp:115` rejects shaders above that configured limit. Windows
Application event 1000 recorded the PoC engine.dll fault with exception 0xc0000409.

The approved diagnostic adds `d3d9.shaderModel = 3` after the copied classic DXVK layer, retaining
the user's root layer last. It deployed in **4920.9048 ms**, activated in **39.4931 ms**, and reached
gm_construct. `03-RunA/runtime-modules.json` verifies 34 DLLs from the versioned package, including
d3d9.dll, amd_fidelityfx_vk.dll, NvLowLatencyVk.dll and the DLSS family. User visual confirmation is
recorded as failed in session/run JSON. No claim of successful path tracing is made.

### Cleanup and retained files

After the user's stop instruction, only the owned PoC process tree was stopped. Then:

    tools/poc_activation_check.ps1 -Session <session> -Action Cleanup -Multirun

This invoked `tools/uninstall-loader.ps1 -RemoveConfig` and the depot verifier:

    uninstall: removed (633 file-system changes)
    delete 383 file(s) no longer needed
    ok: 2877
    missing: 0
    size_mismatch: 0
    hash_mismatch: 0
    userconfig_differs: 1 (the existing autoexec.cfg difference)

`verify.json` and `created-or-changed.txt` are in the session. No PoC bootstrap DLL/PDB,
native-loader directory or native-loader status data remains. The RTX_c process was not stopped.

Preserved game/Remix output includes rtx-remix logs/capture/mod directories, Sentry metadata/cache,
the engine crash dump/text, metrics.txt, console.log and game-written changes to config.cfg,
cl.db, demoheader.tmp, spray files, modelsounds.cache, mapkeys.res and steam_appid.txt timestamps.
The full before/after listing is retained. Existing console logs were moved into per-run evidence
before each launch, not discarded. No game/Remix-created data was deleted for tidiness.

## 5. Deviations and approvals

- The user approved root CMake's one-line 0.0.1 → 0.1.0 bump, outside the original file scope,
  after the packager/loader minimum-version mismatch was demonstrated.
- The named B folder was gone. The documented `_CompRelease_x64/src/d3d9` copy matched the known
  size/time and A8E39D93 prefix. Its full SHA-256 is pinned in the acceptance script:
  `A8E39D938D96193DF27D245A7F6E72F1C44B75FB2D066A67BDC2CD974EDEA267`.
- The user explicitly approved `-multirun`, overriding the no-other-game precondition for a different
  install. Another PoC instance still blocks a launch. Every actual PoC launch had separate approval.
- After classic shaderModel=0 failed, §9 was observed. The user approved a PoC-only shaderModel=3
  package layer and one A retry. Reference configs and the runtime fork were never modified.
- The baseline ignored the window-close request and UI focus did not permit reliable automation;
  its owned process tree was ended after capture. The final A instance was terminated after the
  user stopped testing. Neither termination is presented as a normal exit for persistence evidence.
- Locked Sentry database/lock files are excluded from text-log capture; they remain in the PoC.

## 6. Open issues and risks

1. **Path tracing remains blocked.** The diagnostic reaches the map but failed the user's visual
   check. Renderer/fixed-function compatibility needs further work; M5 already tracks shader and
   RTX-fix integration. Startup preload success is established independently.
2. **`-dxlevel` persistence is unknown.** Baseline was 95; RTX-on reported 90. No RTX-off launch was
   authorized after the user stopped tests, and the RTX process was not exited normally. Do not
   claim that this setting restores itself. A mitigation still needs the user's decision if it persists.
3. **Real B/rollback acceptance remains open.** Both are covered by synthetic tests; the real B
   package was prepared but never launched. The hold needs the planned real check after rendering
   compatibility and off-state behavior are resolved.
4. The validated kernelbase descriptor shape is Windows-build-dependent; refusal reports fallback
   arguments. Rollback API failures are reported and backing strings are retained to avoid dangling
   pointers. Startup status does not monitor later renderer crashes.

Measured facts and source references are added to [RESEARCH.md](../RESEARCH.md). The PoC is cleaned
and depot-verified, so no installed test state needs removal before review.

## 7. Questions for the user

None pending now: the user explicitly stopped PoC testing and requested this report. Future PoC
launches and any rendering or dxlevel mitigation need fresh authorization. No further launch,
Steam option change, game-binary patch or fork edit was performed.

## 8. Reviewer starting points

1. `loader/proxy/startup.cpp` and `runtime.cpp`: transaction order, SEH ownership, rollback and commit.
2. `loader/core/src/cmdline.cpp`: descriptor validation, partial-write undo and restoration lifetime.
3. `loader/core/src/startup.cpp` plus deployer option changes: last-good policy and unchanged CLI behavior.
4. `loader/proxy/tests/activation_integration.py` and its evidence: real dependency resolution,
   rollback, contention, off switches and status assertions in independent processes.
5. The real session's `02-RunA`, `03-RunA`, module list, user visual failure and cleanup verification.

Review against `389755c..m4-activation`. Claude reviews before any separately authorized merge.
