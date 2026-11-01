# C16-A: scene-adaptive emission in the runtime

Read [AGENTS.md](../../AGENTS.md), [C16-plan.md](C16-plan.md) and [runtime/README.md](../../runtime/README.md)
first. Work in `out\worktrees\c16-runtime` on branch `c16-runtime`.

## Build

Add a runtime patch (`runtime/patches/0016-...`, on top of 0015) that implements the plan's decision:

1. **The adapted luminance.** Make the auto exposure's adapted scene luminance (the geometric-mean
   Yf behind `exposure = targetAdaptedYf / (adaptedYf + noise)`, `auto_exposure.comp.slang`) available
   to the shaders that evaluate opaque materials: either bind it to those passes, or read it back on
   the CPU with a small fixed latency and put it in the raytracing constant buffer. Choose and say
   why; a frame or two of latency is fine (the exposure adapts over 0.15-0.75 s). With auto exposure
   off, use `rtx.adaptiveEmission.fallbackLuminance` (pick and document a default).
2. **The material input.** `emissive_adaptive_intensity` (float, 0..65504, default 0) for opaque
   materials: in the X-macro table of `rtx_material_data.h`, packed for the GPU in `rtx_materials.h`
   (use a free slot or flag bit; grow the layout only if nothing is free, and say what you chose),
   decoded in the shader and applied where `emissiveRadiance` is computed
   (`opaque_surface_material_interaction.slangh:948`, and any other opaque emissive evaluation you
   find). When the input is above 0 and the feature is on, it replaces `emissive_intensity`:
   `emissiveColor x emissive_adaptive_intensity x rtx.adaptiveEmission.scale x clamp(L_adapt, min, max)`.
   Keep the emissive blend override's influence as today.
3. **Options** (`RTX_OPTION`, documented like the others): `rtx.adaptiveEmission.enable` (true),
   `rtx.adaptiveEmission.scale` (1.0), `rtx.adaptiveEmission.minLuminance` and `maxLuminance`
   (clamps, documented defaults), `rtx.adaptiveEmission.fallbackLuminance`.
4. **Observability.** Log the adapted luminance and the exposure at camera cuts and every five
   minutes (an additive field in T4's `[RTX Memory]` line is fine, or a line of its own), so a value
   can be checked against a frame during tuning.
5. **Material definition.** If the runtime package ships the MDL that USD materials reference
   (`AperturePBR_Opacity.mdl`), declare the new input there with its default and description; say
   what you found.

## Tests and import

- Unit tests for the packing (round trip with and without the input) and the emission formula
  (feature on/off, input 0, clamps, fallback). Runtime unit tests pass.
- Rebuild once with `runtime\build_runtime.ps1` (the verified Release configuration), import only the
  changed runtime files with `tools\inputs.py import runtime` (mind the Git LFS quota), check
  `python tools\build_package.py --require-nlctl`, run `tools\test.ps1 -Config Release`.
- Docs: `runtime/README.md`, a new ADR `docs/decisions/0067-scene-adaptive-emission.md` (and its row
  in `docs/decisions/README.md`), facts with file:line in `docs/RESEARCH.md`, `docs/TESTING.md`, a
  CHANGELOG line under `## [Unreleased]` in a section `### C-16 (unreleased)`.

## Rules

Only this worktree and your clones under its `out\`. Never change the user's fork at
`H:\BACKUP_20260815\Modding\dxvk-remix-gmod` (read it freely). Never launch Garry's Mod (Claude tests
in the game). Never touch the field or PoC install, Steam's files or any `user.conf`. Never push,
merge, tag or commit on `main`. No downloads. Shared docs get additive edits only.

Your final message is your report: the design choices (luminance delivery, packing), files and
commits, the build identity and DLL hash, tests and results, the exact import command, anything not
done and why.
