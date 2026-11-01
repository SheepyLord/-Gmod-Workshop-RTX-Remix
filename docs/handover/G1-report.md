# G1: a glass overhaul (report)

The user's request (2026-10-31), about the glass the package shipped (Glass-Rewrite-Remix, a proof of
concept from the original repository): only bullets scatter glass, other causes such as a body make it
disappear; the break pattern and the region that gets velocity are the same wherever the glass is hit;
no cracks are drawn after damage that does not break it; many broken panes, and piles of pieces, make
the game lag. Broken glass only has to interact with the map and with itself; an alternative physics
engine such as VPhysics-Jolt could simulate it. During integration (2026-11-01): "Make the glass break
pattern more random, currently it is always a Octagon."

The user's decisions: a new MIT system that replaces Glass-Rewrite-Remix in the package; our own Jolt
module; broken glass collides with the map and other pieces only, on each client; both glass kinds,
annealed and tempered, chosen in the settings menu. Plan and design: [G1-plan.md](G1-plan.md),
[ADR 0070](../decisions/0070-glass-overhaul.md). Codex (`gpt-6.1-sol`, effort max) wrote the Lua system
and the native module in two parallel tasks, then two fix passes each from what the game showed; Claude
reviewed, integrated, ran the game QA on the PoC, fixed what the game found, and publishes.

## What was built

| Task | Brief | What it does |
|---|---|---|
| G1-A | [G1-A-lua.md](G1-A-lua.md) | The MIT add-on (`glass/addon`, shipped as `nlglass`): server-owned convex panes (`nlglass_pane`), one damage entry point for bullets, melee, blasts, props, ragdolls, players, NPCs and vehicles (energy `0.5 m v²`, 12,000 per bullet damage point), strength scaled by area and thickness squared (the reference 96x64 pane breaks at 450,000; cracks start at 8 %, capped at 36,000; tempered 3.5 times stronger), deterministic integer fracture on server and clients, growing cracks sent as impacts, remaining-glass collision, map `func_breakable_surf` windows replaced with their outputs bridged, native `func_breakable` glass watched, spawn presets, the tool, settings menu in seven languages ([ADR 0071](../decisions/0071-glass-impact-model.md), [0074](../decisions/0074-glass-contact-and-quiet-map-outputs.md)) |
| G1-B | [G1-B-native.md](G1-B-native.md) | `gmcl_nlglass_win64.dll`: a Jolt Physics 5.3.0 world per client; map brushes, displacements and static props imported on a worker thread, stepped off the game thread; the debris manager (`NLGlassDebris`): budget 2,000 pieces, lifetime 120 s, settled pieces merged into area batches, view and distance culling, a 64-piece client fallback without the module ([ADR 0072](../decisions/0072-glass-debris-world-and-batching.md)) |
| Fix pass 1 | [G1-fix-pass.md](G1-fix-pass.md) | A: body contact from incoming movement, incremental fracture, map outputs without engine shatter, client timings. B: refused hulls skipped instead of disabling Jolt, double-precision clipping, background preparation and stepping, staged piles ([0073](../decisions/0073-glass-native-fix-pass.md), [0075](../decisions/0075-incremental-glass-topology.md), [0078](../decisions/0078-glass-background-work-and-staged-piles.md)) |
| Fix pass 2 | [G1-fix-pass-2.md](G1-fix-pass-2.md) | A: breaks bounded at 200 annealed / 300 tempered pieces, lit cracks, the 250-unit/s contact default (walking 200 stays below, running 400 above), deferred client builds. B: larger consolidated piles, grouped and culled individual draws, per-frame manager costs ([0076](../decisions/0076-glass-bounded-break-density.md), [0077](../decisions/0077-glass-client-build-queue.md), [0079](../decisions/0079-glass-pile-consolidation.md), [0080](../decisions/0080-glass-visibility-and-frame-costs.md)) |

Reports: [G1-B](G1-B-report.md), [G1-B fix](G1-B-fix-report.md), [G1-B second pass](G1-B-fix2-report.md);
G1-A's are in [ROADMAP](../ROADMAP.md) and [TESTING](../TESTING.md).

Integration (`g1-int` in `out\worktrees\g1-int`), by Claude: the package's eleventh part `glass`
(`tools/workshop.json`: the add-on, its licence, Jolt's licence, the module from `packages/glass`
through `tools/inputs.py import`; `publish_workshop.py` and `package.yml` watch `glass/addon` and Jolt's
licence); `NLGlassDebris.Prepare()` so the map is imported before the first break; the QA add-on
[`tools/qa/nlglass_qa`](../../tools/qa/nlglass_qa/lua/autorun/nlglass_qa.lua.md) (modes `field`, `map`,
`contact`, `old`); and the fixes below.

## What the game found, and the fixes

Runs are under the main checkout's `out/qa-poc/g1/` (PoC, 1920x1080 windowed, RTX on).

1. **Panes drew black** (run 01): the brief named `rtx/replace_me/glassmat`, whose texture does not
   exist. Panes and pieces now use `models/props_combine/health_charger_glass`, which Remix replaces
   with the package's translucent PBR glass (`base_mod/breakable_glass`).
2. **Jolt never ran** (runs 01, 02): one degenerate brush, then one hull Jolt refused, switched the whole
   map to the fallback. Fix pass 1 skips and counts single shapes; gm_construct imports 2,095 brushes
   (3 skipped, 1 refused), modern_house 1,477 brushes and 54 prop models.
3. **The 50-pane scene was slow** (run 03: 33.8 ms mean while falling, 11.9 ms settled with 388
   batches): fix pass 2 (consolidated piles, culled draws, bounded breaks).
4. **Walking into glass broke it** (runs 06-08). The QA's walk/run step first never reached run speed:
   GMod takes the run speed from the user command's buttons, so a `SetupMove` hook stays at 200; it now
   holds forward and sprint through `StartCommand` in both realms (run 07: 400). The verdict now counts
   the impacts the glass server accepted and the glass left, since annealed glass keeps its frame
   after a breakout and the entity alone proved nothing (the walk had broken out 86 % of the pane). Two
   causes:
   - Glass-Rewrite-Remix archived `rtx_glass_player_break_speed` (default 100; 80 in the PoC's
     `cfg/server.vdf`) and `rtx_glass_velocity_transfer` (2) under the names this system reuses, and GMod
     restores archived values over a new default. The first start of the new system resets those two
     once (`rtx_glass_settings_version` records it) and keeps later choices. Every install that ran the
     old add-on, the field install included, has these values.
   - In the code, a player's or NPC's physics-shadow collision took the prop energy rule (85 kg at
     200 units/s is 1.7 million against 450,000) and skipped the speed gate; bodies now always use the
     body rule. Found by reading the code while chasing the walk; not proven to have fired in game.
   Run 10, with both: walk 200 units/s, no impact, 100 % glass left; run 400 units/s, the pane breaks.
5. **Always an octagon** (the user): every ray of a hit shared the same ring radii and 8 rays were
   spaced evenly (±4°), so each hole and crack ring was a near-regular polygon. Now a hit takes 6-10 rays
   by its seed (two more per 120,000 energy, at most 16) at uneven seeded gaps, every ray has its own
   inner ring radii (0.8-1.2 of the ring's), and a break also releases about a third of the next ring's
   small interior cells, a ragged edge. Still integer-seeded, so all players get the same pieces.
   Offline render of the real code, before and after: `out/g1-pattern/pattern-before-after.png` in
   `g1-int`; in game, run 10 and 11 cracks.
6. G1-A and G1-B had both numbered decision records 0074-0077; G1-B's are now 0073 and 0078-0080.

## Measurements (PoC)

Field run 10 (gm_construct, final build `0.0.0-dev.20261101100544+d9e04e20`): every cause leaves
pieces, no pane disappears without them.

| Step | Result | Live pieces | Frame mean / p99 |
|---|---|---|---|
| Two 15-damage rounds | cracks, no pieces | 0 | 8.25 / 9.69 ms |
| Four more rounds | the region around the hits breaks out | 161 | 10.87 / 62.04 ms |
| 400-damage round at a corner and at a centre | each breaks out where it hit | 320 | 9.52 / 24.59 ms |
| Twelve 8-damage rounds on 256x128 | weak hits add up | 353 | 8.88 / 10.68 ms |
| Oil drum 30 kg at 700 units/s, ragdoll at 650 | both burst a pane | 452 | 13.06 / 143.65 ms |
| Player walks 200 / runs 400 into 64x96 | whole / broken | 542 | 10.58 / 11.66 ms |
| Blast; tempered: four rounds, then a blast | breaks; tempered holds, then small cubes | 718 | 11.62 / 50.33 ms |
| Scripted `Break` input | breaks | 787 | 11.18 / 36.19 ms |

The 50-pane scene (the same view, 50 96x64 panes broken by blasts within 1.5 s):

| Scene | Live / moving | Frame mean / p99 | Manager think + draw | Jolt step |
|---|---|---|---|---|
| Before the panes (787 settled pieces from the earlier steps) | 787 / 0 | 8.75 / 11.77 ms | 0.03 ms | 0.08 ms |
| While falling | 2,000 / 1,236 | 25.31 / 113.22 ms | 1.69 + 6.99 ms | 1.50 ms |
| 15 s later, settled (62 batches) | 2,000 / 1 | 9.74 / 16.39 ms | 0.05 + 0.11 ms | 0.12 ms |
| Old system (run 12): the empty scene | 0 | 8.87 / 10.20 ms | | |
| Old system, the same 50 panes while falling | 361 shard entities (it keeps at most 256 loose pieces) | 18.18 / 109.13 ms | server entities, Source physics | |
| Old system, 15 s later | 302 shard entities | 10.89 / 14.49 ms | | |

For the user's point 4: the old system's settled pile of about 300 pieces costs 2.0 ms over its empty
scene; the new system's 2,000 cost 1.0 ms over the scene before. While falling, the new system costs
7 ms more than the old one with 6.6 times the pieces; most of it is drawing about 1,000 moving pieces
one by one (6.99 ms of manager draw). `rtx_glass_debris_budget` trades pieces for frame time.

History of the same scene: run 03 (before fix pass 2) 33.83 ms falling and 11.91 ms settled with 388
batches; run 05 22.59 / 9.43 ms; run 08 23.38 / 9.81 ms. Settled glass costs the manager 0.16 ms per
frame; the rest of the 1 ms over the scene before is Remix path tracing 2,000 visible translucent
pieces. The p99 values are the frames where pieces appear (62 ms even for one pane in the bullet
step); offline, the fracture of a break costs about 0.7 ms, so most of a spike is the mesh and body
creation or Remix taking in new geometry, not separated yet.

modern_house (run 11, 44 native `func_breakable` panes; the map itself runs at about 19 ms): one round
cracks a pane (an irregular web); eight more and the engine breaks it, 203 pieces; a thrown ragdoll
bursts the second pane (391 live, 25.83 / 161.8 ms while falling, Jolt 1.01 ms).

## Tests

52 glass tests under LuaJIT (`tools/tests/test_nlglass.py`): the real fracture and an engine harness
with GMod stubs, including the integration regressions `irregular`, `settings_migration` and the
shadow collision in `walk_run`, each failing on the code before it. G1-B's native tests (19 cases) and
debris harness. Full suite: FULL_SUITE.

## Open issues

- Frame spikes when pieces appear: 62 ms for one pane, 113 ms p99 for 50 panes in 1.5 s, 144-162 ms
  for a ragdoll's burst. The cause is not separated (piece meshes and bodies, or Remix taking in new
  geometry); measuring and spreading that work over frames is the next performance step, together
  with drawing moving pieces in batches (falling: 25.3 ms mean against 8.75 ms before).
- Broken glass does not collide with props or players and cannot be picked up (the user's decision).
- Two clients and prediction are covered by the harness only, not by a two-player game session.
- The NVIDIA driver crash at start-up seen once (run 05, `nvoglv64.dll`, before the glass module
  loaded) is the deferred driver-crash class; not investigated.
- The glass material Remix substitutes shows the faint square grid of its source texture
  (HL2's wired-glass break texture); unchanged from before G1.
