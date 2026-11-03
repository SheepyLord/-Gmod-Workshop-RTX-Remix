# 0102: Character PBR maps stay preloaded

- Status: Accepted 2026-11-03
- Decided by: the user's rule for R13's memory work, "visible quality unchanged"
  ([R13-plan.md](../handover/R13-plan.md)), applied to the A/B measured in
  [R13-P](../handover/R13-P-report.md)
- Builds on: [0100](0100-one-copy-and-idle-release-of-game-textures.md) (patch 0026: undrawn preloads
  give way under real VRAM pressure)

## Context

A Remix material with `preload_textures = 1` loads every mip of every map when the mod loads, drawn or
not, and keeps it pinned. rpai writes the flag on every material, the fixes' ToPBR on game-map
materials without a replaced albedo, the material editor by default. In the field the mods preload
11.05 GB of files, 8.50 GB of them rpai's `ai_pbr` (R13-B). Without the flag a map starts at its five
smallest mips and sampler feedback loads what the screen needs once the material is drawn, so the
characters nobody spawns would cost nothing.

R13-P measured both on the PoC: the same four characters, the same spawn points and cameras, three
sessions each.

- **Memory.** Streaming held 2.23 GB less of replacement textures at idle (2.66 to 0.43 GB), 1.64-1.71
  GB less driver VRAM and 1.70 GB less private bytes; the working set did not change.
- **The settled image is the same.** Final images and the roughness, shading-normal and
  base-reflectivity views differ between the variants about as much as between two sessions of one
  variant, and only along edges.
- **Every first appearance is visible.** A streamed character appears with its maps' smallest mips:
  at the stand-in's crossfade Robin's emblem is a flat grey shape and her bodice plain; at +138 ms the
  bodice is still smeared. The last upgrade lands 155-880 ms (10-50 frames) after the first draw, on an
  NVMe drive with the files in the file cache. A preloaded character is complete in its first frame.
- **Removing a character drops its maps at once** (1.39 GB within about 105 ms), so its next spawn pops
  in again.

## Decision

- rpai, ToPBR and the material editor keep writing `preload_textures = 1`. Existing mods are not
  migrated.
- Memory savings on character maps come from the runtime or from removing duplicates, not from the
  flag. Both need the user's go-ahead:
  - **Load a preload on its first draw** (a runtime patch): no load at mod start, every mip loaded in
    the frame that first draws the material, then pinned as today and released only under 0026's
    pressure rule. It keeps the look and moves the cost to a hitch at a character's first draw in a
    session (not measured yet).
  - **Duplicate mods** in the field: Evernight's and March 7th's maps and layers in `ai_pbr` and
    `pbr_evernight_march7th` are byte-identical (1.16 GB loaded twice); Robin's and Guinaifen's maps
    are identical but their layers differ (the R13-P report, section 5).

## Consequences

- Startup VRAM and commit keep the preloads: about 11 GB in the field, most of it characters not
  spawned. Under real VRAM pressure 0026 releases the undrawn ones, as before.
- ToPBR's reason in its source (`usda.cpp`: generated normals would have no sampler-feedback stamp to
  inherit) does not hold on this runtime: a material's stamp comes from its first replaced texture in
  albedo, roughness, metallic, normal order. Its flag stays for the reason above.
- A later runtime change to how preloads load has to pass the same A/B (the lab in the R13-P report).

## Alternatives considered

- **Stream every character map:** measured, visible at every first appearance and respawn.
- **Preload the albedo only, stream normal, roughness and metallic:** not measured. It would save
  about two thirds of the bytes, and the smeared shading at first draw would remain.
- **Stream, and hide a character until its maps are resident:** a runtime change to instance
  submission; the character would appear later than its spawn.
