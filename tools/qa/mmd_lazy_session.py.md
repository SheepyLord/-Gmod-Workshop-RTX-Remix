# mmd_lazy_session.py

R13-A's PoC driver ([ADR 0099](../../docs/decisions/0099-saved-characters-load-on-first-use.md)):
memory phases, the lag report's trigger and first spawns on every route, with a copy of the field
character library. The game itself is started and quit by [poc_session.py](../poc_session.py.md);
[mmd_lazy_probe.lua](mmd_lazy_probe.lua.md) runs in both game realms.

```powershell
# Once: a working copy of the main session's read-only field cache (out\r13\field-cache).
robocopy <main>\out\r13\field-cache out\r13-a\library /E /COPY:DAT /DCOPY:T /MT:16
# The current package (the PoC's own Workshop item), the lag trigger's candidate actions:
python tools\qa\mmd_lazy_session.py --out out\r13-a\<run> --library out\r13-a\library --sequence reproduce
# This worktree's hotloader, with R13-C's memory profile stood in for:
python tools\qa\mmd_lazy_session.py --out out\r13-a\<run> --library out\r13-a\library --textures out\r13-a\textures `
    --sequence measure --candidate --status-memory profile=minimum,warm_characters=0
```

- `--library`: a copy inside this worktree's `out`. Before and after each run it is put back to the
  field cache's files (size and modification time decide; a changed or missing file is copied again,
  a file the session added is removed). The field cache itself is only read.
- `--sequence`: `idle` (memory with nothing spawned), `trigger` (screenshots of the NPC tab and the
  Player Model window, then the trigger the reproduction found, split and traced: a plain Combine
  soldier, a character with no saved entry spawned as a citizen, then a saved character spawned as a
  Combine soldier, each a new fit and a new entry), `combine` (stock parts of a first Combine soldier
  one at a time: a Metro Police officer, a citizen with an AR2, a frag grenade, two items, then an
  unarmed Combine soldier), `ammo` (the part that did it, HL2's AR2 alt-fire ammo item, split: the
  `combineball` particle system precache, its model's precache, then the item),
  `reproduce` (each candidate action of the lag
  report with a phase after it, then a map change, a reload of that map and, last, the material
  system's reloads `mat_reloadallmaterials` and `mat_reloadtextures` with `sv_cheats 1`), `measure`
  (idle memory, then first spawns timed on every route: a ready and a cold character from the NPC
  tab, the hotloader's NPC and ragdoll, a player model, a dupe, a save and its load, removal, the
  fixes' manual purge `rtx_flush_textures`, and a map change with an NPC-tab spawn), `integrated`
  (R13's check of one memory profile with the built package: idle memory, the newest and the oldest
  character from the NPC tab, their removal, a plain Combine soldier (the lag report's trigger) with
  phases 30, 90 and 150 seconds after it while the runtime releases idle textures, then the same two
  characters again).
- `--candidate`: at the main menu (the loader has deployed; no game Lua realm exists yet) copies this
  worktree's hotloader files that differ from the deployed ones into the PoC add-on, and puts the
  deployed ones back after the run (hash-checked).
- `--textures`: a folder of the assets' `textures\<sha256>.png`, kept in the copy as well. The main
  session's field cache has none, and the native module reads them to load a character (spawns,
  presentation); copy the ones the manifests name from the field library, read-only.
- `--status-memory`: `key=value,...` (or a JSON object) merged into this session's
  `native-loader/status.json` `activation.memory` before the map, as R13-C's loader writes it.
- `--console`, `--map`, `--idle`, `--width`/`--height` (1920x1080), `--players`, `--workshop`
  (waits for the Workshop mount before the map), `--lock-wait` (minutes, 120), `--extra` (a launch
  option passed to the game, such as `-insecure` for a loader config with
  `patch_sets.require_insecure`; repeatable).

Takes the exclusive `out\r10\poc.lock` (retries every two minutes; never removes another task's
lock), ends a running field game first (WM_CLOSE, then forced after 60 s; `field-games*.json` name the
PIDs), and launches with `-multirun`. The driver needs the library copy in place when it starts, so
queue a second session only after the first one has put it back. Under the lock it swaps the library copy in as
`garrysmod\data\mmd_hotloader`, empties `rtx-remix\mods\~gmod_topbr`, copies the PoC's other data
folders, moves the PoC console log away unread, and samples the game's private bytes and working set
every 2 s (`ram.csv`). Afterwards it restores all of them exactly (changed data files are archived in
`data-after`), moves new saves into `saves-after`, restores `config.cfg` and the shared video registry
values, and releases the lock. A PoC still running keeps the snapshot and the lock for recovery.

GMod keeps `cfg/config.cfg` in Steam Cloud (`Steam\userdata\<account>\4000\remote\cfg`): a game takes
the cloud copy at start and writes its own settings there at its quit, so a PoC session's last
settings reach the user's field game at its next start (runs 08 to 13 left a player model and
`kleiner`; another driver leaves `fps_max 60`). Before the quit the session therefore executes the
field game's own `config.cfg` (read only, from a copy it puts in the PoC's `cfg` folder and removes)
and writes the config, and `settings-before.json` / `settings.json` record the field and cloud
hashes before and after.

Outputs in `--out`: `phases.json` (per phase: game textures, replacement textures, DXVK and driver
bytes, private bytes, working set, both realms' census), `events.json` (spawn times, screenshots,
errors), `entries.json`, `plan.json`, screenshots, `console-after.log` (this session's own log only),
`session.json` and the evidence `poc_session.py` collects. Exit 0 when the sequence completed and the
game quit normally; 3 when the lock stayed busy; otherwise an exception (read the evidence).
