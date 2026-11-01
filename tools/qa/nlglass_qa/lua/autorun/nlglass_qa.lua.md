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
6. The player walks, then 7. runs, into a 64x96 pane from 160 units away: the player's own movement,
   with forward (and sprint) held in the user command for 1.6 s by a `StartCommand` hook that both realms
   run (GMod takes the run speed from the command's buttons, so changing the move data alone keeps the
   walk speed); prints whether the pane entity is still there, the impacts the glass server accepted
   on it, the share of glass left and the top speed reached. A walk must leave it whole (no impact,
   100 % left), a run must break it. The entity alone proves nothing: annealed glass keeps its frame
   after a breakout. The impacts are counted by wrapping `NLGlass.Server.Impact`, the one entry point
   of every cause.

`nlglass_qa contact` runs only steps 6 and 7.

`old` (gm_construct, with the package from before G1, whose fixes part still carries Glass-Rewrite-Remix):
the performance scene of step 11 with the old system, for the before/after comparison: 50 96x64
`procedural_shard` panes built the way that add-on's map replacement builds one (its block model scaled
to the pane), broken by the same blasts; prints the number of shard entities while they fall and 15 s
later. Start it with a client Lua that runs `nlglass_qa old`.
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
