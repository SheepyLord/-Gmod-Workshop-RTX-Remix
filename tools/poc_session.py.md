# poc_session.py

Drives Garry's Mod sessions on a test install (default: the PoC) for acceptance tests, with nobody
at the keyboard: installs the bootstrap and a `config.json`, launches the game, waits for the map,
optionally loads a save and pins the camera, takes screenshots of the game window, records the
loaded modules, ends the game with a normal `quit`, collects the logs, and uninstalls again. Each step
appends a record to `<evidence>\session.json` and writes its files to `<evidence>\<step name>\`.

```powershell
$e = 'out\poc-sessions\example'
python tools\poc_session.py --evidence $e install --allow-local out\packages\runtime-a.gma --remix on
python tools\poc_session.py --evidence $e run --name 01-rtx-on --addons --settle 30 --screenshots 2 --hide-hud
python tools\poc_session.py --evidence $e config --allow-local out\packages\runtime-b.gma
python tools\poc_session.py --evidence $e run --name 02-b
python tools\poc_session.py --evidence $e nlctl rollback {root}
python tools\poc_session.py --evidence $e config --allow-local out\packages\runtime-b.gma --remix off
python tools\poc_session.py --evidence $e run --name 03-off
python tools\poc_session.py --evidence $e uninstall
# A reference install (only launched and read; nothing of the loader there):
python tools\poc_session.py --root H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\legacy-reference --evidence $e run --name ref --reference --addons
```

Prepare legacy-reference as a separate pinned legacy copy before that example. The user replaced
GarrysMod_RTX_c with this project's implementation on 2026-10-30; never use it as a classic baseline
or write there. The migration acceptance fixture is out/legacy-game (see ADR 0042).

## How it talks to the game

Source runs the payload of a `WM_COPYDATA` message sent to its `Valve001` window as console text
(the mechanism behind `-hijack`; the user's own harness uses it too). It works in single-player, and
`quit` sent this way ends the session normally (the game writes `config.cfg`, Remix closes its log).
GMod refuses `quit` from Lua, and `WM_CLOSE` does not end it ([RESEARCH.md](../docs/RESEARCH.md)
section 11).

Client Lua (the camera and HUD hooks, the Workshop mount) goes through the console too, and nothing
is written into the game folder for it. Source's console splits text at `;` and line breaks and
drops what follows `//`, so the code travels hex-encoded: `lua_run_cl NL_S=""`, then lines of at most
200 hex digits `lua_run_cl NL_S=NL_S.."<hex>"`, then
`lua_run_cl RunString((NL_S:gsub("..",function(h) return string.char(tonumber(h,16)) end)),"nl_session_<name>")`
decodes and runs it under the chunk name `nl_session_camera` or `nl_session_mount`. If one line is
not delivered, the rest are not sent and the attempt counts as failed.

Two things lose console text without a word, and the script works around both. While a map loads,
or the RTX fixes reload models after it, the window does not answer for many seconds, so each send
waits up to 10 s and is tried six times. Text the window accepts during those reloads can also be
dropped, so before a save or the camera the script waits until `console.log` has been quiet for 5 s
(at most 90 s), and it sends the camera Lua again until that Lua prints its `NL_SESSION_EYE` line
(three tries).

## Steps

- `install`: runs [`install-loader.ps1`](install-loader.ps1.md) for `--config` (Release by default)
  and writes `native-loader\config.json` from `--allow-local`, `--allow-dev`, `--allow-workshop`
  (each repeatable), `--remix on|off`, `--reshade auto|on|off` (`remix.reshade`, loader 0.5.0; left out
  unless given), `--performance-tier auto|high|medium|low`, `--gpu-crash-dumps off|next_start|always`
  and `--memory-telemetry on|off` (`remix.performance_tier` and the `diagnostics` keys, loader 0.11.0;
  each left out unless given, since an older loader rejects them) and `--require-insecure yes|no`. An
  existing `config.json` is
  never replaced silently. If its bytes differ from what this install would write, the step is
  refused before the installer runs, and nothing changes. With `--replace-config` the old file is
  first saved as `<evidence>\config.json.before-<UTC time>` and the copy checked. The evidence folder
  is used, not the config's own folder, because `uninstall -RemoveConfig` deletes `native-loader\`
  with everything in it. The step's record then has `config_backup` with the copy's `path` and
  `sha256`. A config that changes while the installer runs is kept, and the step fails.
- `config`: rewrites `config.json` the same way, between runs (no check: replacing it is its job).
- `run --name <step>`: launches `bin\win64\gmod.exe` from the game root with
  `-game garrysmod -multirun -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons`
  (`-multirun`: the user may be playing another install meanwhile, and Source ends a second
  instance at once otherwise, with exit -1 and an empty log; a game of the same install is still
  refused before the launch)
  (`--workshop`, `--addons` leave the last two out; `--no-window` leaves out `-windowed -w -h`, so the
  game's saved video settings and the loader's window options apply), `--extra` arguments, `+maxplayers 1`
  (`--players`), `+mat_dxlevel` (prints the level), `+map gm_construct` (`--map`) and `--post`
  arguments.
  - **With `--workshop` the map is not on the command line.** GMod mounts Workshop add-ons twice at
    start: first before Steam has listed the subscriptions (`Mounted 0 of 755 workshop addons!`),
    then once it has (`Addons have changes - remounting`, `Mounted 752 of 755 workshop addons!`).
  - A map asked for in between waits on that fetch ("Waiting for Steam Workshop to finish...") and
    the window stops answering.
  - So the run starts at the menu, waits for the second mount line (or a first one that mounted all
    of them, or had nothing to mount; or a first that mounted some but not all, once 20 s pass without
    `Addons have changes - remounting`, `PARTIAL_MOUNT_GRACE`: a remount may follow it, R3-013) and 5 s
    of quiet log, then sends `map <name>`.
  - The record has `workshop_mounted`, `workshop_ready`, `workshop_ready_by` (which of those rules),
    `quiet_before_map`, `seconds_to_workshop` and `map_command`.
  - **Crash-report prompts are declined.** The start after a crash shows the Remix runtime's "RTX Remix
    Crash Report" question (upload crash data?) and sometimes a notice after it; unanswered, they held
    the run until its timeout. A background watchdog checks every second from launch through the
    process's exit, including console sends, screenshots, settle/probe waits and shutdown. It answers
    message boxes in its own game process with No (`IDNO`), then OK (`IDOK`), by button id so any Windows
    language works (record: `declined_crash_prompts`, successful sends only). Each answer has a 1 s
    `SendMessageTimeoutW` limit with `SMTO_ABORTIFHUNG`. It never answers Yes, and removes any inherited
    `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` from the game's environment: that flag grants upload
    consent. The watchdog's stop wait is bounded at 3 s; errors are kept as `crash_watchdog_errors`.
  - **Crash minidumps are kept.** Declined, Remix deletes the reports, the only evidence of a crash
    (in R4 a PoC crash lost its dump this way). So before the launch the run copies every `*.dmp` under
    `rtx-remix\logs\.sentry-native` into `<step>\crash-reports-before\` (record:
    `crash_reports_before`), and after a run without a normal quit into `<step>\crash-reports\`
    (`crash_reports`). The watchdog also copies available dumps before declining a live crash prompt,
    since that answer can delete this run's reports. Those copies remain listed even if the source
    disappears before the final collection. A locked or disappearing dump does not prevent log
    collection; copy errors are recorded and copies retried on the next prompt check and at shutdown.
    Copies replace the evidence file atomically, so an interrupted retry preserves an earlier copy.
    A dump in a subfolder is named `<subfolder>-<name>.dmp`.
  - **Device loss and persistent hangs fail promptly.** Health checks throughout the run look for
    `VK_ERROR_DEVICE_LOST` or `Exiting after GPU device loss` in this run's
    `rtx-remix\logs\remix-dxvk.log` (`device_lost: true`, `device_lost_marker`). The pre-launch log
    text is excluded if the file is unchanged or appended; a truncated/replaced log is read anew.
    A temporarily locked log is retried (`remix_log_read_error`) while window checks continue.
    `IsHungAppWindow` checks the game window without sending a message. A continuously unresponsive
    window gets a 120 s grace (`hung_seconds` only after that grace); recovery resets the timer, so
    shorter map-load stalls do not fail. Before console sends and captures, the run waits out such a
    stall without touching the hung window. All long waits poll health at most every 0.5 s; an already
    active console send retains its 10 s limit and checks health before retrying.
    On failure the record keeps `failed` and `normal_quit: false`, skips all remaining game operations,
    and gives Remix up to 60 s to exit while the prompt watchdog continues. It then uses the existing
    process ownership and creation-time checks to stop only this run's game/helpers. Records include
    `failure_exit_wait_seconds`, `terminated_processes` when forced, and the actual numeric `exit`
    (also for forced exits). Logs, modules already observed and available crash reports are collected.
  - **`--menu-shot`** (with `--workshop` and a map) saves `menu.png` of the main menu once the Workshop
    is mounted, before the map is asked for: the loader's diagnostics panel, the native add-on cards
    and the startup text are only there (record: `menu_screenshot`).

  It waits for `Clientside Lua startup!` in `console.log` (`--timeout`, 300 s), then:
  `--load-save <name>` sends `gm_load` and waits for the next map (`save_command` and `save_loaded`
  in the record: `gm_load` prints nothing when the save's map is missing); with
  `--mount-workshop <id>` it first mounts that installed Workshop item from client Lua
  (`steamworks.DownloadUGC`, then `game.MountGMA`, as GMod does for a Workshop save), so a save whose
  map is a Workshop item loads in a session started with `-noworkshop`; `--change-map <map>` instead
  sends `map <map>` and waits for that map (`map_command` and `map_changed`), so a Workshop map such
  as `gm_poolrooms` loads the same way without a save. `--mount-workshop` is repeatable: a library a
  local add-on needs (Zippy's Library, 3146473253, for the user's `enhanced_blood`) is mounted the same
  way from the user's own subscription, never copied (`workshop_mounted_items`); `--console` commands are sent;
  `--camera x,y,z,pitch,yaw,roll[,fov]` pins the view with a client `CalcView` hook; `--hide-hud`
  hides the HUD and view model (client hooks, plus `cl_drawhud 0` / `r_drawviewmodel 0`, which are not
  archived and are set back before quitting) and closes Derma dialogs for 30 s.
  - **`--lua FILE`** (repeatable) runs a client Lua file after the camera, through the console like
    the camera's Lua. Its chunk is `nl_session_lua<n>`, and a first line that prints
    `NL_SESSION_LUA <n>` goes in front. The file is sent again (three tries) until that line has
    printed: Lua sent while the RTX fixes reload models is lost. The record has `lua`: `file` and
    `started` for each.
  - **`--lua-shots SECONDS`**, after `--settle` and before the plain screenshots, lets the Lua pace its
    own screenshots, for a tour of views or settings in one session.
    - Each `NL_SHOT <label>` line it prints (label: up to 48 of `A-Z a-z 0-9 _ . -`) gives one
      screenshot, `shot-<nn>-<label>.png`.
    - The run answers each with the console command `nl_shot_taken <nn>`, so the Lua can go on to
      the next view.
    - It stops at `NL_SHOT_DONE`, when the game exits or after SECONDS. The record has `lua_shots`
      (the screenshots, with `label` and `seconds`) and `lua_shots_done`.

  After `--settle`
  seconds, `--fps SECONDS` times every frame for that long (client Lua through the console, a
  `PostRender` hook, sent once more if its result does not come) and records `fps`: `frames`,
  `seconds`, `fps`, `median_ms`, `p99_ms` and `max_ms`. A game window without focus sleeps between
  frames (`engine_no_focus_sleep`), so a performance run also sends `--console "engine_no_focus_sleep 0"`
  and `--console "fps_max 0"`. Then it saves `--screenshots` PNGs of the client area (`PrintWindow` with `PW_RENDERFULLCONTENT`,
  so the window need not be in front; a screen grab if that comes back black). Capture refuses an
  already hung window and runs in a daemon worker with a 5 s timeout to cover a freeze racing the
  health check. Only the caller saves the returned image, so a timed-out worker cannot write a late
  screenshot. A capture error/timeout uses the same bounded failure cleanup. The run lists the modules,
  sends `quit` and waits for the exit (`--quit-timeout`); if that fails the game and its helpers are
  terminated and the record says so (`normal_quit: false`). Only what this run started is ended: the
  `gmod.exe` it launched (through its own process handle) and every `gmod.exe` from the same install
  whose parent chain leads to it (the game starts its Chromium helpers as children). Parents come from
  a Toolhelp32 snapshot. Every process on the chain must have been created at or after the launch and
  no later than its child, so a recycled PID is never taken for the game's. Each helper's creation
  time is checked again on the handle that terminates it. Other `gmod.exe` processes from the same
  install are left running and listed in the record as `not_ours`; helpers ended after the game
  exited are listed as `terminated_helpers`. It then keeps the session's
  `console.log` text and, unless `--reference`, `loader.log`, `status.json` and `session.json`, and
  the Remix log when this run wrote one; the record names the map, `mat_dxlevel`, the `d3d9.dll` and
  `stdshader_dx6.dll` that were loaded, and the start-up outcome.
  Numeric exits also have `exit_hex`; known exits have `exit_name`: `0x60D0DEAD` is Remix's GPU-crash
  exit (also sets `device_lost`), and `0xCFFFFFFF` means Windows closed a not-responding program.
  Both force `normal_quit: false` and a failed record even if a console quit had been requested.
- `--reference`: for an install that is only read (the classic RTX install): its `console.log` is
  read from where it ended before the launch and never moved, and the loader's files are not looked
  for. The game itself still writes what it always writes (its logs, `config.cfg` when it quits).
- `nlctl <arguments>`: runs `nlctl.exe` of the selected build; `{root}` stands for the game root.
- `uninstall`: [`uninstall-loader.ps1`](uninstall-loader.ps1.md) `-RemoveConfig`, then
  [`steam\verify_install.py`](steam/verify_install.py.md) against the field install's manifests.

The two installer scripts run in Windows PowerShell (`powershell`), always started without
`PSModulePath` in its environment, so it builds its own module path. A `PSModulePath` inherited
from PowerShell 7 (a Python started from `pwsh`) lists PowerShell 7's modules first, and Windows
PowerShell then cannot find `Get-FileHash`, which `install-loader.ps1` needs.

## Side effects

- Writes only to the test install: the bootstrap, `native-loader\`, the files the loader deploys,
  and what the game and Remix write themselves. Nothing is written for client Lua (it goes through
  the console). `config.json` backups go to the evidence folder. An existing `console.log` is moved
  into the step's evidence before a launch, except
  with `--reference` or `--allow-steam-managed` (the user's own installs: read from where it ended,
  never moved; [`field_snapshot.py`](field_snapshot.py.md) puts the field install's back). Steam
  settings and launch options are never touched.
- GMod writes its video settings to `HKCU\Software\Valve\Source\garrysmod\Settings`, which every
  GMod install of the user shares ([RESEARCH.md](../docs/RESEARCH.md) section 11); this script does
  not save or restore them.
- Refuses to launch while a game from the same install runs. Other installs may run. Ends only
  the game it launched and that game's helpers (see `run`).

## Requirements and exit codes

Windows, Python 3.10+, Pillow (screenshots only), a built loader (`tools\build.ps1`). Exit 0 when the
step completes without `failed`, 1 when refused or when the record has `failed` (including device loss,
a persistent hang, capture failure, or either named crash exit). Other non-normal quits still require
reading `normal_quit` in the record; [`qa/release_qa.py`](qa/release_qa.py.md) rejects them.

Tests: [tests/test_poc_session.py](tests/test_poc_session.py.md) (no game is started).
