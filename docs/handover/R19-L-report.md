# R19-L report: the loader

Part R19-L of [the R19 plan](R19-plan.md): the pre-release review's loader findings
([R19-review.md](R19-review.md)), branch `r19-loader`. Every real finding is fixed and tested; F-08 stays
by design with the reason at the code; F-03 was a false positive. The version is not bumped: the
integrator sets 0.14.0, and **the guard's new rule (F-02) depends on that number**.

## The findings

| ID | Result | How, where |
|---|---|---|
| **H2** (high) | Fixed | Content-only candidates need a subscription: Steam's `WorkshopItemDetails` entry must have a `subscribedby` naming a non-zero account id. Details below. `loader/core/src/discovery.cpp`, `include/nl/discovery.h`; [ADR 0111](../decisions/0111-content-packages-only-from-subscribed-items.md) |
| **M5** | Fixed | `displace()` no longer sends a take-over's original to a `backup/originals/<path>` that is taken (an uninstall left a file there). That file stays; the file found now is kept as a changed copy in `backup/edits/<tx>/<path>`, with a note. A taken `backup/edits/<tx>/<path>` (copies from before an uninstall reset the numbering) becomes `backup/edits/<tx>-<n>/<path>`. Never overwrites, never fails. `deploy.cpp` (`occupied`, `free_edits_path`, `displace`, `notes_for`) |
| **NLCORE-01** | Fixed | Uninstall carries the journal's existing `retired` entries into its new journal, so the journal stays until a read-only or locked file is really gone. `deploy.cpp` `remove_all` |
| **NLCORE-02** | Fixed | The no-work return of a planning pass removes what an earlier pass of the same run staged (`finish`). `deploy.cpp` `deploy_plan` |
| **NLCORE-03** | Fixed | Files moved into `backup/originals` and `backup/edits` are hashed just before their move, like the legacy moves. A file changed since the plan fails the run, which undoes itself; the next run plans with the file as it is. No in-run replan: the trigger is an editor saving during the seconds of extraction. `deploy.cpp` `checked_before_move` |
| **NLCORE-04** | Fixed | Rollback checks a root file both generations share (size and time, else hash) and refuses while it is missing or changed: "apply puts the package's copy back, then roll back". `deploy.cpp` `roll_back` |
| **NLCORE-05** | Fixed | Size sums saturate (`add_size`), and the space check compares without overflow. A package that declares more than the whole volume holds is skipped as broken, so it cannot stop the others; one that only needs more free space than there is still stops the run, as before (for the CLI, treating that as broken would remove the deployed older version). `deploy.cpp` `disk_space`, `ensure_space`, `deploy_plan` |
| **F-01** | Fixed | Player README: `remix.enabled: false` is the way to play without RTX, and says what it does; `-nonativeloader` (and `NATIVE_LOADER_DISABLE=1`, `native-loader\disable`) is a troubleshooting switch that deploys, hides and puts back nothing (the package's add-ons stay mounted and run without Remix; RTX console settings stay; Workshop updates wait). Also lines for H2 and F-02. `dist/README-native-loader.txt` |
| **F-02** | Fixed | An RTX start holds `garrysmod/data/native-loader/rtx-session.txt` with delete-on-close until the process ends; the guard needs it next to an "active" report from loader 0.14.0 or later. Details below. `core/src/status.cpp`, `include/nl/status.h`, `proxy/startup.cpp`, `companion/.../_nativeloader_guard.lua` |
| **F-03** | False positive | Unchanged, as the plan says. |
| **F-04** | Fixed | `load_first` records a dependency as done only once it loaded; a failed one is tried again at the module's next load. The first failure and the success are reported once each (no growing `session.json`). `proxy/modules.cpp` |
| **F-05** | Fixed | `LOAD_WITH_ALTERED_SEARCH_PATH` is added only when the caller passed no `LOAD_LIBRARY_SEARCH_*` flag; the replacement is loaded by full path, so the search flags look beside it anyway. `proxy/modules.cpp` `replacement_flags` |
| **F-06** | Fixed | `resolve_exports()` runs before the observer check, so the rundll32 host has the real forwarding table (any module there importing `winmm.dll` by name binds to the proxy). The observer still runs no loader work. `proxy/bootstrap.cpp` |
| **F-07** | Fixed | `nlctl scan` walks without `skip_permission_denied`. A folder it cannot list is a failure ("folder not scanned") and the walk goes on; an entry whose attributes cannot be read is a failure; exit 1 either way. `cli/nlctl.cpp` |
| **F-08** | By design | Loading System32's `winmm.dll` in `DllMain` stays: the forwarding table must be filled before anything calls an export, which can happen before the entry point. A comment at the `LoadLibraryW` gives the reason no lock cycle can form. I read the import tables myself: the static imports are `ntdll.dll` and API sets only; WINMMBASE, the MME sets, AudioSes, the user32 sets and OLEAUT32 are delay-loaded. `proxy/bootstrap.cpp` |

### H2 in detail

- **The rule.** A content-only candidate (an item not in `allow.workshop`) comes only from an item whose
  `WorkshopItemDetails` entry has a `subscribedby` naming at least one non-zero account id. The value is
  comma-separated account ids: this machine's record has one to four per item. `steamworks.DownloadUGC`
  leaves a details entry without it; this machine has 40 such items.
- **Not subscribed and not deployed:** no candidate at all, and not listed as skipped.
- **Deployed but not subscribed:** `unsubscribed`, so it is removed exactly like an ADR 0025
  unsubscribe: no keep-last-good hold, no rollback copy. The reason reads "not subscribed: Steam has it
  only because the game or a server downloaded it (or it was unsubscribed); content packages come only
  from subscriptions, so a package it deployed is removed". The "(or it was unsubscribed)" is there
  because the same state follows a real unsubscribe while Steam keeps the files.
- **No record, no verdict.** All of these add no new candidate and keep every deployed one as before:
  - the acf missing or unparsable;
  - no `AppWorkshop` or no `WorkshopItemDetails` section;
  - an item entry that is not a block;
  - a `subscribedby` that is not account ids.
  ADR 0025's rule for an item listed nowhere with its folder gone is unchanged.
- **Unchanged:** the allowlist needs no subscription, and `subscribed_content: false` still works.
- **Real data:** `nlctl plan` of the PoC lists the same five decisions with the 0.13.0 build and with
  this one (the RTX package and four subscribed content packages). None of this library's 40
  unsubscribed items holds a package, so H2 removes nothing on this machine.

### F-02 in detail, and why not a timestamp

- **The plan's `os.time() - os.clock()` does not estimate the process start in GMod.** I checked
  rather than assumed:
  - `bin\win64\lua_shared.dll` imports only `tier0.dll`, `vstdlib.dll` and `KERNEL32.dll`, so LuaJIT's
    `clock()` is a statically linked CRT's. Read from the PoC's import table with a standard-library
    script (`out\r19-loader\pe_imports.py`, git-ignored).
  - The UCRT's `clock()` is QPC wall time since *that CRT's* initialization (Windows SDK 10.0.26100
    `ucrt\time\clock.cpp`, `ucrt\initializers\clock_initializer.cpp`). For a static CRT that is when
    `lua_shared.dll` loads.
  - That load comes after the bootstrap's whole start-up: `gmod.exe` imports neither tier0 nor
    lua_shared, so they load later, dynamically. If GMod had replaced `os.clock` with tier0's timer
    (I found no sign of it), that clock would start after the bootstrap too.
  - The estimate would therefore lag the creation time by the deployment, which takes minutes after a
    package update, plus the engine's start. A 30 s tolerance would drop the guard from real RTX
    sessions. A tolerance wide enough for that would accept the old report of an RTX start that crashed
    a minute in, which is when players reach for the off switch. Sleep and clock changes add more
    error.
- **The check I chose is a per-process marker that Windows itself removes.**
  - *The bootstrap.* After an activation commits, it creates `rtx-session.txt` with `CREATE_ALWAYS`,
    `FILE_FLAG_DELETE_ON_CLOSE` and read sharing only, writes `session_token=<PID>-<creation>`, and
    never closes the handle. Windows closes it when the process ends, whether by quit, crash or Task
    Manager, and deletes the file. No other process can delete or replace it while it is held.
  - *Any other bootstrap start* (no active activation) deletes a marker nobody holds: the leftover of a
    power loss or system crash. Uninstall (`status::remove`) does too.
  - *The guard.* `localRTXStart()` still requires the "active" report. When that report's
    `loader_version` is 0.14.0 or later, it also needs the marker: first `file.Exists`, then a
    `file.Find` listing, which never opens the file. An older loader's report decides alone, as
    before, so players who update the Workshop item but keep an old `winmm.dll` lose nothing. With no
    readable report, the marker alone shows this start's RTX, which also covers the first half of the
    Codex finding (a status file that could not be written).
  - *The routes.* Early and autorun use the same check. The verified multiplayer route never reads
    status and is unchanged.
- **Residual cases, all narrower than before:**
  - Power loss during an RTX session followed directly by an off-switch start (only a later normal
    start clears the marker).
  - Two games at once from one folder, an RTX one and an off-switch one (the old code had this too).
  - A marker that could not be created: a session note says so, and the guard stays out of that
    session.

## Tests run

| Test | Result |
|---|---|
| `tools\build.ps1 -Config Release` | builds, `/W4 /WX` |
| `nl_tests "--skip=deploy faults:"` | 269 cases pass |
| New cases: discovery ×2, deploy ×6 (M5, NLCORE-01 to 05), startup ×1 (H2), status ×1 (marker) | pass; against the old `deploy.cpp` all six deploy cases fail at their finding |
| `guard_session_marker.lua` (18 cases, new CTest `nl_guard_session_marker`) | pass; against the old guard 7 fail (the stale cases and the marker-only ones) |
| `tools/tests` guard harness (`test_render_guard*.py`, 47 tests, run only, R19-T's files) | pass unchanged |
| `nl_activation_integration` (28 scenarios, 2 new: the marker's life, H2 through the real `winmm.dll`) | pass |
| `nl_session_integration` (F-04 retry run, F-05 search-flag load), `nl_exit_observer_integration` (F-06), `nlctl_crosscheck_gmapack` (F-07, the `icacls` case ran), `nl_proxy_tests`, `nl_render_guard_tests` | pass |
| `nlctl scan` of the real Workshop folder (TESTING.md's real-data check) | 817/817 parsed, 84 LZMA, no failures |
| `tools\test.ps1 -SkipNative` | conventions OK, 578 Python tests OK |
| `tools\test.ps1 -Config Release` (full, as CI runs it) | C++ build, 27 of 27 CTests (the fault cases and `nl_glass_tests` included), 578 Python tests: pass. Its conventions step failed on this report's own link, since fixed: `tools\check_repo.py` passes |
| `tools\test.ps1` (full, Debug, the default) | 26 of 27 CTests pass. `nl_glass_tests` fails in Debug only, in two glass cases (see Open issues). It links none of this part's code, and passes in Release |

## Proposed lines for the shared docs

**CHANGELOG.md, under [Unreleased]**

- **Content packages only from subscribed Workshop items** (R19 H2, ADR 0111). The loader deploys a content package without the allowlist only from an item that Steam's record (`subscribedby` in `appworkshop_4000.acf`) shows an account of this computer subscribed to, no longer from every installed item. Any server's client Lua can make the game download an item (`steamworks.DownloadUGC`); such an item is never deployed, and a content package an older loader deployed from one is removed at the next start, like an unsubscribe. A missing or unreadable record adds nothing and keeps what is deployed. Allowlisted items are unchanged.
- **The render guard installs only in this start's RTX session** (R19, proxy F-02). An RTX start holds `garrysmod/data/native-loader/rtx-session.txt` until the game exits (Windows deletes it however the game ends). The companion's guard needs it next to an "active" report from loader 0.14.0 or later, so a start with `-nonativeloader` after an RTX session no longer installs the guard from that session's report.
- **A left-over original no longer blocks deployment** (R19 M5). When `native-loader/backup/originals/<path>` holds a file an uninstall left there, a deployment that takes the path over keeps the file it finds in `backup/edits` (a numbered sibling folder if that is taken) with a note, instead of failing at every start.
- **Deployer edge cases** (R19 NLCORE-01 to 05):
  - uninstall keeps its journal while files an earlier run could not delete remain;
  - a package that fails its checks leaves no staged bytes;
  - a file moved into `backup/originals` or `backup/edits` is hashed before its move, so one changed during extraction fails the run and is planned again;
  - a rollback refuses while a root file both generations share is missing or changed;
  - declared sizes saturate in the free-space check, and a package declaring more than the disk holds is skipped.
- **Proxy fixes** (R19 F-04 to F-07):
  - a module dependency that failed to load is tried again at the module's next load;
  - a caller's `LOAD_LIBRARY_SEARCH_*` flags no longer make an overridden module's load fail;
  - the exit observer's rundll32 forwards winmm calls to System32;
  - `nlctl scan` reports folders it cannot list.
- **Player README** (R19 F-01): `remix.enabled: false` is how to play without RTX; `-nonativeloader` is described as a troubleshooting switch that deploys, hides and puts back nothing.

**docs/RESEARCH.md**

- **Steam's `subscribedby`** (2026-11-05). In `appworkshop_4000.acf` it holds comma-separated decimal account ids.
  - This library: 817 installed items, 817 details entries. 777 have `subscribedby`: 744 with three ids, 22 with four, 10 with one, 1 with two.
  - 40 have none. Their entries hold `manifest`, `timeupdated`, `timetouched`, `latest_*` and sometimes `ugchandle`: what `DownloadUGC` leaves.
  - None of the 40 holds a native package: `nlctl plan` of the PoC is the same with loader 0.13.0 and with R19's.
- **GMod's Lua clock** (2026-11-05):
  - GMod's `bin\win64\lua_shared.dll` imports only `tier0.dll`, `vstdlib.dll` and `KERNEL32.dll`, so it links the C runtime statically. LuaJIT's `os.clock()` therefore counts from when that DLL loads, after the loader's start-up, not from the process start.
  - The UCRT's `clock()` is QPC wall time since its CRT's initialization, and -1 past `LONG_MAX` ms (Windows SDK 10.0.26100 `ucrt\time\clock.cpp`, `ucrt\initializers\clock_initializer.cpp`).
  - `bin\win64\gmod.exe` imports USER32, KERNEL32, ADVAPI32, ole32, WINMM, dbghelp and, delayed, libcef: no tier0 and no CRT DLL.
- **System32 `winmm.dll`'s imports** (10.0.26100.1). Static: `ntdll.dll` and API sets only. Delay-loaded: WINMMBASE.dll, the `api-ms-win-mm-mme`/`misc` sets, AudioSes.DLL, the `ext-ms-win-ntuser-*` sets, OLEAUT32.dll, `api-ms-win-core-com` and `ext-ms-win-oleacc`. So the proxy's load of it under the loader lock waits on no other thread (R19 F-08).
- **A file held with `FILE_FLAG_DELETE_ON_CLOSE` and read sharing only:**
  - `GetFileAttributesW`, `FindFirstFileW`, `std::filesystem::exists` and Python's `os.stat` see it;
  - another `DeleteFileW` fails with `ERROR_SHARING_VIOLATION`, and a second `CREATE_ALWAYS` fails;
  - it is gone within moments of the holding process being killed (`test_status.cpp`, `activation_integration.py`).
  - GMod's `file.Exists` is still to be confirmed in game; see the checks below.
- **`nlctl scan` of this library's 817 Workshop archives** with R19's stricter walk: all parse, 84 LZMA, no failures (2026-11-05).

**docs/decisions/README.md** (to paste as it is; the link is relative to that folder)

```markdown
- [0111: Content packages come only from subscribed Workshop items](0111-content-packages-only-from-subscribed-items.md) (R19 H2, the user; amends decision 1 of 0027).
```

**docs/ON_DISK_LAYOUT.md** (not this part's path)

- In the status.json section: `garrysmod/data/native-loader/rtx-session.txt` (R19).
  - Held by an RTX start with delete-on-close for the life of the game process; it contains `session_token=<PID>-<creation FILETIME>`.
  - Windows deletes it when the process ends. The companion's guard requires it next to an "active" report from loader 0.14.0 or later.
  - A start without RTX deletes one that no process holds (a power loss's leftover), and so does uninstall.
- In the edits row: changed copies go to `backup/edits/<tx>-<n>/` when `backup/edits/<tx>/` already holds that path.

**docs/TESTING.md:** add CTest `nl_guard_session_marker` (registered only with LuaJIT).

**The root `README.md`** (not this part's path) repeats what F-01 found:

- Line 177: "To skip the loader for a single session without uninstalling, add `-nonativeloader`". Add:
  "(for troubleshooting: the package's add-ons stay in the game and run without Remix; to play without
  RTX, set `"remix": { "enabled": false }`)".
- Lines 210-211, "Can I go back to plain Garry's Mod?". Lead with the RTX-off setting as the way to play
  without RTX and uninstalling as the way back. Describe `-nonativeloader` as skipping the loader for one
  start, for troubleshooting.
- Line 188, "Content packages ... load from any subscription". Add "(loader 0.14.0: only from items you
  subscribed to, never from items a server only downloaded)".

ADR 0027's wording ("any subscribed item") is now what the code does; its readers should follow the link
to 0111, which the decision index line above provides.

## What the integrator must do

1. **Set the version to 0.14.0.** The guard applies the marker rule to reports from 0.14.0 on, and with
   0.13.x it behaves as before.
2. **No imports or pins.** `companion/` is a packaging input that `package_fixes.py` reads directly, so the
   guard change reaches the RTX package when it is built. The loader ships in the release zip.
3. **In the game** (PoC, after the version bump, with the new `winmm.dll` and a package built from this
   guard):
   1. RTX start, then a map:
      - `garrysmod\data\native-loader\rtx-session.txt` exists while the game runs;
      - `status.json` `session.notes` has "RTX session marker held until the game exits: ...";
      - in the client realm, `NativeLoaderRenderGuard.installation` is `early`. For example
        `lua_run_cl print(NativeLoaderRenderGuard and NativeLoaderRenderGuard.installation)` with
        `sv_allowcslua 1`, or poc_session's client Lua. `autorun` is acceptable where the early view is
        unavailable.
      - This confirms GMod's `file.Exists` sees a file held with delete-on-close.
   2. Quit, or end the game in Task Manager: the marker is gone.
   3. **The finding's check.** Start the same PoC with `-nonativeloader`:
      - `status.json` is unchanged, still "active";
      - there is no marker;
      - on a map, `NativeLoaderRenderGuard` is `nil` and the console shows no `[nativeloader] RTX guard:` lines.
   4. Unchanged behaviour: a `remix.enabled: false` start gives no guard, and a verified multiplayer
      join still installs it ("verified multiplayer bootstrap").
   5. **H2.** The first PoC start with 0.14.0 deploys what `nlctl plan` shows: the RTX package and the
      four subscribed content packages, with no "not subscribed" removals. For the field's two-start
      check, `nlctl plan <field root>` (read-only) previews the same.
   6. A normal RTX session also covers F-04 to F-06:
      - the fixes' binary modules load (`session.json` `module_dependencies` "loaded");
      - the shader override is "redirected";
      - the loader log says "exit observer ready", and a normal quit shows no rundll32 error.
4. **Strings to translate:** none. The new texts are deployment reasons and notes in English, which the
   companion only prints in its console diagnostic, and the English player README.

## Open issues

- GMod's `file.Exists("native-loader/rtx-session.txt", "DATA")` on a file held with delete-on-close is
  verified only by analysis and by the Windows APIs and CRT `stat` it can use (all see the file in the
  tests). The guard falls back to `file.Find`, a directory listing. In-game check 1 confirms it.
- NLCORE-03 fails the run on drift, without replanning in the same run; the next start replans.
- The guard's tests in `tools/tests` (R19-T's path) do not exercise the marker. I added the decision test
  under `loader/guard/tests` instead. The harness's mock reports loader 0.10.1, so it keeps the old
  rule and passes unchanged.
- **Not this part's code: `nl_glass_tests` fails in the Debug build** (`tools\test.ps1` without
  `-Config`), on the unchanged `r19-int` glass code, in two cases. It passes in Release, which CI runs.
  For R19-G or the integrator:
  - "glass overfull contact tables count saturation and keep the world running" ends with
    `0x80000003`, a debug assertion (Jolt's asserts exist only in Debug);
  - "glass benchmark 4000 colliding pieces settle within 15 simulated seconds 30 wall and 120 CPU
    seconds" misses its wall-clock limit in Debug on this busy machine.
