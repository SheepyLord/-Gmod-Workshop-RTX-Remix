# R1 handover: whole-repo code review

- From: Claude, 2026-10-28. Claude wrote M2, M3, M5-M7, M4's parts 1-2 and the M4 review fixes.
- To: Codex, which wrote M1 and most of M4.
- Branch: `r1-review`, in the worktree
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review`.
- Baseline: `main` at `8f8a540` (M0-M7, pushed to `origin`), plus the commit that adds this brief.
- In parallel: nothing changes `main` until your report has been triaged.

This brief is your task specification. [AGENTS.md](../../AGENTS.md) applies in full. If anything here
seems to conflict with it, AGENTS.md wins: stop and report the conflict.

## 1. Purpose

M0-M7 are merged and pushed. The loader has run in the user's real install (M7, then rolled back).
The next steps are installing it there for good and perhaps publishing packages. Before that, the
user wants a thorough, independent review of the whole repository.

Most of the code was written by Claude and checked only by Claude's reviews and tests. Your M1 and
M4 code was reviewed by Claude. Review all of it with the same rigour, your own included.

**You review and report. You do not fix.** Claude verifies every finding and fixes the accepted ones.
You may then be asked to check the fixes (section 9).

What matters, in this order:

1. **Harm to the user's install or data.** A Steam depot file written, a user's file overwritten or
   deleted, Remix's `user.conf` touched, or state that uninstall or rollback cannot recover.
2. **Trust.** Native code (DLLs, patch sets, module overrides) deployed or run from a source the user
   did not allowlist ([ADR 0003](../decisions/0003-native-trust-allowlist.md)), or a package writing
   outside its areas.
3. **The game.** A crash, hang or long stall caused by the loader, at start or in play, with RTX on or
   off. Every off switch must give a pure pass-through.
4. **Tools that touch real installs:** install, uninstall, snapshot and rollback, the PoC drivers.
5. **Tests and docs.** Tests that would not catch a broken invariant; docs that say something the code
   does not do.

Out of scope:

- style, naming, formatting and rewrites;
- performance, except start-up time;
- the accepted decisions themselves ([0001-0013](../decisions/README.md)).

Do report code that disagrees with a decision record, and any decision that rests on a fact you find
to be wrong.

## 2. Read first

1. [AGENTS.md](../../AGENTS.md): rules 1-9 and the glossary.
2. [ARCHITECTURE.md](../ARCHITECTURE.md), [ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md) and
   [PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md).
3. The [decision records](../decisions/README.md), above all:
   - [0003](../decisions/0003-native-trust-allowlist.md): the allowlist;
   - [0007](../decisions/0007-transactional-deployment.md): transactional deployment;
   - [0008](../decisions/0008-activation-at-startup.md): activation;
   - [0009](../decisions/0009-startup-deployment-last-good.md): start-up deployment, keep-last-good;
   - [0010](../decisions/0010-rtx-session-extras.md): patch sets, module override, session variables;
   - [0011](../decisions/0011-lua-addon-folders.md): add-on folders as a package area;
   - [0013](../decisions/0013-rtx-only-addons-hidden-without-rtx.md): RTX-only add-ons hidden without
     RTX.
4. The module READMEs. In [loader/core](../../loader/core/README.md), the sections "GMA reader rules",
   "LZMA rules", "JSON rules", "Path rules", "Deployment rules" and "Rules for code here" state
   invariants for you to check. Also [loader/proxy](../../loader/proxy/README.md),
   [loader/cli](../../loader/cli/README.md), [loader/tests](../../loader/tests/README.md),
   [loader/proxy/tests](../../loader/proxy/tests/README.md) and [companion](../../companion/README.md).
5. [TESTING.md](../TESTING.md), and how each milestone was accepted:
   - [M1 report](M1-report.md) and [review](M1-review.md);
   - [M4 report](M4-report.md) and [review](M4-review.md);
   - [M5](M5-report.md), [M6](M6-report.md) and [M7](M7-report.md) reports.
6. [RESEARCH.md](../RESEARCH.md) as needed: the facts about GMod, Remix and Windows that the code
   relies on.

## 3. State at handover

- `main` = `origin/main` = `8f8a540`, plus this brief.
- Nothing of ours is installed in any game folder:
  - the PoC (`H:\SteamLibrary\steamapps\common\GarrysMod_PoC`) is vanilla, with no `winmm.dll` and no
    `native-loader\`;
  - the field install was rolled back at the end of M7.
- Test results on `8f8a540`:
  - `tools\test.ps1` (Debug): conventions OK; 91 Python tests, 1 skipped (no LuaJIT); CTest 16/16
    (135 `nl_tests` cases, the exhaustive fault cases, the proxy cases, the synthetic game scenarios
    and the KERNEL32-only import check).
  - `tools\build.ps1 -Config Release`: CTest 16/16.
- Size in tracked lines:

  | Part | Lines | Priority |
  |---|---|---|
  | `loader/proxy` (without `generated/` and tests) | 1,560 | 1: runs inside `gmod.exe` |
  | `loader/core` (`src/` 5,650, `include/` 1,390) | 7,040 | 1-2: start-up and deployment; `deploy.cpp` alone is 1,357 |
  | `loader/cli/nlctl.cpp` | 616 | 3 |
  | Tools (Python and PowerShell, without tests) | 4,190 | 2 for those that touch installs |
  | Lua companion | 220 | 3 |
  | C++ tests, synthetic hosts and integration scripts | 6,000 | 2: as evidence for the invariants |
  | Python tests | 1,470 | 3 |
  | Vendored: `third_party/lzma`, `tools/gmapack` | — | Provenance and licence only, plus how our code calls the decoder |

## 4. What to review, in this order

Each area lists its files, what must hold, and the questions the user most needs answered. The
questions are a floor, not a limit.

### 4.1 Area A: code that runs inside `gmod.exe` (first)

Files:

- `loader/proxy/`: `bootstrap.cpp`, `activation.cpp`, `startup.cpp`, `runtime.cpp`, `modules.cpp`,
  `generated/` and `generate_exports.py`;
- the `nl_core` code that start-up calls: `startup.cpp`, `status.cpp`, `session.cpp`, `cmdline.cpp`,
  `activate.cpp`, `patch.cpp`, `sha256.cpp`, and `deploy.cpp` and `fs.cpp` as they run at start-up.

Must hold:

- Pure pass-through, with nothing set, loaded or hooked, and nothing written beyond the files
  ON_DISK_LAYOUT documents for that case, when:
  - any off switch is set;
  - the host is not the game (GMod's command-line tools, Chromium helper processes);
  - the config or the journal is missing, disabled or invalid.
- Any failure before the runtime is committed leaves a vanilla process. The environment, `PATH`, the
  command line (kernelbase's caches and the PEB), the Vulkan loader and the DLL search are all as they
  were. After the commit nothing is undone.
- `winmm.dll` imports only KERNEL32. `DllMain` does only work that is safe under the loader lock.
- Every export forwards to the matching System32 `winmm` function, by name or ordinal, through
  register-preserving thunks.
- With RTX off: no patch set, no module override and no RTX session variables. Only two things happen:
  - the one-time restore of values an RTX session changed (ADR 0010);
  - the hooks of ADR 0013, which apply only to the add-on folders of `requires_remix` packages.
- Patch sets apply only when all of these hold:
  - they come from the deployed (allowlisted) generation;
  - their pattern occurs exactly once in the module;
  - `-insecure` is on the command line, while the config's `patch_sets.require_insecure` is true (the
    default).

Questions:

1. **Loader lock.** What runs inside `DllMain`, and inside the `LdrRegisterDllNotification` callback
   (`modules.cpp` `on_dll` → `handle`)? That callback patches code, writes import slots, allocates,
   takes an SRW lock and writes `session.json`. Can any of it deadlock, load a library, or re-enter
   our own hooks?
2. **Exceptions.** The project builds with CMake's default `/EHsc`. Consider an SEH fault caught by any
   `__except`: `on_dll`, `startup_seh`, `report_seh`, `rollback_guarded`, `install_hook`. What is left
   behind?
   Destructors skipped, an SRW lock still held, a half-applied patch or import write, a half-written
   file? Can a later call then deadlock or crash?
3. **Concurrency in the hooks of `modules.cpp`.** These are the `LoadLibrary*`, `FindFirstFile*`,
   `FindNextFile*` and `FindClose` hooks. They run on any thread for the whole process. Check:
   - `g_state`'s lifetime against `uninstall()`;
   - the tracking of open searches: a handle closed through a path we do not hook, a handle value
     reused;
   - every shared container.
4. **The search filter (ADR 0013).** Does `filesystem_stdio.dll` get exactly what an empty or shorter
   listing would give it? Consider the error codes, `FindFirstFileExW`'s info levels and flags, A and
   W calls with non-ASCII names, and relative patterns. Can the filter hide anything other than the
   listed folders directly inside `garrysmod\addons`?
5. **Import hooks.** `game_module()` covers everything under the game root except `native-loader\`.
   That includes add-on binary modules and the user's own DLLs in `bin\win64`, such as the field
   install's DXVK `d3d9.dll`.
   - Is hooking all of those safe?
   - Can an overridden module still load without the redirect: a delay load, a `LoadLibrary` found
     through `GetProcAddress`, `LdrLoadDll`, a load before `install()`?
   - Is the PE parsing in `hook_imports_recorded` safe on any module?
6. **Patch application (`nl::patch`).** Check:
   - the bounds in `find()` and `sections()`;
   - sections that are not readable;
   - patching code that another thread may be executing;
   - what the session report says when a patch is skipped.
7. **Command line (`nl::cmdline`).** Check:
   - the validation of the `UNICODE_STRING` / `ANSI_STRING` descriptors and the `USHORT` limits;
   - the PEB and kernelbase's caches;
   - buffers that must live for the whole process;
   - the restore when something else has replaced a slot.
8. **Activation order and undo (`runtime.cpp`).** The steps are:
   - environment variables;
   - launch arguments;
   - System32's `vulkan-1.dll`;
   - the `PATH` prepend (which replaced `SetDllDirectoryW` in ADR 0010);
   - the absolute `d3d9.dll` preload;
   - the `GetModuleHandleW(L"d3d9.dll")` check.

   Is every step undone on failure, in the right order? What if the user already has `PATH` entries,
   `DXVK_*` variables, or a `d3d9.dll` in `bin\win64`?
9. **Session console variables (`nl::session`, ADR 0010).** These are `+exec
   nativeloader_session.cfg`, the record in `native-loader\session_cvars.json`, and the one-time
   restore. Can a value in the user's `config.cfg` be lost or overwritten? Consider a crash mid-session,
   the user changing a value between sessions, and two sessions.
10. **Start-up time.** Can anything block the game's start for a long time or for ever? Consider lock
    waits, the retries in `nl::fs`, a reader holding `status.json`, and a very large deployment.

### 4.2 Area B: deployment, state and inputs (`nl_core`)

Files in `loader/core/src/`:

- deployment and state: `deploy.cpp`, `fs.cpp`, `journal.cpp`, `planner.cpp`, `startup.cpp` (the
  keep-last-good policy);
- packages and rules: `package.cpp`, `paths.cpp`, `manifest.cpp`, `config.cpp`, `discovery.cpp`;
- parsers: `vdf.cpp`, `gma.cpp`, `lzma.cpp` (and how it calls `third_party/lzma`), `json.cpp`,
  `utf8.cpp`;
- checksums: `crc32.cpp`, `sha256.cpp`.

Must hold (ADR 0007, AGENTS.md rules 2-4, and the core README's rules):

- **Replacing and removing.** Only files the journal records are replaced or removed, and only after a
  full SHA-256 shows they are unchanged.
  - Someone else's file blocks its package.
  - A changed file is left in place and reported.
  - Create-only roots are never replaced.
- **Protected files.** No Steam depot file is ever written, renamed or deleted. Remix's `user.conf` is
  never touched.
- **Links.** Nothing is placed, moved or deleted through a link (symlink, junction or other reparse
  point) below the game folder.
- **Interruptions.** After a crash, a kill or a power cut, the next run's recovery ends in the old
  state or the new one.
- **Allowlist.** Only allowlisted sources are opened, deployed or activated, and native code comes
  only from them.
- **Untrusted input.** Archive, manifest, JSON, KeyValues and config bytes are untrusted.

Questions:

1. **Path rules** (`paths.cpp`, `manifest.cpp`, ADR 0011). After Windows normalises a path a package
   names, can it land outside the package's areas, on a depot file, or on another package's file?
   Consider case, trailing dots and spaces, 8.3 names, `\\?\` prefixes and Unicode. Can two packages'
   paths differ only in case without the planner noticing?
2. **Depot files inside package areas.** `garrysmod/cfg`, `garrysmod/lua/bin` and `garrysmod/addons`
   can hold Steam's files. What stops a package from replacing one? Include a depot file that happens
   to be missing when the package deploys.
3. **Links.** Is there a gap between the check (`refuse_links`, `through_link`) and the create, move or
   delete that follows it? Does any write go in place, and so through a hard link, rather than by
   rename?
4. **Transactions.** Check the order of journal writes, flushes and renames, and what
   `recover_pending` does for each step type. Then consider:
   - a full disk during staging;
   - a file held open by an antivirus scanner or by Steam;
   - the lock file left by a crashed process;
   - two deployers at once.
5. **Allowlist and identity** (`config.cpp`, `discovery.cpp`, `planner.cpp`, ADR 0003, ADR 0006).
   - How is a candidate tied to its allowlist entry: Workshop id, local path, dev folder?
   - Can a package that is not allowlisted be deployed or activated by claiming an allowlisted id or
     name?
   - Can an allowlisted package take another package's files or the runtime slot?
6. **Untrusted input** in `gma.cpp`, `lzma.cpp`, `json.cpp`, `vdf.cpp` and `manifest.cpp`:
   - integer overflow, bounds and limits;
   - decompressed size;
   - the total extracted size against `ensure_space`;
   - does discovery ever open an archive that is not allowlisted?
7. **Keep-last-good and holds** (`startup.cpp`, ADR 0009). Walk its decisions with a source that is
   missing, unreadable, mid-update, disabled in `addonnomount.txt`, or removed from `config.json`.
8. **Uninstall.** Does it remove exactly what the journal lists and nothing else? It must leave changed
   files, remove folders only when empty, and keep the journal until everything is gone.

### 4.3 Area C: `nlctl`

`loader/cli/nlctl.cpp` and its tests in `loader/cli/tests/`. Check:

- the same invariants as area B;
- that `--dry-run` never writes;
- argument parsing, including paths with spaces or non-ASCII characters;
- exit codes and output against [loader/cli/README.md](../../loader/cli/README.md).

### 4.4 Area D: tools that touch real installs or the user's data

| Tool | What must hold |
|---|---|
| [`install-loader.ps1`](../../tools/install-loader.ps1.md), [`uninstall-loader.ps1`](../../tools/uninstall-loader.ps1.md) | Never overwrite or remove a `winmm.dll` the loader did not install (hash check). Refuse a Steam-managed install unless `-AllowSteamManaged`. Uninstall removes exactly the journal's files, then the bootstrap |
| [`field_snapshot.py`](../../tools/field_snapshot.py.md) | Runs against the user's real install, so rollback must never lose user data. See the questions after this table |
| [`poc_session.py`](../../tools/poc_session.py.md), [`poc_parity.py`](../../tools/poc_parity.py.md), [`smoke_test.ps1`](../../tools/smoke_test.ps1.md), [`poc_activation_check.ps1`](../../tools/poc_activation_check.ps1.md), [`poc_deploy_check.ps1`](../../tools/poc_deploy_check.ps1.md) | Write only to the PoC, or to nothing with `--reference`. Read only their own session's part of a console log. Terminate only processes they started. Put back exactly what they changed |
| `tools/steam/`: [`verify_install.py`](../../tools/steam/verify_install.py.md), [`make_vanilla_copy.py`](../../tools/steam/make_vanilla_copy.py.md), `steam_manifest.py`, `vdf.py` | `verify_install.py` must never call an install vanilla when it is not: what exactly does it compare? `make_vanilla_copy.py` writes only the new copy |
| [`package_runtime.py`](../../tools/package_runtime.py.md), [`package_fixes.py`](../../tools/package_fixes.py.md) | Manifests and hashes match what is packaged. The fixes package leaves out the Steam files that the fixes repository overwrites. Nothing unintended is packaged: secrets, logs, `user.conf`. Data roots and roots the runtime writes are create-only |
| [`check_repo.py`](../../tools/check_repo.py.md), [`test.ps1`](../../tools/test.ps1.md), [`build.ps1`](../../tools/build.ps1.md), [`VsDevEnv.psm1`](../../tools/lib/VsDevEnv.psm1.md) | They enforce what AGENTS.md says they enforce. Their environment changes do not leak into the caller |

Questions on `field_snapshot.py`:

- **Moving, not deleting.** New entries must be moved, never deleted. Check the fallback in `move_out`
  when the rename fails, for example across volumes.
- **Links and restores.** Links must be moved and never followed. Restores must write in place.
- **The registry restore** imports the export, then prunes keys and values missing from it. It must
  never delete anything the user had.
  - Check `read_reg` against every form `reg export` writes: multi-line hex, escaped quotes,
    `REG_MULTI_SZ`, `REG_EXPAND_SZ`, empty values, keys with unusual characters.
  - What happens when an export fails or is truncated?
- **Coverage.** What can a session change that the snapshot does not cover?

### 4.5 Area E: the Lua companion

`companion/nativeloader/lua/autorun/client/nativeloader.lua`. Check:

- that it copes with a missing, stale, partial or malformed `status.json` or `session.json`: the JSON
  parse, nil fields, wrong types;
- that nothing it reads can make it run code;
- that it does no per-frame work and does not spam the console;
- that the update check (`steamworks.FileInfo`) works as [ADR 0012](../decisions/0012-distribution-route.md)
  and the [M6 report](M6-report.md) describe.

### 4.6 Area F: tests

For every "must hold" above, name the test that would fail if the invariant broke, or report the gap.
Look for:

- tests that cannot fail: vacuous assertions, or fixtures that skip the code under test;
- tests that depend on this machine's state: the registry, Steam paths, running processes;
- tests that depend on timing;
- fault-injection coverage of the start-up path (deployment inside the game process), not only of
  `nlctl`.

### 4.7 Area G: docs against code

Compare:

- [ON_DISK_LAYOUT.md](../ON_DISK_LAYOUT.md)'s schemas against the parsers and serializers: `config.json`,
  `state.json`, `status.json`, `session.json`, `session_cvars.json`;
- [PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md) against `manifest.cpp`: every key, type and limit;
- [ARCHITECTURE.md](../ARCHITECTURE.md)'s flows against `startup.cpp`;
- each script's `.md` (usage, inputs, side effects, exit codes) against the script;
- [COMPONENTS.md](../COMPONENTS.md) and the module READMEs against the files;
- counts and statuses that are out of date.

Drift is P3, unless it could lead someone into a harmful action; then it is P2.

### 4.8 Area H: licences and repository hygiene

- `third_party/lzma`: the SHA-256 values in its README match the files, and the licence is there.
- `tools/gmapack`: provenance and licence (AGENTS.md rule 7).
- No code copied from `garrys-mod-rtx-remixed` (GPL-2.0) into this MIT repository. Its checkout is
  at `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`, read only. Compare the places where our code
  does similar things: patch-set handling, the module override, Lua, packaging.
- What the packagers put into packages: GPL-2.0 Lua and binaries from that repository, and NVIDIA
  binaries from the Remix fork. Note what a public release would have to carry, such as licence texts
  and source offers. This is a question for the user, not a code defect.
- No binaries, packages, secrets or personal data in tracked files (`git ls-files`).

## 5. How to check

Reading the code is the main tool. Confirm what you can:

1. **Baseline first.** In the worktree, run `tools\test.ps1`, then `tools\build.ps1 -Config Release`,
   and record the summary lines. If either fails on the clean worktree, stop and report it.
2. **Reproduce suspected defects.**
   - For `nl_core`, write a small test. A temporary test case in `loader/tests` is the quickest; a
     synthetic game folder under `out\r1-review\` also works.
   - Run it, and keep its code and output under `out\r1-review\repro\<finding id>\`.
   - Then revert the working tree: only the report is committed.
3. **In-process behaviour.** The synthetic game hosts in `loader/proxy/tests` cover most paths: a copied
   `gmod.exe` beside the built `winmm.dll`, under `out\`. Do not launch the real game.
4. **Optional, if already on this machine (download nothing):**
   - MSVC `/analyze` on `loader/core` and `loader/proxy`, in a scratch build under `out\r1-review\`;
   - an AddressSanitizer build (`/fsanitize=address`) of `nl_tests`;
   - a short run of crafted and mutated inputs through the parsers: GMA, LZMA, JSON, KeyValues,
     manifests.
5. **Read-only use of the PoC.** `tools\steam\verify_install.py` may run against the PoC. Nothing else
   touches a game install.

## 6. Boundaries

| You may | You may not |
|---|---|
| Read anything in this repository, the fixes checkout and the Remix fork (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`) | Change production code, tests, tools or docs, except the report. A temporary change for a repro is reverted before you commit |
| Build and run the tests, the synthetic hosts, `nlctl` and the Python tools on folders under `out\` | Write to any game install (the PoC included), `GarrysMod_RTX_c` or its backups, the fixes checkout or the fork. Launch GMod. Change Steam settings or launch options |
| Write under `out\r1-review\`: scratch, repros and evidence | Read or search a `console.log` from the user's installs, or anything under the main checkout's `out\m7\snapshot\`. That folder holds copies of the user's own files, including their full console log; those logs hold months of the user's play |
| Add `docs/handover/R1-report.md` and commit it on `r1-review` | Push, merge into `main`, rewrite history, or use the network (download nothing) |

**Registry.** `tools\test.ps1` runs the `field_snapshot` tests, which create and delete a throwaway key
`HKCU\Software\NativeLoaderTest_<random>`. Nothing else may touch the registry.

**Git.** Commit only the report, and later updates of it, on `r1-review`. If the sandbox stops you
writing to git, ask the user for approval. If approval is not possible, leave the report uncommitted
and say so.

## 7. Order of work and keeping progress

1. The baseline (section 5, step 1).
2. Area A, then B, then D.
3. Then C, E, F, G and H.

Add findings to the report as you go, and keep its coverage table current: each file reviewed, partly
reviewed, or not yet.

If your context or time runs short:

1. finish the area you are in;
2. commit the report with its coverage table;
3. stop and say what remains.

The user will start another session with the same prompt, which continues from the table.

## 8. The report (`docs/handover/R1-report.md`)

1. **Summary:** the commit reviewed, how you checked, the baseline test results, and the number of
   findings at each severity.
2. **Findings table**, most severe first: ID (`R1-001`, ...) | Severity | Area | File:line | Title.
3. **One section per finding:**
   - **What is wrong:** the code, with file:line at the reviewed commit.
   - **Failure scenario:** the concrete input or state, and the wrong result it leads to. A P0 or P1
     without one is a question, not a finding.
   - **Evidence:** the repro (its path under `out\r1-review\repro\`) and its output, or the exact trace
     through the code.
   - **Confidence:** confirmed (reproduced), likely (traced, not reproduced), or question.
   - **Suggested fix:** a sentence or two, no patch.
4. **Checked and fine:** per area, what you verified and found correct, so the coverage is visible.
5. **Coverage table:** every source file in scope, marked reviewed, partly reviewed, or not reviewed.
6. **Checks you could not run, and why** (a real-game run, for example). Claude can run those with
   [`poc_session.py`](../../tools/poc_session.py.md).
7. **Questions** for the user and for Claude.

Severity:

| Level | Meaning |
|---|---|
| P0 | Damage to the user's install or data: a depot file written, a user's file overwritten or deleted, state that uninstall or rollback cannot recover. Also: native code run from a source the user did not allowlist, or a crash or hang of the game in a normal setup |
| P1 | Wrong behaviour in a supported setup with a realistic trigger: a Workshop update during start-up, a scanner holding a file, a non-ASCII user or game path, a second instance, a full disk, a power cut. Also: a security weakness that needs an unusual but plausible condition |
| P2 | Robustness with an unlikely trigger; an invariant stated in the docs with no test; docs that could lead someone into a harmful action; code likely to cause bugs when it is next changed |
| P3 | Small issues: docs drift, dead code, unclear names |

Already known. Report these only if you find a new angle:

- **The companion is hidden with RTX off.** It ships in the fixes package, so it is hidden along with
  its update notice ([ADR 0013](../decisions/0013-rtx-only-addons-hidden-without-rtx.md)).
- **Watched files are not copied.** `field_snapshot.py` records only size and time below
  `garrysmod/data` and `garrysmod/settings`. Rewritten add-on state there cannot be put back exactly
  ([M7 report](M7-report.md)).
- **Untested start-up paths** ([M4 review](M4-review.md)):
  - no test drives an SEH fault through the start-up boundary;
  - the real command-line swap was exercised only with `bin\win64\gmod.exe` started directly, not
    through Steam's root launcher.
- **Patch sets need `-insecure` by default.** This is by design: the config's
  `patch_sets.require_insecure`.
- **The private Workshop upload test (M6) has not been run.** It is publishing, so it is the user's
  call.

## 9. After the report

Claude verifies each finding and records it as accepted or rejected, with the reason, in a triage
note. Claude fixes the accepted findings on a separate branch, then tests them, including real PoC
runs where they matter. The user may then ask you to check the fixes against your findings; that round
gets its own short brief.

## 10. Stop and ask

Stop and ask the user only if:

- the baseline tests fail on the clean worktree; or
- this brief seems to conflict with AGENTS.md.

Some checks would need a game launch, writing outside `out\`, the registry beyond the test key, or the
network. Do not stop for those: list each under "Checks you could not run" in the report and carry on.
