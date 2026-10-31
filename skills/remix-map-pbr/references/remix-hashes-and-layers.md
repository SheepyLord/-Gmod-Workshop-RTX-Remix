# Texture hashes, mod layers and what the runtime accepts

## The hash

Remix replaces a material by the hash of the game texture a draw binds. In this user's setup that hash is
XXH64 of the texture's top mip as uploaded, because `rtx.useObsoleteHashOnTextureUpload = True`. The RTX
package sets it in its `classic_remix_defaults.conf` layer; the runtime's own default is False, a
different scheme. A mod built for one scheme does nothing under the other: the user's two old blood mods
never applied for that reason (found by reading the hashes back in game, 2026-10-27).

What gets hashed:

- **DXT1/3/5:** the top mip's blocks exactly as stored in the VTF (they are uploaded unchanged). Nearly every
  map texture is DXT, so prediction is exact.
- **BGRA8888:** the stored bytes (the tag textures).
- **Animated textures:** every frame is its own texture and hash (the animated water normal gave 29 hashes on
  gm_poolrooms).
- **Opaque 24-bit uploads (X8R8G8B8):** the old runtime hashed a pad byte holding leftover memory, so the
  same sheet could hash differently between sessions. Runtime builds from 2026-10-26 20:20 on hash with the
  pad bits zeroed (deterministic); this repository's packaged runtime includes that change. Map textures
  are rarely affected; characters were.

## Predicted hashes

`tex_jobs.py` reads each VTF's top mip (the smaller mips are stored first, then frames, faces and depth
slices) and hashes it, for every frame. Results:

- modern_house: 106 of 110 predictions matched the live game exactly (2026-10-27);
- Backrooms: predictions verified in game for the DXT formats (5 of 5 checked);
- gm_poolrooms: offline hashes matched the live ones for every surface handled.

A prediction is wrong when the game uploads another copy of the texture than the one you hashed: a texture
path that the base game or another mounted addon also provides. On modern_house HL2's `lights/white`,
`lights/white002`, `lights/white003` and two de_elysion metals (`models/de_elysion/metal/metal_01`, `_03`)
hashed differently in game.

## Live hashes

- **gmRTX's Lua API:** `RemixMaterial.GetAllTextureHashes(<material name>)` returns the hashes Remix
  computed for the textures the game uploaded for that material. It knows only textures already drawn:
  load the map and look around (all regions) first. `live_hashes.py` runs it for every inventoried
  material and writes `work/live_hashes.json`; `tex_jobs.py` then adds the live hashes that are not another
  texture's prediction.
- **The debug module** (`gmcl_rtxdebug_win64.dll`, addon `rtx_debug`): `Remix.TrackedTextures` gives
  `{material, texture, hash}`; it needs single player, `-insecure` and `sv_cheats 1`.
- **gmRTX's categorisation:** `MaterialPipeline.AutoCategorisation.ExportHashes(file)` writes the decal list.
  gmRTX's smart-mark puts every world texture in `rtx.decalTextures` (3,862 hashes on gm_poolrooms); a
  `-0x...` entry in such a list means "removed".

Category bits (`RemixMaterial.SetHashCategory(hash, flags)` adds to what the hash has; `RemoveHashCategory`
clears all; `GetHashCategory` reads): 1<<2 sky, 1<<3 ignore, 1<<9 hidden, 1<<10 particle, 1<<12 decal
(DecalStatic), 1<<18 animated water. To toggle one for a test, read the flags, change them, and restore
with `RemoveHashCategory` then `SetHashCategory(original)`: a "restore" with `SetHashCategory` alone left the
pool floor hidden in the user's game (2026-10-26).

## When a hash does not match, or changes

| Cause | Example | What to do |
| --- | --- | --- |
| Another mounted copy of the texture path | modern_house's `lights/white*`, de_elysion metals | live hashes, merged by `tex_jobs.py` |
| A different hash scheme | the old blood mods | check `rtx.useObsoleteHashOnTextureUpload` where the mod will run |
| The draw binds another slot than you tagged | the Water shader hashes `$normalmap`, not `$basetexture` | tag the slot the shader binds; read the live hash back |
| A tag texture created after the game mounted content | Modern House's mirror tag resolved to `vgui/white` | bind it at runtime with `SetTexture`; it also works after a restart |
| The texture changed | a map update, a replaced VTF reloaded | extract again, rerun `tex_jobs.py` and `build_mod.py` |
| Opaque 24-bit re-uploads (old runtime) | rpai's characters; Source re-uploaded textures about 13 times on gm_poolrooms | fixed in the 1.6.1-merge builds; re-check hashes after any runtime change |

## Checking that the replacements apply

- Report the counts: textures, predicted, matched live, live-only, left without a replacement and why.
- Flip the mod in the running game from the same camera: `stock.py on`/`off` (it also takes the addon out)
  or `RemixConfig.SetConfigVariable("rtx.enableReplacementMaterials", "False")` and back to `"True"`.
- Roughness overrides that are hard to see in shading show in Remix debug view 89 (primary perceptual
  roughness): with the debug module under `sv_cheats 1`, `Remix.SetDebugView(89, 0)`, undone with
  `Remix.RestoreConfig("rtx.debugView.debugViewIdx")` (used for character hair, 2026-10-26).
- A surface still unchanged after a correct hash: another mod that sorts earlier replaces the same hash
  (below).

## The mod folder

```
rtx-remix/mods/<map>_rtx/
  mod.usda          root layer; rewritten atomically on every build
  materials.usda    the replacements
  textures/         <texture with / as __>_<kind>_<sha1 of the PNG, 10 hex>[p].<a|n|r|m|h|e|t>.rtex.dds
```

### `mod.usda`

A USD 1.0 layer whose metadata carries `customLayerData` with `lightspeed_game_name` "Garry's Mod (x64)",
`lightspeed_layer_type` "replacement", `lightspeed_mod_name` and `lightspeed_mod_version`, plus
`metersPerUnit = 0.01`, `upAxis = "Z"`, `timeCodesPerSecond = 24`, and `subLayers` listing `./materials.usda`
(after `./lights.usda` or `./meshes.usda` when they exist; an earlier sublayer is stronger). The runtime
watches this file's timestamp.

### `materials.usda`

A hierarchy of `over` prims: `RootNode` → `Looks` → one `mat_<HASH>` per texture hash (16 upper-case hex
digits, no `0x`) → `Shader`. Schematically:

```
over "RootNode" { over "Looks" { over "mat_0123456789ABCDEF" { over "Shader" {
    <source asset: AperturePBR_Opacity or AperturePBR_Translucent>
    <one input per map and constant>
} } } }
```

| `Shader` attribute | Type | Notes |
| --- | --- | --- |
| `info:mdl:sourceAsset` | uniform asset | `@AperturePBR_Opacity.mdl@` or `@AperturePBR_Translucent.mdl@`, the runtime's built-in MDLs |
| `info:mdl:sourceAsset:subIdentifier` | uniform token | the same name without `.mdl` |
| `inputs:preload_textures` | bool | 0 to stream (Modern House and Backrooms, GBs), 1 to preload (poolrooms, 150 MB) |
| `inputs:diffuse_texture` | asset, `colorSpace = "auto"` | the albedo DDS as `@./textures/<file>@`; `@@` authors it empty, which a constant diffuse needs |
| `inputs:normalmap_texture` | asset, `raw` | octahedral BC5; `int inputs:encoding = 0` |
| `inputs:reflectionroughness_texture`, `inputs:metallic_texture` | asset, `raw` | BC4 |
| `inputs:height_texture` | asset, `raw` | BC4 with max-filtered mips; `float inputs:displace_in` (depth over one texture repeat), `displace_out` |
| `inputs:emissive_mask_texture` | asset, `auto` | BC7; with `bool inputs:enable_emission`, `float inputs:emissive_intensity` |
| `inputs:transmittance_texture` | asset, `auto` | translucent materials |
| constants | bool, int, float, color3f | `reflection_roughness_constant`, `metallic_constant`, `diffuse_color_constant`, `emissive_color_constant`, `ior_constant`, `thin_walled`, `thin_wall_thickness`, `transmittance_color`, `transmittance_measurement_distance`, `use_diffuse_layer`, `sprite_sheet_rows`, `sprite_sheet_cols`, `sprite_sheet_fps`, `use_legacy_alpha_state`, `blend_enabled`, `blend_type` |

### Textures

| Kind | Suffix | NVTT format | Colour space |
| --- | --- | --- | --- |
| albedo | `.a` | BC7, gamma-correct mips | auto (sRGB) |
| normal | `.n` | BC5 | raw |
| roughness, metallic | `.r`, `.m` | BC4 | raw |
| height | `.h` | BC4, max mip filter | raw |
| emissive, transmittance | `.e`, `.t` | BC7, gamma-correct mips | auto |

Content-named files are never overwritten while the runtime holds them open; the next build prunes unused
ones. Albedo keeps an alpha channel only for translucent or alpha-tested materials.

## What this runtime accepts in USD

The runtime is the user's dxvk-remix-gmod fork on `c6b48ed1` with the remix-1.6.1 merge (this repository's
`runtime/base.json` and patches; the user's install since 2026-10-25). Its log still says
`remix-main+c6b48ed1`, because the version string comes from that commit.

- **Colour inputs load** (`color3f` constants for materials and lights). `rtx.usd.legacyIgnoreColors`
  (default False) brings back the old fork's behaviour of ignoring them. The older build `384581b1` (before
  2026-10-25) rejected every three-component input ("has unexpected type, using default value") and never
  loaded `alpha_test_type` or `blend_type`; rpai's notes (`mmd-remix-pbr/references/runtime-notes.md`) still
  describe that build, and rpai writes only bools, floats and textures. The map pipelines write colours and
  need a runtime that loads them.
- **Colour constants are decoded as sRGB.** Pass sRGB values (the pipelines' `overrides.json` and
  `materials.json` are sRGB). Linear kelvin colours passed as constants rendered warmer than meant
  (gm_poolrooms' window and panel glow, 2026-10-26).
- **A bound emissive texture replaces the emissive colour constant:** bake the tint into the texture.
- **Unauthored inputs inherit from the game texture:** without `diffuse_texture = @@` the game's texture is
  used and `diffuse_color_constant` is ignored (mirrors, LED strips).
- **Translucent materials have no roughness.**
- **Normal maps are always decoded as octahedral;** `inputs:encoding` is written but ignored.
- **`alpha_test_type = 0` means "never": every texel transparent.** The default when it is left out is
  "always" (7). A rainbow-blood mod carried the 0 (2026-10-27).
- **Blending works:** `use_legacy_alpha_state 0`, `blend_enabled 1`, `blend_type 6` (emissive) makes an
  unordered emissive layer (gm_poolrooms' caustics).
- **Parallax:** `rtx.displacement.mode` 2 is on (0 off); about 1 ms at 4K on modern_house.
- `uint8` inputs load only when written as `uchar` (noted on the old build; unverified on this one).

## Mod priority and folder names

The runtime keeps its mods sorted by priority (0 for every folder mod) and then by folder path, and for a
texture hash it returns the first mod that replaces it (`AssetReplacer::getReplacementMaterial` iterating the
mod set ordered by `Mod::ComparePtrs`; read in the runtime source on 2026-10-31). Path order is
case-sensitive: `!` < digits < upper case < `_` < lower case < `~`.

| Folder | What | Order |
| --- | --- | --- |
| `!advanced_material_editor` | the user's AME profiles (never write there; its bridge resets it) | wins over every other mod |
| `!astra_startup_<map>` | the fork's startup GMA loader output | before every name without `!` |
| `Emissives` | HL2 fluorescent tube light, shipped in the RTX package | upper case: before lower case |
| `ai_pbr` | rpai's characters | |
| `base_mod` | the RTX fixes' base mod (37 MB) | before every `gm_...` and `modern_...` |
| `gm_br_rtx`, `gm_construct`, `gm_poolrooms_rtx` | map mods (`gm_construct` exists in the user's install; its content unverified) | |
| `modern_house_rtx`, `rtx_water` | | |
| `~gmod_topbr` | gmRTX's automatic ToPBR conversion (DDS written at run time) | loses to everything |

So a lower-case map mod beats ToPBR and loses to AME and to any earlier-sorting mod that replaces the same
hash: on modern_house five textures (grass, the pool ladder, two kitchen props, one light texture) kept
other mods' versions (2026-10-27). Name the folder `<map>_rtx` and, before shipping, compare its hashes with
every other folder in `rtx-remix/mods` (collect the `mat_<HASH>` names of each `materials.usda`).

The runtime's `publishSearchPaths` comment says "the last mod wins": that is about resolving relative asset
paths, not about which material replaces a hash. Inside one mod, an earlier sublayer of `mod.usda` is
stronger (USD).

## Hash replacements are global

A replacement applies wherever its texture is drawn: every map, every prop. Backrooms remastered 209
base-game textures (HL2 and CS:S `tile/`, `concrete/`, furniture) and Modern House 8; with `gm_br_rtx`
installed, those textures carry the Backrooms look on every map that uses them, and on modern_house too,
since `gm_br_rtx` sorts first. The sessions left it so; whether the user wants it is unverified: ask. To
keep a look on its map:

- **Tag textures.** The map's addon binds a texture of its own to the material at runtime (`SetTexture` on
  the slot the shader hashes), only on its map, and the mod targets the tag's hash. gm_poolrooms tags its
  water, light openings, hall panels and caustic classes; Modern House its mirrors.
- **Only the map's own textures.** Leave base-game textures (those found in VPKs, `src: vpk` in the
  inventory) to Remix or to a global mod.

## Reloads and discovery

- The runtime watches `mod.usda`'s timestamp. Write the DDS and `materials.usda` first, then replace
  `mod.usda` atomically (a temporary file and a rename). The swap takes about a second; with many
  preloaded textures it lagged about 9 s (rpai). Builds on `c6b48ed1` log no "swapped in" line: check in
  game.
- A new mod folder is found only at startup, or with Alt+X → Enhancements → Loaded USD Files → "Rescan Mods
  & Reload USD Stage".
- After a reload, texture streaming slows the next seconds (18 fps measured on Backrooms against a steady
  12.7 ms): wait before you measure. Each reload with many preloaded textures stalls the game briefly, so
  keep reloads few during captures.
- A production rebuild: Modern House's build puts the quality letter in the DDS name, so new files never
  replace open ones; gm_poolrooms' build skips names that exist, so delete its old DDS before switching.

## Remix options set from Lua

`RemixConfig.SetConfigVariable(key, value)` sets a live option (values as strings, vectors as
`"x, y, z"`). `RemixConfig.GetConfigVariable(key)` returns the value in `rtx.conf`, or `""`, never the live
value; so to put an option back, keep `rtx.conf`'s value or your own defaults table. Apply the options when
the map starts, again a few times in the first minute (the addons re-apply three times, 20 s apart) because
other code may reset them, and restore them at `ShutDown`. These are live changes only; the remaster writes
no config file. If the map owns the sky, answer the native loader companion's `NativeLoaderSkyOwner` hook
with the add-on's name (this repository's ADR 0031).

## Lights: Remix API lights, not USD

Map light entities reach Remix only as fixed-function lights of whatever models are drawn (view-dependent),
and world mesh hashes are unstable (the meshed world renderer `rtx_mwr_enable` is off), so lights anchored
to meshes in USD are fragile. All three remasters create Remix API lights from Lua
(`RemixLight.CreateSphere`, `CreateRect`, `CreateDisk`, `CreateCylinder`, `CreateDistant`, `DestroyLight`);
those lock the device and are safe from Lua. A distant light's radiance is what a white surface facing it
shows: the sun is about 4-5 (2200 blew the scene out). `build_mod.py` would sublayer a `lights.usda`; none
was written.

Remix API calls that create or destroy meshes and materials from Lua (`CreateMesh`, `DestroyMesh`,
`CreateMaterial`, `DestroyMaterial`) race GMod's render thread (`mat_queue_mode -2`) and crash in `d3d9.dll`;
`CreateMeshBatched` and persistent instances are safe (RTX Water, 2026-10-26). The remasters draw their own
geometry (mirrors, panels, curved tiles, caustic cells) as ordinary GMod meshes in
`PreDrawTranslucentRenderables` with tag textures; meshes drawn in `PostDrawOpaqueRenderables` never reach
Remix.

## How the mod reaches players

- **This repository (native loader):** a content package built by `tools/package_content.py` holds
  `native/root/rtx-remix/mods/<mod>/**` (kind `root-files`) and `native/root/garrysmod/addons/<addon>/**`
  (kind `lua-addon`), both `replace-owned` (ADR 0023). The loader deploys them at start-up from a Workshop
  item, a local archive or a development folder; with loader 0.4.0 or later a content package from any
  subscribed item deploys without the allowlist (ADR 0027). The folder name stays the mod's name, so the
  priority rules above apply unchanged. A deployed file that was changed is put back at the next start, the
  changed copy kept in `native-loader\backup\edits` (ADR 0035): do not hand-edit a deployed mod.
- **The fork's startup GMA loader** (`docs/PBR_GMA_LOADER.md`): a startup `d3d9.dll` proxy reads
  `data_static/astra/<map>/rtx/startup.json` (version 1) from GMA addons, turns `.dds.dat` payloads into
  content-addressed `textures/<sha256>.dds` and `mod.usda.dat` into the layer, and publishes
  `rtx-remix/mods/!astra_startup_<map>/` after verifying every dependency. It accepts only the built-in
  `AperturePBR_Opacity.mdl`/`AperturePBR_Translucent.mdl` by name, and ships RTX IO off (it stalled texture
  uploads). None of the three remasters used it.
