# release_qa.py

One command for the release QA protocol in [docs/TESTING.md](../../docs/TESTING.md) ("Release QA
protocol"): runs the scripted sessions one after another through
[`poc_session.py`](../poc_session.py.md), checks each against the pass rules, and writes one summary. It
launches the game only through `poc_session.py run` and installs nothing: put the loader (and, on the
PoC, the package to test) in place first.

```powershell
# The user's own install, with the user's own launch options:
python tools\qa\release_qa.py --field --root H:\SteamLibrary\steamapps\common\GarrysMod --evidence out\qa-field\release --extra=-insecure --extra=-tickrate --extra=120
# The PoC, after `poc_session.py install --allow-local <package .gma>` (the package before its publish):
python tools\qa\release_qa.py --root H:\SteamLibrary\steamapps\common\GarrysMod_PoC --evidence out\qa-poc\round --extra=-insecure
# Check recorded runs again without launching anything:
python tools\qa\release_qa.py --root <install> --evidence <folder> --evaluate-only
```

| Option | Meaning |
|---|---|
| `--root` | The game install |
| `--evidence` | `poc_session.py`'s evidence folder; each session goes into `<nn>-<session>\`, numbered after the folders already there |
| `--field` | The user's Steam-managed install: `--allow-steam-managed`, Workshop add-ons mounted (`--workshop`), the game's own window settings (`--no-window`), the main menu screenshot in the first session. Without it (the PoC): no Workshop mount, the modern_house map mounted from the user's subscription alone (`--mount-workshop 3495468649 --change-map modern_house`), and `mat_queue_mode 2` as the field has it |
| `--only` | Sessions to run, comma-separated, in order (default all: `session,spawnmenu,map-glass,spawned-glass`) |
| `--extra` | A launch option for every session (repeatable), e.g. the user's own `-insecure -tickrate 120` |
| `--timeout` | Seconds one session may take (default 1200) |
| `--evaluate-only` | Launch nothing: check the latest recorded run of each session |

## Sessions and pass rules

| Session | Probe | Map | Passes when |
|---|---|---|---|
| `session` | [`rtx_session_probe.lua`](rtx_session_probe.lua.md) | gm_construct | guard installed with no errors, before and after the toolgun; the toolgun is selected and its screen redraw draws with no error |
| `spawnmenu` | [`spawnmenu_probe.lua`](spawnmenu_probe.lua.md) | gm_construct | the creation tabs are listed and none is missing |
| `map-glass` | [`map_glass_probe.lua`](map_glass_probe.lua.md) | modern_house | a glass pane is found and breaks into shards; the probe reaches its end |
| `spawned-glass` | [`spawned_glass_probe.lua`](spawned_glass_probe.lua.md) | gm_construct | the spawned pane breaks into more shards than it had |

Every session must also have loaded its map, quit normally, logged no Lua error, run RTX (`active`),
recorded no status error and finished its probe (`NL_SHOT_DONE`). A session that crashed fails with
the minidumps `poc_session.py` kept (`crash-reports\`), and new Remix crash reports under
`rtx-remix\logs\.sentry-native` during the run fail the summary too.

`device_lost` or a recorded `hung_seconds` fails even if a record claims a normal quit. The summary
line and `qa-summary.json`'s `problems` explicitly say `GPU device lost` or `game window hung for N s`;
each session also retains `device_lost`, `hung_seconds`, `exit`, `exit_hex` and `exit_name` from the
harness. Known exits name Remix's GPU crash (`0x60D0DEAD`) and Windows closing a not-responding program
(`0xCFFFFFFF`). The harness gives window stalls (map loads, model reloads) a 120 s grace and failures a 60 s exit wait,
then stops only its own classified processes while preserving the evidence.

Around the sessions it records the SHA-256 of `user.conf`, `rtx.conf`, the loader's `winmm.dll`,
`winmm.pdb`, `native-loader\config.json` and `bootstrap-install.json`, and of
`reg export HKCU\Software\Valve\Source\garrysmod` (kept as `before-registry.reg` / `after-registry.reg`).
Any change fails the summary. The game itself writes `garrysmod\cfg\config.cfg` and `client.vdf` (the
client convars add-ons archive) at a normal quit, so those two are copied before and after
(`before-config.cfg`, `after-client.vdf`, ...) and compared value by value (`settings` in the summary:
`changed`, `added`, `removed`); numbers compare as numbers, since a slider writes a convar back in the
engine's `%f` form (`0.00` becoming `0.000000` is no change, R5). A new key, such as an add-on version's new convar, is only reported.
A changed or removed value fails in `client.vdf`, and in `config.cfg` for `mat_queue_mode`, which a session
switches off for a moment and must put back (R4-28).
Crash prompts throughout each run are declined by `poc_session.py`'s background watchdog (never
accepted); live crash dumps are copied before those answers can remove them.

**Writes:** the evidence folder (sessions, `qa-summary.json`, the copies above). **Changes in the game
install:** only what the game itself does in a session (its logs, `config.cfg`).
**Exit codes:** 0 when every session passed and nothing watched changed; 1 otherwise; 2 on bad
arguments.

Tests: [`tests/test_release_qa.py`](../tests/test_release_qa.py.md).
