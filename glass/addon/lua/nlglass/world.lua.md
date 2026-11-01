# world.lua

Client helper included by `debris.lua`; returns a world-state controller. `Begin(budget, gravity)`
requires `nlglass`, reads only `maps/<map>.bsp` from `GAME` after a 256 MiB size check, and passes its
bytes to the module. Thus mounted Workshop maps use the game's normal virtual filesystem.
`Tick()` imports two unique prop collision models or 64 instances per frame through a coroutine.
Temporary `ClientsideModel` objects use `PhysicsInit`/`GetMeshConvexes` and are always removed.
No collision, over-complex or native-refused model collision is skipped and counted. Individual
refused convexes/instances never disable the world; structural BSP failures or no usable collision
at finish select fallback. `Must`, `Fail` and `Shutdown` are internal helpers. Failure logs once per map
and releases the native world. No disk writes, network traffic or server code; no process exit code.
