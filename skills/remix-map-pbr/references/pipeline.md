# The pipeline, stage by stage

The three implementations live in the user's fork `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`
(GPL-2.0). Read them there with `git -C <fork> show <branch>:<path>` or in their worktrees; this page
describes what they do. Script names are the Modern House ones unless a column says otherwise.

| Map | Branch (worktree) | Pipeline |
| --- | --- | --- |
| gm_poolrooms (Workshop 2849511871) | `sheepylord/rtx-water-poolrooms` (the main checkout) | `source/gm_poolrooms_rtx/tools`, doc `docs/GM_POOLROOMS_RTX.md` |
| gm_br_complex + gm_br_pitfalls (Workshop 2821179466) | `claude/rtx-remix-map-enhancement-bda9ac` (`.claude\worktrees\rtx-remix-map-enhancement-bda9ac`) | `source/gm_br_rtx/tools`, doc `docs/GM_BR_RTX.md` |
| modern_house (Workshop 3495468649) | `claude/modern-house-rtx` (`.claude\worktrees\modern-house-rtx`), local only | `source/modern_house_rtx/tools`, doc `docs/MODERN_HOUSE_RTX.md` |

The Modern House branch also carries copies of the other two pipelines and docs, but the Backrooms branch
has one newer commit (`e4d548d`, the PAS visibility) and a newer `docs/GM_BR_RTX.md`: read Backrooms from its
own branch.

## Where things live, for one map

In the fork, `garrysmod/` mirrors the game folder and is what the fork's CI packs into its nightly zip.

```
garrysmod/rtx-remix/mods/<mod>/               the Remix mod: mod.usda, materials.usda (generated),
                                              textures/*.rtex.dds (generated; git-ignored for MH and BR)
garrysmod/garrysmod/addons/<addon>/
    addon.json
    lua/autorun/<addon>.lua                   boots on the map only; scoped engine settings; server parts
    lua/<addon>/sh_config.lua                 scoped Remix options, their defaults for restore, sun/times
    lua/<addon>/cl_main.lua                   settings, light manager, sun, mirrors, map fixes
    lua/<addon>/lights.lua (or lights/<map>.lua, cl_lights_data.lua)   generated light list
    lua/<addon>/mirrors.lua, vis_points.lua   generated (Modern House)
    materials/<addon>/*.vtf                   tag textures (unique Remix hashes)
    data_static/<addon>/*.txt                 generated meshes (poolrooms: curved tiles, caustic cells)
source/<map>_rtx/tools/                       the pipeline; <x>_paths.py says where everything is
source/<map>_rtx/map_extract/                 the extracted Workshop map (the author's files; git-ignored)
source/<map>_rtx/work/                        intermediates, shots, measurements (git-ignored)
docs/<MAP>_RTX.md, docs/<map>_rtx/            write-up, gallery.jpg, gallery/, compare/
```

`work/` after a full Modern House run: `inventory.json`, `textures.json`, `jobs_ai.json`,
`live_hashes.json`, `src/` (decoded sources), `ai/<texture>/` (AI outputs and `done.json`), `tex/<texture>/`
(composed maps, `stamp.json`, `result.json`), `composed.json`, `tag_hashes.json`, `sky_hashes.json`,
`sheets/` (contact sheets), `shots/<map>/<label>/`, `perf_<map>_<label>.json`, `ab_<camera>.json`,
`cull_<label>.json`, `survey_cameras.json`, `loadtime_<map>.txt`, `loadprof_<map>.json`, `vpk_cache/`, logs.

## Script map

| Stage | Modern House | Backrooms | gm_poolrooms |
| --- | --- | --- | --- |
| Paths | `mh_paths.py` | `br_paths.py` | `poolrooms_paths.py` |
| Extract | `extract_map.py [gma] [--skip-gma]` | `extract_map.py` | `extract_map.py [gma] [--out DIR]` |
| Readers | `gma.py`, `bsp.py`, `vtf.py`, `vmt.py`, `vpk.py`, `mdl.py`, `mdlgeo.py` | same (`bsp.py` adds a `Vis` reader) | `gma.py`, `bsp.py`, `vtf.py`, `geo.py` |
| Inventory | `inventory.py [--top N]` | `inventory.py` | by hand from the live hashes (a handful of surfaces) |
| Classify | `classify.py` (+ `overrides.json`) | `classify.py` | none: `materials.json` by hand |
| Hashes, AI jobs | `tex_jobs.py` (+ `live_hashes.py`) | `tex_jobs.py` (prediction only) | `vtfwrite.remix_hash`, live hashes read from the game |
| AI | `ai_tex.py <jobs.json>` | `ai_tex.py` | `ai_maps.py <name> <src.png> <size>` |
| Materials | `compose.py`, `overrides.json` | `compose.py`, `overrides.json` | `gen_tile.py`, `gen_plaster.py`, `gen_props.py`, `materials.json` |
| Tags | `vtfwrite.py` (mirror tag) | none | `vtfwrite.py` (water, openings, panels, caustic classes) |
| Mod | `build_mod.py`, `texlib.py` | same | `build_mod.py` (from `materials.json`), `texlib.py` |
| Lights | `gen_lights.py`, `lights_style.json` | same, per map | `gen_lights.py`, `openings.py`, `lights_style.json` |
| Sky | `gen_sky.py` (fallback), physical sky in the addon | none | none (the map's own black skybox) |
| Mirrors | `gen_mirrors.py` | none | none |
| Visibility | `gen_vis.py`, `cullcheck.py` | `rtx_patch_vis_pas` (C++), `vischeck.py` | not addressed |
| Special | none | loading fixes in RTXFixesBinary and gmRTX Lua | `unwrap_stretchy.py`, `gen_caustics.py`, `gen_caustic_mesh.py [--trace]`, `gen_water.py` (retired) |
| Game driver | `game.py` (`MHRTX_GAME`) | `game.py` (`BRRTX_GAME`) | `game.py` (`POOLRTX_GAME`) |
| Cameras | `survey.py`, `cameras_modern_house.json` | `find_cameras.py`, `cameras_<map>.json` | `cameras.json` |
| Shots | `tour.py <map> <label>`, `times_tour.py` | `tour.py <map> <label>` | `tour.py <label>` |
| Before/after | `stock.py on\|off`, `compare.py`, `gallery.json` | same | "before" tour shot before installing, `compare.py` |
| Performance | `perf.py`, `abtest.py`, `stackprof.py`, `loadprof.py` | `perf.py`, `stackprof.py` | tour timing only |
| Restart | `restart.py` | `restart.py` | `restart.py` |
| Install | `deploy.py` | `deploy.py` | junctions (`mklink /J`) or copies |
| Review | `contact_sheet.py` | sheets in `work/` | composites in `work/` |

## Stage details

### Paths module

One small module per map holds every location: the project folder, the repository root, the addon and mod
folders (under `garrysmod/`), the docs folder, `work/`, `map_extract/` and its `gma/`, the Workshop id and the
map names. Every other script imports it, so a new map starts by copying and editing this one file.

### Extraction (`extract_map.py`, `gma.py`, `bsp.py`)

Reads the Workshop `.gma` (default: `steamapps/workshop/content/4000/<id>/*.gma` in the game's library) and
unpacks it to `map_extract/gma/`. For each BSP it extracts the embedded pakfile to `map_extract/<map>/pak/`
with `pak_listing.txt`, the entity lump to `entities.json`, the static props to `static_props.json`, and the
parsed faces (polygons, materials, texinfo) to `work/<map>/faces.pkl`. `bsp.py` is a minimal VBSP v19-21
reader: entities, pakfile, texdata/texinfo, faces (normal from the plane; applying `side` on top flips it
twice, a bug fixed on poolrooms), models, static props, lightmap luminance, and (Backrooms on) the vis lump
for clusters, PVS and PAS rows.

### Readers (`vtf.py`, `vmt.py`, `vpk.py`, `mdl.py`, `mdlgeo.py`)

- `vtf.py`: VTF 7.0-7.5 header and top mip of frame 0 to RGBA (DXT decode vectorised, HDR as float).
- `vmt.py`: KeyValues parser with `patch` includes; resolves a texture in the order the game mounts:
  the BSP's pakfile, then the Workshop addon, then the base-game VPKs (GMod, HL2, CS:S content).
- `vpk.py`: VPK v1/v2 directory reader for that fallback (`work/vpk_cache/`).
- `mdl.py`: a model's texture names, `$cdmaterials` and skin families.
- `mdlgeo.py`: model-space vertices per mesh from `.mdl` + `.vvd` (+ `.vtx` triangles on Backrooms), LOD 0,
  used to size lights from a lamp's lens.

### Inventory (`inventory.py`)

For every map: world materials by visible face area (excluding `tools/`), static props and prop entities by
instance count, and for every material its shader, its texture slots (`$basetexture`, `$basetexture2`,
`$bumpmap`, `$normalmap`, `$envmapmask`, `$selfillummask`, `$detail`, ...), its flags (`$translucent`,
`$alphatest`, `$additive`, `$selfillum`, `$surfaceprop`, `$seamless_scale`, `$color`, `$color2`, ...), and for
each texture where it was found (pak, gma or vpk), its size, format, frames and flags. Output
`work/inventory.json`; prints the most important entries.

### Classification (`classify.py`)

An ordered list of (class, regex) rules over "material name + base texture name", then a `$surfaceprop`
table, then the shader (`UnlitGeneric` → unlit), else `generic`. First match wins, so specific rules go
first (Backrooms needed a metal-door rule before the wood rule). VBSP's cubemap-patched copies
`maps/<map>/<material>_<x>_<y>_<z>` and `_wvt_patch` are reduced to the original name first, or a
`maps/` prefix matches the wrong rule (it matched a paper rule on Backrooms).

Modern House classes: skip, water, emitter (`lights/white*`), dead_light, light, mirror, glass_frosted,
aluminium, glass_opaque, glass, foliage, bark, ground, carpet, pool_tile, marble, brick, stone, tile,
wood_floor, polished_concrete, matte_black, concrete, lacquer, plaster_graphic, plaster, chrome,
painted_metal, canvas, paper, wood, fabric, ceramic, rubber, plastic. Backrooms adds wallpaper,
ceiling_tile, linoleum, metal, backdrop (painted distant views). `overrides.json` "textures" can pin a class
per texture. Classes that get no AI: skip, decal, unlit, water, emitter, mirror, glass, glass_frosted.

### Texture list, hashes and AI jobs (`tex_jobs.py`)

For every `$basetexture`/`$basetexture2` the maps draw it records in `work/textures.json`: the predicted Remix
hash of every animation frame, size, format, the materials using it and their classes, whether a world shader
uses it, its share of the world area and prop instances, the material's bump and envmap-mask textures, its
`$selfillum`, `$translucent`, `$alphatest` and alpha-as-mask flags, and the `$color`/`$color2` tint (Modern
House; `_off` lamp variants ignored). Sources are decoded to `work/src/<texture>.png`.

The AI job list `work/jobs_ai.json` (most visible first) gives each texture an output size, tiling and upscaler:

| Rule | Modern House | Backrooms |
| --- | --- | --- |
| World texture | 4096 if share ≥ 0.15 % or source ≥ 2048, else 2048; tiled | 4096 if share ≥ 0.4 % or source ≥ 2048, else 2048; tiled |
| Prop texture | 4x, at least 512, at most 2048 | same |
| Upscaler | DAT for all | DAT for world, props with ≥ 12 instances and lights; SPAN otherwise |
| Maps | normal, roughness; height for world floor/wall classes | same, own height classes |
| Skipped | no-AI classes, animated textures (frames > 1) | same |

Counts: Modern House 153 textures (145 from the map's GMA, 8 from base-game VPKs), 141 AI jobs (31 world at
4096, 18 world at 2048, 80 props at 2048, 6 at 1024, 6 at 512). Backrooms 1162 textures (953 GMA, 209 VPK),
1134 AI jobs.

`merge_live_hashes` (Modern House) adds, for a texture whose materials reported live hashes that match none
of its predictions, those live hashes, unless they are another texture's own prediction.

### Live hashes (`live_hashes.py`)

Writes the inventory's material names to `garrysmod/data/mhrtx/`, runs client Lua that calls
`RemixMaterial.GetAllTextureHashes(<material>)` for each, and writes `work/live_hashes.json`
(`{material: [hash, ...]}`). The map must be loaded and looked around in first, so the textures were
uploaded. Then run `tex_jobs.py` again. More in `remix-hashes-and-layers.md`.

### AI maps (`ai_tex.py`; poolrooms `ai_maps.py`)

Runs in the rpai venv and imports rpai's `ModelRunner` from `MHRTX_RPAI` (`BRRTX_RPAI`, `POOLRTX_RPAI`);
the weights come from `%USERPROFILE%\.rpai\models\pbrify`. Per job:

- upscale with the 4x model chosen (DAT `4x-PBRify-UpscalerV4`, or SPAN), then Lanczos to the target size;
  when the target is not larger than the source it only resizes;
- padding of a sixteenth of the side (8 to 64 px), wrap-around for tiled world textures and reflect for the
  rest, cropped off again, so tiled outputs stay seamless;
- the 1x normal (`NormalV3`), roughness (`RoughnessV2`) and height models at the output size, or at half size
  above 4096 and upsampled;
- writes `albedo.png` (and `alpha.png` when the source has alpha), `normal_raw.npy` (float16), `rough.png`,
  16-bit `height.png` and `done.json`; a job whose `done.json` matches is skipped.

`MHRTX_AI_TILE` sets the tile size (default 512, overlap 32). Measured on the RTX 5090: 139 jobs in 2722 s
(Modern House), 1132 in 5548 s (Backrooms). poolrooms' `ai_maps.py` does the same for one texture at a time
(plaster, gate, ladder) and leaves the composing to the per-material generator.

### Composition (`compose.py`)

Per texture, from `work/ai/<name>/` and the originals in `work/src/`, writes `work/tex/<name>/*.png`,
`result.json` and a stamp (recomposed only when the recipe, class or AI output changed), in parallel
(`MHRTX_COMPOSE_WORKERS`, default 8). What each recipe key does:

| Key | Effect |
| --- | --- |
| `rough` (lo, hi) | AI roughness normalised to its 2nd-98th percentile, raised to `rough_gamma`, mapped into the range |
| `normal` | AI normal strength (slopes scaled) |
| `bump` | the artist's own bump map added as slopes (Source and PBRify are both DirectX convention; SSBUMP maps are skipped) |
| `detail` | extra relief from the colour's high frequencies, for flat AI normals |
| `height` | `displace_in` for Remix parallax (depth over one texture repeat); 0 = none; forced 0 on props |
| `metal` | metallic constant; `metal_albedo` lifts a bare metal's mean luminance to that F0 |
| `envmask` | how much the material's envmap mask (or alpha used as one) lowers roughness, up to 60 % of it |
| `albedo_max` | soft ceiling on linear albedo (real paint and plaster stop near 0.8) |
| `damp` | large soft moisture patches: darker, glossier, flatter (Backrooms carpets) |
| `saturation`, `exposure` | albedo chroma and brightness (Backrooms Level 0 wallpapers 0.7 / 0.88) |
| `emissive` | emission for light textures from their bright diffuser (luminance above 55 % of the 99th percentile); with `$selfillum` the alpha mask times that threshold, so the trim ring does not glow |
| `emit_rects` | the [u0, v0, u1, v1] parts of an atlas that are the lamp |
| `backdrop` | the whole colour emits (painted distant views) |

The `$color`/`$color2` tint is multiplied into the albedo. Alpha is kept only for translucent or alpha-tested
materials; an alpha that carries an envmap, self-illumination or phong mask is dropped. Normals are written
in Remix's octahedral encoding; a material without a metal map gets `metallic_constant 0`.

Roughness ranges (lo-hi), with `height` where set:

| Class | Modern House | Backrooms |
| --- | --- | --- |
| plaster | 0.80-0.95 | 0.68-0.92, h 0.0012 |
| concrete | 0.66-0.93, h 0.0028 | 0.68-0.95, h 0.0035 |
| polished_concrete | 0.20-0.46, h 0.0006 | |
| stone | 0.34-0.62, h 0.0022 | |
| brick | 0.68-0.92, h 0.0035 | 0.72-0.95, h 0.008 |
| marble | 0.04-0.17, no height | 0.05-0.28 |
| tile | 0.12-0.40, h 0.0022 | 0.06-0.55, h 0.0025 |
| pool_tile | 0.05-0.30, h 0.0028 | |
| wood_floor / wood | 0.28-0.58 / 0.34-0.68 | 0.35-0.75, h 0.0015 |
| lacquer | 0.05-0.22 | |
| aluminium | 0.28-0.52, metal 0.85, no lift | |
| chrome / metal | 0.02-0.10, metal 1, F0 0.62 | metal 0.22-0.62, metal 0.85 |
| painted_metal | 0.30-0.60 | 0.30-0.62 |
| fabric / carpet | 0.85-1.00 / 0.86-1.00, h 0.0014 | 0.82-1.00 / 0.80-0.98, h 0.0016 |
| wallpaper / ceiling_tile | | 0.52-0.78 / 0.80-0.97, h 0.0035 |
| plastic, ceramic, paper | 0.24-0.55, 0.03-0.14, 0.68-0.92 | 0.28-0.60, -, 0.72-0.95 |
| ground, foliage, bark | 0.80-1.00 h 0.0055, 0.45-0.80, 0.75-0.96 | 0.78-1.00 h 0.006, 0.50-0.85, - |
| light | emissive 30 | emissive 14 |
| backdrop | | 0.9-1.0, backdrop 1.6 |
| generic (default) | 0.40-0.80 | 0.42-0.85 |

poolrooms composed by hand: a procedural 4K tile (glaze 0.075, grout 0.88), plaster 0.86-0.96 with the
artist's normal plus high-pass relief, gate steel metallic 0.85 rough 0.38 with alpha cutout, ladder parts by
colour (stainless metal 1 rough 0.14, plastic 0.42, enamel 0.28).

### Hand-made materials (`overrides.json` "materials"; poolrooms `materials.json`)

Each entry: the `textures` (or explicit `hashes`, plus `extra_hashes`) it replaces, the `shader`
(`opacity` or `translucent`), `maps` (texture files) and `inputs` (constants); `drop` removes a generated
entry. Applied after the composed materials. Colour constants in these files are sRGB. Modern House's:

| Entry | Settings |
| --- | --- |
| glass_clear (glazing) | translucent, IOR 1.52, thin-walled 0.25, transmittance (0.92, 0.97, 0.96) at 2, no diffuse layer |
| glass_drinkware | translucent, IOR 1.5, thin-walled 0.12 |
| glass_frosted (shower screens) | translucent, IOR 1.52, thin-walled, `use_diffuse_layer` |
| mirror (tag hash + the mirror model's face) | opaque, diffuse (0.93, 0.94, 0.94), roughness 0, metallic 1 |
| led_strip (`lights/white*`) | diffuse 0.9, roughness 0.35, emission (1.0, 0.72, 0.47) x16; the light itself is an API rect light |
| water_wall | translucent, IOR 1.333, thin-walled 0.5, its own normal map |
| cooktop glass | black glass-ceramic (0.03, 0.03, 0.035), roughness 0.04 |
| sky faces | the `gen_sky.py` faces over HL2's `sky_day02_03` |

poolrooms' `materials.json` holds every material: pool tile (albedo, normal, roughness, height,
`displace_in` 0.008), plaster, gate, ladder, water fallback (translucent, IOR 1.333, transmittance
(0.62, 0.89, 0.97) at 150, not thin-walled), the openings' void emitter (white, 5000 K, intensity 8), the
hall panel emitter (18), and eight caustic classes. The caustics went through three designs: the
translucent-emissive-blend path ignored `emissive_intensity`; a clear translucent layer (IOR 1, thin-walled)
inside the water volume turned the water navy; the final one is an opaque material with
`use_legacy_alpha_state 0`, `blend_enabled 1`, `blend_type 6` (emissive), which Remix draws as an unordered
emissive particle composited by weighted-blended OIT (background x (1 - a) + 4 x a x emission, a the
albedo's luminance), so a tiny grey albedo with a matching emission is effectively additive. Its 8x8 sprite
sheet animates at 13 fps; its 5500 K colour is baked into the sheet.

### Tag textures (`vtfwrite.py`)

Writes small uncompressed BGRA8888 VTF 7.2 files with a full mip chain and predicts their Remix hash (XXH64
of the stored top mip). The addon binds the tag to a material slot at runtime (Lua `SetTexture`), so those
draws get a hash no other texture has, and the mod replaces exactly them. Bind the slot the shader actually
hashes: the Water shader binds `$normalmap`, not `$basetexture`. A tag created after the game mounted its
content may resolve to `vgui/white` until a restart; setting it at runtime worked (Modern House).

### Mod build (`build_mod.py`, `texlib.py`)

Collects composed materials and hand-made entries, encodes every map to
`textures/<name>_<sha1[:10]>[p].<a|n|r|m|h|e|t>.rtex.dds` (the `p` marks production quality) when that file
does not exist, writes one replacement block per hash into `materials.usda`, rewrites `mod.usda` atomically
(temp file and rename) with `lights.usda`/`meshes.usda` sublayers if present, and prunes DDS files no block
uses (`--no-prune` keeps them). `MHRTX_DDS_WORKERS` (default 6) parallel NVTT runs. The USD it writes and
what the runtime accepts: `remix-hashes-and-layers.md`.

`texlib.py`: tileable FFT noise, sRGB/linear, height to DirectX normals, octahedral encode/decode, PNG and
DDS output. NVTT arguments follow the Remix Toolkit's ingestion: albedo, emissive and transmittance BC7
with gamma-correct mips; normals BC5; roughness and metallic BC4; height BC4 with the max mip filter.
`MHRTX_DDS_QUALITY` (`BRRTX_`, `POOLRTX_`) = `normal` (default) or `production` (about 25x slower; about 3 h
for Modern House, stopped; 5 min for poolrooms' few textures).

### Lights (`gen_lights.py`, `lights_style.json`)

Writes the addon's light list. Shapes: rect, disk, sphere (spot-shaped with a cone, softness and focus;
shaping works only on spheres), cylinder; the addon also makes the distant sun when the physical sky is off.
Each light records its vis cluster (probed a little in front of the emitter), so the addon can switch by
PAS. Radiance is linear RGB in Remix units.

- **Modern House** (341 lights): a `FIXTURES` table of lamp models → shape, lens size from the model's
  geometry, offset and direction (`light_inset` as a 42-degree spot, ceiling disks, linear rects,
  pendants, wall spots; a `light_inset` set into the ground and pointing up becomes an uplight); every
  `lights/white*` strip face as a rect light the size of the strip; bollard rings as small spheres; the
  `light_spot` entities no fixture explains as accent spots; and `extra` lights the house lacks (10 in the
  pool). `kinds` give kelvin, radiance, cone and range: downlight 3400 K/600/42°, LED 3200 K/25, shelf LED
  3100 K/14, pendant 2700 K/320, wall spot 2800 K/450, bollard 2800 K/110, uplight 2900 K/420/24°, pool
  5600 K/220/72°. `regions` (boxes, first match wins) change kelvin or scale per room.
- **Backrooms** (1682 and 2687 lights): every static prop or prop entity whose model is a lamp, with lights
  on its lens (troffers as rect lights the size of their diffuser, round lamps as disks, bulbs as spheres;
  prop-combined "floulightbatch" models split back into panels by VTX triangle connectivity); fixtures
  whose skin or texture shows them off stay dark; the light entity the mapper placed under a fixture sets
  its colour and level, with small per-fixture variation (output 12 %, tint 4 %); the remaining entities as
  sphere and spot lights. Flux-based calibration (an earlier one was 10x too dim), a brightness knee at 1000
  (entities went up to 75000) and a radiance cap of 2000. Region boxes can scale spots or points (the
  cistern spot x2.5).
- **poolrooms** (116 lights): `openings.py` merges the coplanar `poolrooms/nothingness` faces (the white void
  behind windows, slots and skylights) into 47 rectangles, each a 5500 K rect light facing into the room; 19
  spot and 22 point lights converted from the entities not inside an opening (a light entity's `pitch`
  key is an elevation, -90 pointing down, the opposite sign of a camera pitch); 28 ceiling panels with
  visible emissive fixtures for the unlit north hall.

### Sky (`gen_sky.py`, the physical sky)

The physical atmosphere (`rtx.skyMode 1`, Hillaire scattering, volumetric clouds, sun disc, stars, moons)
makes its own sun light; set `rtx.atmosphere.sunElevation` and `rtx.atmosphere.sunRotation` = 90 minus the
azimuth (azimuth measured from +x towards +y). Its default clouds (coverage 0.85 with voxel shadows) hide
the sun: Modern House uses coverage 0.27, spread 0.8, type 0.9, `cloudShadowStrength 0`,
`cloudVoxelShadowsEnable False`. Its times: afternoon 21°/228°, golden 7°/242°, noon 58°/190°,
dusk -3°/252°, night -30°/260° (`mhrtx_time`). It cost nothing measurable at 4K. `gen_sky.py` paints a
Preetham clear sky with a Mie glow, cumulus and cirrus for the same sun into six skybox faces (rt +x, lf -x,
bk +y, ft -y, up, dn; `--debug` writes labelled faces) as the fallback where the runtime has no atmosphere.
The native loader's companion has its own physical sky; a map add-on that sets the sky answers the hook
`NativeLoaderSkyOwner` with its name (this repository's ADR 0031; Modern House is recognised by its
`MHRTX_Config`).

### Mirrors (`gen_mirrors.py`)

gmRTX removes every `func_reflective_glass` when a map starts (Source's planar reflection breaks under
Remix). The script takes the eight mirror quads in world space from the BSP's brush models and the entities'
origins, writes them to `lua/<addon>/mirrors.lua`, writes the tag `materials/<addon>/mirror_tag.vtf` (16x16
BGRA) and its hash to `work/tag_hashes.json`. The addon draws the quads with an `UnlitGeneric` material on
that tag in `PreDrawTranslucentRenderables`; the mod makes the tag silvered glass and the path tracer does
the reflection. The mirrors' original texture stays black glass, because the kitchen cooktop uses it too.

### Visibility (`gen_vis.py`, RTXFixesBinary, `cullcheck.py`, `vischeck.py`)

Two independent cullings take geometry out of the ray-traced scene:

- **Client drawing.** gmRTX turns the engine's PVS off twice: `autoexec.cfg`'s `r_novis 1` and
  RTXFixesBinary's `rtx_patch_forcenovis` patch. Either one draws the whole map.
- **Server transmission.** The server sends a client only the entities in the player's PVS: from a typical
  spot in Modern House a fifth of the map (471 of 2377 clusters at the median), so 220-340 of its 381
  networked props and brush entities (glass panes, sliding doors, fixtures) were missing from the client.

Modern House (small): the client keeps drawing everything, and `gen_vis.py` picks one candidate point per
cluster (the centre of its largest leaf) and greedily the fewest whose PVS rows cover every cluster: 31
points in `vis_points.lua`, added to each player's PVS in a server `SetupPlayerVisibility` hook
(`AddOriginToPVS`). Backrooms (about 30000 brush faces, 3000-4000 static props and 5000-7000 entities per
map; 46 ms a frame with the whole map drawn): `r_novis 0` and `rtx_patch_forcenovis 0` scoped, and
`rtx_patch_vis_pas 1` rewrites the engine's in-memory vis table so every PVS lookup returns the PAS row that
`vvis` stores beside it (2-5 % of the map instead of about 1 %), for client drawing and server transmission
alike; put back when the map unloads. Frustum and node culling stay off either way. The engine recomputes
the visible set only when the view enters another cluster, so a change shows after the camera moves to
another room.

### poolrooms-only generators

- `gen_tile.py [json overrides]`: the 512 px 4x4 tile sheet (one tile about 7.7 units) rebuilt at 4096
  (1024 px per tile): height with per-tile lippage and tilt, cushion edges and concave grout; cool off-white
  glaze, grout with grain and joint dirt; glaze roughness about 0.07, grout about 0.9; normals from the
  height; all noise periodic so it tiles.
- `gen_plaster.py`: the AI upscale as albedo, the artist's `plaster_n` upsampled plus high-pass relief from
  the albedo (PBRify's normal of the pale texture was almost flat), roughness 0.86-0.96.
- `gen_props.py`: the vent grille rebuilt at 1024 from the original's bar centres as round bars with alpha
  cutout; the ladder atlas classified by colour into stainless, plastic and enamel.
- `unwrap_stretchy.py`: faces of `pooltile_noreflect_stretchy` rely on `$seamless_scale` triplanar mapping,
  which Remix ignores (tiles 16x too large). Faces are joined into charts across edges under 40 degrees,
  each chart unfolded rigidly from its largest face at the real tile size, and written to
  `data_static/poolrooms_rtx/stretchy_mesh.txt` (2504 faces, 114 charts); the addon draws them with the tile
  material and hides the originals with the NO_DRAW flag.
- `gen_caustics.py`: a looping 8x8 caustic sprite sheet from light refracted through a periodic rippled
  surface to a floor below; stores only the light added above the mean; the colour is baked in linear
  space because a bound emissive texture replaces the colour constant.
- `gen_caustic_mesh.py [--trace]`: cuts the underwater floors into 64-unit cells, gives each the direct
  light the remaster's own lights put on it through the water (Fresnel, absorption, source-size blur;
  occlusion traced in game with `--trace`, cached in `work/caustic_vis.json`), adds a faint floor from bounce
  in lit rooms, quantises into classes, and writes the cells, one tag texture and one material per class.
- `gen_water.py`: the old animated water normal; retired when the user asked for calm water (2026-10-26).

### The addon (Lua), behaviour only

- **Autorun.** Returns unless `game.GetMap()` is one of its maps. Server: `AddCSLuaFile` for the client
  files, hides glow sprites (`env_sprite` HideSprite) and fake beams (`beam_spotlight` LightOff) at
  `InitPostEntity` and `PostCleanupMap`, the PVS-cover hook, the RTX Water profile hook. Client: a list of
  scoped engine settings, each saved and applied at autorun, `Initialize`, `PreRender` and `InitPostEntity`,
  and restored at `ShutDown`; gmRTX's three light-updater hooks (`Think/RTXReady_RTXLightUpdater`,
  `Think/RTXReady_DynamicLightUpdater`, `PostDrawTranslucentRenderables/RTXReady_RenderLightUpdaters`)
  removed while the map runs and put back after, without touching the user's `rtx_lightupdater`; boot on
  `InitPostEntity` only when `RemixLight` and `RemixConfig` exist; a `<prefix>_reload` command.
- **Scoped engine settings.** `rtx_api_map_lights_autospawn 0` (on Backrooms Light2RTX had added 1255 and
  2278 always-on lights), `r_drawbatchdecals 0` (the batched path overflows on hundreds of decals, and
  decals drawn one by one keep stable geometry and hashes), and the visibility settings above. Not
  `r_forcehwlight` (R3-016).
- **sh_config.** The Remix options to set (`rtx.ignoreGame*Lights True`, `rtx.fallbackLightMode 0`, the
  volumetric haze, the tonemapper purity, the sky), a defaults table to restore when `rtx.conf` has no value
  (`RemixConfig.GetConfigVariable` reads `rtx.conf`, not the live value), the sun and times, the light grace
  (3 s) and a light hash base no other add-on uses (0x6A000000 poolrooms, 0xB4000000 Backrooms, 0xB5000000
  Modern House).
- **cl_main.** Applies the options (game lights hidden only when its own lights exist), applies them again
  three times over the first minute, clears Light2RTX's lights, creates the lights through
  `RemixLight.Create*`, runs the light manager (a 0.5 s timer plus a Think hook on cluster change; a
  `viewPos` override so tours light the held camera), the sun, mirrors and fixes (a missing texture bound
  to the house glass with `SetTexture`), logs one `created: ...` line, and on `ShutDown` destroys its lights
  and meshes and restores the options. It leaves world materials alone at unload.

### Game drivers (`game.py`, `restart.py`, `loadprof.py`, `stackprof.py`)

- `game.py`: console text as a `WM_COPYDATA` message to the game's `Valve001` window (the channel behind
  `-hijack`), only to a `gmod.exe` of the configured install (the exe path is checked, since peers run a
  vanilla GMod beside it); Lua through `lua_run_cl` reading code from `garrysmod/data/<prefix>/`, answers as
  JSON there; screenshots with the engine's `jpeg` command (the presented, path-traced frame) from
  `garrysmod/screenshots`; camera holds through the `rtx_agent` add-on. CLI: `con`, `lua`, `luafile`, `shot`.
- `restart.py`: `quit` through the console, a `taskkill /F` of that install's game after a minute, launch
  through `<game root>\_debug_tools\launch_gmod_keeplogs.bat` (exists in the classic install only), wait for
  the console, wait for the Workshop mount (at least 90 % of "Mounted N of M workshop addons"), send `map`,
  then time the load from `console.log` markers ("Lua fixers completed", "Smart-mark complete", the
  addon's "created" line, "Built skybox meshes") into `work/loadtime_<map>.txt` with the longest silences.
  Only with restart permission and only against an install you may restart.
- `loadprof.py [--map] [--from "<console text>"] [--seconds 80] [--no-restart]`: restart, then CPU-profile
  the stalling part of the load.
- `stackprof.py <seconds> <out.json> [thread ...]` and `--report <out.json> <tid> [frame_ms]`: suspends and
  unwinds the game's threads with dbghelp, names Remix functions from `bin\win64\d3d9.pdb`.

### Deploy (`deploy.py`)

With the game closed: copies the addon to `<game>/garrysmod/addons/<addon>` and the mod to
`<game>/rtx-remix/mods/<mod>`, textures as hard links on the same volume (no second copy of 3.2 or 14 GB;
the game keeps them when the worktree goes), after removing a development junction (the link only), and
deletes files the build no longer has. For live iteration the sessions used junctions instead
(`mklink /J`), with `build_mod.py`'s atomic `mod.usda` reload and the addon's reload command. On an install
with the native loader, a folder the loader deployed is its own: test through a content package instead
(`testing.md`), or give a hand-copied development mod another folder name (unverified as a workflow).

## How the three maps differ

| | gm_poolrooms | Backrooms | modern_house |
| --- | --- | --- | --- |
| Done | 2026-10-26 | 2026-10-27, PAS 2026-10-28 | 2026-10-27, culling fix the same evening, R3-016 2026-10-29 |
| Textures | 7 materials plus 8 caustic classes, hand-built; 16 DDS, 150 MB | 1162 textures, automated, 3712 DDS, 14 GB | 153 textures, automated, 490 DDS, 3.2 GB |
| Materials | procedural tile, AI plaster, gate, ladder; tags for water, openings, panels, caustics | recipes per class, damp carpets, muted Level 0 grade, backdrops | recipes per class, hand-made glass, mirrors, LEDs, water wall |
| Lights | 116: openings, entities, hall panels | 1700-2700 per map on the fixtures, switched by PAS (80-90 on, at most about 400) | 341 on the fixtures and LED faces, all on |
| Sky | the map's black skybox | the map's own | physical sky with times of day; painted fallback |
| Visibility | not addressed (whole map drawn by gmRTX) | PAS (`rtx_patch_vis_pas`) | whole map + 31 PVS-cover points |
| Special | black water fix, triplanar unfolding, caustics, RTX Water | three loading fixes in gmRTX and RTXFixesBinary, light-updater suspension | mirrors, glow sprites, missing texture, pool lights, the skybox-boundary load fix in gmRTX |
| Frame time (4K, RTX 5090) | median 15-16 ms | pitfalls 13.2 ms (stock 121), complex 12.8 ms | 16.6 ms (stock 37.2) |
| Load from `map` | about 142 s | 3.5 min / 4 min | about 2.5 min |
| Where it ships | fork branch (pushed) and the RTX package's fixes part | local only | hidden item 3829275998 |

## Reusable as-is vs map-specific

Reusable (rename the paths import and the environment prefix): `gma.py`, `bsp.py`, `vtf.py`, `vmt.py`,
`vpk.py`, `mdl.py`, `mdlgeo.py`, `texlib.py`, `vtfwrite.py`, `ai_tex.py`, `tex_jobs.py` (its thresholds),
`live_hashes.py`, `compose.py` (the engine; the recipes are a look), `build_mod.py` (mod name), `gen_vis.py`,
`game.py`, `tour.py`, `perf.py`, `abtest.py` (its variants name the addon's switches), `stock.py`,
`compare.py`, `survey.py`, `find_cameras.py`, `cullcheck.py`/`vischeck.py`, `stackprof.py`, `loadprof.py`,
`deploy.py`, `contact_sheet.py`.

Map-specific: the paths module; `classify.py` rules (the map's material naming); `RECIPES` (the look);
`overrides.json`; `FIXTURES` in `gen_lights.py` (the map's lamp models) and `lights_style.json` (kinds,
kelvins, regions, extras); `cameras_<map>.json` and `gallery.json`; the addon (map names, settings, hooks,
fixes); poolrooms' generators, written for that map's few surfaces.

## Starting a new map

1. Ask the user (permissions, install, destination, licence of the map's assets). Subscribe only with
   their OK.
2. New worktree of the fork on a new branch (local; push only if asked). Copy Modern House's `tools/`
   folder and addon folder; rename `mh_paths.py`, the `MHRTX_` prefix, the `MHRTX` Lua table, the
   `mhrtx_` console names, the data folder name, the mod name in `build_mod.py`, the light hash base, and
   the `.gitignore` lines.
3. Clear the copied map data: `cameras_*.json`, `gallery.json`, `overrides.json` entries, `FIXTURES`,
   `lights_style.json` regions and extras, the addon's generated files and map fixes.
4. Extract, inventory, read the contact sheets, write the classifier rules for this map's names.
5. Set `*_GAME` and `*_RPAI` for every shell; check the setup (SKILL.md).
6. Work through the workflow; keep a changelog of decisions in the doc page as you go.
