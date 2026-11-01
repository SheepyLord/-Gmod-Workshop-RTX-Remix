# world.lua

Client helper included by `debris.lua`; returns a world-state controller. `Begin(budget, gravity)`
requires `nlglass`, reads only `maps/<map>.bsp` from `GAME` after a 256 MiB size check, and passes
an owned copy to `BeginLoadMap`. Lua's VFS read and the bounded byte copy remain on the client
thread; BSP parsing and static-world cooking run on a module worker. `Tick` polls without waiting,
then extracts two unique prop collision models or adds 64 instances per frame through a coroutine.
The final broadphase optimization also uses `BeginFinishWorld`/`PollFinishWorld` on a worker.
Temporary `ClientsideModel` objects use `PhysicsInit`/`GetMeshConvexes` and are always removed.
Missing, over-complex or refused models/convexes/instances are skipped and counted. A structural
BSP error or a finished map without any usable collision selects fallback and logs once per map.
`Must`, `Fail`, `Shutdown` are internal helpers; shutdown joins workers before releasing their
world, and resets for the next client realm. No disk writes, network or server code; no exit code.
