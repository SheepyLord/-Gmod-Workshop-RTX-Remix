# R7-A: MMD alpha under Remix (brief)

Read [AGENTS.md](../../AGENTS.md), [R7-plan.md](R7-plan.md), [runtime/README.md](../../runtime/README.md),
[ADR 0047](../decisions/0047-ignore-incompatible-model-outlines.md) and [ADR 0048](../decisions/0048-layered-alpha-cutouts.md).
Work on branch `r7-alpha` in `out/worktrees/r7-alpha`. Owns: `runtime/**` (a new patch and its records),
`companion/**`, `tools/qa/alpha_probe.lua` and new QA probes, a new ADR, additive edits to CHANGELOG,
ROADMAP, RESEARCH, TESTING, COMPONENTS. Does not touch `loader/**`, `glass/**`, `packages/**` (Claude imports
the rebuilt `d3d9.dll`), `skills/**`.

## The problem and what Claude measured (PoC, 2026-11-01)

The user: transparent materials render black (their shadow, no colour); example: Columbina's `眼罩` mask, a
Model Hotloader character. "It is not sure whether alphatest is required if we are in Remix; could we use
translucent or a better Remix-managed alpha, since everything in this project runs in Remix. Find the best
way to implement alpha (we had a few rounds on this alpha problem before)."

- Columbina's mask texture: lattice bars alpha 166 (0.65), diamond panes alpha 66 (0.26), clear texels 0.
  In MMD and in the hotloader's preview: white bars, see-through holes.
- Under RTX Model Hotloader draws each part `VertexLitGeneric` with `$alphatest 1`, `$alphatestreference .5`,
  `$allowalphatocoverage 1`; triangles with partly transparent texels ("soft", `mmdhl_soft_alpha`) are drawn
  blended instead (`$translucent 1`, in the opaque pass, `packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_render.lua`).
- GMod RTX runs Source's fixed-function shaders (`VertexLitGeneric_DX7`, `UnlitGeneric_DX6`; probe output).
  `tools/qa/alpha_probe.lua` with a 16-band alpha ramp (`out/qa-poc/r7/04-ramp` in the main checkout) shows:
  alpha-tested lit materials cut at about 0.7 whatever `$alphatestreference` says (Source's DX7 path sends a
  fixed reference; `d3d9_rtx_utils.cpp` `setLegacyMaterialState` takes `D3DRS_ALPHAREF`); blended materials are
  opaque only above `rtx.stochasticAlphaBlendOpacityThreshold` (0.79 in `packages/runtime/layers/classic_remix_defaults.conf`)
  and a stochastic dither below.
- Why the mask vanishes yet shadows the face: a blended opacity in (transparency threshold, stochastic
  threshold] is skipped by primary rays (`shaders/rtx/algorithm/resolve.slangh`, the stochastic early out)
  and left to the stochastic composite, while visibility rays attenuate by `1 - opacity`
  (`shaders/rtx/algorithm/visibility.slangh`). Run `03-columbina`: no mask, a lattice-shaped shadow.
- With a temporary root `rtx.conf` setting that threshold to 0.5 (`05-columbina-thr05`) the mask renders as
  white bars with see-through holes and faint panes, as in MMD. Changing the global threshold would also make
  every other blended surface between 0.5 and 0.79 opaque (map glass, props) and depart from the classic
  settings (R2), so the fix must apply to Model Hotloader materials only.

## What to build

1. **A runtime patch** (the next number in `runtime/patches`, recorded in `runtime/README.md` and `base.json`'s
   flow): a texture category, for example `rtx.mmdAlphaTextures`, whose draws use MMD alpha semantics: an
   alpha test uses reference 0.5 (an option, default 0.5) instead of the draw's `D3DRS_ALPHAREF`, and a blended
   opacity at or above that cut becomes fully opaque (primary, visibility/shadow, indirect, opacity
   micromaps consistent), below it the existing blend/stochastic path stays. Other draws are unchanged.
   Follow how existing categories are declared, hashed into draws and invalidated; respect ADR 0048's
   traversal rules and the cached BLAS flags.
2. **The companion fills the category at runtime** with the Remix hashes of Model Hotloader textures (its
   generated `mmd/...` materials and the soft copies bind the same base textures), as NoSave options joined
   with whatever the user has, the way `companion/nativeloader/lua/autorun/client/nativeloader_model_layers.lua`
   handles outline hashes (`RemixMaterial.GetAllTextureHashes`, `RemixConfig.SetConfigVariable`); late-loaded
   textures included; cheap; a translated RTX-tab opt-out only if you find a real need.
3. Decide, with evidence, whether the hotloader's own Remix-path choices (blended soft triangles, alpha-tested
   parts) still need anything once the category exists; that add-on lives in `packages/model-hotloader` as an
   imported part, so describe any change it would need instead of editing it.

## Tests, build and report

Runtime unit tests where the fork has them, companion Lua tests, `tools\test.ps1 -Config Release`. Build the
runtime with `runtime\build_runtime.ps1 -Fork H:\BACKUP_20260815\Modding\dxvk-remix-gmod -NoImport` and leave the
built `d3d9.dll` path in your report; Claude imports and runs the game QA (the mask, the ramp plates, map glass
unchanged). Commit on `r7-alpha` (no push, merge, import, game install change or Workshop update). Report in
`docs/handover/R7-A-report.md`.
