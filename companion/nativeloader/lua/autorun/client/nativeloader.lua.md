# nativeloader.lua

The Lua companion's client autorun file. When the client Lua state starts (a map is loaded) it prints
the native loader's start-up and session status to the console, and again whenever the console
command `nativeloader_status` is run. [`tools/package_fixes.py`](../../../../../tools/package_fixes.py.md)
ships it in the RTX fixes package as the add-on folder `garrysmod/addons/nativeloader`. Since M6 it
also says when Steam has a newer version of a deployed Workshop package, which the next start
deploys ([M6 report](../../../../../docs/handover/M6-report.md)).

```
] nativeloader_status
[nativeloader] loader 0.2.0, process 59992, written 30 s before this client started
[nativeloader] deployment: deployed, generation 3
[nativeloader] activation: active (runtime rtx-remix-runtime 1.0.0)
[nativeloader] runtime: rtx-remix-runtime 1.0.0
[nativeloader] session: written 29 s before this client started
[nativeloader] patches: 6 of 7 applied
[nativeloader]   skipped datacache.dll dx80_vtx_to_dx90_vtx: pattern matched 0 times
[nativeloader] override stdshader_dx6.dll: redirected (H:\...\shaders\stdshader_dx6.dll)
[nativeloader] session variables: 34 set by nativeloader_session.cfg
[nativeloader] restored variables: 0 by nativeloader_restore.cfg
```

## Inputs

Both files are read from the `DATA` path (`garrysmod/data/`) with `file.Read` and parsed with
`util.JSONToTable` inside `pcall`. A missing, empty or invalid file is reported, never an error.

`native-loader/status.json` (written by the bootstrap at every active start;
[ON_DISK_LAYOUT.md](../../../../../docs/ON_DISK_LAYOUT.md)), schema 1 only:

| Field | Printed |
|---|---|
| `schema` | anything but `1` stops the report |
| `loader_version`, `process_id`, `utc` | first line; `utc` (`YYYY-MM-DDThh:mm:ss.fffZ`) gives the age |
| `deployment.outcome`, `.generation`, `.reason`, `.blocked_by`, `.skipped[]` (`package`, `reason`) | deployment line, skipped packages |
| `activation.outcome`, `.reason`, `.runtime.id`, `.runtime.version` | activation and runtime lines |
| `activation.reshade.outcome`, `.reason`, `.settings` (loader 0.5.0, [ADR 0028](../../../../../docs/decisions/0028-reshade-in-rtx-sessions.md)) | `reshade: active (ReShade from ...), settings migrated in native-loader\reshade`; no line when no package carries ReShade or the status is older |
| `session.cvars`, `.cvars_exec`, `.recorded`, `.restore_values`, `.restore_exec`, `.notes[]` | the session-variable and restore lines, and every note |
| `packages[]`: `id`, `label`, `source`, `time_updated` | the update notice for Workshop packages (below) |
| `errors[]` | the first five |

`native-loader/session.json` (written by the bootstrap in sessions with module hooks: patch sets and
overrides with RTX, the hidden add-ons without), schema 1 only; its absence is reported as "no
session.json":

| Field | Printed |
|---|---|
| `schema`, `process_id`, `utc` | age; a `process_id` other than status.json's is pointed out |
| `patches[]`: `module`, `name`, `result` (`applied`/`skipped`), `reason` | applied count; every patch not applied with its reason |
| `overrides[]`: `module`, `requested`, `loaded`, `result` (`redirected`/`failed`) | one line each, with the file loaded |

**Stale reports.** The loader writes status.json once per start, and an off switch or a start without
the loader leaves the previous one. A report whose `utc` is more than 15 minutes before the client
started (`os.time()` when this file ran) is printed as `STALE, not from this session`. The age is
measured against the client start, also for later `nativeloader_status` commands, so a session that
stays in a map for hours still counts as current. A client started more than 15 minutes after the
game itself (a long stay in the main menu) shows its own report as stale.

## Side effects

- The console output and the console command `nativeloader_status`.
- The update notice: for each deployed Workshop package, `steamworks.FileInfo` asks Steam for the
  item's update time. That is a Steam request, not one of its own.
  - GMod hands `FileInfo`'s times over as 32-bit floats, rounded to a 128 s step at today's
    timestamps (1793444836 comes back as 1793444864), while `time_updated` is Steam's exact time. So
    only a time more than one such step after the deployed one counts as newer; compared directly,
    the deployed version itself looked newer for about half the items, and its restart notice came at
    every start (the Evernight and March 7th item, 2026-10-31).
  - When Steam has a newer version than the one deployed, it prints the notice once per item per
    session, and shows a `notification.AddLegacy` hint, in the player's language when the
    translations load (`nativeloader/i18n.lua` through `include`, English otherwise; the console
    lines stay English).
  - A timer (`nativeloader_updates`, every 600 seconds) checks again, because Steam may download an
    update while the game runs.
- It runs on the client only (`lua/autorun/client`, plus a `CLIENT` guard). There is no exit code.

Checked outside the game under LuaJIT 2.1 with the GMod functions it uses mocked (missing, fresh,
stale and invalid files, odd field types, `utc` dates around leap days and month ends).

## R20-A bootstrap update reminder

After InitPostEntity and four seconds, loaders older than 0.15.0 get a scaled Derma reminder when
the package's published release record is newer. Version comparison handles SemVer prereleases and
large numeric identifiers without floating-point ordering. Loaders from 0.15.0 use the main menu.
The JSON record is at `addons/nativeloader/resource/loader-release.json`; it is read physically via
BASE_PATH, at most 1 KiB, never through GAME mounting. Exactly version/url, a canonical ASCII JSON
record and the fixed version-specific project URL are required. The active runtime must be
gmod-rtx-remix and match native discovery's package/source. The committed journal (BASE_PATH,
`native-loader/state.json`, at most 16 MiB) must have no pending transaction, exactly one runtime
owner, and exactly one unchanged size/SHA-256 entry for the record. Missing/invalid/foreign data is
silent. No Steam request is made for this reminder.

The three buttons open only the validated release URL, defer for this process, or ignore that version.
DATA `native-loader/loader-update-seen.txt` stores the status process token (PID/UTC for older
reports) to survive map changes; `loader-update-ignored.txt` stores the ignored version for this
older-loader fallback. The new menu uses its own local cookie. Both DATA files are bounded to 128
bytes on read. No loader/cloud/Remix settings are changed.
Title/body/buttons use the six catalogs, with fonts, frame, title bar and controls scaled by ScrH()/1080 and
bounded to the viewport. Errors are contained by pcall. Harness: `tools/tests/loader_update_harness.lua`.
