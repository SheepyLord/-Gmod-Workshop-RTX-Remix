# M1 report: inert winmm bootstrap

- Assignee: Codex, 2026-10-27 (America/Vancouver).
- Status: **complete; all M1 acceptance checks passed**.
- Branch: m1-bootstrap, based on M0 commit 770e2ee. No push, merge or history rewrite.
- Active worktree: H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/worktrees/m1-bootstrap.
- Build/evidence directories are relative to that worktree below. Everything is inside the
  parent folder selected by the user.

## 1. Summary

The inert winmm.dll forwards all 181 system export ordinals (180 names and ordinal-only 2),
activates only for the main x64 GMod process, honors all three off switches, restores the
EXE entry point before guarded logging, and continues into the game. Chromium helper processes
stay pure pass-through. M1 loads no packages or Remix runtime.

Debug and Release each pass all four CTest entries: the existing core test, 16 proxy cases,
generated-export consistency and 23 installer assertions. The full runner also passes the
56 Python tests (one pre-existing skip). Both DLLs import only KERNEL32.dll.

The real Release smoke test passes five gm_construct launches, strict normalized console
comparison, all off switches and two console-tool comparisons. The enabled log belongs to
the launched game PID and proves engine.dll, shaderapidx9.dll and d3d9.dll were absent.

The PoC is left with **no winmm.dll, winmm.pdb or native-loader directory**. All 2,877 depot
files match before/after the install checks. The field and RTX reference installs, Steam
settings, launch options and user.conf were not changed.

## 2. Files added and changed

- loader/proxy: CMakeLists.txt, README.md, activation.h/.cpp, bootstrap.h/.cpp, startup.cpp
  and version.rc.in implement the proxy, pure gating, entry hook and log.
- loader/proxy/generate_exports.py and its documentation generate the committed text files
  generated/exports.json, exports.h, winmm.def and thunks.asm without third-party Python.
- loader/proxy/tests: CMakeLists.txt, README.md, host.cpp, test_activation.cpp, test_proxy.cpp,
  install_tests.ps1 and its documentation provide independent export/forwarding checks,
  synthetic main/Chromium hosts, switch/rotation/failure tests and installer regression checks.
- tools/install-loader.ps1 and its documentation implement version/hash-verified install,
  rollback, Steam-managed refusal, WhatIf and state-preserving uninstall.
- tools/smoke_test.ps1 and its documentation implement five real launches, PID-verified
  logging evidence, two tool comparisons and restoration of the prior loader/log state.
- loader/CMakeLists.txt adds the proxy; loader/README.md records it. Root CMakeLists.txt scopes
  C/C++ compiler flags away from MASM/RC.
- tools/test.ps1 and its documentation now filter generated directories relative to the
  repository, so an ancestor named out does not suppress all Python tests.
- CHANGELOG, COMPONENTS, ROADMAP (M1 row only), TESTING, RESEARCH and the handover index/report
  record the final behavior, measurements and active worktree. M2-owned sources, AGENTS.md,
  package format and accepted ADRs remain unchanged.

The module READMEs contain the source-by-source inventory:
[proxy](../../loader/proxy/README.md), [tests](../../loader/proxy/tests/README.md).

## 3. Design choices and discovered bug

MASM leaf jumps preserve the Win64 ABI and dispatch through a table initialized from the full
System32 winmm.dll path. Names resolve by name; ordinal-only entries resolve by ordinal.
An unavailable export uses a zero-return fallback and is reported. The system reference is
retained for process lifetime. No new forwarding or hook approach/ADR was needed.

DllMain uses fixed buffers and allocation-free logic, creates no threads, waits for nothing,
and writes no files. It saves 14 original entry bytes and installs the specified absolute
FF 25 jump with protection restoration and instruction-cache flushing. The hook restores the
bytes first, runs logging behind separate C++ and SEH guards, and calls the original entry.

The real smoke test exposed Chromium children reusing bin/win64/gmod.exe without inheriting
the parent's -nonativeloader flag. These children overwrote the main log. They now stay inert
when a decoded --type=value or --type value argument is present. Unit and child-process cases
cover the roles and near-misses; smoke also requires the log PID to match the launched game.

The installer supplements version identity with a SHA-256 receipt to refuse edited DLL/PDB
files. It preflights both files before uninstall and restores prior bytes on install failure.
The smoke script snapshots only the loader files/logs, disable flag and console log it touches
and restores them in finally, including on its earlier detected failure.

An unrecoverable OS refusal to restore already patched entry bytes terminates instead of
recursively reentering the patched address. Ordinary logging failures are contained and the
host continues. This limit is documented in the proxy README.

## 4. Acceptance evidence

### Full build and tests

Commands in the active worktree:

    tools/test.ps1
    tools/build.ps1 -Config Release

Both configurations:

    100% tests passed, 0 tests failed out of 4
    16 test case(s), 0 failed
    Installer OK: 23 checks (synthetic roots only).

The full Debug runner additionally reports 28 + 19 + 9 Python tests, one existing skip,
repo conventions OK and All checks passed. Raw output:
out/m1-full-debug-tests.txt, out/m1-full-release-tests.txt. Detailed C++ counts also appear
in each build's Testing/Temporary/LastTest.log.

Export and dependency checks:

    python loader/proxy/generate_exports.py --check
    py -3.12 tools/diag/pe_imports.py out/build/win64-debug/loader/proxy/winmm.dll out/build/win64-release/loader/proxy/winmm.dll

    winmm exports OK: 181 system ordinals covered, generated files consistent
    static: KERNEL32.dll

No VC++ runtime DLL or delay imports. Full Release DLL SHA-256:
E9B1327A89853344DD967D4B6C5C8E48E52F49849C208EA7605B61EF278A3351.

### Real PoC smoke

    tools/smoke_test.ps1 -Config Release

    Smoke OK: five map loads; matching normalised console logs; all off switches;
    two identical, inert tools; original loader state restored.

Evidence: out/smoke/20261028T012849979Z. summary.json has success=true, restored=true and error=null.

| Run | PID | gm_construct | Loader log |
|---|---|---|---|
| Baseline | 21336 | loaded | absent |
| Enabled | 64992 | loaded | present; same PID |
| -nonativeloader | 36792 | loaded | absent |
| NATIVE_LOADER_DISABLE=1 | 80548 | loaded | absent |
| native-loader/disable | 34532 | loaded | absent |

vpk.exe and bspzip.exe both match baseline stdout/stderr/exit code and create no log.
Their no-argument exits are 1 and -1 respectively. Both import tier0.dll, which imports WINMM.dll.

Excerpt from enabled.loader.log:

    utc=2026-10-28T01:28:57.694Z
    process_id=64992
    phase=exe_entry_point
    entry_point_restored=1
    exports.resolved=181
    exports.total=181
    module.engine.dll=0
    module.shaderapidx9.dll=0
    module.d3d9.dll=0
    startup.complete=1
    elapsed_ms=0.2898

The command line in that log is the main -game garrysmod ... +map gm_construct launch.
Console normalization preserves order and all nonempty messages, changing only formatting and
the documented thumbnail allocation counts. No unexplained differences were suppressed.

### Depot integrity and final state

Installed Release, ran the verifier, uninstalled with removal of only the newly created M1 state,
then ran the verifier again:

    python tools/steam/verify_install.py <PoC> --manifests-from <field> --report out/m1-poc-installed-verify.json
    tools/install-loader.ps1 -Config Release -Uninstall -RemoveState
    python tools/steam/verify_install.py <PoC> --manifests-from <field> --report out/m1-poc-uninstalled-verify.json

Both reports:

    ok: 2877
    missing: 0
    size_mismatch: 0
    hash_mismatch: 0
    userconfig_differs: 1 (autoexec.cfg)

The user-config difference already existed; all depot files match. Final checks confirm no
PoC winmm.dll/PDB, no native-loader state and no running test game. The field path was read only
for its Steam manifest/cache metadata.

## 5. Deviations and build-location recovery

- The brief's prepared worktree and m0 tag were absent. Used clean M0 commit 770e2ee; no tag/history change.
- Defender initially blocked the sibling M1 checkout and system-temp fixture copies. The user
  instructed building inside H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix and leaving no builds
  elsewhere. The active branch now lives in its ignored out/worktrees/m1-bootstrap directory.
  Host fixtures now use the CMake binary directory. All final checks pass there.
- Removed the old sibling checkout/build after preserving text evidence under out/prior-validation.
  Automatic approval review rejected deletion of seven old temp executables; after checking their
  hashes, moved them into out/prior-validation/legacy-fixtures instead. Those temp roots contain
  no generated binaries now. No security settings were changed by the agent.
- The selected nested worktree exposed the test runner's absolute-path filtering bug; the small
  repository-relative fix and its script documentation are included under the user's location request.
- The Chromium-role gate fixes the actual GMod process selection; it does not change the specified
  entry patch, forwarding technique, native trust policy or existing off switches.

## 6. Open issues, retained facts and user questions

No M1 acceptance work remains. No user action is required. Claude can review m1-bootstrap and this
report before any separately authorized merge; no push/merge was performed.

Unsigned proxy builds can still be detected at other locations; validation here uses the user's
selected folder. Future milestones must keep Chromium helpers inert and preserve the PID check.
The design's ordinary hook-restoration/logging failure limits remain documented.

Measured Windows/export versions, baseline marker, Chromium commands, test discovery, smoke timing
and final integrity evidence are in [RESEARCH.md sections 7–8](../RESEARCH.md).
