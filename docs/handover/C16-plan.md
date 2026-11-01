# C-16: steady eye-white brightness (plan)

The user's request (2026-10-31):

> Implement a solution to the eye white texture's brightness problem. Eg. maybe an environment light
> adaptive emissive or something else at your choice. [...] The eye white region of the character
> could be over dark and over bright when the environment light has changes, which does not ensemble
> the style of these characters.

Claude is the project manager; Codex (`gpt-6.1-sol`, effort max, Fast tier) writes the code in two
tasks; Claude reviews, integrates, measures in the game and publishes.

## Findings

- **How the eye whites emit today.** The PBR packs made with [`mmd-remix-pbr`](../../skills/mmd-remix-pbr/SKILL.md)
  give an anime face sheet one emissive map: the albedo times a class weight (eye white 0.025, iris
  0.04, catchlight 0.6; [standards](../../skills/mmd-remix-pbr/references/standards.md)), with
  `emissive_intensity` re-levelled at publish time (Robin's pack, `pbr_robin`: 0.6). The standards
  already name the conflict: emission lifts the eye white out of the socket's grey to just under the
  cheek, and "more would glow in dark maps, because auto-exposure lifts emission relative to lit skin".
- **Why no fixed value works.** The runtime's auto exposure (`src/dxvk/rtx_render/rtx_auto_exposure.h`,
  `src/dxvk/shaders/rtx/pass/tonemap/auto_exposure.comp.slang:144-165` in the patched tree) sets
  `exposure = targetAdaptedYf / (adaptedYf + noise)`, capped at `rtx.autoExposure.maxExposure` (16 in
  the package). A fixed emission L is shown as exposure x L. In a dim scene the exposure is high and
  the eye white glows (the user's warm screenshot); in a bright scene the exposure is low, the
  emission vanishes next to the lit skin, and the eye white shows the socket's shadow (grey: the
  user's other two screenshots, Robin, 2026-10-31).
- **Where emission is computed.** Opaque materials: `opaque_surface_material_interaction.slangh:948`,
  `emissiveRadiance = emissiveBlendOverrideInfluence * emissiveColor * emissiveIntensity`. Material
  inputs are read from USD by name through the X-macro table in `rtx_material_data.h` and packed for
  the GPU in `rtx_materials.h`. The runtime's eye shading (`rtx.eye.*`) applies only to Source
  eyeballs, not to MMD eye meshes.

## Decision: scene-adaptive emission

A new optional opaque-material input, `float inputs:emissive_adaptive_intensity` (default 0, off).
When it is above 0 (and `rtx.adaptiveEmission.enable` is on), the material's emission is
`emissiveColor x emissive_adaptive_intensity x L_adapt` instead of `emissiveColor x emissive_intensity`,
where `L_adapt` is the auto exposure's adapted scene luminance (the geometric-mean Yf the exposure is
computed from; scene-referred).

- While the exposure is within its cap, exposure x L_adapt is about `targetAdaptedYf`, so the
  emission's contribution on screen is the same in a bright scene and a dim one: the eye white keeps
  a steady light floor instead of glowing in the dim and greying in the bright.
- Once the exposure is capped (very dark scenes), the emission fades with the scene: no glowing eyes
  in the dark.
- A runtime without the feature ignores the input and uses `emissive_intensity` as today, so packs
  keep working with older RTX packages.

Alternatives considered and left as follow-ups: a per-material offset that lets shadow and indirect
rays ignore close occluders (the eye white would be lit like an unoccluded surface; touches every
visibility path), and a screen-space floor relative to the nearby skin (needs material masks after
DLSS ray reconstruction).

## Tasks

| Task | Brief | Branch / worktree |
|---|---|---|
| C16-A runtime | [C16-A-runtime.md](C16-A-runtime.md) | `c16-runtime` in `out\worktrees\c16-runtime` |
| C16-B content | [C16-B-content.md](C16-B-content.md) | `c16-content` in `out\worktrees\c16-content` |

Then Claude: integrate on `c16-int`, measure on the PoC, tune the default, update the character packs
and publish.

## Acceptance (in game, PoC, Robin's pack)

- Eye white against the cheek, measured on fixed patches as the skill's A/B protocol does: within one
  band (about 0.85-1.05 of the cheek) in a bright outdoor scene, a dim interior and at night.
- In a dark scene the eye white is never brighter than the cheek.
- The runtime log reports the adapted luminance it uses, so a value can be checked against a frame.
