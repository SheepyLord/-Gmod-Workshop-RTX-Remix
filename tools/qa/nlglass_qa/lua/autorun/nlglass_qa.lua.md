# nlglass_qa.lua

A QA add-on for the G1 glass system, never shipped: copy `tools/qa/nlglass_qa` into a test install's
`garrysmod/addons/` for one session (the PoC), then remove it. It needs the glass add-on (`nlglass_pane`,
`NLGlassDebris`) and a listen server.

Server: the console command `nlglass_qa` (the listen-server host only) places the player on the
gm_construct field spot (831.235, 576, -143.08), facing west, and runs these steps in order, each waiting
for the client to report its screenshot:

1. Bullets (15 damage) at one point of an annealed 96x64 pane: after one round, after two, after six
   (break), and three seconds later.
2. A 400-damage round at a corner of one pane and at the centre of another, in flight and settled.
3. A thrown oil drum (700 units/s), 4. a thrown ragdoll (650 units/s), 5. the player pushed into a pane
   (500 units/s), 6. an explosion in front of a pane, 7. six rounds into a tempered pane, 8. a scripted
   `Break` input.
9. Performance: the empty field for 6 s, 40 panes broken by blasts (frame times over 4 s while they
   fall), then 15 s later.

It removes its panes, props and ragdolls between steps and prints `NL_QA <step>` lines. Client: frames
each step with a `CalcView` camera 140 units in front of the pane (HUD hidden), samples frame times
with `PostRender`, prints `NL_QA client <label> backend <jolt|vphysics|none> live moving sleeping
batches frames mean_ms p99_ms` from `NLGlassDebris.Stats()`, then `NL_SHOT <label>`; the
`nl_shot_taken` reply from `poc_session.py --lua-shots` moves the server to the next step, and
`NL_SHOT_DONE` ends it. Start it with [`nlglass_qa_start.lua`](../../../nlglass_qa_start.lua.md).

Side effects: the session's player position, entities it spawns and removes, and the panes broken.
Exit codes: none (game Lua).
