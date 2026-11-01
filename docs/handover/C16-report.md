# C-16: steady eye-white brightness (report)

The user's request (2026-10-31): anime characters' eye whites, which the PBR packs give a little
emission, turn over-dark or over-bright when the light changes, which does not suit their style;
research and implement a solution (three screenshots of Robin: grey eye whites in daylight, glowing
ones in a dim warm scene). Plan and design: [C16-plan.md](C16-plan.md). Codex (`gpt-6.1-sol`, effort
max) wrote the runtime and the content side in two parallel tasks; Claude reviewed them, integrated,
measured and tuned in the game, and rebuilt the character packs.

## The cause

A fixed emission is shown multiplied by auto exposure: in a dark scene the exposure rises (up to the
package's cap of 16) and the eye white glows beside dimly lit skin; in a bright scene the exposure falls
and the emission's lift vanishes, leaving eye whites that the eyelids shade grey. Path tracing shades
the recessed eye; anime shading does not.

## What was built

| Task | Brief | What it does | Review |
|---|---|---|---|
| C16-A | [C16-A-runtime.md](C16-A-runtime.md) | Runtime patch 0016: opaque materials may carry `emissive_adaptive_intensity`; above 0 their emission is `emissive color x value x scale x adapted scene luminance` (auto exposure's mean, read back without stalls), so it stays steady on screen while the exposure is free and fades once it is capped; options `rtx.adaptiveEmission.*`, `[RTX Adaptive Emission]` log lines ([ADR 0067](../decisions/0067-scene-adaptive-emission.md)) | Claude: the value is packed into spare bytes of the 64-byte material record losslessly (the DLSS mask's alpha byte is a constant `0xff` in this fork, the invalid subsurface index fits 24 bits); every reader uses the new accessors; 28/28 runtime unit tests |
| C16-B | [C16-B-content.md](C16-B-content.md) | rpai writes the input for eye materials as `fallback x R`; `set_adaptive_emission.py` migrates published packs byte for byte; character packaging verifies the inputs survive ([ADR 0068](../decisions/0068-adaptive-eye-emission-publishing.md)) | Claude: matches the plan; the provisional `R` was the open number |

Integration (`c16-int` in `out\worktrees\c16-int`), by Claude:

- [`tools/qa/eye_white_probe.lua`](../../tools/qa/eye_white_probe.lua.md): spawns a Model Hotloader
  character, frames its face from above and shoots noon, golden hour, dusk and night. Client Lua may
  not run `lua_run`, so the player is placed with a `--console` line, which makes every run frame the
  character in the same pose and light (the map's random spawn points had changed both).
- [`tools/qa/eye_white_patches.py`](../../tools/qa/eye_white_patches.py.md) with
  [tests](../../tools/tests/test_eye_white_patches.py.md): the eye white's linear luminance over the
  cheek's in fixed boxes.
- The tuned default `R = 25` in rpai, its documentation and tests
  ([ADR 0069](../decisions/0069-tuned-adaptive-eye-emission.md), superseding 0068's provisional value).

## Measurements (PoC, Robin)

The eye white's luminance over the cheek's; about 1 is the anime look
([TESTING.md](../TESTING.md#project-manager-gpu-acceptance-2026-10-31-claude-poc)):

| | noon | golden hour | dusk | night | lamp-lit room, day / night |
|---|---|---|---|---|---|
| fixed emission (before) | 0.69 | 0.52 | 0.88 | 46 | 0.79 / 0.84 |
| `R = 1/0.18` (provisional) | 0.62 | 0.61 | 0.48 | 0.31 | |
| **`R = 25` (shipped)** | **0.98** | **1.38** | **0.77** | **0.70** | **1.04 / 1.04** |

The night glow is gone and in the dark the eye white stays below the cheek, as the plan requires. The
room and noon are in the plan's band of 0.85-1.05; golden hour (the face in shade while the frame is
lit) and dusk (a low sun on the cheek, not in the recessed eye) are not: the emission follows the
frame's average light, the cheek its own, and one value per material cannot tell them apart. 25
keeps the worst case smallest. Comparison sheets: `out/qa-poc/c16/sheet-fixed-vs-v15.png`,
`sheet-room.png`.

## Packs

Rebuilt from their last builds in `out\packages\<name>` with `set_adaptive_emission.py --multiplier 25`
(the old archives and layers are kept in each folder's `pre-c16`); only `native/manifest.json` and the
model layers changed, and `check_pack.py --deep` gives the same warnings as before:

| Item | Package | Change | State |
|---|---|---|---|
| 3829892354 | `robin-rtx` `0.0.0-dev.202611010515+3a6d9e61` | Robin's three face materials 0.6 -> input 15; the archive's description brought up to the current rules (it now names the RTX package and says GMod cannot mount the item) | uploaded 2026-11-01 (`gmpublish update`, hidden; Steam sent 2.9 MB of changed content) |
| 3830769477 | `evernight-march7th-rtx` `0.0.0-dev.202611010518+103fde9b` | Evernight 0.6 -> 15, March 7th 0.04 -> 1 | uploaded 2026-11-01 (hidden; 2.4 MB) |
| 3829348717 | `guinaifen-rtx` | two face materials 0.6 -> 15 | waits for the user: `check_pack.py` refuses its older display name `Guinaifen (桂乃芬)` (the ASCII-name rule from R5) |

The RTX package with the runtime went to 3829070317 with the merge (`0.0.0-dev.20261101052452+2768a059`,
the content digest tested on the PoC). Players get both at the next start after Steam has fetched them.

On the field install, rpai's own `rtx-remix\mods\ai_pbr` also holds Evernight's and March 7th's layers
(fixed emission, 0.6 and 0.04). Remix takes a material from the first mod that has it, and `ai_pbr`
sorts before `pbr_evernight_march7th`, so there those two keep the fixed emission until `ai_pbr` gets
the input too (a field change, for the user to ask for). Robin and Guinaifen are only in their packs.

## Tests

- C16-A: 28/28 runtime unit tests; C16-B: 17 tests; integration: the 8 new measurement tests and the
  updated content tests (25 in the two files).
- `tools\test.ps1 -Config Release` on `c16-int`: repository conventions, 24/24 CTests and 401 Python
  tests (348 tools, 28 gmapack, 25 Steam; two existing skips).

## Open issues

- Outdoors by day the band is 0.77-1.38. Closing it needs a signal local to the eye, such as the light
  the face receives; nothing in the runtime offers that today.
- `adapted_yf` is each frame's mean while the exposure is smoothed (tau 0.15-0.75 s): moving between a
  bright and a dark place briefly brightens or dims the eye whites before the exposure settles.
- The log records cuts and every five minutes only, so a sky change inside a session has no record.
- Not covered in the game: Source eyes, decals, an emissive-blend or SSS material with the input, auto
  exposure off (C16-A's unit tests cover their formula and packing).
- A character whose eyes are drawn or built differently from Robin's may want its own level
  (`--emissive-adaptive-intensity`, or `--multiplier` on a published pack).
