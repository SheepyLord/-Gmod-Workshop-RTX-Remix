# mmd_lazy_load_harness.lua

LuaJIT harness for R13-A's load-on-first-use regression, invoked by
[test_mmd_lazy_load.py](test_mmd_lazy_load.py.md). Arguments: the generated production snippet, the
packaged `lua/mmdhl` folder, and one scenario: `server_none`, `server_budget`, `server_convar`,
`server_first_use`, `server_fallback`, `server_map_change`, `server_forget`, `client_host` or
`client_remote`.

The fixture library has four characters (archives of 500, 700, 4000 and 300 MiB), one with a player
model and its arms, saved approvals and a use record. Disk reads and writes, `game.MountGMA`,
`util.PrecacheModel` (which refuses a model that is not mounted), list and player-model entries,
network messages, ConVars, timers and entities are instrumented; binding (native attachment and
appearance) is reduced to its boundary, as in the R12-A harness. `server_map_change` reloads the four
files with the engine's own `SetModel`/`PrecacheModel`/`IsValidModel`, as a new map's Lua state has
them. Writes stdout only. Exit 0 with `PASS <scenario>`, otherwise nonzero with the failed assertion.
