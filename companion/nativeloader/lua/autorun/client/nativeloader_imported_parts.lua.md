# nativeloader_imported_parts.lua

R15 ([ADR 0104](../../../../../docs/decisions/0104-painted-shadows-and-solid-hair.md)). Client autorun
file that changes how two kinds of imported-character parts are drawn in RTX sessions, and nothing else.

**Painted shadows** (the user's item 43). Many MMD characters paint shadows as partly transparent
overlays: over the eyes (目影), under the fringe (发影), on the face or body (陰影). Path tracing casts the
real shadow there, so the painted one darkens twice. The rules in
[`painted_shadows.lua`](../../nativeloader/painted_shadows.lua.md) find them by name and by their
properties (Laevatain's `Moyin` and its unnamed black `Hair+`). The controller publishes the result as
`mmdhl.RenderHiddenParts(ent)`: a table `{[slot + 1] = true}` for the character's asset, or nil. The
Model Hotloader's `mmdhl.SyncMaterialState` reads it on its own interval (every 8 frames per character)
and leaves those parts out of what it sends to the native renderer. Bodygroups, networked state, saves,
dupes, the editor's part list and every file stay as they are.

**Solid hair** (the user's item 44). For a hair part that [`solid_hair.lua`](../../nativeloader/solid_hair.lua.md)
finds eligible (a hair name, an alpha channel, a texture, material alpha 1), the controller samples the
alpha of the part's generated texture (`materials/mmd/t/<hash>.vtf`, from the mounted asset archive):
the 80-byte header, then 32 rows per frame through `file.Open`, `Seek` and `Read`, never the whole file.
Shares are cached per texture. When the texture is solid by that module's rule, the part's public
material loses `MATERIAL_VAR_ALPHATEST` (256) and alpha-to-coverage, and its soft copy
(`mmdhl.softMaterials[asset].soft[slot]`, made at the part's first draw and looked for until it exists)
loses `MATERIAL_VAR_TRANSLUCENT` (2097152). The draws become opaque, so the runtime's MMD alpha category
([ADR 0081](../../../../../docs/decisions/0081-mmd-alpha-texture-category.md)) has no alpha state to act
on. Texture hashes, and so PBR replacements and eye-white aliases, do not change.

Each changed material keeps the flag it had and its alpha-to-coverage value; they are put back when
`nativeloader_solid_hair` is 0, outside RTX sessions, when the asset is re-imported or unloaded, and at
`ShutDown`. A material reloaded from disk gets its flag back and loses it again at the next check
(every 2 seconds per hair part). Only the one bit is set or cleared: other flags stay as they are.

## Settings and commands

| Name | Default | Effect |
|---|---|---|
| `nativeloader_hide_painted_shadows` | 1 | Leave painted shadows out of the draw. Menu: Rendering > Model outlines, "Hide painted shadows" |
| `nativeloader_solid_hair` | 1 | Draw measured hair solid. Menu: "Solid hair" |
| `nativeloader_imported_parts_status` | command | Prints, for each character on the map: its painted shadows (slot, name, kind, rule) and its hair parts (shares of clear, cut and partial texels, size, time taken, decision, whether it is applied) |

Both settings act only in RTX sessions: `mmdhl.UsesRemixPreview()` must be true (checked once a second).

## Bounds

- Only characters on the map (`mmdhl.Entities()`) are classified and measured; the library's metadata
  for characters never spawned is not.
- Painted shadows: one classification per asset (a few hundred string searches). A textured part that
  only its texture's file name could decide makes the controller read the asset's
  `data/mmd_hotloader/assets/<id>/manifest.json` once, at most one manifest per second and only up to
  8 MiB (`util.JSONToTable` in `pcall`). In the field library (2026-11-04) 15 of 159 models need it.
- Solid hair: at most one texture is being sampled, 32 rows per frame (a 256-square grid over the top
  mip); four hair parts are looked at per frame.

## Inputs and side effects

Reads `mmdhl.assets`, `mmdhl.softMaterials`, the mounted generated VTFs and asset manifests. Writes
nothing to disk. Changes only the `$flags` and `$allowalphatocoverage` of the public and soft materials
of measured hair parts, in memory. Tested by [`imported_parts_harness.lua`](../../../../../tools/tests/imported_parts_harness.lua.md).
