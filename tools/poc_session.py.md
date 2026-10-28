# poc_session.py

Drives Garry's Mod sessions on a test install (default: the PoC) for acceptance tests, with nobody
at the keyboard: installs the bootstrap and a `config.json`, launches the game, waits for the map,
takes screenshots of the game window, records the loaded modules, ends the game with a normal
`quit`, collects the logs, and uninstalls again. Each step appends a record to
`<evidence>\session.json` and writes its files to `<evidence>\<step name>\`.

```powershell
$e = 'out\poc-sessions\example'
python tools\poc_session.py --evidence $e install --allow-local out\packages\runtime-a.gma --remix on
python tools\poc_session.py --evidence $e run --name 01-rtx-on --settle 30 --screenshots 2
python tools\poc_session.py --evidence $e config --allow-local out\packages\runtime-b.gma
python tools\poc_session.py --evidence $e run --name 02-b
python tools\poc_session.py --evidence $e nlctl rollback {root}
python tools\poc_session.py --evidence $e config --allow-local out\packages\runtime-b.gma --remix off
python tools\poc_session.py --evidence $e run --name 03-off
python tools\poc_session.py --evidence $e uninstall
```

## Steps

- `install`: runs [`install-loader.ps1`](install-loader.ps1.md) for `--config` (Release by default)
  and writes `native-loader\config.json` from `--allow-local`, `--allow-dev`, `--allow-workshop`
  (each repeatable), `--remix on|off` and `--require-insecure yes|no`.
- `config`: rewrites `config.json` the same way, between runs.
- `run --name <step>`: launches `bin\win64\gmod.exe` from the game root with
  `-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons`, a local-only
  remote console (`-usercon -ip 127.0.0.1 -port 27199` and a random `rcon_password`), `--extra`
  arguments, `+mat_dxlevel` (prints the level), `+map gm_construct` (`--map`) and `--post` arguments.
  It waits for `Clientside Lua startup!` in `console.log` (`--timeout`, 300 s), waits `--settle`
  seconds, saves `--screenshots` PNGs of the client area (`PrintWindow` with
  `PW_RENDERFULLCONTENT`, so the window need not be in front; a screen grab if that comes back
  black), lists the game's modules, then sends `quit` through the remote console and waits for the
  exit (`--quit-timeout`). If the remote console fails, the game and its helpers are terminated and
  the record says so (`normal_quit: false`). It then copies `console.log`, `loader.log`,
  `status.json` and the Remix log (when this run wrote one) and records the map, `mat_dxlevel`, the
  `d3d9.dll` and `stdshader_dx6.dll` that were loaded, and the start-up outcome.
- `nlctl <arguments>`: runs `nlctl.exe` of the selected build; `{root}` stands for the game root.
- `uninstall`: [`uninstall-loader.ps1`](uninstall-loader.ps1.md) `-RemoveConfig`, then
  [`steam\verify_install.py`](steam/verify_install.py.md) against the field install's manifests.

## Side effects

- Writes only to the test install: the bootstrap, `native-loader\`, the files the loader deploys,
  and what the game and Remix write themselves. An existing `console.log` is moved into the step's
  evidence before a launch. Steam settings and launch options are never touched.
- GMod writes its video settings to `HKCU\Software\Valve\Source\garrysmod\Settings`, which every
  GMod install of the user shares ([RESEARCH.md](../docs/RESEARCH.md) section 11); this script does
  not save or restore them.
- Refuses to launch while a game from the same install runs. Other installs may run.

## Requirements and exit codes

Windows, Python 3.10+, Pillow (screenshots only), a built loader (`tools\build.ps1`). Exit 0 when the
step completed (a run whose game failed still completes: read its record), 1 when it was refused.
