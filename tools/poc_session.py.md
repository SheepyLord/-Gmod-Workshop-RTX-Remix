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
section 11). Client Lua (camera, HUD) goes through `lua_run_cl` reading a file the script writes to
`garrysmod\data\nl_session\` and deletes afterwards.

Two things lose console text without a word, and the script works around both. While a map loads,
or the RTX fixes reload models after it, the window does not answer for many seconds, so each send
waits up to 10 s and is tried six times. Text the window accepts during those reloads can also be
dropped, so before a save or the camera the script waits until `console.log` has been quiet for 5 s
(at most 90 s), and it sends the camera Lua again until that Lua prints its `NL_SESSION_EYE` line
(three tries).

## Steps

- `install`: runs [`install-loader.ps1`](install-loader.ps1.md) for `--config` (Release by default)
  and writes `native-loader\config.json` from `--allow-local`, `--allow-dev`, `--allow-workshop`
  (each repeatable), `--remix on|off` and `--require-insecure yes|no`.
- `config`: rewrites `config.json` the same way, between runs.
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
  terminated and the record says so (`normal_quit: false`). It then keeps the session's
  `console.log` text and, unless `--reference`, `loader.log`, `status.json` and `session.json`, and
  the Remix log when this run wrote one; the record names the map, `mat_dxlevel`, the `d3d9.dll` and
  `stdshader_dx6.dll` that were loaded, and the start-up outcome.
- `--reference`: for an install that is only read (the classic RTX install): its `console.log` is
  read from where it ended before the launch and never moved, and the loader's files are not looked
  for. The game itself still writes what it always writes (its logs, `config.cfg` when it quits).
- `nlctl <arguments>`: runs `nlctl.exe` of the selected build; `{root}` stands for the game root.
- `uninstall`: [`uninstall-loader.ps1`](uninstall-loader.ps1.md) `-RemoveConfig`, then
  [`steam\verify_install.py`](steam/verify_install.py.md) against the field install's manifests.

## Side effects

- Writes only to the test install: the bootstrap, `native-loader\`, the files the loader deploys,
  `garrysmod\data\nl_session\` (deleted after each run), and what the game and Remix write
  themselves. An existing `console.log` is moved into the step's evidence before a launch, except
  with `--reference` or `--allow-steam-managed` (the user's own installs: read from where it ended,
  never moved; [`field_snapshot.py`](field_snapshot.py.md) puts the field install's back). Steam
  settings and launch options are never touched.
- GMod writes its video settings to `HKCU\Software\Valve\Source\garrysmod\Settings`, which every
  GMod install of the user shares ([RESEARCH.md](../docs/RESEARCH.md) section 11); this script does
  not save or restore them.
- Refuses to launch while a game from the same install runs. Other installs may run.

## Requirements and exit codes

Windows, Python 3.10+, Pillow (screenshots only), a built loader (`tools\build.ps1`). Exit 0 when the
step completed (a run whose game failed still completes: read its record), 1 when it was refused.
