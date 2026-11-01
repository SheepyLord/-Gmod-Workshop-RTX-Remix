# nlglass_engine_harness.lua

Runs the actual G1-A bootstrap, server, protocol, entity, tool, catalogs, menu and client modules in
isolated mocked server/client Lua environments. `NLGlassDebris` is a stub exposing only the plan's
public API; no G1-B code, native module or game process is used.

```powershell
luajit tools/tests/nlglass_engine_harness.lua glass/addon/lua network
```

Inputs: Lua root and scenario. `damage`, `collision`, `bodies`, `scripted`, `native`, `map`,
`collision_mesh`, `network`, `blast_cleanup`, `save_dupe`, `tool_menu`, `geometry`, `late_entity`,
`collision_failure` exercise all damage causes,
real PhysObj mass and relative velocity, deferred physics mutation, player/NPC/vehicle contacts and
hole exclusion, forced breaks without an initial snapshot, native health ownership and recorded /
breaker / nominal fallback, once-only surface output bridging, remaining frozen convexes, actual
typed packets with float32 fields, two-client replay, late join, cached mesh drawing, deduplicated
explosion impulses, cleanup epochs, property-only restore/dupe, tool CPPI/limits, translations,
admin authorization, injection refusal and reset (including queued edits), rotated triangular brush
frames/material objects, surviving cleanup panes, delayed client entities, reused index safety and
collision-build failure. Engine callback order and object liveness can be
controlled in memory. It asserts no server Think/Tick hooks are installed.

Output: assertion diagnostics and `engine <scenario> OK`. Side effects exist only in mocked tables
(network outboxes, collision meshes, sounds, UI controls, debris calls). No filesystem writes,
game launch, install mutation or network connection. Exit 0 passes; Lua assertions exit nonzero.
The bridge test proves input routing, not the engine's actual Hammer output semantics.
