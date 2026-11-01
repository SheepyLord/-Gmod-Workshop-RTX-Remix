# R7: the user's report of 2026-11-01 (report)

The user's four points (plan: [R7-plan.md](R7-plan.md)): (1, high) transparent materials render black,
showing only their shadow, for example Columbina's `眼罩` (blindfold) on an `npc_citizen` in the field
session; (2) a message after a crash such as running out of memory; (3) broken glass that reacts to
follow-up damage and is pushed by players and Source physics objects, one way; (4) a memory warning that
made no sense at 64.0 / 90.6 GiB, and an add-on list that should show `gmod-rtx-remix` in full and only
count the others. Mid-round the user added: find the best way to implement alpha under Remix (alpha test
may not be needed; translucent or a Remix-managed alpha), and granted full permission to close, launch and
update both the PoC and the field game, to decide without asking, and to push and publish when done.

Claude investigated point 1 on the PoC, wrote three Codex briefs (`gpt-6.1-sol`, effort max), reviewed and
integrated on `r7-int`, ran the game QA and fixed what the game found.

## What was built

| Task | Brief | What it does |
|---|---|---|
| R7-A | [R7-A-mmd-alpha.md](R7-A-mmd-alpha.md) | Runtime patch 0017: texture category `rtx.mmdAlphaTextures` (saved) joined with the NoSave `rtx.gmod.mmdAlphaTexturesForSession`, cutoff `rtx.mmdAlphaCutoff` 0.5; for tagged legacy draws the alpha test uses the cutoff and blended opacity at or above it becomes 1 in the shared opacity evaluator, so primary, shadow, PSR, indirect and opacity micromaps agree. The companion (`nativeloader_mmd_alpha.lua`) fills the session list ([ADR 0081](../decisions/0081-mmd-alpha-texture-category.md), [report](R7-A-report.md)) |
| R7-B | [R7-B-crash-diagnostics.md](R7-B-crash-diagnostics.md) | An exit observer: the same `winmm.dll` under `rundll32` waits on a pinned game handle and shows one localized message with the reason, advice, exit code and evidence folder; the memory warning below 18 GiB free commit or a 24 GiB limit; one count line for content add-ons ([ADR 0082](../decisions/0082-map-commit-headroom-and-addon-summary.md), [ADR 0083](../decisions/0083-external-exit-observer-from-the-proxy.md), [report](R7-B-report.md)) |
| R7-C | [R7-C-glass-interaction.md](R7-C-glass-interaction.md) | Kinematic mirrors of players, NPCs, ragdoll bones and props in each client's Jolt world; bounded splitting by bullets (forwarded by the server near recent breaks), blasts, bodies and landings; a per-player switch; then a fix pass for fast props (swept discovery, immediate boxes, native shape casts) ([ADR 0084](../decisions/0084-glass-one-way-interaction.md), [report](R7-C-report.md)) |

## Point 1: what the game showed, and the fixes

- **Cause.** Columbina's mask texture has bars at alpha 0.65 and panes at 0.26. Model Hotloader draws such
  partly transparent triangles blended in the opaque pass under Remix (`mmdhl_soft_alpha`). The runtime skips
  a blended opacity between its transparency threshold and `rtx.stochasticAlphaBlendOpacityThreshold`
  (0.79 in the package) in primary rays, but visibility rays still attenuate by `1 - opacity`: no mask, a
  lattice-shaped shadow on the face (run `03-columbina`). An alpha ramp on plain plates (`04-ramp`) showed
  the fixed-function path also alpha-tests lit models at about 0.7, whatever `$alphatestreference` says.
  A 0.5 threshold in a temporary root `rtx.conf` drew the mask as in MMD (`05-columbina-thr05`); changing it
  for everything would also turn map glass and props between 0.5 and 0.79 solid, hence the scoped category.
- **Integration fix.** With R7-A's runtime the mask was still invisible (`13`, `15`). The runtime reports no
  hash for the mask's public material, because a part whose every texel is partly transparent is drawn only
  through the hotloader's soft copy; the soft copy, tracked by its plain name, reports the live hash
  `0x4F9DC84370047174` (`16-mask-diag2`; the offline prediction `0xFB16...` was wrong). A first attempt,
  binding a tracked wrapper of the texture off-screen, never reported a hash. The companion now also
  tracks the soft copies listed in `mmdhl.softMaterials` (`f7a6a94`, harness cases that fail on R7-A's code).
- **Result** (`17-mask-softcopy`, `18-mask-softalpha-off`): the mask renders as white bars with see-through
  holes and no shadow band, with soft alpha on (faint panes, as in MMD) and off (clear holes, as in the
  hotloader's preview). The registered list holds the mask's hash among 47 tracked materials.

## Point 2: the exit report on the PoC

- Previews of all six reasons read correctly in English, Chinese, Japanese and Russian (`06-exit-previews`).
- A game ended with `0xC0000017` showed "System memory exhausted … Exit code: 0xC0000017" with its session
  folder and wrote `exit-report.json` with reason `out_of_memory` (`08-exit-oom`); the next start received the
  same reason for its menu notice (`09-menu`). A real start-up crash (`0xC0000005`, Remix wrote a Sentry dump)
  was reported as "Crash detected … Access violation" (`07-exit-oom`). Both observers exited when dismissed.
- Integration fix: the dialog's evidence path mixed `\` and `/`; it now uses one style.
- A start to the main menu with the new loader ran and quit normally (`19-menu`).

## Point 3: glass on the PoC

The interaction steps (`26-interact`, gm_construct, Jolt, piece size 8, the final glass code):

| Step | Pieces split: contact / landing / bullet / blast | Mirrored Source bodies | Source |
|---|---|---|---|
| Walk at 200 units/s through a pile | 24 / 0 / 0 / 0 | 12 | walks through (x 458.0), health 100 |
| Run at 400 units/s through a pile | 31 / 16 / 0 / 0 | 12 | runs through (x 194.8), health 100 |
| Ragdoll dropped onto a slab | 8 / 13 / 0 / 0 | 17 (bones) | |
| Oil drum (30 kg) thrown onto a pile | 5 / 0 / 0 / 0 | 1 | |
| Bullet into a slab | 0 / 9 / 1 / 0 | | |
| Blast at a slab | 0 / 8 / 0 / 1 | | |
| Large piece dropped from a window | 0 / 16 / 0 / 0 | | |

With the switch off (`12-interact-off`) every counter stays at zero. Nothing pushes back: players
walk and run through the pieces at full speed and keep their health.

What the game found, fixed at integration:

- **The drum crossed the pile.** In `10-interact` and `11-interact` the drum first flew over the pile:
  the QA threw it from the pane's height (`7b49de9`). Thrown lower, it crossed nine pieces without
  touching them. That was a real gap: Jolt runs no CCD for kinematic bodies, and discovery missed
  fast bodies. R7-C's fix pass (`r7-glass-fix`: swept discovery, immediate boxes for fast bodies,
  native shape casts) gives 5 contact splits (`23-interact-on`, `26-interact`).
- **The body search cost frame time.** With interaction on, the 50-pane scene's manager think rose
  from 0.02 ms to 0.49 ms with nothing moving, and Lua spikes reached 26 ms (`24-field-on`). The
  10 Hz search tested regions through Source vectors. A probe (`25-probe`) measured 35 ns per
  component read, against 0.5 ns for a Lua number: 512 bodies against 32 regions took 3.13 ms, and
  0.30 ms on numbers. The test now runs on numbers (`83dd866`).
- **Client physics bodies were misplaced.** The same probe showed that `PhysObj:GetAABB` is in the
  object's own frame. The coarse boxes of client physics bodies (client ragdolls, client props) were
  placed near the map origin, then dropped. They now take the body's pose. Server props have no
  client physics object and already used an oriented box, which is why the drum worked. The test
  double now behaves like the game, and the old code fails its two checks.

The 50-pane scene (the G1 sequence, then 50 panes broken by blasts), same build, interaction off
(`27-field-off`) then on (`28-field-on`). Before each run the machine was at 13-17 % CPU, with no
other game running:

| Scene | G1 run 10 | R7, interaction off | R7, interaction on |
|---|---|---|---|
| Before the panes (787 / 912 settled pieces) | 8.75 / 11.77 ms | 8.96 / 12.81 ms | 8.85 / 16.58 ms |
| While 2,000 pieces fall | 25.31 / 113.22 ms | 26.28 / 134.30 ms | 28.60 / 134.33 ms |
| Settled | 9.74 / 16.39 ms | 9.17 / 14.66 ms | 9.32 / 17.25 ms |
| Manager think: before / falling / settled | 0.01 / 1.69 / 0.05 ms | 0.02 / 1.79 / 0.02 ms | 0.18 / 2.61 / 0.26 ms |

Frame mean / p99 in each cell, except the last row. Walking keeps a pane whole and running breaks it,
in both runs.

- **Interaction off:** R7 matches G1 within 1 ms in the mean. The falling p99 (134 against 113 ms)
  is the second-worst of about 150 frames: a single sample, also 142 ms in run 21.
- **Interaction on, while pieces fall:** the mean costs 2.3 ms more than off. The added Lua is
  0.8 ms of think (landing splits, one replacement a frame, and the capture) and 0.6 ms of draw (the
  split pieces). The p99 is unchanged. As the user asked, the falling cost was left alone.
- **Interaction on, nothing moving:** 0.2-0.3 ms of Lua per frame, mostly the 10 Hz search.

## Point 4: diagnostics

The memory warning now needs less than 18 GiB of free commit, or a commit limit under 24 GiB; 64.0 /
90.6 GiB does not warn ([ADR 0082](../decisions/0082-map-commit-headroom-and-addon-summary.md)). The
18 GiB reserve comes from the saved R6 sessions, which added 11.1-16.2 GiB of system commit from start
to map load. The panel and its copied text show `gmod-rtx-remix` with its version and hash, and one
count line for the other enabled add-ons. Unit tests cover the thresholds and the panel's JavaScript.
The field menu, below, shows the result on the user's machine.

## Tests

`tools\test.ps1 -Config Release` on `r7-int`, final tree (loader 0.12.0): repository conventions OK,
26 of 26 CTests (the native glass cases included), 470 Python tests (two skipped, as before), "All
checks passed".

- The glass harness's physics-object test double now returns `GetAABB` in the object's own frame;
  `scene_fallback` and `scene_sweep_bounds` fail on the capture code before `83dd866`.
- The companion's 20 MMD alpha scenarios include four soft-copy cases; `soft_only` and `soft_late`
  fail on R7-A's code.

## Field install

FIELD

## Open issues

- The exit report cannot appear for a power loss, a killed observer or a failure before the observer is ready.
- Alpha below the 0.5 cutoff keeps Remix's stochastic blend (a dither on large flat areas).
- Cosmetic glass contacts can still be missed beyond the documented caps (32 regions, 96 bodies, sweep caps).
- The falling-glass frame cost is unchanged by request ("leave it for now").
