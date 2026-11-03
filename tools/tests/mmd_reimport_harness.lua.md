# mmd_reimport_harness.lua

LuaJIT harness for the R12-A lifecycle regression, invoked by
[test_mmd_reimport.py](test_mmd_reimport.py.md). Arguments: generated production snippet, packaged
Lua directory, `server|client`, `retained_archive|changed_fit|withdraw_live|failed_write|missing_mount|orphan_variant|reload`.

Models native `PrepareCarrier` returning a retained archive's manifest without recreating its
deleted `rig.json`. Executes the actual delete function, both spawn factories, readiness gates,
model lookup and persistence `SetModel` wrapper with an outer delegating addon wrapper. File/mount,
precache, entities and network adapters are instrumented; appearance binding is reduced to its
readiness and manifest publication boundary. Both realm simulations use the server persistence
wrapper to exercise it against their separate reusable state. Existing entities retain their
immutable rig while deleted reusable entries and conversion variants are invalidated; another
asset remains cached. Writes stdout only. Exit 0 with `PASS <realm> <scenario>`, otherwise nonzero.

`orphan_variant` removes just a converted carrier's sidecar before a withdrawal callback arrives
and changes the saved bone pins: mounted bytes and a cached Lua object cannot satisfy readiness.
`reload` reloads persistence while its guarded SetModel wrapper stays installed, then deletes and
reimports. The active wrapper and the withdrawal callback must keep the same conversion memo.
