# M1 handover: the inert bootstrap (`winmm.dll` proxy)

- From: Claude (author of M0 and the plan), 2026-10-27
- To: Codex
- Branch: `m1-bootstrap`, in the git worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix-M1`
- Baseline: `main` at tag `m0` (the M0 scaffold)
- In parallel: Claude implements M2 on branch `m2-core` in the main checkout (see section 6)

This brief is your task specification. [AGENTS.md](../../AGENTS.md) applies in full and wins if
anything here seems to conflict with it; if so, stop and report the conflict.

## 1. Read first

1. [AGENTS.md](../../AGENTS.md): rules, build and test commands, documentation duties.
2. [docs/decisions/0001-bootstrap-winmm-proxy.md](../decisions/0001-bootstrap-winmm-proxy.md): why
   the bootstrap is a `winmm.dll` proxy that works at the EXE entry point.
3. [docs/ARCHITECTURE.md](../ARCHITECTURE.md), "Boot sequence" steps 1 and 2. M1 builds step 1 and
   the frame of step 2, nothing more.
4. [docs/ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md): the `native-loader\` folder and the off switches.
5. [docs/RESEARCH.md](../RESEARCH.md) section 1: which DLLs GMod imports and why `winmm` works.
6. [docs/TESTING.md](../TESTING.md): the PoC install and how to launch it.

## 2. State at handover

- `tools\test.ps1` passes on the baseline: conventions OK, 56 Python tests, C++ build and CTest.
- `loader/core` is a placeholder (`nl::version()`); `loader/proxy` does not exist yet.
- The PoC install `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` is byte-identical to the vanilla
  x86-64 build 26229091 (2,877 depot files verified), plus `steam_appid.txt`. Nothing of ours is
  installed in it.
- Toolchain on this machine: VS 2022 Build Tools (MSVC 14.44), bundled CMake 3.31 and Ninja 1.12,
  Windows SDK 10.0.26100, Python 3.12. `tools\lib\VsDevEnv.psm1` finds the compiler even though
  `vswhere` cannot.

## 3. Goal

With our `winmm.dll` in `bin\win64`, the PoC behaves exactly as without it, while we can prove that
our code ran at the EXE entry point before any engine DLL loaded, wrote a log, and honoured every off
switch. No package discovery, deployment or runtime preloading yet (M2 to M4).

## 4. Deliverables

### 4.1 `loader/proxy/`: the `winmm.dll` target

- New CMake module `loader/proxy` (add `add_subdirectory(proxy)` to `loader/CMakeLists.txt`) building
  a DLL with output name `winmm.dll`, linked with `nl_build_options` (static CRT, `/W4 /WX`).
- A version resource identifying it (for example `InternalName` / `OriginalFilename` = `nl_winmm.dll`,
  `FileDescription` = "GMod native loader bootstrap", version from `nl/version.h` or the CMake project
  version). The install script uses it to tell our DLL from a foreign `winmm.dll`.
- The proxy may link `nl_core` but must not modify `loader/core/**` (owned by M2). Put M1 helpers in
  `loader/proxy/` (for example a small static library `nl_proxy_logic` that the tests also link).

### 4.2 Forward every `winmm` export

- Every export of `%SystemRoot%\System32\winmm.dll` (names, ordinals, ordinal-only exports) must be
  exported by our DLL and reach the system implementation.
- Generate the export list from the system DLL with a stdlib-only Python script (no `pefile`; with its
  `.md` beside it), commit the generated files, and add a test that fails when the current system
  `winmm.dll` has an export ours lacks. Record the export count and the Windows build it came from in
  RESEARCH.md.
- Preferred technique: MASM thunks (`enable_language(ASM_MASM)`), each export a
  `jmp qword ptr [table + 8*i]`, with the table filled in `DllMain` from the system DLL loaded **by
  full path** (`GetSystemDirectoryW` + `\winmm.dll`). Loading `"winmm.dll"` by bare name would return
  our own module and recurse. An export the system DLL lacks must point to a stub that fails safely
  (returns 0) and is logged.
- Alternative: linker forwarders to an absolute system path. That hard-codes the Windows folder;
  choose it only with a new decision record (`docs/decisions/0006-...md`) that explains the trade-off.

### 4.3 Host check and off switches (in `DllMain`, cheap, loader-lock safe)

- Activate only when the host is `...\bin\win64\gmod.exe` (case-insensitive) and our DLL sits in that
  same folder. Every other host (hlmv, studiomdl, vbsp and the other tools that load `winmm` through
  `tier0.dll`; the CTest hosts) gets a pure pass-through: no hook, no files written.
- Game root = the EXE's folder, two levels up (`bin\win64\..\..`).
- Off switches, any one of which makes the DLL a pure pass-through:
  - launch option `-nonativeloader` (own tokeniser over `GetCommandLineW`, handling quotes; do not
    pull `shell32` into `DllMain`);
  - environment variable `NATIVE_LOADER_DISABLE=1`;
  - file `<root>\native-loader\disable`.
- Put the decision logic in pure functions (`should_activate(exe path, module path, command line,
  env value, disable-file exists)` and similar) so they are unit-tested without a process.

### 4.4 Entry-point hook and the start-up step

- When active, `DllMain` (`DLL_PROCESS_ATTACH`) patches the host EXE's entry point
  (`OptionalHeader.AddressOfEntryPoint`) with an absolute jump (`FF 25 00 00 00 00` + 8-byte address)
  to our hook, after saving the original bytes. Use `VirtualProtect`, restore the protection, and call
  `FlushInstructionCache`.
- The hook restores the original bytes first, runs the start-up step, then calls the original entry
  point with the same argument and returns its result.
- The start-up step must never let an exception or SEH fault escape (wrap it with `__try`/`__except`
  in a small separate function as well as `try`/`catch`). On any failure: log it and continue
  into the game.
- In M1 the start-up step only logs. It writes `<root>\native-loader\logs\loader.log` (create
  folders; rotate, keeping about five old logs) with:
  - loader version, UTC timestamp, process id;
  - EXE path, game root, working directory, command line;
  - result of each off-switch check;
  - system `winmm.dll` path and how many exports resolved;
  - whether `engine.dll`, `shaderapidx9.dll` and `d3d9.dll` are already loaded (expected: no; this is
    the proof that we run before the engine);
  - elapsed time.
- `DllMain` does nothing else: no threads, no waiting, no file writes, no `LoadLibrary` except the
  system `winmm.dll`.

### 4.5 Tests (CTest, run by `tools\build.ps1`)

Put them in `loader/proxy/tests/` (own target, for example `nl_proxy_tests`). Reuse the existing
harness: include `loader/tests/nl_test.h` and compile `loader/tests/test_main.cpp` into your target
(do not edit either file; M2 adds tests next to them).

1. Unit tests for the pure functions: host-path matching (`bin\win64\gmod.exe` yes; `bin\gmod.exe`,
   `hlmv.exe` or a mismatched DLL folder no; case-insensitive), root derivation, command-line
   tokenising (quotes, `-nonativeloader` as a whole token only), switch precedence.
2. Export completeness: every system export (name and ordinal) is present in the built `winmm.dll`.
3. Forwarding: load the built DLL by full path in a test process; make sure its module handle differs
   from the system `winmm.dll`; call a few harmless functions through it (`timeGetTime`,
   `timeBeginPeriod(1)` / `timeEndPeriod(1)`, `waveOutGetNumDevs`, `mmsystemGetVersion`) and compare
   with the system DLL where results are deterministic.
4. Hook integration without GMod: build a tiny host that statically imports `winmm` (calls
   `timeGetTime`). The test copies it to `<temp>\bin\win64\gmod.exe` beside the built `winmm.dll`,
   runs it, and asserts:
   - `<temp>\native-loader\logs\loader.log` exists;
   - the log shows the start-up step ran before the host's `main` (the host writes its own
     timestamped marker);
   - the host exits normally.
   Repeat with each off switch, and with the host under another name: no log, normal exit.

### 4.6 Scripts (each with `<script>.md` beside it)

- `tools/install-loader.ps1`:
  - copies the built `winmm.dll` (and its `.pdb`) into `<GameRoot>\bin\win64\`; `-Uninstall`
    removes only a `winmm.dll` it can identify as ours (version resource) and leaves
    `native-loader\` unless `-RemoveState` is given;
  - `-GameRoot` defaults to the PoC; `-Config Release|Debug`;
  - refuses a Steam-managed install (one whose folder name appears as `installdir` in an
    `appmanifest_*.acf` of its `steamapps`) unless `-AllowSteamManaged` is given; the field install
    is Steam-managed, the PoC is not;
  - refuses to overwrite a `winmm.dll` that is not ours.
- `tools/smoke_test.ps1`: launches the PoC twice (baseline without the bootstrap, then with it) and
  compares the two runs.
  - Requires Steam running (check for the `steam` process; otherwise exit with a clear message).
  - Launch `bin\win64\gmod.exe` with the working directory set to the game root and
    `-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons +map gm_construct`.
  - Wait (with a timeout) for a "map loaded" marker in `garrysmod\console.log`. Find a reliable marker
    from a baseline run yourself and document it in RESEARCH.md.
  - Then end the game process.
  - Copy the evidence (console logs, `loader.log`) to `out\smoke\<timestamp>\`.
  - Compare normalised console output; differences must be explainable or the test fails.
  - Uses `install-loader.ps1` to switch states and leaves the PoC as it found it.

### 4.7 Documentation (part of done, see AGENTS.md)

- `loader/proxy/README.md` and `loader/proxy/tests/README.md` naming every source and generated file.
- Update `loader/README.md` (proxy row), `docs/COMPONENTS.md` (bootstrap, install and smoke-test rows:
  status and paths), `docs/ROADMAP.md` (M1 row only), `docs/TESTING.md` (how to run the smoke test),
  `docs/RESEARCH.md` (new facts with numbers), and `CHANGELOG.md`: a new `### Added (M1: inert bootstrap)`
  block directly under `## [Unreleased]`.
- Write `docs/handover/M1-report.md` (section 8).

## 5. Definition of done

- [ ] `tools\test.ps1` passes, including all new tests (Debug), and `tools\build.ps1 -Config Release` passes.
- [ ] The built `winmm.dll` imports no VC++ runtime DLLs (check with `tools\diag\pe_imports.py`).
- [ ] Export-completeness, forwarding, host-gating, off-switch and hook-integration tests exist and pass.
- [ ] On the PoC, with Steam running: the baseline and bootstrap runs both reach gm_construct;
      console output matches after normalisation; `loader.log` shows the start-up step ran with
      `engine.dll` not yet loaded; each off switch yields no log and a normal start.
- [ ] Two console tools from the PoC's `bin\win64` that load `winmm` through `tier0` (for example
      `vpk.exe` with no arguments; pick a second one that exits by itself) behave the same with and
      without the bootstrap installed, and write no log.
- [ ] `python tools\steam\verify_install.py <PoC> --manifests-from "H:\SteamLibrary\steamapps\common\GarrysMod"`
      still reports every depot file OK after install and after uninstall.
- [ ] The PoC is left with the bootstrap uninstalled (or say in the report that you left it installed).
- [ ] Docs updated as in 4.7; report written.

## 6. Boundaries

| You may change | Do not change |
|---|---|
| `loader/proxy/**` (new) | `loader/core/**`, `loader/cli/**`, `third_party/**`: owned by M2, being written in parallel |
| `loader/CMakeLists.txt` (add one line), `loader/README.md` (proxy row) | `tools/steam/**`, `tools/gmapack/**`, `tools/check_repo.py`: report bugs instead |
| `tools/install-loader.ps1`, `tools/smoke_test.ps1` and their `.md` (new) | `docs/decisions/0001`-`0005` (accepted; supersede with a new record if needed) |
| Root `CMakeLists.txt` only if MASM needs it, with a comment | `AGENTS.md` (Claude updates the status line when merging) |
| Shared docs (CHANGELOG, ROADMAP M1 row, COMPONENTS, TESTING, RESEARCH): additive edits only | `docs/PACKAGE_FORMAT.md` (M2) |
| The PoC install: only `bin\win64\winmm.dll` (+ `.pdb`), `native-loader\`, and files the game writes itself (`garrysmod\console.log`, ...) | The field install `...\common\GarrysMod`, `GarrysMod_RTX_c` and its backups: never write; read only what `verify_install.py --manifests-from` needs (Steam's app manifest and depot cache) |
| Files under `out\` | Steam settings, launch options, anything outside these paths |

Git:

- Work only on `m1-bootstrap` in the M1 worktree, and commit in logical steps.
- Never push, never merge into `main`, never rewrite history.
- If the sandbox stops you writing to git, ask the user for approval. If approval is not possible,
  leave the work uncommitted and say so in the report.

## 7. Practical notes

- In-game tests need the user's real desktop session with Steam running. A sandboxed process may not
  be able to start GMod or reach Steam. If the launch fails for that reason, request approval to run
  `tools\smoke_test.ps1` outside the sandbox, or ask the user to run it and paste the summary.
- Writing to the PoC needs `H:\SteamLibrary\steamapps\common\GarrysMod_PoC` to be writable in your
  sandbox; the user has been told to add it.
- `-noworkshop -noaddons` keeps GMod from mounting the 759 Workshop items the account has installed.
  The PoC shares that Workshop folder with the field install.
- No network access is needed for M1. Do not download anything.
- The root `gmod.exe` is a 32-bit launcher; launch `bin\win64\gmod.exe` directly.

## 8. Report (`docs/handover/M1-report.md`)

1. Summary: what works, what does not.
2. Files added and changed.
3. Design choices: forwarding technique, hook details, anything that needed a new decision record.
4. Evidence: each command you ran for the definition of done, with the lines that show success
   (test counts, the `loader.log` excerpt, the smoke-test summary, the `verify_install` summary).
5. Deviations from this brief and why.
6. Open issues and risks; facts added to RESEARCH.md.
7. Questions for the user.

## 9. Stop and ask instead of guessing

- Anything that would modify a Steam depot file, the field install, Steam settings or launch options.
- A forwarding or hook approach that differs from section 4 (draft a decision record, then ask).
- Smoke-test differences you cannot explain.
- Any need for network access or new third-party code.
