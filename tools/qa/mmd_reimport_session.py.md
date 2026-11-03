# mmd_reimport_session.py

R12-A's isolated PoC delete/reimport probe. Uses the existing `poc_session.py` owner for launch,
health checks, screenshots, normal quit and session-only console collection. Never launches,
focuses, sends input to, reads logs from or changes the field install.

```powershell
python tools/qa/mmd_reimport_session.py --gate
python tools/qa/mmd_reimport_session.py --out out/r12-a/baseline --source out/r12-a/source/endminf/女管理员.pmx
python tools/qa/mmd_reimport_session.py --out out/r12-a/fixed --source out/r12-a/source/endminf/女管理员.pmx --candidate
# Optional cold-registration case: a saved carrier restored at startup, never spawned this session.
python tools/qa/mmd_reimport_session.py --out out/r12-a/seed --source out/r12-a/source/endminf/女管理员.pmx --seed-only
python tools/qa/mmd_reimport_session.py --out out/r12-a/cold --source out/r12-a/source/endminf/女管理员.pmx --seed-cache out/r12-a/seed/data-after/mmd_hotloader --cold
```

Copy the user's source folder into this worktree's `out` first. Evidence must be a new directory
there. Checks the R12 field activity gate (foreground PID and `GetLastInputInfo`) before taking the
exclusive shared `out/r10/poc.lock`, and again immediately before launch. Exit 2 means activity
blocks launch: retry after five minutes while doing other work. Exit 3 means another task holds
the PoC: retry after two minutes. Never removes another task's lock.

Under the lock, temporarily moves the PoC `garrysmod/data` and generated `~gmod_topbr` directory
into evidence, uses empty test directories, then archives generated data and restores the originals.
This also isolates automatic PBR and eye-white caches produced when characters are drawn. Candidate mode
starts at the main menu, backs up five shipped Lua files after loader startup, and stages the
worktree's production files before requesting the first map. Both game Lua realms therefore start
with these files, without auto-refreshing a persistent `SetModel` wrapper. The originals are
hash-verified after restoration; the probe logs the wrapper's source/definition line.
Preserves `config.cfg`, restores the game's shared video registry values, and renames the prior
PoC console without reading it. Screenshots require PrintWindow (no occluded desktop fallback).
The game itself writes its normal
logs and settings. Does not change loader config, Steam files/settings, native binaries or
Remix `user.conf`. Uses `-multirun`; imports from the copied source only.

The sequence covers NPC/player before deletion, identical reimport and ragdoll/NPC/player after,
a changed scale carrier and its own delete/reimport, model-only ragdoll-to-NPC conversion and
old entities across a new fit. JSON events, screenshots, owning-session logs and cache snapshots
go under `--out`. Exit 0 completes; an exception/nonzero exit requires reading evidence. A live PoC
process preserves snapshots and the lock for recovery.

The test session sets `sv_cheats`, `ai_disabled`, `engine_no_focus_sleep` and `fps_max` locally
for deterministic placement and rendering while occluded; its saved config is restored on exit.

`--seed-only` stops after the first imported NPC. `--seed-cache` copies that generated test cache
into the isolated cache after snapshotting; the seed stays unchanged. `--cold` deletes the entry
before the first spawn, so saved menu registrations have mounted its carrier without warming the
server's model lookup. This distinguishes a warm Lua cache masking a missing sidecar from a fresh
session's lookup. Each separate launch still obtains the lock and passes the activity gate.
