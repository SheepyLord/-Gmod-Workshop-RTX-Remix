# G1: second fix pass (performance and tuning, two parallel tasks)

Both tasks start from `g1-int` after the first fix pass ([G1-fix-pass.md](G1-fix-pass.md)) was merged.
Read that file, [G1-plan.md](G1-plan.md) and your original brief first.

## What the game showed (PoC, Jolt running; `out/qa-poc/g1/03-qa` and `04-map` in the main checkout)

Every cause breaks glass into pieces; panes, pieces and cracks look like glass; weak hits add up;
tempered glass resists four rounds and shatters into small cubes under a blast; native
`func_breakable` windows on modern_house crack from one round, break with pieces when the engine breaks
them, and a thrown ragdoll bursts one. Jolt imports gm_construct (2,095 brushes, 3 skipped, 1 refused)
and modern_house (1,477 brushes, 54 prop models). Physics is cheap (about 1.6 ms per step with 1,453
pieces moving). The client still pays elsewhere:

| scene | live / moving | frame time mean / p99 | Jolt step |
|---|---|---|---|
| gm_construct, no pieces moving (678 settled, 40 batches) | 678 / 0 | 8.71 / 11.59 ms | 0.09 ms |
| 50 panes broken by blasts within 1.5 s, while falling | 2,000 / 1,453 | 33.83 / 139.38 ms | 1.58 ms |
| the same 15 s later, all settled, **388 batches** | 2,000 / 0 | 11.91 / 28.95 ms | 0.07 ms |
| modern_house: one large window broken by rounds | 416 pieces | baseline about 20 ms | |
| modern_house: a second window burst by a ragdoll, falling | 952 / 536 | 30.15 / 159.6 ms | 2.86 ms |

## G1-A second pass (Lua; branch `g1-lua-fix2`)

Owns what it owned in the first pass.

1. **Pieces per break.** One large modern_house window became 416 pieces and another 536. Keep the
   look (small pieces at the impact, large away from it) but bound the pieces one break makes, for
   example scaling ring and ray density down with the pane's area so a large window gives at most about
   200 annealed pieces (tempered about 300), and never more than the cells' cap. Record the counts for a
   96x64 pane, a 256x128 pane and a 128x256 window, for a centre and a corner hit.
2. **Cracks must not glow.** Cracks use an `UnlitGeneric` material; under Remix unlit materials tend to
   render at full brightness, so cracks would glow in a dark room or at night. Use a lit material (for
   example `VertexLitGeneric` with a white base texture) so the path tracer shades them; keep them thin
   and on both faces.
3. **Walking does not break a window, running does.** GMod walks at 200 units/s and runs at 400, and
   `rtx_glass_player_break_speed` defaults to 180, so walking into any pane breaks it. Default it to
   250, update the settings menu, its translations if a text changes, and the docs.
4. **Cost of a break on a client.** The mocked client handler still measured 23.7 ms per break; with 50
   breaks within 1.5 s that is visible. Bring it down (for example defer the mesh and collision build of
   the remaining glass to the next frame, build pieces' polygons only once) and record the numbers.

## G1-B second pass (native and debris manager; branch `g1-native-fix2`)

Owns what it owned in the first pass.

1. **Settled piles in few draws.** 2,000 settled pieces were drawn in 388 batches and cost about 3 ms
   (8.7 to 11.9 ms) with p99 spikes to 29 ms. Consolidate settled chunks per area (aim for a handful of
   draws per area, rebuilt rarely and spread over frames), and find and remove the source of the spikes.
   Target: 2,000 settled pieces within 1 ms of the frame time without them, no spike above 16 ms.
2. **Moving pieces.** With 1,453 pieces moving the frame took 34 ms on average while Jolt took 1.6 ms:
   the cost is drawing each piece from Lua. Cut the per-piece work (one material change per batch of
   pieces, no per-piece allocations, cached matrices), skip pieces outside the view or beyond a distance,
   and draw small distant pieces not at all; consider faster sleeping on contact with the ground so
   pieces spend less time moving, without making them stick in the air. Target: the 50-pane break under
   20 ms on average while falling.
3. **Instrumentation.** `NLGlassDebris.Stats()` reports the manager's own time per frame (think and
   draw, milliseconds, averaged) and draw calls per frame, so the QA can attribute frame time.

## Both

`tools\test.ps1 -Config Release` passes. Never launch Garry's Mod; Claude runs the game checks. Never
write to the PoC or field install, touch Steam's files or `user.conf`, upload, or push, merge, tag or
commit on `main`. No downloads. Shared documents get additive edits only. Commit on your branch; your
final message is your report: what changed per item, tests and measured numbers, what remains for the game.
