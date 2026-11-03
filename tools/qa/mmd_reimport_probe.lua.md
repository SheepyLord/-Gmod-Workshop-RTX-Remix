# mmd_reimport_probe.lua

R12-A's two-realm probe, injected by [mmd_reimport_session.py](mmd_reimport_session.py.md).
Not an autorun and never installed in the field. Imports the driver's copied PMX through the real
native worker, removes only its isolated test entry through `library.Delete`, and spawns through
client `RequestSpawn`. Server observations inspect model readiness, rig metadata, attachment and
physics; a delegating outer `SetModel` wrapper exercises the compositeentities call ordering.
It also exercises ragdoll-to-citizen conversion and retains old entities while preparing other fits.

Inputs: current PoC hotloader and the source path supplied by the driver. Outputs: `R12A_*` JSON
console lines and QA entities. Changes client camera/HUD hooks for screenshots and isolated test
library data. The driver restores the cache and code after normal game shutdown. No files outside
the isolated PoC cache are explicitly written by this Lua. No exit code; failures emit
`R12A_ERROR`, which the driver treats as failure.
