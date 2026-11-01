# Remix PBR AI (rpai)

Generates and upscales PBR textures for **RTX Remix** from a model that has
only diffuse textures, and publishes them as a hot-reloadable Remix mod. Built
for Garry's Mod RTX with models imported through **Model Hotloader** (PMX/PMD),
and tested on Hyacine (风堇1.0by_mobius, 78 materials, 19 textures).

```
rpai run "E:\G\Upload\Hyacine\1_PMX\风堇1.0by_mobius\风堇1.0.pmx"
```

## What it does

| Step | Command | How |
| --- | --- | --- |
| 1. Find Remix hashes | `hashes` | Asks the running game over its console. Each material's captured texture hash comes from `RemixMaterial.GetAllTextureHashes`. Textures the game has not drawn yet (hidden outfit parts, morph-toggled overlays) get hashes **predicted offline** from Model Hotloader's VTFs (or a compiled addon's, see [Compiled models](#compiled-models---mdl)). |
| 2. AI maps | `generate` | Takes the **original** images from the PMX folder, not the game's copies. Upscales them with PBRify (DAT) up to 4096 px, then generates normal, roughness and optionally height maps with PBRify. |
| 3. Material-aware tuning | `generate` | Classifies every PMX material (cloth, metal, skin, face, iris, eye white, eye highlight, lashes, hair, leather…) from its name and sphere map, then **rasterises the classes into texture space** from the PMX UVs. A shared atlas can be metal in some texels and cloth in others. |
| 4. Publish | `publish` | Encodes DDS with the NVTT exporter bundled in the Remix Toolkit, using the Toolkit's own BC7/BC5/BC4 settings. Writes `over "mat_<HASH>"` layers into `rtx-remix/mods/ai_pbr/`, and the runtime hot-reloads them. |

The AI models are [PBRify_Remix](https://github.com/Kim2091/PBRify_Remix) v1.7.2 (CC0), the same models
NVIDIA's ComfyUI Remix workflow chains (`restapi_pbrify.json`): upscaler → 1x normal / roughness / height.

### Why the class step matters

Remix replaces materials **per texture hash**, and MMD textures are shared atlases. On Hyacine one
cloth sheet (`衣.png`) is used by 39 materials, 8 of them metal fittings, plus leather shoes. An AI
roughness map alone cannot tell red cloth from red-painted metal. The UV class map gives cloth
roughness ≈0.78, metal 1.0 metallic / ≈0.28 roughness, leather ≈0.42, and so on. It keeps only the
AI map's *local variation* for detail. Faces and eyes get flat normals on purpose, because anime
faces are painted flat.

### UV island borders (gutters)

MMD sheets are mostly empty: Guinaifen's stockings cover 24% of `siwa.png`, and the rest is black
with alpha 0. PBRify reads every island border as a relief step. On the stockings that gave a
ridge tilted up to 78° along the paint edge and 3–8° just inside the island (0.8° in the interior).
The legs are unwrapped as front and back halves, so in game a thin crease ran down the inner and
outer side of each leg, the "normal slit" at the UV seams (2026-10-25). Three things now keep the
gutter out of the maps (`compose.gutter_fill`, `GUTTER_VERSION`):

* **AI input.** Before the normal, roughness and height models run, the gutter band around the
  islands is filled with the nearest island texel, so the AI never sees an edge there. The band is
  1/128 of the sheet (32 texels at 4096). Beyond it the sheet's own paint stays, so a byte-identical
  sheet that another model maps differently keeps sensible maps further out. The upscaled albedo is
  unaffected and stays cached; only the 1x models re-run, and their cache names carry a digest of the
  UV coverage.
* **Finished maps.** The same band of the normal, roughness, metallic, height and anisotropy maps
  repeats the island edges, so bilinear filtering and mip levels up to 4 never blend gutter values
  into a border.
* **Class roughness means.** The AI roughness variation is kept around each class's mean over the
  texels the class covers on the mesh. The gutter used to be averaged in: it pulled the stockings'
  mean from 0.43 to 0.28, so the nylon rendered at 0.42 where its class said 0.30. On Guinaifen's
  other sheets the effect was below 0.07 (cloth on `衣.png` 0.485 → 0.55 at the aggressive 0.55).

### Anime faces and eyes

A cel-painted face should keep its drawing, not gain physical detail, so the face classes are
tuned separately and no style preset touches them. Values were set on a close-up of Guinevere
against the original Remix materials, using fixed screen patches (`docs/guinevere/face_ab.jpg`,
`eyes_ab.jpg`, `eye_emission_sweep.jpg`):

| Class (matched by name) | Roughness | Emission | Why |
| --- | --- | --- | --- |
| face (颜, 脸, blush…) | 0.60 | – | No AI relief or roughness blotches; matte, so nose and cheeks never get a plastic hot spot |
| mouth (口, 齿, 舌: interior, teeth, tongue) | 0.60 | – | At 0.12 the tongue mirrors the dark mouth cavity at grazing angles and its pink reads as shadow (patch 81 → 43) |
| lash (眉, 睫, 眼线) | 0.85 | – | Lashes, brows and eyeliner are ink: no glints |
| sclera (白目, 眼白) | 0.25 | 0.025 | Grey in the socket at any roughness (134 vs 134), so it emits a little of its own white: 63–165 → 190–208, just under the cheek's 217 |
| eye / iris (目, 瞳) | 0.06 | 0.04 | Mirror-smooth keeps the colour; 0.18 veils it white (saturation 0.47 vs 0.62) |
| highlight (目光, ハイライト) | 0.50 | 0.6 | The catchlight mesh reads as pure white (208 → 254) |

Emission is the albedo's own colour times the class weight, so the iris glows gold and the eye white
white. Class borders stay sharp, and gutters repeat the nearest island edge so mip levels never
spread the sheet's skin paint as a glowing rim. The face material gets `enable_emission` and
`emissive_intensity` (the strongest weight on the sheet times the publish multiplier). Fixed
emission glows relative to lit skin under dark-scene auto exposure and loses its lift in bright
scenes. C-16 adds `float inputs:emissive_adaptive_intensity` on maps whose recorded classes include
`sclera`, `eye` or `highlight`, keeping the fixed intensity as an older-runtime fallback.

`--emissive-adaptive-intensity R` sets the adaptive/fallback ratio per unit adapted scene luminance
(also a top-level JSON setting). The USD value is `fallback * R`. Default `R = 1/0.18`, about
5.555556: at exposure 1, adapted luminance is the package's target 0.18, so the adaptive emission
matches today's `linear albedo * class weight * --emissive-intensity`. For fallback 0.6 that writes
3.33333333; for 0.04 it writes 0.222222222. This default is provisional and awaits in-game tuning.
`0` opts out, and `--emissive-intensity 0.7` (or 1.3) scales both modes. These are publish-only
options; cached maps are sufficient, with no regeneration. Non-eye emitters stay fixed. See
[standards](../references/standards.md#scene-adaptive-eye-emission-c-16-provisional-2026-10-31).

For a staged copy of an already published mod, use
[`set_adaptive_emission.py`](../scripts/set_adaptive_emission.py.md) with `--multiplier` (per-material
fallback ratio) or `--value` (literal USD input). It changes only emissive-map shader inputs and
keeps all other bytes, including the fixed fallback. `package_characters.py` copies and checks
the published layers byte for byte, carrying both inputs into the package.

### Body skin: left as Remix renders it

**Standard: body skin gets no PBR.** A sheet that is only skin gets no override, so Remix keeps the
game's texture and its legacy material. Skin on a sheet shared with other classes (Guinevere's neck
on `衣.png`) gets the legacy look: roughness 0.7 (`rtx.legacyMaterial.roughnessConstant`), flat,
original colours. Tattoo and decal sheets classed as skin are left to Remix too. The `skin` class
carries `"original": 1`.

**Body skin changes are made and applied only on the user's request** (de-light, relief from the
model's own normal map, subsurface scattering, skin roughness, also on shared sheets). A look
tested on request but not kept goes to `presets/on_request/`, which nothing loads automatically;
`rpai generate/publish "<pmx>" --settings presets/on_request/<file>.json` shows it again when asked,
and a run without it returns to the standard. `generate` prints a note whenever skin gets PBR.

This was decided on 2026-10-25 from a full-body AABB on Guinevere:

* **Method.** Four variants, A original Remix skin, B PBR roughness 0.50 with the original colours,
  C B plus 25% de-light, D B plus 50% de-light. Each was shot twice back to back (AABB) from scripted
  cameras on the neck and collarbones, the abdomen and both arm views. The repeat noise was
  0.5–1.0/255.
* **The AI has nothing to add.** On all three models' body sheets the raw AI roughness is 0.70 ± 0.03
  and the normals tilt under 1.6°. Roughness 0.42–0.66 moved lit skin by at most 2/255 under room
  light, and B was indistinguishable from A: 1.4–2.2/255 on average, 95–101% of the painted detail
  kept.
* **De-lighting costs detail.** Toon skin sheets paint pink shading into joints and creases, and path
  tracing shades the same places again, so the knees read as rashes. Removing that paint softened the
  knee blush (peak redness 67 → 39 at 50%) but kept only 94/84/82% (neck/abdomen/arm) of the painted
  body detail at 50%, and 96/88/88% at 25%. The collarbones and the line below the navel faded.

Images: `docs/guinevere/aabb_*.jpg` (A–D per view, with the measurements), and `skin_ab.jpg` (the
earlier limb-only test that was not accepted as a standard). `delight` stays available for presets
that want it (`compose.delight`). It works on low frequencies only, protects strongly coloured
paint per texel, and skips decal sheets.

Subsurface scattering is the PBR feature that could change skin meaningfully. It is not part of the
standard yet; see the next section for what it takes in this runtime.

### Subsurface scattering in this runtime

The first attempts rendered skin near-black, which looked like a broken feature. It works once two
conditions are met (measured on Guinevere's forearm, `docs/guinevere/sss_test.jpg`):

| Body material | Skin, mean RGB |
| --- | --- |
| override, no SSS | 211 / 193 / 178 |
| + `subsurface_diffusion_profile = 1` | 165 / 134 / 106 (tan here; black in the first test) |
| + `use_legacy_alpha_state = 0`, `blend_enabled = 0` | 186 / 171 / 158 (scatters, but grey) |
| + `subsurface_transmittance_texture` = the skin albedo | 206 / 187 / 172 (6/255 from no SSS) |

Why, from the runtime's source: the runtime is the fork sambow23/dxvk-remix-gmod at commit 384581b1
(the log says `DXVK_Remix: remix-main+384581b1`), based on upstream 68ee7965, between remix-1.5.2
and 1.6.0.

* **Diffuse is replaced, not added to.** In diffusion-profile mode the direct-lighting pass zeroes
  the diffuse lobe and adds the scattering term (`integrator_direct.slangh`). That term comes from one
  probe ray per pixel, which must hit the same subsurface material. The indirect path (ReSTIR GI or
  NRC) has no scattering case. If the probe never lands, only the specular sheen is left.
* **The probe only hits opaque geometry.** Model Hotloader's draws carry an alpha-blend or
  alpha-test state, so Remix files the body as non-opaque and the opaque-only probe misses it.
  Forcing the material opaque fixes that, for body sheets only: decal and overlay sheets need their
  alpha.
* **The skin colour comes from transmittance.** In this mode the colour is the transmittance colour,
  default 0.5 grey, which is why step 3 is grey. Colour constants cannot be set in this fork, so it
  must be a texture.
* **Small scales fall short.** The probe length is `max(R × radius_scale × diffusionProfileScale × 2,
  0.1)` while the ray starts about R above the surface. Below about 0.5 it misses. Upstream fixed this
  in remix-1.6.0 (5941c63c, REMIX-5909); this fork does not have it.
* **Thin-opaque transmission** (`subsurface_measurement_distance`) only adds light that arrives from
  behind the surface, so it shows nothing under top lighting.

Units: the mean free path is radius × radius_scale × `rtx.subsurface.diffusionProfileScale` × 0.01
world units, about 0.005 GMod units at the defaults. `subsurface_max_sample_radius` is packed into
0–1, so 16 means R = 1.0. Using it for real would need a skin tuning pass with a full-body AABB
(radius, scale and the colour textures), like the one that set the current standard.

## Install

```
powershell -ExecutionPolicy Bypass -File setup.ps1
rpai doctor
```

`setup.ps1` puts the venv and model weights in `%USERPROFILE%\.rpai` (override with `RPAI_HOME`).
PyTorch's DLLs fail to load from long folder paths (WinError 206), so that runtime folder must stay
short. The code folder can live anywhere.

Requires: Python 3.12, an NVIDIA GPU (tested on an RTX 5090 with torch 2.8 cu129), and the RTX Remix
Toolkit installed (it provides `nvtt_export.exe`). The game must be running for live hashes.

## Use

1. Import and spawn the model in game (Q → MMD) so Remix captures its textures.
2. `rpai run "<model.pmx>"`
3. **First time only:** Remix discovers new mod folders only at startup. Press **Alt+X → Enhancements →
   Loaded USD Files → "Rescan Mods & Reload USD Stage"** once, or restart the game. After that, every
   publish reloads automatically within about a second, because the runtime watches `mod.usda`'s timestamp.

Commands, each taking the PMX path:

| Command | Purpose |
| --- | --- |
| `run` | hashes + generate + publish |
| `hashes` | refresh hashes (re-run after showing hidden parts in game) |
| `generate` | AI maps into `%USERPROFILE%\.rpai\work\<model>\` (skips up-to-date textures; `--force` redoes them) |
| `publish` | DDS + mod layer |
| `remove` | take this model out of the mod |
| `compare` | screenshots the running game without, then with, this model's layer from the current camera, and saves a side-by-side in the work folder. After each reload it waits for Remix's "swapped in" log line: with 1.4 GB of preloaded DDS the swap lagged the reload by ~9 s, and a fixed delay photographed the old state |
| `status` / `doctor` | list published models / check the install |

Useful options: `--only "衣.png,髪.png"`, `--max-size 2048`, `--upscaler span` (about 40× faster,
slightly softer), `--height --displacement 0.03` (POM height maps, off by default),
`--emissive-intensity 0.7` (eye emission level, default 1),
`--emissive-adaptive-intensity 5.555555555555555` (adaptive/fallback ratio, default `1/0.18`; `0` off),
`--mod my_mod`, and `--settings tune.json`.

For an **8 GB GPU audience**, generate and publish with `--max-size 2048` (or use `run` with that
flag). A publish-only flag does not resize previously generated maps. Check per-texture size
overrides before generating and verify the referenced DDS dimensions before packaging. See
[Publishing for 8 GB GPUs](../SKILL.md#publishing-for-8-gb-gpus) for commands and memory costs.

Review `work\<model>\preview.jpg` (albedo, class map, normal, roughness, metallic and emissive per
texture) and `work\<model>\classes.json` (class and reason per material).

### Tuning

`tune.json`:

```json
{
  "max_size": 4096,
  "presets": {
    "cloth": {"rough": 0.85, "normal": 1.2},
    "metal": {"rough": 0.2},
    "_materials": {"11": "cloth"}
  }
}
```

Class fields: `rough` (base roughness), `rough_ai` (how much AI variation to keep), `metal`,
`normal` (AI normal strength, 0 = flat, above 1 amplifies), `height`, `emissive` (light emitted as
a multiple of the albedo; 0 when absent), `delight` (fraction of broad painted shading removed
from the albedo; 0 when absent), `aniso` (Remix anisotropy -1..1 along the texture axes, published
as `anisotropy_texture`; 0 and no map when absent; negative stretches highlights along V, e.g. down
a leg), `f0` (lift the class's median linear luminance on the mesh to this reflectance, one factor
per sheet up to 3x, the albedo then published; 0 when absent; opt-in: on Robin R18, f0 0.74 brought
satin gold from 12-25% under the original brightness to -10%..+4%, at the cost of a paler halo; see
`references/standards.md`) and
`original` (1 = leave these texels to Remix; a sheet made only of such classes gets no override).
`_materials` pins a PMX material index to a class.

**Gold type per character** (2026-10-26, details and the table in
`references/standards.md`): painted gold has a low reflectance (F0 0.17-0.55 against real gold's
~0.74), so at the aggressive polish (0.12) it mirrors a dim room as dark bronze (Robin ZZZ's halo
-37% in game). The per-model presets therefore give painted golds a satin metal (0.30-0.36: both
Robins, Guinaifen/Guinevere, Kafka's bronze, Firefly's brass) and keep the polish where the metal
is bright or tiny (Cyrene's silver, Castorice's brooch, Firefly's silver bunny trim).

The defaults use cloth normal 1.44 and leather 1.12. Both were raised 1.6× after the Hyacine A/B
below. For the subtler original look, pass `presets/mild_normals.json` (cloth 0.9, leather 0.7):
`rpai run "<pmx>" --settings presets/mild_normals.json`. The AI outputs (upscaled albedo, raw
normal and roughness) are cached in `work\<model>\raw`, so re-tuning only recomposes the maps. That
takes seconds, and only textures that contain a changed class are redone. `--no-prune` on
`publish`/`run` keeps the previous DDS files, so an older layer can still be swapped in for an A/B.

Presets:

* `presets/aggressive.json` pushes every material class away from Remix's legacy roughness 0.7.
  Cloth goes to 0.55, stockings 0.30, leather 0.20, latex 0.08, hair 0.28 and metal 0.12. It
  amplifies the AI roughness variation (up to 1.2×) and sets normals well above 1 (cloth 2.6,
  leather 2.0). It leaves skin and the face classes at their anime-safe defaults (see above).
* `--settings` can be given several times; later files win, and a file can `include` others.
* **Per-model presets:** `presets/models/<model key>.json` is merged automatically for that model,
  after `--settings` and before command-line flags. Use it for class pins (`_materials`) and a
  model's style. Example: `presets/models/firefly_r18_0d01d7d3.json` includes the aggressive preset
  and pins seven materials.
* **Per-texture size:** `"textures": {"丝袜.png": {"max_size": "source"}}` (or a number) lifts the
  4096 cap for one sheet. The albedo is then published at that size, replacing the game's copy.
  Firefly's stockings atlas holds ~20 stocking designs in 11059×8847, and the legs use one
  1276×1516 cell. Model Hotloader's 4096 copy leaves that cell 472×561 texels, so full resolution
  gives the legs 2.7× the texels per axis (`docs/firefly_stockings_texture_res.jpg`). Remix logs a
  harmless "doesn't fit into STAGING memory" error for textures over 96 MB. It then uploads them
  synchronously instead of streaming (a short hitch on reload; the texture stays resident).

### Recoloured albedo (`albedo_source`, on request)

* **`"textures": {"body.png": {"albedo_source": "<path>"}}`** makes a recoloured copy of a sheet
  (relative to the texture's folder, or absolute) the albedo and the AI input for that sheet, and
  always publishes it as the albedo, since the game still holds the original. The sheet then gets
  an override even when all its classes keep the original look. Skin colour is body skin work:
  made only on the user's request.
* **`scripts/recolour_skin.py`** makes such a copy: it moves the skin base tone (median of bright,
  low-chroma texels on the given materials' UV islands) to a reference's in CIELAB a*/b*, keeps
  lightness, keeps 75% of the shading chroma around the base, and gives vivid texels (lips,
  nipples) only part of the shift. Measure the base on the mesh (`--pmx`, `--materials`):
  Evernight's peach background fill (b* 9.3, against 6.0 on the mesh) made the body cool.
  Evernight (2026-10-30): skin Lab 94.2/5.0/6.0 → 94.2/2.0/1.2 against the reference's
  91.6/1.5/1.0, lightness spread unchanged.

### The model's own normal maps, per-texture classes, subsurface scattering

* **`"textures": {"Body.png": {"normal_map": "Body normal.png"}}`** replaces the AI normals of that
  sheet with a normal map the model ships under any name (relative to the texture's folder). The
  class `normal` strength still scales it, so a skin class at the default 0 stays flat; on skin
  sheets it is used only on the user's request (see Body skin below). For an artist's map, set the
  classes on that sheet to `normal` 1.0 in its per-texture presets (the class defaults are tuned
  for the weak AI normals). A regular map's Y convention is measured from integrability: a height
  field's slopes have no curl, and green read with the wrong sign gives them plenty. Robin's ZZZ
  `_N` maps had 3.0x and 2.4x more curl read as OpenGL, so they are DirectX; integrating both
  readings showed raised stars for DirectX and streaked saddles for OpenGL. Below a 1.5x margin
  OpenGL is assumed. Game rips may keep the normal in red and green only (Robin's maps hold a mask
  in blue, mean 125/255); when blue is no z, z is rebuilt. A map whose red and green channels are
  identical is a flattened one:
  Guinaifen's `Body normal.png` (2048, lavender base 176/176/241) holds one slope channel, about
  (nx + ny) / 2 of an OpenGL map. `compose.relief_normals` rebuilds the height along that diagonal
  (chosen by least energy; anatomy check: the navel must be a pit, the kneecaps equal bumps),
  blurs away the 8-bit steps, drops shapes broader than 96 texels (the mesh has them) and puts a
  soft knee on the slope against bake faults. Its slopes are subtle (p99 2.4° as authored), so
  skin needs a strength around 8-16. UV borders get the same care as the AI input does: the map's
  own bake padding does not line up with the model's islands (its steps drew a slit down the
  sides of Guinaifen's body, where the front and back halves meet), so the slope outside the
  islands is replaced by the island edge's own, and the relief fades to flat over the last 12
  texels of each island, because the two halves are rebuilt separately and would not agree at the
  seam.
* **Per-texture class presets**, `"textures": {"Body.png": {"presets": {"skin": {...}}}}`, change a
  class on one sheet only. Guinaifen's skin class also covers her upper neck on the cloth atlas,
  which must not get the body sheet's relief strength.
* **`sss` / `sss_radius` class fields** turn on Remix's diffusion-profile subsurface scattering for a
  sheet whose every class asks for it (`sss` = `subsurface_radius_scale`, `sss_radius` = the RGB
  mean free path ratio, a `color3f` that loads since runtime `c6b48ed1`). Publish forces the
  material opaque and uses the published albedo as the transmittance texture (see below for why).

### Region rules (parts of a material)

Anime sheets paint gold trim and embroidery straight onto cloth, so a per-material class cannot
make them metal. `regions` in a settings file reclassifies texels by the colour painted under them:

```json
"regions": [
  {"texture": "衣.png", "within": ["cloth"], "class": "metal",
   "hue": [28, 58], "sat": [0.30, 1.0], "val": [0.50, 1.0], "doc": "gold trim"}
]
```

`within` limits a rule to classes, `rect` (UV fractions x0 y0 x1 y1) to an area, and
`hue`/`sat`/`val` to an HSV range (hue may wrap). Only texels a UV triangle covers are matched. One
opening removes speckle and one dilation keeps anti-aliased edges. Rules apply in order, each on
the classes the rules before it left, so one rule can turn gold islands into metal and the next
the white facets inside them into gem. Check each rule before generating.

**Whole UV islands.** `"islands": 0.6` takes every UV island (triangles joined by shared vertices,
one piece of the unwrap) whose texels within the rule's classes match the colours for at least
that fraction; with `rect`, texels outside the rectangle count as misses, so a rectangle picks the
islands that lie in it. `"box": [x0, y0, z0, x1, y1, z1]` keeps only islands whose centroid lies
in that box (PMX model units, Y up). Robin's whole outfit, skin and jewellery are one material on
one sheet, and texel colours overlap (the champagne gold and the warm skin shading both read as
hue 20-35 at low saturation), but each island is one thing: the 20 skin islands are 100%
skin-coloured (the next best, a lace sleeve, 60%), the 91 gold ones 40-100% gold (the rest 6% or
less), and the 18 islands of shoes and ankle straps are the purple ones below 2.6 units. Set
thresholds in such gaps, not near an observed value: at 0.6 the lace sleeve's 0.60 flipped
between runs at different sizes. On Guinevere the tinted UV overview made maroon panels look navy and led to a wrong
"silver" rule; `docs/guinevere/gold_trim_regions.jpg` shows the corrected result on the raw
sheets. `docs/guinevere/TEXTURE_ANALYSIS.md` is a worked example of reviewing every texture and
region.

### Authored PBR maps

When a texture is named like `X_BaseColor` (also `_Albedo`, `_Diffuse`, `_Color`), sibling files
`X_Normal`, `X_Roughness`, `X_Metallic` and `X_Height` are used instead of the AI for those maps,
without class tuning, since an artist's map beats a guess. The normal map's Y convention is
measured from the height map: green follows the height gradient down the rows in OpenGL maps and
opposes it in DirectX ones. Without a height map, OpenGL is assumed (Substance's default). Black,
unused texels in exported normal maps are made flat.

### Moved or renamed model folders

The PMX is matched to its Model Hotloader import by path first, then by content: each import's
manifest records the PMX's SHA-256 (`sourceHash`). Renaming the folder after importing still works.

### Compiled models (`--mdl`)

A character can also reach the game as a compiled addon: a QC compile of the PMX, such as
sheepylord's ports (`models/sheepylord/<game>/<name>.mdl` with VMT/VTF materials in a folder addon).
Give the model path once and rpai remembers it for that PMX (`%USERPROFILE%\.rpai\compiled_models.json`):

```
rpai run "<Robin.pmx>" --mdl models/sheepylord/zenless_zone_zero/robin_zzz.mdl
```

The PMX still gives the UVs, material names and original images. The MDL lists its materials and
their folders, each VMT names its `$basetexture`, and that VTF is what Remix hashes. PMX materials
are matched to the MDL's by name (the compile names them after the PMX's; Robin: 11 of 11).
Files are looked up in the MDL's own addon first, then in the other folder addons, then in
`garrysmod/`. The model key is `<name>_<sha1 of the model path>[:8]` (Robin: `robin_69c55742`).
Compiled VTFs are DXT-compressed and upload their blocks unchanged, so the offline hash of the top
mip is exact (3 of 3 live hashes on Robin). `abtest.py --asset models/.../x.mdl` frames the
spawned entities of that model; it has no part hiding (`--hide` needs Model Hotloader).

**The PMX images must not carry an alpha the VMT would cut.** rpai publishes the upscaled albedo
with the source image's alpha, and Remix keeps the game's alpha state. sheepylord's Mornye-style
VMTs set `$alphatest 1` / `$alphatestreference 0.5` even where the game VTF is opaque, so a PMX
image whose alpha is a mask rather than coverage cuts the material away in game. Wuthering Waves
`_D` sheets keep a toon mask in alpha (mean 0.2-0.4): Hiyuki Alt's skin 1, read from the raw sheets,
rendered as a few fragments, while skin 0, read from the port's own RGB copies, was fine
(2026-10-27). Point the PMX at RGB copies (the port's `tex/` or, for a second skin family, copies
made beside a renamed PMX twin), and check a capture of the published state before moving on.

**A second skin family** (`$texturegroup skinfamilies`) draws other VMTs (`<name>2` in SCMI ports)
with their own textures and hashes. rpai handles it as a second PMX: a copy of the model with every
material renamed like the skin's VMTs and pointed at that skin's images, under its own model name
(key), bound to the same `--mdl`. Hiyuki Alt: `hiyuki_08f3c33e` and `hiyuki2_08f3c33e`.

## Results on Hyacine (2026-10-25, RTX 5090, game running)

* 19 textures and 21 material overrides (the two hidden opaque sheets carry two candidate hashes
  each). Generation took 8 min with the DAT upscaler while sharing the GPU with the game; DDS output
  is 654 MB.
* 12 hashes came live from the game. 7 were predicted for parts not drawn yet: the alpha-0 outfit
  layers and the morph-toggled overlays.
* The first publish needed one "Rescan Mods" click. The second publish hot-reloaded on its own
  (`USD mod async reload completed successfully` in `rtx-remix/logs/remix-dxvk.log`).
* A/B from a fixed camera (`docs/hyacine_compare.jpg`, crops in `docs/hyacine_ab_*.jpg`): the
  background differs by 1.3/255, which is path-tracing noise, and the changes sit on the model. The
  shoes (leather 0.42 vs Remix's legacy default roughness 0.7), metal fittings, the hair accessory
  and the eyes change most. The cloth stays close to before (0.78 vs 0.7), and the face does not
  change (flat on purpose).
* With the first defaults (cloth 0.9, leather 0.7), the normal maps were mild. The cloth sheets
  measured 2.6° mean tilt (p99 35°, mostly along painted outlines), the rope texture 2.5° (p99 11.5°),
  and skin, face and hair stayed flat.
* Raising cloth and leather 1.6× (now the default) takes the cloth sheet to 3.8° mean tilt (p99 48°).
  In game (`docs/hyacine_normals_*.jpg`: original / AI at 0.9-0.7 / AI at 1.44-1.12 / heatmap), the
  extra relief appears only on trims, seams, the dress emblem and the shoe stitching, at 1.5–3.1/255
  mean change against a 1.3/255 noise floor. Flat painted fabric has no weave detail for the AI to
  find, so it stays flat at any strength. The big visible step is original → AI: leather speculars
  and metal trims.

## Results on Firefly (2026-10-25, aggressive preset)

* 19 textures and 22 overrides. 13 hashes came live; 6 hidden parts (bunny suit, ears, heels,
  beads, blush, one tattoo) are predicted. The heels use their authored Substance maps (OpenGL
  normals, measured). 4 accessory sheets are byte-identical to Hyacine's and shared with her.
* A/B from a fixed camera (`docs/firefly_compare.jpg`, crops in `docs/firefly_aggressive_*.jpg`,
  floor noise 1.0/255): the stockings gain a glossy nylon highlight, the metal brooch and fittings
  reflect, the bow pieces turn glossy, the jacket gets a satin sheen, and trims are embossed. The
  model changes by 2.4–3.7/255 on average, with the strongest pixels on highlights.

## Results on Guinevere (2026-10-25, aggressive + region rules)

Every texture and region was reviewed (`docs/guinevere/TEXTURE_ANALYSIS.md`). Painted gold trim
and embroidery became metal through region rules, and the gong and jewelry are metal. The mallet
and headdress are glossy lacquer and the nylon is stockings. In a fixed-camera A/B the
gold-embroidered skirt changes by 17/255 on average and the bodice and boots by 10–11/255, against
a 4/255 floor. Polished gold and patent leather are the most visible changes. Five of her textures
are byte-identical to Hyacine's or Firefly's and keep those models' maps.

The face sheet was then re-tuned on a close-up (`docs/guinevere/face_ab.jpg`, `eyes_ab.jpg`). Against
the original materials, the eye whites go from dirty grey (63–165/255) to clean white (190–208),
still just under the cheek (217). The catchlight goes from 208 to 254, and the iris stays vivid
gold. Skin, teeth and tongue stay within 7/255 of the original, and the hair and floor references
moved at most 1/255 between those shots.

The body skin was then tested on the full body (`docs/guinevere/aabb_*.jpg`; method under
[Body skin](#body-skin-left-as-remix-renders-it)). A limb-only test had favoured a 50% de-light, but the
full-body AABB showed it fading the painted neck, collarbone and abdomen detail (82–94% kept). PBR
roughness alone was indistinguishable from the original, so body skin is left to Remix on all three
models.

## Results on Guinaifen (2026-10-25, re-import of Guinevere's model)

The same character re-imported from another folder is a new model key (`new_mmd_model_1c2ed2fc`),
but its textures are byte-identical, so it shares every Remix hash with `new_mmd_model_9cdc990f` and
its layer (alphabetically first) wins for all 13 overrides.

* **Stocking seam crease fixed** (see [UV island borders](#uv-island-borders-gutters)). Near-border
  normal tilt on `siwa.png` 4.0° → 0.8° (interior 0.6°). In game, AABB of 6 variants × 6 views
  with repeat noise 0.9-1.9/255: the crease's line contrast went from 5.9 / 3.6 / 2.7 / 1.7 (inner
  shin, outer shin, outer thigh, top-down overview) to -0.6…0.35, the level of the original Remix
  render (-0.2…0.06).
* **Stockings: the user kept the old satin look** (variant B): the seam fix only, with roughness set
  to 0.42 in the per-model preset. Before the fix, the gutter bias had turned the aggressive 0.30
  into an effective 0.42. Measured but not chosen: the aggressive 0.30 (wet latex, orange-peel
  highlights), 0.34 with `aniso` -0.6 (highlight stretched down the leg), and that with AI normals
  0.7 (cleanest streaks). Sheets and metrics:
  `%USERPROFILE%\.rpai\work\new_mmd_model_1c2ed2fc\aabb_stockings_20261025\`. The variant layers
  saved there are records only: their stocking DDS files were pruned when B was published.
* **Body skin from the model's own normal map, tested on request and reverted at the user's request**
  (the live layer is back to the post-stocking state, body skin left to Remix). The flattened
  `Body normal.png` rebuilt by `relief_normals`, strength 12, roughness 0.55, changed skin by
  2.9-7.8/255 against 0.4-0.7 repeat noise: kneecaps, toe pads and creases, the spine groove and the
  clavicle line read as shape. Subsurface scattering was rejected (artifacts and a neck seam, see
  runtime-notes). The side seams of the body first showed a slit (line contrast 1.9-2.8 at the
  flanks); the border handling in `relief_normals` brought it to the original's 0.0. The recipe is
  kept unapplied in `presets/on_request/new_mmd_model_1c2ed2fc_body_skin.json`; sheets are in
  `aabb_skin_20261025\` in the same work folder (`round3_*` for the seam fix).

## Results on Kafka, Cyrene and Castorice (2026-10-25, aggressive)

Three ragdolls in one scene: Kafka (`new_mmd_model_4ab9d7e3`, 13 overrides), Cyrene
(`cyrene_dd112b38`, 17) and Castorice (`castorice_7b47f232`, 17). The game had Cyrene and
Castorice imported from their `_NoBDSM` PMX files; the copies the user provided are Blender
re-exports with identical UVs, materials and byte-identical textures, so rpai ran on the imported
PMX files. Every texture and metal material was reviewed per material on the raw sheets (the
reasons are in each per-model preset's `doc`); stockings use the 0.42 satin roughness the user
chose for Guinaifen. The AI stage took 26 min for Kafka (2048 sheets, upscaled) and about 8.5 min
each for the others (mostly 4096 or 8192 sheets, only downscaled).

* **Measured before/after** on 13 scripted views shot twice each, before any of the three layers
  was published and after (`%USERPROFILE%\.rpai\work\_batch_20261025\ab`, `final_metrics.md`,
  `summary_*.jpg`): repeat noise 0.7-2.4/255 per view, mean change 2.1-6.9, 2-24% of the pixels
  changed beyond 4x their local noise. Kafka changes most (coat satin sheen +21/255 on a fixed
  patch, embossed seams, polished bronze trims, patent-leather straps), then the three faces (eye
  whites +28 and irises +12 to +14 per the face standard), then Cyrene's and Castorice's dresses.
* **Body skin unchanged.** Cyrene's and Castorice's `Body.png` also hold the nails and the
  tongue, so they get an override whose skin texels are the legacy look (0.702, flat, the game's
  albedo); bare skin patches moved 0.4-0.9/255 (thigh, knee, shin, arm).
* **Two metal mistakes found in game and fixed:** Kafka's earring pearl rendered as a dark chrome
  ball (patch 207 -> 126/255; a region rule turns the white texels of the earring metal into a
  smooth dielectric, back to 207) and Cyrene's 首饰 "Jewelry" held only white rose petals and
  leaves (dark chrome roses; pinned to cloth). See `references/texture-review.md`.
* **Shared sheets and layer order.** `castorice_*` and `cyrene_*` sort before the earlier layers,
  so for sheets byte-identical to ones Hyacine or Firefly already override (`bq.png`, `黑.jpg`,
  Castorice's heels) their presets leave the sheet to the existing layer (per-texture
  `original: 1`) instead of taking the hash over. Accessory sheets that uploaded with new hashes
  this session (`口球.png`, `Blindfold Text.png`) are owned by Castorice's layer.
* **Name rules added** for gems named after their setting, glasses, the band-aid, leg straps,
  tear and "Shy" overlays and veils (`classify.py`); the four earlier models classify unchanged.

## Results on Robin R18 (2026-10-26, aggressive)

The HSR Robin (`知更鸟.pmx`, `robin_r18_f9c3e4b4`, Model Hotloader), whose outfit atlas is the
same art as `robin_zzz`'s body sheet. 83 materials, 20 sheets; 14 hashes live, 6 predicted for
hidden parts. Seven sheets are byte-identical to ones earlier layers already override, and this
layer sorts last, so only her own 13 were generated (`--only`); the AI stage took 222 s. The
review found four name traps: purple satin wrist cuffs named 手环 ("bracelet", metal by 环), a
face mask 口罩 (mouth by 口), white crystal halo flowers 光环花 (metal by 环) and the neck 脖子 on
the outfit atlas (cloth by the texture name). Gold piping painted on the dress becomes metal by
colour; her gold is satin champagne (0.30) by the gold-type decision.

Measured in game the next session (bracketed A, P polished, S satin, A2; 6 views twice; repeat
noise 0.5-1.0/255, drift 1.6-3.3; `%USERPROFILE%\.rpai\work\robin_r18_f9c3e4b4\aabb_20261026\`,
`robin_r18_gold_types.jpg`): the published layer changes the model by 3.6-6.7/255 per view against
the mean of both originals. Iris +27.2 (eye standard), face +4.6, white dress +4.1, purple bodice
+6.9; body skin +1.4 to +2.0 against drift up to +3.0 (unchanged, as the standard requires). Gold
pixels: satin -19% (halo) to -25% (torso), polished -37% to -45%, with equal highlight peaks; the
numbers are in `references/standards.md`. A second bracketed run tested the reflectance lift
(`aabb_20261026_f0`): satin plus `f0` 0.74 came closest to the original brightness (pixel-weighted
distance 8.2%, against 10.8% for f0 0.55 and 21.0% for satin alone) and is published, with a paler
halo as its cost.

## Re-imports whose source folder is gone (`--asset`)

Guinaifen's import (`new_mmd_model_1c2ed2fc`) wins every hash it shares with Guinevere's, but her
source folder was deleted. `rpai <command> <Guinevere's 桂乃芬.pmx> --asset 1c2ed2fc` binds the
byte-identical PMX to her import (same key, same preset). The raw AI cache is named after the
source path, so it was renamed to the new path's signature after checking every texture's
Hotloader content key matched Guinevere's (14 of 14); otherwise the AI stage reruns.

With no copy of the PMX anywhere, the import itself has one: `assets/<id>/model.bin` is the
source PMX byte for byte (its SHA-256 is the manifest's `sourceHash`). March 7th (2026-10-30,
`model_e2c25f9e`) was rebuilt as `%USERPROFILE%\.rpai\sources\march_7th_1.0\三月七 1.0.pmx` from it,
with the textures the manifest names (`materials[].base`) copied from another download and checked
against the import's VTFs pixel by pixel (`remixhash.top_mip_rgba`; mean difference 0.0 on 5 of 5).

## Results on Robin (2026-10-25, aggressive, a compiled addon)

The first character that came as a compiled addon, not a Model Hotloader import: sheepylord's
`robin_zzz` (`models/sheepylord/zenless_zone_zero/robin_zzz.mdl`), a ragdoll lying face up, with
the source PMX and the game rip's textures beside it. See [Compiled models](#compiled-models---mdl).

* **3 sheets, 3 overrides, all hashes live** (DXT5 prediction 3/3). The DAT stage took 407 s for
  the three 2048 sheets (4096 out); recomposing after a rule change takes about 10 s.
* **The rip's own normal maps** (`Robin_Body_Map1_N`, `Map2_N`, 1024) replace the AI normals at
  strength 1.0: red/green only, rebuilt z, DirectX by the curl test. Dress folds, embossed trims,
  stars and hair strands are the artist's relief; skin stays flat.
* **One material, 622 islands.** The `Body` material carries the dress, gloves, skin, gold,
  crystals and shoes on one sheet. Island rules took 20 skin islands (all 100% skin paint; next
  best 60%, the lace sleeve), 91 gold islands (40-100%; the rest 6% or less), 2 crystal stars and
  18 shoe and strap islands below 2.6 of 20.9 units (96-100% purple). The reasons are in the
  per-model preset's `doc`.
* **Measured in game, A (original Remix) vs B (PBR layer), each view shot twice:** repeat noise
  0.5-0.8/255 on the model; model change 6.0-10.3/255 over 6 views
  (`%USERPROFILE%\.rpai\work\robin_69c55742\aabb_20261025\`, `run1`, `robin_before_after.jpg`).
  The floor moved too (2.4-6.1/255): lighting drifts in this map over minutes. A bracketed run
  (A, B, A again, `run2`) measured that drift at 2.5-3.2/255 on the model between captures 4
  minutes apart, and B against the mean of both A captures at 3.6-7.6/255. Fixed patches, B minus
  the mean of A before and after: iris +22.9, eye white +15.7 (face standard), white dress +7.0,
  shoe -6.3, heel -4.1 (patent gloss), gold star -31.6. Body skin did not change beyond the drift
  (shin -1.6, while the floor next to it moved -1.9 and the drift was -2.2), as the standard
  requires.
* **Polished gold reads dark in this room.** At the aggressive metal roughness 0.12 the
  champagne gold reflects the dark wooden floor: the halo ring went from 152 to 96 in luminance,
  the gold stars from 118 to 86. That is the same metal standard as Kafka's bronze and
  Guinevere's gold; a satin gold (roughness about 0.3) is a per-model preset change if wanted.
* **Bracket long captures.** With drift of about 3/255 over 4 minutes, a single A-then-B capture
  overstates small effects (run 1 put 4-6/255 on the floor). Shoot A again after B and compare B
  with the mean of both A captures, as `run2` did.

## Results on Eldreda Sunbringer and Eldreda Alt (2026-10-27, aggressive, compiled addons)

Two ragdolls from one folder addon (`eldreda_sunbringer.mdl`, `eldreda_sunbringer_alt.mdl`,
keys `eldreda_207edb89` and `eldredacasual_9345b723`). All 10 hashes were live, and the DXT
prediction agreed 5/5 per model. `face.png` and `hair.png` are byte-identical in both models:
Eldreda's layer owns them, and the Alt's preset leaves them alone. `skin.png` is left to Remix.

* **Name traps.** `Bodysuit` and `Top` took skin from the texture name 体 (body). The three
  English-named `EyeHighlight` catchlight meshes fell to face. Horns, head gear and ornaments on
  the hair sheet are hard parts, pinned to leather (no plastic class exists).
* **Island and colour rules.**
  * Eldreda's champagne-gold paint (hue ~28, sat ~0.37) needs the wider hue 12-48, sat 0.12-0.70.
  * The Alt's silver is painted blue-tinted (hue 218-222, sat 0.10-0.22) while her white fabric
    is neutral; rectangles keep the rules off the denim and her blue-grey jacket stripes.
* **In-game AABB** (bracketed): leather and armour +12% to +13% with brighter highlights, cloth +3%
  to +11%, painted gold -7% to -25% and silver -13% to -38% as satin metal; skin and face within
  drift. Numbers are in the per-model presets' `doc`.
* **The AI stage needed a commit cap** beside the game (`references/runtime-notes.md`, "Commit
  memory"). It ran one texture at a time, waiting while another session's uncapped rpai jobs held
  15-18 GB.
* **Captures need the player near the target** (`references/testing-protocol.md`). The Alt was
  re-shot with the player teleported beside her and returned afterwards.

## How the hashes are found

Remix hashes the top mip of each texture as uploaded (`D3D9CommonTexture::SetupForRtxFrom`):
`XXH64(data, size, 0)` because `rtx.useObsoleteHashOnTextureUpload = True` in this install's `rtx.conf`.
Measured on Hyacine against the live hashes:

* VTFs with an alpha flag upload as BGRA: 5 of 5 reproduced.
* Opaque VTFs mostly upload as X8R8G8B8 with a zero pad byte (BGR0): 4 of 7 reproduced. The face
  sheet uploaded as BGRA, and the body and hair sheets matched nothing.

So **live hashes win**, and prediction only fills in textures that have not been drawn yet. Predicted
textures get every plausible candidate hash; an override for a hash nothing uses does nothing.
`hashes` prints which textures are predicted. Show those parts in game and re-run it to confirm them.
A hash the game reported once is kept for later runs, shown as "live (earlier run)", including
`--no-live` runs and parts hidden at the time. Texture keys are content hashes, so it stays valid
until the texture or `rtx.useObsoleteHashOnTextureUpload` changes. Before this, a `--no-live` run
swapped 3 of Guinevere's verified hashes for wrong predictions, and their overrides silently
stopped applying.

The console channel is the `WM_COPYDATA` message behind Source's `-hijack`: the game executes the
payload as console text. Lua goes through `lua_run_cl RunString(file.Read(...))`, and the client writes
its answer to `garrysmod/data/rpai/`.

## Output

```
rtx-remix/mods/ai_pbr/
  mod.usda                         sublayers, one per model (rewritten atomically on publish)
  models/<model>.usda              over "mat_<HASH>" { over "Shader" { inputs... } }
  textures/<model>/<sha16>_<digest>.<a|n|r|m|h|e>.rtex.dds
```

DDS names carry a content digest, so a texture the runtime holds open is never overwritten. Stale
files are pruned on the next publish. Normals are written in Remix's octahedral encoding
(`inputs:encoding = 0`). The albedo is replaced when the upscale is larger than the game's texture
or when a preset de-lit it; otherwise Remix keeps the game's own albedo.

Identical texture files in two models (common MMD accessory sheets like `asanawa.png`) have one
Remix hash, so they are one material in game. Both model layers override it, the alphabetically
first layer wins (USD's earlier sublayer is stronger), and `publish` prints a note naming the
winner.

Remix checks mods in path order and the first one with a replacement for a hash wins
(`Mod::ComparePtrs` in `rtx_mod_manager.h`). `!advanced_material_editor` sorts before `ai_pbr`, so
your Advanced Material Editor profiles still override the AI maps. `~gmod_topbr` sorts after, so the
AI maps override the automatic ToPBR conversion.

## Limits

* Models must come through Model Hotloader, or a compiled addon whose material names match the
  PMX's (`--mdl`), because the texture and VMT mapping is read from one of them.
* PBRify is trained on photographic CC0 materials. On painted anime textures, normals mostly follow
  painted outlines, and baked shading is not removed by default (`delight` is opt-in, see
  [Body skin](#body-skin-left-as-remix-renders-it)). Height maps are therefore off by default.
* This Remix runtime (`bin/win64/d3d9.dll`, fork sambow23/dxvk-remix-gmod 384581b1) rejects every
  3-component material and light input (`color3f`, `float3`, `double3`, `half3`, `color3d`,
  `color3h`). It logs "has unexpected type, using default value", about 400 times each for
  `diffuse_color_constant`, `emissive_color_constant` and `subsurface_radius` (Advanced Material
  Editor profiles and other mods included).
  * The cause is a type check the fork added in its "fix crashes" commit 061b8be0
    (`rtx_material_data.h`, `rtx_lights_data.cpp`). It only accepts dxvk's own `Vector3`, which no
    USD value ever holds. Upstream Remix has no such check.
  * The same check drops `uint8` inputs unless written as `uchar`, and never loads
    `alpha_test_type` or `blend_type`.
  * A rejected value still hides weaker layers' values behind the default.
  * Bools, floats and textures load, so rpai only writes those. For lights, colour temperature
    (`enableColorTemperature`, `colorTemperature`) is the only way to set a colour.
* Material classes are keyword heuristics for CN/JP/EN names. Check `classes.json` and pin mistakes
  with `_materials`.
