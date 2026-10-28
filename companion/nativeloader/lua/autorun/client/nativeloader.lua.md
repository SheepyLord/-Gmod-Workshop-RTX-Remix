# nativeloader.lua

The Lua companion's client autorun file. When the client Lua state starts (a map is loaded) it prints
the native loader's start-up and session status to the console, and again whenever the console
command `nativeloader_status` is run. [`tools/package_fixes.py`](../../../../../tools/package_fixes.py.md)
ships it in the RTX fixes package as the add-on folder `garrysmod/addons/nativeloader`. M6 adds the
restart notice ([M5 plan](../../../../../docs/handover/M5-plan.md)).

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
| `errors[]` | the first five |

`native-loader/session.json` (written by the bootstrap in RTX sessions with patch sets, module
overrides or session variables), schema 1 only; its absence is reported as "no session.json":

| Field | Printed |
|---|---|
| `schema`, `process_id`, `utc` | age; a `process_id` other than status.json's is pointed out |
| `patches[]`: `module`, `name`, `result` (`applied`/`skipped`), `reason` | applied count; every patch not applied with its reason |
| `overrides[]`: `module`, `requested`, `loaded`, `result` (`redirected`/`failed`) | one line each, with the file loaded |
| `session_cvars`: `exec`, `count`; `restore`: `exec`, `count` | one line each when present |

**Stale reports.** The loader writes status.json once per start, and an off switch or a start without
the loader leaves the previous one. A report whose `utc` is more than 15 minutes before the client
started (`os.time()` when this file ran) is printed as `STALE, not from this session`. The age is
measured against the client start, also for later `nativeloader_status` commands, so a session that
stays in a map for hours still counts as current. A client started more than 15 minutes after the
game itself (a long stay in the main menu) shows its own report as stale.

## Side effects

None beyond the console output and the console command `nativeloader_status`: no file writes, no
network, no hooks or timers. It runs on the client only (`lua/autorun/client`, plus a `CLIENT`
guard). There is no exit code.

Checked outside the game under LuaJIT 2.1 with the GMod functions it uses mocked (missing, fresh,
stale and invalid files, odd field types, `utc` dates around leap days and month ends).
