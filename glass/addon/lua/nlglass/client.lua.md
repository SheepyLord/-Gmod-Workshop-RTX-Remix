# client.lua

Cached pane/crack rendering, collision prediction and debris event replay.

Client-only bootstrap include. Consumes authoritative records/impacts; creates meshes and matching frozen pane collision and updates them on state changes or late network entity creation. Calls only NLGlassDebris Spawn/Impulse/Clear, plays glass sounds and impact effects. Clears meshes/debris on cleanup/shutdown. The debris manager itself belongs to G1-B. No direct disk writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
