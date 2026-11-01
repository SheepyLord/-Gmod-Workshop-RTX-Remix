# R8: the user's report of 2026-11-01, after R7 (plan)

The user's request, after R7 was published (`0.0.0-dev.20261101124815+39da503d`, loader 0.12.0):

1. **(Severe)** Since the alpha fix, characters show strong rendering noise that changes every frame.
   It is visible with DLSS off and very obvious with DLSS on (two screenshots from the field session:
   two Model Hotloader characters lying on a floor, the noise on the legs).
2. **(High)** C-13 is incomplete: GShader Library (Workshop 3542644649) "still crashes the game or
   causes instability and errors" on a tester's computer. Reinvestigate vanilla add-on compatibility:
   graphics add-ons such as Quick Bloom/HDR (2811767286), Real CSM (2817072898), Life Mod: Advanced
   Graphic Settings (1837527967), GShader Library and its collection 3728139288, and custom DX11 shader
   APIs (LUX), must not fail a map load or the game under RTX.
3. **(Low)** The frame cost while lots of glass falls at once (left alone in R7): investigate and
   resolve; a smart mitigation is fine.
4. **(Low)** Glass collision levels like the MMD physics; by default no collision with living entities
   (players, NPCs).
5. **(Low)** Shooting fractured glass with bullets, or hitting it with a crowbar, does not break it further.

Standing permissions (the user, 2026-11-01): close, launch and update the PoC and the field game without
asking; decide with Codex instead of asking; push `main` and update the Workshop when done.

## 1. Character noise (Claude)

Measured on the PoC with Remix's "Primary Alternate Disocclusion Threshold" debug view
(`DXVK_RTX_DEBUG_VIEW_INDEX=128`; white where the denoisers discard history), Robin lying face up:

| Run | Runtime | Companion | History discarded on the character |
|---|---|---|---|
| `03-noise-mask-g1` | G1 (before R7) | G1 | none |
| `01-noise-mask` | R7 | R7 (tags all hotloader textures) | the whole character (37 % of the frame) |
| `04-noise-mask-notrack` | R7 | stopped before the spawn | none |
| `05-noise-mask-trackonly` | R7 | stopped; Robin's 166 materials tracked, nothing tagged | none |
| `06-noise-mask-tagonly` | R7 | stopped; Robin's 15 texture hashes tagged | the whole character |

Cause: runtime patch 0017 marks an instance's material as changed when its MMD alpha state differs from
the instance's stored alpha state. That state is also written by `mergeInstanceHeuristics` for a later draw
in the same frame, and a new instance starts untagged; `hasMaterialChanged` makes the geometry resolver
discard DLSS-RR history (and use the alternate disocclusion threshold without RR) for every pixel of the
character, every frame. Patch 0018 compares the first draws of consecutive frames through a per-instance
key and never flags an instance seen for the first time; the fork's unit test covers the decision.

## 2. Vanilla add-on compatibility (R8-C, Codex)

PoC run `07-gshader` (gm_construct, RTX, single player) with GShader Library, its FXAA, SSDO and SSR
effects and NikNaks: the map loads and the game quits normally on this machine, but the render guard
rejects `worldpos.lua:27` (`GetRenderTargetEx`, "unknown image format") by raising an error inside the
add-on's Initialize hook, which players see as a Lua error, and the engine logs a run of "Failed to create
shader". The tester's crash is not reproduced here. Brief: [R8-C-addon-compat.md](R8-C-addon-compat.md).

## 3-5. Glass (R8-G, Codex)

Brief: [R8-G-glass.md](R8-G-glass.md).

## Integration

On `r8-int`: the runtime import (patch 0018), both Codex branches, PoC QA (the noise probe with and
without DLSS; the add-on sets; the glass QA), the full suite, merge into `main`, push and publish, then
the field install. ADR numbers: R8-G 0085, R8-C 0086.
