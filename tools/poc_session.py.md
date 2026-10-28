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
python tools\poc_session.py --root H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c --evidence $e run --name ref --reference --addons
```

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
  (each repeatable), `--remix on|off` and `--require-insecure yes|no`. An existing `config.json` is
  never replaced silently. If its bytes differ from what this install would write, the step is
  refused before the installer runs, and nothing changes. With `--replace-config` the old file is
  first saved as `<evidence>\config.json.before-<UTC time>` and the copy checked. The evidence folder
  is used, not the config's own folder, because `uninstall -RemoveConfig` deletes `native-loader\`
  with everything in it. The step's record then has `config_backup` with the copy's `path` and
  `sha256`. A config that changes while the installer runs is kept, and the step fails.
- `config`: rewrites `config.json` the same way, between runs (no check: replacing it is its job).
- `run --name <step>`: launches `bin\win64\gmod.exe` from the game root with
  `-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons`
  (`--workshop`, `--addons` leave the last two out), `--extra` arguments, `+maxplayers 1`
  (`--players`), `+mat_dxlevel` (prints the level), `+map gm_construct` (`--map`) and `--post`
  arguments. It waits for `Clientside Lua startup!` in `console.log` (`--timeout`, 300 s), then:
  `--load-save <name>` sends `gm_load` and waits for the next map (`save_command` and `save_loaded`
  in the record: `gm_load` prints nothing when the save's map is missing); with
  `--mount-workshop <id>` it first mounts that installed Workshop item from client Lua
  (`steamworks.DownloadUGC`, then `game.MountGMA`, as GMod does for a Workshop save), so a save whose
  map is a Workshop item loads in a session started with `-noworkshop`; `--console` commands are sent;
  `--camera x,y,z,pitch,yaw,roll[,fov]` pins the view with a client `CalcView` hook; `--hide-hud`
  hides the HUD and view model (client hooks, plus `cl_drawhud 0` / `r_drawviewmodel 0`, which are not
  archived and are set back before quitting) and closes Derma dialogs for 30 s. After `--settle`
  seconds it saves `--screenshots` PNGs of the client area (`PrintWindow` with `PW_RENDERFULLCONTENT`,
  so the window need not be in front; a screen grab if that comes back black), lists the modules,
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
step completed (a run whose game failed still completes: read its record), 1 when it was refused.

Tests: [tests/test_poc_session.py](tests/test_poc_session.py.md) (no game is started).
