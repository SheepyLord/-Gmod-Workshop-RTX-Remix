# 0104: Painted shadows left out of the draw, and solid hair, for imported characters in RTX sessions

- Status: Accepted 2026-11-04
- Decided by: the user's items 43 and 44 ([R15 plan](../handover/R15-plan.md)); the user allowed
  "switching away from Alphatest if needed"

## Context

**Painted shadows.** Many MMD characters paint shadows as partly transparent overlays: 目影 over the
eyes, 发影 under the fringe, 陰影 on the face and body. Under path tracing the real shadow is cast there,
so the overlay darkens twice: a dark band over the eyes. Nothing hid them; the eye-white rules only
exclude them. Their names and styles vary (field library, 2026-11-04): untextured black at alpha
0.2-0.5 (Endfield, Wuthering Waves), a plain 黑.jpg or 灰.jpg (Star Rail), a region of the face or eye
atlas (まぶた影), an untextured grey (ホタル), and names without 影: Laevatain's `Moyin` (the pinyin of 目影)
and its unnamed black `Hair+`.

**Alpha on hair.** Every imported part's public material alpha-tests at 0.5 with alpha-to-coverage, and
the hotloader's soft copy blends a part's partly transparent triangles; in RTX sessions the runtime's
MMD alpha category ([ADR 0081](0081-mmd-alpha-texture-category.md)) makes opacity at or above 0.5 opaque
and leaves lower opacity blended or stochastic. Laevatain's hair texture keeps a mask in its alpha
inside the strands (clear 3.6 %, 9-127: 1.6 %, partial 5.0 %), so the hair shows see-through notches. The
user removed `$alphatest` from that material, and it looked right. ADR 0081 replaces the alpha-test
reference of categorized draws with the cutoff, so a lower reference on the material would not reach
the ray tracer: only a draw without alpha state is opaque.

## Decision

A companion client controller, `nativeloader_imported_parts.lua`, acting only in RTX sessions
(`mmdhl.UsesRemixPreview()`), for characters on the map:

1. **Painted shadows** are found by pure rules (`painted_shadows.lua`): by name (目影 and its variants,
   发影, 陰影, 面具影, the romanized `Moyin`, 影 standing alone, the word `shadow`, at most 3 % of the
   model's indices; 眼影 and `eyeshadow` only when dark, grey or painted from a dark image, because they
   also name make-up), and without a name when untextured, dark and see-through, or painted from a plain
   dark image, at most 0.5 % of the indices. Glasses and authored hidden parts never count.
   They are left out of the draw through a hook in the Model Hotloader's `mmdhl.SyncMaterialState`:
   `mmdhl.RenderHiddenParts(ent)` returns the slots to leave out. Bodygroups, saves, dupes, networked
   state and files do not change. `nativeloader_hide_painted_shadows` (default 1) turns it off.
2. **Solid hair** (`solid_hair.lua`): a hair part (hair names, without overlays and accessories) with an
   alpha channel and material alpha 1 has its texture's alpha sampled (a 256-square grid over the top
   mip, 32 rows per frame). When the texture has 10 % or fewer clear texels, 20 % or fewer partial ones,
   and at least 0.2 % below half, its public material loses `$alphatest` and alpha-to-coverage, and its
   soft copy loses `$translucent`: the user's fix, applied in memory. The flags are put back when
   `nativeloader_solid_hair` (default 1) is 0, outside RTX, on re-import or unload and at shutdown.

## Consequences

- Laevatain's eyes lose the dark band and its hair is solid; Endfield hair (JEPT, Yvonne) is solid too.
  Hair whose alpha cuts strands out of the texture, whose alpha is binary, or that is see-through on
  purpose keeps the alpha test and the soft copy.
- A few other models' hair with partial alpha below half becomes solid as well (Tda式初音ミクV4X's twintail
  ends, 芙提雅, 薇薇安): their fades become opaque. One checkbox turns the rule off for every character.
- Texture hashes stay, so PBR replacements, imported game PBR and eye-white aliases are unaffected.
- The hotloader gains a seven-line, `pcall`-guarded hook; without the companion it behaves as before.
- The render guard's exact bundled-path table lists the three new companion files.
- No per-part manual choice: a part the rules miss can still be hidden with its bodygroup, and a wrong
  one shown by turning the setting off. The field library's 6,684 parts gave no false positive.

## Alternatives considered

- **A lower alpha-test reference** (keep holes for clear texels only): ADR 0081 replaces the reference
  of categorized draws with the 0.5 cutoff, so it would not reach the ray tracer without a runtime change.
- **A runtime rule or a per-texture "opaque" category**: needs a fork rebuild, and the build trees of
  earlier rounds are gone; the in-memory material flags give the same opaque draw.
- **Hiding painted shadows by bodygroup**: changes saves, dupes and multiplayer state; the user asked
  for automatic hiding in RTX sessions, where the real shadows replace them.
- **Names only**: misses `Moyin`, `Hair+` and unnamed overlays; properties only: misses the atlas-painted
  ones (まぶた影) whose colour comes from the face texture.
