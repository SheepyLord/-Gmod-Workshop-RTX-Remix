# mmd_lazy_probe.lua

R13-A's two-realm probe, injected through the console by [mmd_lazy_session.py](mmd_lazy_session.py.md).
Not an autorun and never installed. It drives the routes a player uses and reports memory:

- `R13A.Phase(name)` / `R13A.ServerCensus(name)`: a `R13_PHASE <name> <UTC> lua_kb=<n> vram=<json>`
  line (the runtime's `RemixResource.GetVramStats`, the main session's `summarize_ram.py` format) and
  `R13A_CENSUS` JSON per realm: saved registrations, how many of their models Source has loaded
  (`util.IsModelLoaded`, which loads nothing), lazy entries, NPC-tab and player-model entries,
  presented characters and `mmdhl.readiness.Describe()` when the hotloader has it.
- `R13A.Watch()`: game-texture GPU memory every 0.5 s; a rise of more than 256 MB is reported as
  `R13A_JUMP` with the last action the driver announced (`R13A.Action`).
- Wraps `game.MountGMA` (both realms) and the server's carrier `util.PrecacheModel` to report each
  mount and precache with its time and action (`R13A_MOUNT`, `R13A_PRECACHE`).
- `R13A.TraceServer()` / `R13A.Trace()`: the lag trigger traced on `SysTime()`, the clock both
  realms of one process share (`R13A_TRACE` lines). The server reports before and after the
  hotloader's `PublishActor`, `SendActorRegistration`, `RegisterActor`, `PublishRig`,
  `SpawnActorNative` and `AttachNative`; the client reports its registration message and the
  `RegisterActor`, `PublishActorEntry` and `UnregisterActor` calls with the game-texture GPU memory,
  and every frame whose game-texture memory moved by more than 64 MB.
- Actions: the NPC tab with the imported characters' category populated, the hotloader window with
  one character previewed, Sandbox's Player Model window, a stock NPC from the NPC tab's own command,
  spawns through the library's `RequestSpawn`, the NPC tab's `gmod_spawnnpc` for a saved entry, a
  player-model choice and respawn, a dupe (duplicator copy and paste), removals, the catalog an
  approval broadcasts, one archive mount, and camera views for screenshots. Spawns are timed until
  the character is presented (`R13A_PRESENTED`, milliseconds).
- `R13A.Entries()` lists the client's saved entries one line each (`R13A_ENTRY`), as the console cuts
  a printed line at about 4 KB.

Changes client camera/HUD hooks, opens and closes menus, and spawns QA entities in the isolated
session. Writes no files. No exit code; failures print `R13A_ERROR`, which the driver records.
