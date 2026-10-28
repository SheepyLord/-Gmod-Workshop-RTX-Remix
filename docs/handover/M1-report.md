# M1 report: inert winmm bootstrap

- Assignee: Codex, 2026-10-27 (America/Vancouver)
- Branch/worktree: `m1-bootstrap`, `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix-M1`
- Base: `770e2ee` (`M0` on main). The brief's `m0` tag and prepared M1 worktree did not exist;
  created the requested branch/worktree from that clean M0 commit. No history rewritten.
- Status: **implementation delivered; acceptance blocked pending Windows Defender review**.
  M1 is not marked complete. No push or merge.

## 1. Summary

Implemented the complete inert bootstrap, generated forwarding files, tests, installer and smoke
script. Debug and Release compile with `/W4 /WX`, static CRT and only `KERNEL32.dll` imports.
All 56 Python tests and repo conventions pass. Five pure activation/token/root cases pass;
installer checks pass in 23 assertions on synthetic roots. The initial native run passed actual
export completeness, multimedia forwarding and log-before-main hook integration.

Defender then blocked the initial DLL as `Trojan:Win32/Bearfoos.A!ml` (2147731250). The full native
suite consequently failed on loads/copies. Further proxy execution and enabled PoC runs are
awaiting human review; no security exclusions, threat allowances or antivirus settings were
changed by the agent. Do not interpret successful compilation or initial partial tests as M1
acceptance. The smoke script has been parsed and reviewed but not run end to end.

The actual PoC baseline reached `gm_construct`. `vpk.exe` and `bspzip.exe` baseline runs exit by
themselves. The PoC has **no `winmm.dll`/PDB installed and no `native-loader` state directory**;
the field install, RTX reference installs, Steam settings and launch options were not changed.

## 2. Files

- `loader/proxy/CMakeLists.txt`, `README.md`: DLL, logic library, MASM/RC, generation guard and tests.
- `loader/proxy/activation.h`, `activation.cpp`: allocation-free pure host/root/argument/off-switch logic.
- `loader/proxy/bootstrap.h`, `bootstrap.cpp`: process state, full-path system load, export lookup,
  `DllMain` gating and the 14-byte absolute entry patch/restore.
- `loader/proxy/startup.cpp`: UTF-8 log, rotation, module/timing proof and separate C++/SEH guards.
- `loader/proxy/version.rc.in`: installer identity and project version.
- `loader/proxy/generate_exports.py`, its `.md`, and generated `exports.json`, `exports.h`,
  `winmm.def`, `thunks.asm`: stdlib-only export generation and committed inventory.
- `loader/proxy/tests/CMakeLists.txt`, `README.md`, `host.cpp`, `test_activation.cpp`, `test_proxy.cpp`,
  `install_tests.ps1` and its `.md`: 14 C++ cases, static-import host, generation and installer tests.
- `tools/install-loader.ps1` and `.md`: PoC-default install/uninstall, identity/hash receipt,
  Steam-managed protection, WhatIf and explicit optional state deletion.
- `tools/smoke_test.ps1` and `.md`: five map launches, strict console comparison, two console tools,
  saved evidence and restoration of prior loader/log state in `finally`.
- `loader/CMakeLists.txt`: one proxy subdirectory line. Root `CMakeLists.txt`: scopes C/C++ options
  away from MASM/RC. `loader/README.md`: proxy row.
- Additive M1 notes in CHANGELOG, COMPONENTS, TESTING and RESEARCH; only the M1 ROADMAP row changed.
  This report was added. M2-owned paths, accepted ADRs and AGENTS.md were not edited.

## 3. Design choices

MASM leaf thunks preserve arguments and return addresses and jump through the resolved pointer
table. Names and ordinals exactly follow the committed System32 inventory, including ordinal 2's
`NONAME`. Named functions resolve by name; ordinal-only functions by ordinal. Missing functions
return zero and are reported in debugger output and the active startup log. System `winmm.dll`
is loaded once per proxy attachment by its full System32 path and kept for process lifetime.

`DllMain` creates no threads, waits for nothing and writes no files. Fixed buffers plus pure
functions gate the host and all switches. It saves 14 entry bytes, writes `FF 25 00 00 00 00` plus
the hook address, restores protection and flushes the instruction cache. The hook restores the
entry bytes before guarded logging, then calls the original entry with the same argument/result.
Static CRT thread notifications are preserved. There is no package discovery or runtime preload.

No new decision record was needed: forwarding and hooking follow the accepted ADR and brief.
An unrecoverable OS refusal to restore the entry bytes (both VirtualProtect and debugger-write
fallback fail) terminates rather than recursively entering the patched address. Logging failures
are caught and return to the game; inability to create the log still emits a debugger diagnostic.

The installer adds a hash receipt to enforce the existing user-edit rule beyond version identity.
It refuses a DLL/PDB that no longer matches the receipt (or selected build for a manual copy).
Uninstall retains all state unless explicitly given `-RemoveState`. The smoke test preflights
both installer operations with WhatIf before it snapshots or changes anything.

## 4. Evidence

### Baseline before editing

`tools\test.ps1` on the new M1 worktree:

```text
repo conventions OK
Ran 28 tests ... OK (skipped=1)
Ran 19 tests ... OK
Ran 9 tests ... OK
100% tests passed, 0 tests failed out of 1
All checks passed.
```

### Current code and build checks

- `tools\test.ps1 -SkipNative`: the same 56 Python tests, one pre-existing skip; conventions OK.
- `tools\build.ps1 -NoTests`: `Build win64-debug OK`.
- `tools\build.ps1 -Config Release -NoTests`: `Build win64-release OK`; retained in
  `out/m1-release-build.txt`. Full `build.ps1 -Config Release` with CTest remains pending.
- `python loader\proxy\generate_exports.py --check`:
  `winmm exports OK: 181 system ordinals covered, generated files consistent`.
- `py -3.12 tools\diag\pe_imports.py out\build\win64-debug\loader\proxy\winmm.dll`
  and the Release equivalent: `static: KERNEL32.dll`, no delay imports.
- Filtered pure C++ cases for activation, game root, argument tokens, backslashes/quotes and
  switch precedence: all passed. A filtered command-line-off integration case also passed on a
  subsequent rebuilt fixture; that is not a complete suite result.
- `loader\proxy\tests\install_tests.ps1 -Repo <M1 worktree> -Config Release`:
  `Installer OK: 23 checks (synthetic roots only).` Evidence: `out/m1-installer-tests.txt`.
- PowerShell parser: zero parse errors in installer, smoke script and installer tests.

### Initial runtime suite and antivirus failure

The first `tools\build.ps1` run after implementation printed:

```text
covered 181 system ordinals and 180 names
ok   proxy exports every system name and ordinal including ordinal-only entries
ok   forwarded multimedia calls reach the separate system module
ok   entry hook logs before main and restores the executable entry point
```

The remaining fixtures were blocked by Defender. A rerun reported:

```text
copy_file: Operation did not complete successfully because the file contains a virus or potentially unwanted software.
14 test case(s), 9 failed
67% tests passed, 1 tests failed out of 3
```

That historical run preceded addition of the fourth CTest (installer). The source has 14 C++ cases
and four CTest entries now; a clean complete native result is outstanding. No enabled PoC
`loader.log` excerpt is available. The initial synthetic log was asserted in-process then removed
by the test's normal scratch cleanup; do not substitute it for the required in-game evidence.

### Resumed validation after user review

The user reviewed the detection and reported excluding
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`. Resumed full Debug and Release validation.
The M1 worktree is a sibling of that directory; its test copies also run under `%TEMP%`.
Fresh `Get-MpThreatDetection` records at 18:21–18:22 name those paths and the Release build,
which Defender removed during the tests. Viewing configured exclusions required administrator
rights, so no exclusion contents were assumed or changed by the agent.

- `tools\test.ps1`: conventions and all 56 Python tests pass; Debug has 7 of 14 proxy cases pass,
  with the 7 child-host cases blocked. The installer CTest fails hashing a Defender-blocked copy.
- `tools\build.ps1 -Config Release`: **11 of 14 proxy cases pass**, including complete exports,
  real forwarding, entry hook timing and **all three off switches**. The remaining host/path,
  logging-failure and rotation cases exit with `0xc0000906`. The installer CTest then reports a
  missing build because Defender already removed `out/build/win64-release/loader/proxy/winmm.dll`.
- Both configurations finish with 2 of 4 CTest entries passing; this is still a failed full suite.
  Raw evidence: `out/m1-full-debug-tests.txt`, `out/m1-full-release-tests.txt`.
- `0xc0000906` is `STATUS_VIRUS_INFECTED`, confirmed in the installed SDK's
  `shared/ntstatus.h:11558`. The existing error output and fresh Defender resource paths account
  for these failures; no native code workaround was introduced.
- Asked the user to review the actual M1 build and generated test-copy detections. PoC remains
  uninstalled and no further in-game run was attempted while this block persists.

### PoC baseline and tools (initial run)

Launched `bin\win64\gmod.exe`, cwd = PoC root, with exactly:

```text
-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons +map gm_construct
```

Observed in `out/baseline/console.log`:

```text
Map: gm_construct
Clientside Lua startup!
Redownloading all lightmaps
Thumbs: 58711 => 58770
```

Stopped only that game process tree. `vpk.exe` no args: exit **1**; `bspzip.exe` no args: exit **-1**.
Their JSON evidence is in `out/baseline/`. PE inspection confirms both import `tier0.dll`, which
imports `WINMM.dll`. Enabled/off-switch runs and tool comparisons await review of the detection.

### Depot integrity

`python tools\steam\verify_install.py <PoC> --manifests-from <field install>
--report out\m1-poc-verify.json` checks only the field install's manifest/cache metadata:

```text
ok: 2877
missing: 0
size_mismatch: 0
hash_mismatch: 0
userconfig_differs: 1 (autoexec.cfg)
```

No proxy was installed into the PoC, so after-install/after-uninstall verification is still part of
the pending acceptance run. All game depot files remain vanilla; GMod-authored config/cache and
console output are the allowed baseline-launch side effects.

## 5. Deviations

- Prepared M1 worktree/tag were absent; used the actual clean M0 commit without adding a tag.
- Complete Debug/Release CTest and enabled PoC smoke acceptance could not be finished after the
  Defender block. Full native failure is recorded, not hidden/skipped as a passing full suite.
  Current compile-only, pure, installer and Python checks are explicitly distinguished above.
- Installer hash receipt, rollback and WhatIf strengthen the stated no-user-edit rule without
  changing native trust or the off switches. No accepted decisions were changed.

## 6. Open issues and retained facts

1. Review Defender detection 2147731250 before further native execution. Then run full Debug and
   Release checks and `tools\smoke_test.ps1`; investigate every unexpected console difference.
2. The actual GMod enabled log must still prove engine/shader API/D3D9 absence. Each off switch
   and both tool comparisons must pass. Run the depot verifier after installing and uninstalling;
   leave the PoC uninstalled.
3. Smoke restoration and normalization are implemented but not yet validated against all five
   real launches. Generated evidence stays below `out/` and no binaries belong in git.
4. Seven earlier antivirus-blocked synthetic fixtures remain at
   `C:\Users\matt-peng\AppData\Local\Temp\nl-proxy-测试-49108-1` through `-7`, containing only the
   synthetic host executables. Automatic approval review rejected both recursive and narrower
   nonrecursive cleanup commands with `blocked by policy`; no further deletion workaround was
   attempted. The test constructor now cleans up on copy failure in future runs.

Measured export set/Windows version, static imports, real baseline marker, tool imports/exits,
Python selection and the detection evidence are recorded in [RESEARCH.md §7](../RESEARCH.md).

## 7. User action

Review the locally built DLL detection in Windows Security → Protection history and decide
whether to allow it. If approved by the user, resume the outstanding native and PoC validation;
otherwise leave M1 incomplete with this report as the reviewable handoff.
