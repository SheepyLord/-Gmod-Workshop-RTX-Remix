# R13-A: saved characters load on first use (report)

Branch `r13-hotloader`, from `r13-int` `70acb49`. Implementer: Claude (subagent). The brief is
R13-A in the [R13 plan](R13-plan.md); the decision is
[ADR 0099](../decisions/0099-saved-characters-load-on-first-use.md). No push, merge or publication.
Times are UTC on 2026-11-03. Evidence is in the worktree's `out\r13-a\` (run folders named below).

## Summary

- **The lag trigger is the first Combine soldier of a session.** Spawning one (the NPC tab's stock
  `npc_combine_s`, or a character spawned as a Combine soldier from the hotloader) made every texture
  Source had loaded GPU-resident within one frame: game textures 0.29 → 17.07 GB and private bytes
  26.96 → 43.31 GB on the copied field library (`19-baseline-trigger`). The part that does it is
  the AR2 alt-fire ammo item the soldier precaches (`item_ammo_ar2_altfire`; spawning that item alone
  does the same, `21-baseline-combine-parts`). The current package had every
  saved character's textures loaded, because each map precached all of them. The field's file writes
  before its jump (`names/assets` twice, then `approved.json`) match a hotloader spawn as a Combine
  soldier, which reproduced the jump (`09-baseline-reproduce`).
- The engine-side step that touches every loaded texture is outside R13-A's paths (no packaged Lua
  reacts to a Combine soldier; see below). R13-A removes what it multiplied: characters that are not
  used are no longer loaded, so the same Combine soldier made 5.0 GB resident with this computer's
  "high" ready set of 10 characters (`20-candidate-high-trigger`) and 1.85 GB with the recommended
  5 (`13-candidate-rec-reproduce`), instead of 16.8 GB.
- **Saved characters load on first use; the most recently used stay ready** (ADR 0099). Idle with
  nothing spawned, on this computer's high profile (10 characters ready): private bytes
  27.03 → 14.97 GB, working set 20.87 → 9.09 GB. On the minimum profile (none ready): 9.56 GB and
  3.53 GB.
- Every route works: the NPC tab (ready and cold), the hotloader's NPC, ragdoll and player model, the
  Player Model window, a dupe, a save and its load, removal, a map change with a new spawn, and a
  listen server; no error models, no Lua errors, no "missing model".
- First spawns of a character that is not ready take what its precache costs: up to about 0.6 s for
  most characters, about 0.9-1.9 s for the largest (阮·梅 R18: 4.0 s ready, 4.9-6.0 s cold, both
  including its presentation).
- **A PoC session changes the user's game settings through Steam Cloud** (found while explaining a
  player model that survived the `config.cfg` restore). The driver now ends every session with the
  field game's own settings; the cloud copy matches the field's `config.cfg` again (`settings.json`).

## The trigger

### How it was found

`tools\qa\mmd_lazy_session.py --sequence reproduce` replays the lag report's candidates one at a time
on the current package (the PoC's Workshop item `6bb413bf`), with the copied field library (57
characters, 98 saved NPC and player rigs) and a phase after each. The probe reports any rise of game
textures (`usedAppTextureBytes`) of more than 256 MB, with the action that preceded it.

| Action (current package) | Game textures after | Run |
|---|---:|---|
| idle: every saved character precached at map start | 0.29 GB | 09 |
| the catalog an approval broadcasts | 0.29 GB | 09 |
| the hotloader window with a character previewed | 0.29 GB | 09 |
| the NPC tab with the 71 imported entries | 0.30 GB | 09 |
| the Player Model window (7 imported player models) | 0.30 GB | 09 |
| a saved character from the NPC tab | 0.44 GB | 09 |
| a saved player model | 1.22 GB | 09 |
| a manhack, left to attack for 25 s | 1.22 GB | 09 |
| an unregistered character's archive mounted, then that character as a ragdoll | 1.54 GB | 09 |
| **a saved character spawned as a Combine soldier from the hotloader** | **17.12 GB** | 09 |
| a map change, a reload of that map (fresh session state each) | 0.27 GB | 09 |
| `mat_reloadallmaterials`, then `mat_reloadtextures` | 0.23-0.24 GB | 09 |

The rise came in one sample after the Combine spawn; private bytes rose 29.08 → 44.64 GB at the same
time (`ram.csv`). `--sequence trigger` then split the step, with every frame's game-texture memory
and the hotloader's publication, registration and spawn calls traced on `SysTime()` (one clock for
both realms):

| Step (current package, `19-baseline-trigger`) | Game textures | Private bytes |
|---|---:|---:|
| idle | 0.29 GB | 26.96 GB |
| **a stock Combine soldier from the NPC tab** (`gmod_spawnnpc npc_combine_s`, no hotloader code) | **17.07 GB** | **43.31 GB** |
| then a character with no saved entry spawned as a citizen (new fit, new entry) | 17.09 GB | 43.99 GB |
| then a saved character spawned as a Combine soldier | 17.10 GB | 44.09 GB |

The rise happened between two frames (frame 7565, 1.4 s after the spawn command) with no hotloader
call in between: the trace's server wrappers (`PublishActor`, `RegisterActor`, `PublishRig`,
`SendActorRegistration`, `SpawnActorNative`, `AttachNative`) report nothing until the next step.
A hotloader spawn as a Combine soldier creates an `npc_combine_s`, which is why run 09's new fit
triggered it; the hotloader spawns before it in run 09 (a citizen from the NPC tab, a player model, a
ragdoll that made a new fit) did not.

### What it touches, and what R13-A changes

The step makes **every texture Source has loaded** resident, not just the soldier's: the jump equals
the textures of every precached character. With R13-A only the ready set and the characters used
this session are loaded, so the same step costs what they hold:

| Build (memory profile) | Loaded saved entries before | Game textures before → after | Private bytes before → after | Run |
|---|---:|---:|---:|---|
| current package | 98/98 | 0.29 → 17.07 GB | 26.96 → 43.31 GB | 19 |
| R13-A, high (10 characters, 6,311 MiB) | 12/98 | 0.30 → 5.32 GB | 15.13 → 19.94 GB | 20 |
| R13-A, recommended (5 characters, 3,260 MiB; hotloader Combine spawn) | 9/99 | 1.54 → 3.39 GB | 15.10 → 17.15 GB | 13 |

Which part of the soldier does it (`--sequence combine`, stock entities one at a time on the
current package, `21-baseline-combine-parts`):

| Spawned (in this order) | Game textures after | Private bytes after |
|---|---:|---:|
| idle | 0.29 GB | 26.95 GB |
| a Metro Police officer (`npc_metropolice`, unarmed) | 0.29 GB | 26.95 GB |
| a citizen with an AR2 (`weapon_ar2`) | 0.29 GB | 26.96 GB |
| a frag grenade (`weapon_frag`) | 0.29 GB | 27.10 GB |
| a health vial (`item_healthvial`) | 0.29 GB | 26.89 GB |
| **the AR2's alt-fire ammo (`item_ammo_ar2_altfire`)** | **17.07 GB** | **43.44 GB** |
| an unarmed Combine soldier | 17.07 GB | 43.45 GB |

Every `npc_combine_s` precaches `item_ammo_ar2_altfire` (with `item_healthvial` and `weapon_frag`).
Spawning that item alone does it within two seconds, and run 19's soldier, which never dropped one,
shows that its precache is enough. The item's precache loads its model
(`models/items/combine_rifle_ammo01.mdl`) and, as recalled from the Source SDK 2013 code (not checked
here), the `combineball` particle system. `--sequence ammo` splits the two; it was not run, because
R13-B held the PoC for its own runs after run 21. No packaged Lua names these entities or reacts to
them (searched: the fixes' `remixbinary` Lua, the companion, BBS, the glass, water and material
editor add-ons), and the trace shows no Lua call at the jump. The step is in the engine or the
runtime, outside R13-A's paths, and is described here for R13-B and the main session:

- **What to fix there:** whatever, on the first precache of the AR2 alt-fire ammo (a first Combine
  soldier), binds or uploads every loaded texture. Patch 0022 creates a managed texture's GPU image
  on its first sampling, upload or `PreLoad`, so one pass that touches every loaded texture creates
  all their images at once, and nothing evicts them.
- **Until then** the ready set's archives (`warm_mib`) bound what one Combine soldier can make
  resident, plus whatever the session already used. R13-B's managed-texture budget releases them
  when idle.

### The field's lag, read again

The field's writes before its jump were `names/assets` at 02:41:07 and 02:41:10, then `approved.json`
at 02:41:16. A hotloader spawn that makes and publishes a new fit writes that: the server's
and the client's asset load (`registerShortName` rewrites `names/assets/<id>.json`), then
`PublishRig`; in run 09 the Combine new fit rewrote that character's `names/assets` file and
`approved.json`. The field's jump (14.35 GB within 30 s, 09:41:12-09:41:44) is consistent with a
Combine soldier spawned in that minute. The manhack the user remembered did not trigger it on its own
in runs 08, 09 and 13.

## What changed

All in `packages/model-hotloader` (Lua; files and index through `tools\inputs.py import`), with
LuaJIT tests and QA tools:

- `lua/mmdhl/actors.lua`
  - `mmdhl.ActorMetadataReady` and `mmdhl.PublishActorEntry`: an NPC-tab or player-model entry from
    validated metadata (a loadable rig whose identity matches its model, its carrier and arms carrier
    and its material archive on disk), marked `lazy`; nothing mounted or loaded.
  - `mmdhl.PrepareRegisteredActor(model)`: the ADR 0090 gate (mount, precache, `IsValidModel`) right
    before a lazy entry's first real use.
  - Clients in the server's process (single player, a listen host) publish host entries from metadata
    (`mmdhl.HostsServer`); a remote client still mounts at registration.
  - The readiness module (`mmdhl.readiness`): the budget from `status.json`, the use record, the ready
    set at map start (`mmdhl.RestoreActors`), the menu icons, and `Describe()` for QA.
  - Use is recorded on every spawn, NPC-tab spawn, player model and restored or pasted entity.
- `lua/mmdhl/persistence.lua`: the `Entity:SetModel` wrapper prepares a lazy entry first (every route:
  NPC tab, player model, saves, dupes, tools); on the server `util.PrecacheModel` and
  `util.IsValidModel` of a carrier path mount it first (Sandbox's player class precaches before
  `SetModel`).
- `lua/mmdhl/sharing.lua`: the map-start restore hands its entries to `mmdhl.RestoreActors`.
- `lua/autorun/mmdhl.lua`: `MountPackage` reuses a carrier the other realm of the process already
  mounted (the exact model is visible) instead of mounting it again, in both realms.
- Client `ClientsideModel`, `ClientsideRagdoll` and `ents.CreateClientProp` of a carrier mount it
  first (model previews). `SpawnIcon` of a carrier (the Player Model window, spawnlists, model
  pickers) shows its real cached image if one exists, otherwise its name, and never loads the model
  (`out\r13-a\20-candidate-high-trigger\menu-player-models.png`; the NPC tab's entries carry no model
  image: `menu-npc-tab.png`). Opening both loaded nothing (12/98 before and after).

### The contract

| What | Where | Meaning |
|---|---|---|
| Characters kept ready | `garrysmod/data/native-loader/status.json` → `activation.memory.warm_characters` | the most recently used this many characters are mounted and precached at map start |
| Their archives, at most | `activation.memory.warm_mib` | MiB of material archives the ready set may hold; a character too large for what is left is passed over for an older one that fits |
| No file, no `activation.memory`, or a field missing | | none kept ready |
| ConVar `mmdhl_warm_characters` | server, default -1 (automatic) | overrides the count, 0-256, applies at once (tests) |
| ConVar `mmdhl_warm_mib` | server, default -1 (automatic) | overrides the MiB cap, applies at once (tests) |
| Use record | `garrysmod/data/mmd_hotloader/recent.json` | `{version=1, uses={{asset, unix time}, ...}}`, newest 512; before it existed, the time the native module last prepared a carrier (`names/rigs/<key>.json`) |

R13-C's loader 0.13.0 writes the two fields (high: 10 and RAM/10; recommended: 5 and RAM/10;
minimum: 0 and 0). The PoC runs an older loader, so the driver writes them into the session's
`status.json` (`--status-memory`); this computer is a high one (32 GB VRAM, 63,116 MiB RAM: 10
characters, 6,311 MiB).

## Measurements

PoC, 1920x1080, the copied field library, no Workshop add-ons; the current package (`6bb413bf`,
the Workshop item) against this branch's hotloader Lua staged into the same deployment.

### Memory

| Build | Phase | Private | Working set | Game textures | Loaded saved entries | Run |
|---|---|---:|---:|---:|---:|---|
| current | idle | 27.03 GB | 20.87 GB | 0.39 GB | 98/98 | 12 |
| R13-A high | idle | 14.97 GB | 9.09 GB | 0.29 GB | 12/98 (10 characters, 4.8 GiB) | 16 |
| R13-A recommended | idle | 11.98 GB | 5.84 GB | 0.39 GB | 7/98 | 11 |
| R13-A minimum | idle | 9.56 GB | 3.53 GB | 0.29 GB | 0/98 | 17 |
| current | after the routes below | 29.93 GB | 21.50 GB | 2.61 GB | 99/99 | 12 |
| R13-A high | after the routes below | 19.49 GB | 11.04 GB | 2.61 GB | 15/99 | 16 |
| R13-A high, listen server | idle | 15.20 GB | 9.02 GB | 0.29 GB | 12/98 | 18 |
| R13-A minimum | after the routes below | 15.61 GB | 7.26 GB | 2.61 GB | 4/99 | 17 |
| current | next map, idle | 24.83 GB | 20.66 GB | 0.27 GB | 99/99 | 12 |
| R13-A high | next map, idle | 12.15 GB | 7.99 GB | 0.27 GB | 16/99 | 16 |
| R13-A minimum | next map, idle | 10.44 GB | 6.34 GB | 0.27 GB | 0/99 | 17 |

Runs 10 and 11 staged a few non-Lua package files by mistake (fixed in the driver before run 12;
the hotloader then printed a runtime-DLL check warning and carried on). Their idle and spawn numbers
agree with the later runs; they are kept as supporting evidence only.

### First spawns (until the character is presented)

| Route | Current | R13-A high | R13-A recommended | R13-A minimum |
|---|---:|---:|---:|---:|
| NPC tab, the newest character (阮·梅 R18; ready except on the minimum) | 4,039 ms | 3,989 ms | 3,865 ms | 4,925 ms |
| NPC tab, a character not ready (真珠) | 528 ms | 614 ms | 509 ms | 519 ms |
| hotloader menu, NPC (Evanescia) | 1,071 ms | 1,155 ms | 1,115 ms | 1,145 ms |
| hotloader menu, ragdoll (大国主 R18) | 3,059 ms | 3,524 ms | 3,497 ms | 3,515 ms |
| player model (三月七) | 1,108 ms | 1,671 ms | 1,092 ms | 1,661 ms |
| NPC tab after a map change (昔涟) | 900 ms | 983 ms | | 1,037 ms |

In the current package every character was precached at map start, so these are presentation times;
R13-A adds the precache of a character that is not ready. The largest (阮·梅 R18) costs 0.9 s on the
minimum profile (run 17; 1.9 s in run 10, whose precache alone took 1,979 ms); most cost up to
0.6 s. Runs differ by a few hundred milliseconds on the same route (the recommended column is run 11,
which stopped at the save step).

### Routes

All with the character attached, its own model valid and no `models/error.mdl`
(`routes.py`: `ENTITY ... attached=True error_model=False valid=True`), 0 Lua errors:

- NPC tab: a ready and a cold character; after a map change, a cold one (runs 12, 16, 17).
- Hotloader menu: an NPC, a ragdoll, a player model; spawns as a citizen and as a Combine soldier
  that make a new fit and a new entry (runs 16, 17, 20).
- Player model chosen in the Player Model window's way (`cl_playermodel` and a respawn): the base
  class's `util.PrecacheModel` mounts the carrier before `SetModel` (runs 12, 16, 17).
- A dupe of an NPC; a save with 7 characters and its load on the same map (restored in place):
  7 of 7 attached again (runs 12, 16, 17).
- Removal, the fixes' `rtx_flush_textures`, then a map change and a new NPC-tab spawn (runs 12, 16,
  17).
- A listen server (`--players 2`: "mode MP, dedicated No", "Players: 1 / 2"), the high profile: every
  route above with the same outcome, idle private 15.20 GB and working set 9.02 GB, first spawns
  within about 0.1 s of single player's (run 18).
- A player on another server still downloads and mounts at registration (unchanged path; the LuaJIT
  `client_remote` case). A second computer was not available.
- Deleting a character (R12-A) forgets its use record and leaves its entries out (LuaJIT
  `server_forget`); a delete and re-import was not replayed on the PoC. R12-D's eye-white choices
  are untouched: the companion's module is unchanged, and it made eye-white proxies for the presented
  characters in every run (`data-after\nativeloader\eye_whites`).
- Importing a new character was not replayed: the trigger was found without it.

### After removal

Source keeps a used character's model, materials and textures until the map changes: GMod cannot
unprecache a model, and the model's materials keep their textures. Removing the five characters of
the routes above freed nothing in any build (game textures stay 2.61 GB). The fixes'
`rtx_flush_textures` (`UncacheAllMaterials`, then a renderer purge) is the only earlier release:

| Build | Removed: private / game textures | After `rtx_flush_textures` | Run |
|---|---:|---:|---|
| current | 30.53 / 2.61 GB | 10.53 / 0.32 GB | 12 |
| R13-A high | 19.74 / 2.61 GB | 14.79 / 2.61 GB | 16 |
| R13-A high, listen server | 19.68 / 2.62 GB | 14.38 / 2.61 GB | 18 |
| R13-A minimum | 16.55 / 2.61 GB | 13.33 / 2.61 GB | 17 |

With R13-A the purge released CPU copies but not the 2.3 GB of GPU images of the removed characters,
which stayed until the map changed (the fixes' map-exit line still reported 2,489.6 MiB). What holds
them was not identified: the same characters, the same purge and the same five presented assets in
the hotloader's client cache, and no texture reference in R13-A's Lua; the visible difference is
that R13-A precached them mid-map at first use instead of at map start. R13-B's managed-texture
budget releases idle GPU images either way, and the next map loads none of these characters unless
they are in the ready set (`map2-idle` 0.27 GB of game textures in every build).

## Steam Cloud carries a PoC session's settings to the field

GMod keeps `cfg/config.cfg` in Steam Cloud (`C:\Program Files (x86)\Steam\userdata\322575385\4000\remote\cfg\config.cfg`).
A game takes the cloud copy at start (it rewrote the PoC's local `config.cfg` within seconds of the
launch, run 13) and writes its own settings back at its quit. So the driver's restore of the PoC's
local `config.cfg` never reached the cloud: a player model chosen in run 08 was the player's model at
the start of runs 10 and 11, and after run 12 the cloud held `cl_playermodel "kleiner"` and
`fps_max "60"` (another driver, `mmd_reimport_session.py`, sends `fps_max 60`), where the field's own
`config.cfg` (03:02:48) has `"Bai Mei"` and `300`. The field game would have taken those at its next
start.

`mmd_lazy_session.py` now executes the field game's `config.cfg` (read only, from a copy it puts in
the PoC's `cfg` folder and removes) and writes the config before the quit. After run 09 the cloud
copy is byte-identical to the field's (`0ebf6a15...`, `09-baseline-reproduce\settings.json`), and
each later run records the same. Other drivers that quit the PoC still write their own settings to
the cloud: the main session should decide whether `poc_session.py` does the same for everyone.

## PoC use and the field game

- Lock holds (`out\r10\poc.lock`, task R13-A): 10:40-10:42, 10:45-10:48, 10:49 (crash), 10:49-10:52,
  10:53-11:03 (run 05, released after a manual restore), 11:03 (crash), 11:04-11:11, 11:12-11:25,
  11:57-12:11, 12:11-12:26, 12:26-12:34, 12:34-12:44, 12:44-12:55, 12:55-13:03, 13:03-13:07,
  13:07-13:11, 13:11-13:18, 13:18-13:26, 13:26-13:31. Each restored the PoC's data, saves, spawn
  icons, ToPBR output, `config.cfg` and video registry values, and repaired the library copy.
- No field game was running at any launch: no PID was ended (`field-games*.json`).
- The loader had moved the PoC's deployment to the current Workshop package by itself before these
  runs; it was left as it was. Two launches (03 and 06) crashed at the main menu in the NVIDIA driver
  (`nvoglv64.dll+0xe622f8`) right after another game's exit; a 45 s pause before launching avoided it.

## Tests

- `tools\tests\test_mmd_lazy_load.py` (LuaJIT, the packaged Lua): no profile, a profile's count and
  MiB cap, the ConVar override, first use through `SetModel`, `util.PrecacheModel` and
  `util.IsValidModel`, the use record and its fallback, a map change, deletion, host clients, menu
  icons, a remote client. The existing morph and reimport harnesses got stubs for the new ConVars.
- `tools\test.ps1 -Config Release` passes in this worktree: CTest 26 of 26, the Python suite's 532
  tests and the repository checks ("All checks passed"; `out\r13-a\test-release.log`).

## Open items and decisions for the main session

- The engine/runtime step behind the Combine trigger (above): R13-B or a follow-up. A cheap check
  is `PrecacheParticleSystem("combineball")` and the ammo model's precache on their own
  (`--sequence ammo`).
- ADR 0090's status line should say "superseded in part by 0099" (outside R13-A's paths).
- Steam Cloud and the PoC: make every PoC driver end with the field's settings (`poc_session.py`), and
  check the cloud copy before the user's next start.
- The ready set on a high computer is 10 characters (up to 6.3 GB of archives): one Combine soldier
  makes all of it resident until R13-B's budget releases it. Lower `warm_characters` if the trigger
  stays.
- With R13-A, `rtx_flush_textures` no longer releases removed characters' GPU images before the map
  changes (above); the holder was not identified.
- Not tested: a second player on another computer, and a session with the Workshop add-ons mounted
  (the field's other add-ons; the trigger reproduced without them).
