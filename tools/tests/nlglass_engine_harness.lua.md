# nlglass_engine_harness.lua

R7-C expects the additional per-player interaction control and verifies its six translated labels
(English is the source text) and reset default alongside the existing server settings/permission tests.
`debris_interest` exercises the real server/fracture path and checks that only released pieces
register a bounded recent-break region.

Second-pass `lit_cracks` captures material shader/parameters and checks non-emissive lit strips,
matching outward normals, thin widths and both faces. `walk_run` checks 200/249/250/400-unit/s
normal contacts, pre-movement sweeps, menu display and admin reset to the shared default 250;
since G1 integration also a player's physics-shadow collision at each speed (it took the prop
energy rule before, so a walk broke glass). `settings_migration` pre-creates the values
Glass-Rewrite-Remix archived under shared names (contact speed 80, velocity transfer 2, player mass
80), then checks the first start resets only the first two, records the migration and keeps a later
choice; it fails on 8536d87.

Fix-pass scenarios: `body_contact`, `player_move`, `client_settings`, `map_outputs`, `last_impact`,
`blast_order`, `budget`. Each fails against the 3096b2e add-on. They cover departing/distant/rotated
bodies, a 500-unit/s pre-movement contact with stopped entity velocity, independent replicated
client convars, raw once-only native output mirroring without Shatter, weak native impact recording,
blast-after-spawn ordering and the 8,192 slider limit.

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

`topology` round-trips near-cap live cells/coarsening groups through the typed wire mock, checks
message size and compares the next break's polygons. `client_build` counts one physics build and
one mesh pair per break, no weak-hit rebuild and no repeated-packet debris. `draw_cull` counts
zero stationary Matrix/LocalToWorld/class calls, verifies distance/eye-plane culling and a moving
pose update. `initial_sync`/`target_sync` check one readiness push and independent per-pane repair.
The contact probe includes the QA SetVelocity base impulse and player yaw; blast ordering also
covers an engine-native removal deferred after damage.

Second-pass `client_build` asserts no meshes/collision build in the receiving frame and one
build on the next. `build_queue` checks same-pane burst coalescing, two-pane and soft elapsed-time
limits, repeated Think calls, latest revision, shared render/collision positions, cancellation
by snapshots/removal/whole-break/cleanup, and collision attachment for a late entity. `shared_geometry`
checks triangle counts, position sharing, thickness and outward winding on a rectangle and triangle.
Lit cracks also check triangle winding after the shared strip builder changed.

`client_timings` prepares 100 hits, restores a fresh near-cap server/client state before each of
40 samples, and measures actual server/client hit/break handlers with QueryPerformanceCounter.
Client reset and initial snapshot/build are outside timing. The Lua mesh/convex work is real;
engine APIs, transport, debris simulation and renderer submission are mocks. It reports mean/p99
milliseconds; these numbers do not predict GMod/Remix frame times. Second-pass output separates
the receiving handler from the next frame's queued build and reports their per-sample sum, so
deferring work cannot hide it. The same workload prepares 502 cells before and 164 after the
new density cap. A mock frame advance drains work between the hit and break measurements.

Output: assertion diagnostics and `engine <scenario> OK`. Side effects exist only in mocked tables
(network outboxes, collision meshes, sounds, UI controls, debris calls). No filesystem writes,
game launch, install mutation or network connection. Exit 0 passes; Lua assertions exit nonzero.
The bridge test proves input routing, not the engine's actual Hammer output semantics.
