# spawned_glass_probe.lua

Client Lua for `poc_session.py run --console "sv_cheats 1" --lua tools\qa\spawned_glass_probe.lua
--lua-shots 120` (any map): spawns the procedural glass add-on's own pane (`gm_spawnsent
procedural_shard_4`), aims at it and shoots it with the 357. It isolates the add-on's drawing from the
map-glass handler: in review R4 the pane alone crashed RTX sessions with `mat_queue_mode 2` until shards
drew their own mesh. Prints `NL_GLASS` lines (spawned count, shards after the shot) and takes
screenshots before and after. Side effects: that session's map state only. Exit codes: none.
