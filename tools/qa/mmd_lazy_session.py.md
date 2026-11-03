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
- `--sequence`: `idle` (memory with nothing spawned), `reproduce` (each candidate action of the lag
  report with a phase after it), `measure` (idle memory, then first spawns timed on every route:
  a ready and a cold character from the NPC tab, the hotloader's NPC and ragdoll, a player model, a
  dupe, removal, a map change, a save and its load).
- `--candidate`: at the main menu (the loader has deployed; no game Lua realm exists yet) copies this
  worktree's hotloader files that differ from the deployed ones into the PoC add-on, and puts the
  deployed ones back after the run (hash-checked).
- `--textures`: a folder of the assets' `textures\<sha256>.png`, kept in the copy as well. The main
  session's field cache has none, and the native module reads them to load a character (spawns,
  presentation); copy the ones the manifests name from the field library, read-only.
- `--status-memory`: `key=value,...` (or a JSON object) merged into this session's
  `native-loader/status.json` `activation.memory` before the map, as R13-C's loader writes it.
- `--console`, `--map`, `--idle`, `--width`/`--height` (1920x1080), `--players`, `--workshop`
  (waits for the Workshop mount before the map), `--lock-wait` (minutes, 120).

Takes the exclusive `out\r10\poc.lock` (retries every two minutes; never removes another task's
lock), ends a running field game first (WM_CLOSE, then forced after 60 s; `field-games*.json` name the
PIDs), and launches with `-multirun`. Under the lock it swaps the library copy in as
`garrysmod\data\mmd_hotloader`, empties `rtx-remix\mods\~gmod_topbr`, copies the PoC's other data
folders, moves the PoC console log away unread, and samples the game's private bytes and working set
every 2 s (`ram.csv`). Afterwards it restores all of them exactly (changed data files are archived in
`data-after`), moves new saves into `saves-after`, restores `config.cfg` and the shared video registry
values, and releases the lock. A PoC still running keeps the snapshot and the lock for recovery.

Outputs in `--out`: `phases.json` (per phase: game textures, replacement textures, DXVK and driver
bytes, private bytes, working set, both realms' census), `events.json` (spawn times, screenshots,
errors), `entries.json`, `plan.json`, screenshots, `console-after.log` (this session's own log only),
`session.json` and the evidence `poc_session.py` collects. Exit 0 when the sequence completed and the
game quit normally; 3 when the lock stayed busy; otherwise an exception (read the evidence).
