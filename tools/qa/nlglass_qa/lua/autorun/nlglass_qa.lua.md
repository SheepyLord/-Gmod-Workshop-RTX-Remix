# nlglass_qa.lua

A QA add-on for the G1 glass system, never shipped: copy `tools/qa/nlglass_qa` into a test install's
`garrysmod/addons/` for one session (the PoC), then remove it. It needs the glass add-on (`nlglass_pane`,
`NLGlassDebris`) and a listen server. Start it with [`nlglass_qa_start.lua`](../../../nlglass_qa_start.lua.md).

Server: the console command `nlglass_qa [field|map]` (the listen-server host only) runs steps in order,
each waiting for the client to report its screenshot, and prints `NL_QA <step>` lines.

`field` (gm_construct; the player on (831.235, 576, -143.08), facing west):

1. Bullets (15 damage) at one point of an annealed 96x64 pane: after one round, after two, after six,
   and three seconds later.
2. A 400-damage round at a corner of one pane and at the centre of another, in flight and settled.
3. Twelve 8-damage rounds at one point of a 256x128 pane (weak hits must add up).
4. A thrown oil drum (700 units/s), 5. a thrown ragdoll (650 units/s).
6. The player walks, then 7. runs, into a 64x96 pane from 160 units away: the player's own movement
   with forward (and sprint) held through a `SetupMove` hook for 1.6 s; prints whether the pane is still
   there and the top speed reached (a walk must leave it whole, a run must break it).
8. An explosion in front of a pane, 9. four rounds into a tempered pane, then a blast at it, 10. a
   scripted `Break` input.
11. Performance: the empty field for 6 s, 50 panes broken by blasts (frame times over 4 s while they
    fall), then 15 s later.

`map` (a map with native `func_breakable` glass, such as modern_house): the nearest glass pane to the
player gets one round (crack), then up to eight more until the engine breaks it (break, settled), and
the second nearest is hit by a thrown ragdoll. The player stands 90 units in front of the first pane.

It removes its own panes, props and ragdolls between steps. Client: frames each step with a `CalcView`
camera (HUD hidden), samples frame times with `PostRender`, prints `NL_QA client <label> backend
<jolt|vphysics|none> live moving sleeping batches frames mean_ms p99_ms | jolt step_ms awake brushes
skipped refused statics models` from `NLGlassDebris.Stats()`, then `NL_SHOT <label>`; the
`nl_shot_taken` reply from `poc_session.py --lua-shots` moves the server to the next step, and
`NL_SHOT_DONE` ends it.

Side effects: the session's player position, entities it spawns and removes, and the glass broken.
Exit codes: none (game Lua).
