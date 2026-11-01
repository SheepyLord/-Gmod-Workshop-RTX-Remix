# Material standards and the evidence behind them

These class values are the built-in defaults in `tool/rpai/classify.py`, set from in-game
measurements on this machine's Garry's Mod RTX. C-16's publish-time adaptive emission ratio below
is provisional, authorised by the user's eye-brightness request and awaiting Claude's in-game tuning.
Change a standard only with a new full-body
AABB and the user's decision (see `testing-protocol.md`). Per-model tweaks belong in
`tool/presets/models/<model key>.json`, not in the defaults.

## Class table (defaults)

| Class | rough | rough_ai | metal | normal | Extra | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| default | 0.65 | 0.6 | 0 | 0.7 | | unknown parts |
| cloth | 0.78 | 0.6 | 0 | 1.44 | | normals raised 1.6× after the Hyacine A/B; `presets/mild_normals.json` gives 0.9 |
| stockings | 0.55 | 0.4 | 0 | 0.5 | | nylon/pantyhose (`袜`, `siwa`) |
| leather | 0.42 | 0.5 | 0 | 1.12 | | shoes, belts, collars, blindfolds |
| rubber | 0.22 | 0.2 | 0 | 0.3 | | latex, gags |
| hair | 0.40 | 0.35 | 0 | 0.35 | | |
| metal | 0.28 | 0.5 | 1 | 0.6 | | trims, chains, jewellery, painted gold via region rules |
| gem | 0.05 | 0 | 0 | 0.2 | | glass, crystal, jade |
| nail | 0.25 | 0.1 | 0 | 0.1 | | |
| skin | 0.70 | 0 | 0 | 0 | `original: 1` | **left as Remix renders it** (see below) |
| face | 0.60 | 0 | 0 | 0 | | matte, flat |
| mouth | 0.60 | 0 | 0 | 0 | | mouth interior, teeth and tongue |
| lash | 0.85 | 0 | 0 | 0 | | lashes, brows, eyeliner = ink |
| sclera | 0.25 | 0 | 0 | 0 | `emissive: 0.025` | eye white |
| eye | 0.06 | 0 | 0 | 0 | `emissive: 0.04` | iris |
| highlight | 0.50 | 0 | 0 | 0 | `emissive: 0.6` | catchlight mesh (`目光`, `ハイライト`) |
| wet | 0.15 | 0.1 | 0 | 0.2 | | no rule assigns it; for pins only |

Field meanings:

- `rough`: base roughness.
- `rough_ai`: how much of the AI roughness map's local variation is kept around the class level.
- `normal`: AI normal strength (0 = flat).
- `emissive`: light as a multiple of the linear albedo, at intensity 1. Re-level it at publish
  time with `--emissive-intensity`.
- `delight`: opt-in, fraction of broad painted shading removed from the albedo.
- `original: 1`: leave the texels to Remix. A sheet made only of such classes gets no override.

`presets/aggressive.json` pushes the material classes (cloth 0.55 / normal 2.6, leather 0.20 / 2.0,
metal 0.12, hair 0.28 and so on) and deliberately leaves skin and all face classes alone. Firefly and
Guinevere use it, through their per-model presets; Hyacine uses the defaults.

**Open finding, not a standard change (2026-10-30, Evernight and March 7th):** at the aggressive
`rough_ai` (cloth 1.2, leather 1.0) the AI roughness map tracks paint brightness, so dark paint turns
glossy. Median roughness on mesh texels by albedo value: Evernight's cloth 0.11-0.33 below value 0.35
against 0.61-0.77 above 0.75, dark leather 0.02-0.10 (a black mirror); March 7th's the same. In game
her grey coat read as satin with a reflected red smear (coat patch 81.9 against 94.9 original, drift
0.3) and her sheer black stockings as latex. Both per-model presets now compress the AI spread
(cloth 0.65 / rough_ai 0.35 / normal 2.0, leather 0.25 / 0.4) and keep painted black ink glossy by a
region rule; the coat came back to 91.9. The other aggressive models were made with the same values
and were not re-checked; changing `aggressive.json` needs the user's decision.

## Why the face and eyes are set this way (Guinevere close-up, 2026-10-25)

Anime faces are cel art; the goal is to keep the drawing, not to add physical detail.

- **AI relief and AI roughness variation are off on all face classes.** They turn painted blush and
  shading into bumps and oily blotches.
- **Face 0.60.** A glossier face gets plastic hot spots on the nose and cheeks.
- **Mouth, teeth and tongue are as matte as the face.** At 0.12 the tongue mirrors the dark mouth
  cavity at grazing angles and its pink reads as shadow (patch 81 → 43).
- **The eye white emits a little of its own colour.** It is grey in the socket at any roughness
  (134 vs 134), and emission lifts it from 63–165 to 190–208, just under the cheek's 217. This fixed
  level remains the fallback; C-16 adds scene adaptation to address its auto-exposure conflict below.
- **The iris stays mirror-smooth (0.06).** At 0.18 the bright light above veils it white (saturation
  0.47 vs 0.62), and 0.5 is no better.
- **The catchlight mesh emits 0.6** and reads as pure white (208 → 254).
- **The emissive map handles edges carefully.** It is not blurred at class borders, and its gutters
  repeat the nearest island edge, so mip levels never spread skin paint as a glowing rim.

### Scene-adaptive eye emission (C-16, provisional 2026-10-31)

Fixed emission is multiplied by the scene's exposure: it glows beside dimly lit skin in dark maps
and loses its lift in bright scenes. For a published emissive map whose recorded rasterised classes
include `sclera`, `eye` or `highlight`, rpai now writes `float inputs:emissive_adaptive_intensity`
beside the unchanged `emissive_intensity`. A supporting runtime replaces fixed emission with
`emissiveColor * emissive_adaptive_intensity * L_adapt`, using adapted scene luminance. Exposure
approximately cancels that luminance while below its cap; at the cap the emission fades with the
scene. This is a light floor, not a measured guarantee of a particular eye/cheek ratio.

`--emissive-adaptive-intensity R` (also the top-level JSON setting `emissive_adaptive_intensity`)
is a **ratio to the fallback USD intensity per unit luminance**, not a literal USD value. The writer
sets `adaptive = fallback * R`. Default `R = 1 / 0.18 = 5.555555555555555`; `0` writes an explicit
opt-out and uses fixed emission. The existing `--emissive-intensity I` scales both modes.
Non-eye emitters stay fixed; a cached entry with no class information gets no adaptive input.

Derivation: `compose_maps` stores `M = C * w / S` in the emissive map, where `C` is linear albedo,
`w` the class weight (sclera `0.025`) and `S` the strongest weight on that sheet. Publish writes
fallback `F = S * I`, so the old emission is `M * F = C * w * I`. Choose a provisional mid exposure
of **1**: the package's `rtx.autoExposure.targetAdaptedYf = 0.18` implies `L_mid = 0.18` (ignoring
the small exposure noise term). Set `A = F / 0.18`; then `M * A * L_mid = C * w * I` exactly before
texture/float quantisation. A sheet with fallback `0.6` writes `A = 3.33333333`; a sheet with
fallback `0.04` writes `A = 0.222222222`. No class weights or textures change.

This is a publish option because the current `--emissive-intensity` already re-levels the shared
normalised map at that stage. A new per-class texture weight would require regeneration and could
not give different adaptation ratios to classes sharing the same material input. The option works
with existing `generated.json` class coverage, including region rules, and all previously seen hashes.
Tune with `publish` only; use [`set_adaptive_emission.py`](../scripts/set_adaptive_emission.py.md) for
already published packs (`--value` is literal USD intensity; `--multiplier` applies the ratio).

Older runtimes ignore the new input and use the unchanged fixed fallback. On supporting runtimes,
`rtx.adaptiveEmission.enable = False` or an adaptive input of `0` selects fixed emission. Runtime
scale/clamps and disabled-auto-exposure fallback belong to the runtime; see
[`C16-plan.md`](../../../docs/handover/C16-plan.md). Claude will measure bright, dim and night scenes
on the PoC and tune this default; this content task performs no in-game validation.

## Why body skin is left to Remix (full-body AABB, 2026-10-25)

The user decided this after a test of four variants: original, PBR 0.50, PBR plus 25% de-light, and
PBR plus 50% de-light. Each variant was shot twice back to back on the neck and collarbones, the
abdomen and the arms. The repeat noise was 0.5–1.0/255.

- The AI finds nothing on anime skin sheets: raw roughness 0.70 ± 0.03, normals under 1.6°, on all
  three models.
- PBR roughness alone was indistinguishable from the original: 1.4–2.2/255, with 95–101% of the
  painted detail kept.
- De-lighting the painted joint shading softened rash-like knee blush, but faded the painted neck,
  collarbone and abdomen detail. Only 82–94% of it was kept at 50%, and 88–96% at 25%.
- A first limb-only test had picked the 50% de-light. The user rejected it as a standard because
  it had not been checked on the body. Lesson: skin changes need full-body evidence.
- Shared sheets: the neck on a clothes sheet gets the legacy look, roughness 0.7, flat, with the
  original colours. Tattoo and decal sheets classed as skin are left to Remix too.

### Body skin changes only on request (user rule, 2026-10-25)

Body skin changes are made and applied only when the user asks for them: skin-class overrides
(`original: 0`, roughness, relief), a model's own body normal map on skin sheets, subsurface
scattering, de-lighting, and skin texels on shared sheets. Without a request the standard above
holds. A look tested on request but not kept lives in `tool/presets/on_request/`, which is never
loaded automatically; `--settings <file>` applies it again when the user asks.

**Guinaifen's body relief (tested on request, then reverted at the user's request).** Recipe and
evidence: `tool/presets/on_request/new_mmd_model_1c2ed2fc_body_skin.json`. `textures.Body.png` names
`normal_map` with a per-texture skin preset (`original 0`, roughness 0.55, `normal` 12), and the
upper neck on the cloth atlas gets the same roughness so the join matches. Her map was flattened
(R == G) and is rebuilt by `compose.relief_normals`. Two AABB rounds (front views on a face-up
copy, the back on a face-down copy, clothes hidden for the capture only, repeat noise
0.4-0.7/255): strength 12 changed skin by 2.9-7.8/255, with kneecaps, toe pads and creases, the
spine groove and the clavicle line reading as shape and no false folds after the slope knee;
strength 16 added about 25%. The rebuilt relief first left a slit down the sides of the body, where
the front and back UV halves meet; with the island edge continued outward and the relief faded to
flat over the last 12 texels, the seam's line contrast went from 1.9-2.8 to the original's 0.0
(left and right flank, lc noise up to 0.11). Subsurface scattering was measured and rejected (see
runtime-notes). The face had no authored relief and kept its anime-safe classes.

## Region rules (paint inside one material)

Painted gold trim and embroidery sit on cloth materials, so a per-material class cannot make them
metal. A region rule reclassifies texels by HSV colour inside chosen classes. Only texels a UV
triangle covers are matched. Guinevere's gold:

```json
{"texture": "衣.png", "within": ["cloth"], "class": "metal", "hue": [28, 58], "sat": [0.30, 1.0], "val": [0.50, 1.0]}
```

Painted gold turning metal gave the strongest visible change of all three models (17/255 on the
skirt). Judge colours from the raw texture sheet, never from a tinted UV overlay: a tinted overview
once made maroon panels look navy and produced a wrong "silver" rule.

## Gold and metal type per character (user request, 2026-10-26)

A metal's albedo is its reflectance (F0). Painted anime gold is a mid-tone: measured on the mesh
(median linear luminance of the metal texels) it is 0.17-0.55, where real gold reflects about 0.74
and the painted silvers 0.73-0.97. At the aggressive metal roughness (0.12) a polished surface
mirrors one direction of the room, and in a dim room a low-F0 gold reads dark: Robin ZZZ's halo
went from 152 to 96 (-37%) and her gold stars from 118 to 86 (bracketed AABB, 2026-10-25). A
satin finish gathers light from a wider cone and keeps reading as gold. Bright silver mirrors the
room without going dark. So the type follows each character's paint and what the piece is:

| Character (preset) | Metal on the mesh | F0 | Type | Roughness |
| --- | --- | --- | --- | --- |
| Robin ZZZ (`robin_69c55742`) | champagne gold: halo, stars, crescents, bands | 0.43-0.47 | satin champagne gold, f0 0.74 carried over from Robin R18 (same art; not measured in game) | 0.30 (was 0.12) |
| Robin R18 (`robin_r18_f9c3e4b4`) | champagne gold: piping, stars, treble clef, halo | 0.34-0.39 | satin champagne gold, reflectance lifted to real gold's (f0 0.74, measured below) | 0.30 |
| Guinaifen / Guinevere (`new_mmd_model_1c2ed2fc`, `_9cdc990f`) | yellow gold thread embroidery and trim (35% of the skirt sheet), brass gong, jewelry | 0.23-0.32 | satin yellow gold | 0.32 (was 0.12) |
| Kafka (`new_mmd_model_4ab9d7e3`) | dark bronze brackets and shields, earring hooks; tan web embroidery | 0.17-0.20; 0.44 | satin antique bronze | 0.36 (was 0.12) |
| Firefly (`firefly_r18_0d01d7d3`) | pale brass fittings and bells; hidden bunny trim in white silver | 0.31; 0.97 | satin pale brass; polished silver | 0.30 (was 0.12); 0.12 |
| Castorice (`castorice_7b47f232`) | small yellow gold brooch (0.3% of 上衣.png); near-black glove spikes | 0.55; 0.03 | polished gold jewelry; gunmetal | 0.12 (kept) |
| Cyrene (`cyrene_dd112b38`) | silver headdress, spade frames, chain | 0.73-0.85 | polished silver | 0.12 (kept) |
| Hyacine (defaults, no preset) | rose gold ornaments; silver collar ring and bell | 0.32; 0.78 | satin rose gold and silver | 0.28 (kept, the default metal) |
| Hiyuki Alt (`hiyuki_08f3c33e`, skin 1 `hiyuki2_08f3c33e`; compiled port) | yellow gold ornaments, trims, embroidery and heel plates; black gloss (cuffs, headband) as a glossy dielectric | 0.23-0.37 | satin yellow gold, f0 0.74 (the most recent preset, 2026-10-27; measured in game: gold 6-10% above the original, f0 0.62 2-5% above; the user's choice is pending) | 0.30 |

Satin values sit at the default metal standard (0.28) rather than the aggressive 0.12, with the AI
roughness variation at 0.5.

**Measured in game on Robin R18 (2026-10-26).** Bracketed capture A (original Remix), P (polished
0.12), S (satin 0.30, published), A2 (original again), 6 views shot twice; repeat noise 0.5-1.0/255
on the model (2.7 in the distant full view), drift A2 - A 1.6-3.3. Gold pixels picked by colour on
the original frame, against the mean of A and A2:

| Gold | Polished 0.12 | Satin 0.30 | Brightest 10%, P / S |
| --- | --- | --- | --- |
| halo ring (37,861 px) | -57.8 (-37%) | -29.7 (-19%) | 223 / 217 |
| torso: piping, brooch, stars (81,130 px) | -69.9 (-45%) | -39.4 (-25%) | 183 / 193 |
| choker star and studs (18,732 px) | -46.8 (-36%) | -39.3 (-30%) | 160 / 160 |

Satin halves the darkening on the halo and the brooch (brooch scroll -27.6 vs -5.2, ring -47.5 vs
-17.3) and keeps the same highlight peaks; on the small choker studs it does not help (-48 vs -57).
Even satin gold stays 19-30% darker than the matte original, because a metal has no diffuse
term. The other characters were not spawned; their types follow this measured behaviour of
painted gold.

**Reflectance lift (`f0`), measured on Robin R18 the same day** (user request: keep whichever is
closer to the original brightness). The `f0` class field scales a class's albedo so its median
linear luminance on the mesh meets the target (`compose.lift_reflectance`), keeping the painted
hue and detail. Bracketed A, S (satin 0.30), L1 (satin + f0 0.55), L2 (satin + f0 0.74), A2; each
variant against the original interpolated between A and A2 at its place in the run, and checked a
second way by normalising each capture with the floor next to the gold:

| Gold vs original | Satin | f0 0.55 (x1.42-1.50) | f0 0.74 (x1.91-2.02) |
| --- | --- | --- | --- |
| halo ring | -12% | -3% | +4% |
| choker star and studs | -15% | -9% | -5% |
| piping, brooch, stars | -25% | -14% | -10% |
| pixel-weighted distance (floor check) | 21.0% (23.2%) | 10.8% (12.3%) | **8.2% (9.0%)** |

f0 0.74, about real gold's reflectance, is closest and is what Robin R18 now uses. Its costs: the
halo reads paler (gold saturation 0.19 against the original 0.30; torso 0.30 against 0.33), and
the brightest 10% of gold pixels peak higher than the matte original (halo 242 against 173), as
metal highlights do. The oblique view was left out: its window light moved during the run and the
floor changed as much as the model. Only Robin R18 was measured. Robin ZZZ, whose gold is the same
art, carries the same lift at the user's request (about x1.6-1.7, since her paint reflects 0.43-0.47);
her measurement was skipped for now, and the kit is in her work folder (`aabb_todo_f0`). The other
golds are not lifted.

## Other decided details

- **Authored companion maps** (`X_BaseColor` with `X_Normal`, `_Roughness`, `_Metallic`, `_Height`)
  beat the AI. The normal map's Y convention is measured against the height map; Firefly's heels are
  OpenGL.
- **Per-texture size:** `"textures": {"丝袜.png": {"max_size": "source"}}` lifts the 4096 cap. Firefly's
  fishnet sheet keeps 11059×8847 because its mesh lines blur at 4096. Remix logs a harmless "doesn't
  fit into STAGING memory" for textures over 96 MB.
  This is a high-resolution variant. For an 8 GB audience, check these overrides and generate a
  separate capped variant before publishing with `--max-size 2048 --mod ai_pbr_2048`; see
  [Publishing for 8 GB GPUs](../SKILL.md#publishing-for-8-gb-gpus). A publish-only flag does not
  resize existing generated maps. Keep each size variant in its own mod: publish prunes unused DDS
  files in that mod.
- **Byte-identical sheets** shared between models have one Remix hash. The alphabetically first
  layer wins, and `publish` prints which one.
- **Never override the engine's shared white texture.** Untextured materials (Guinevere's heels)
  use it, and replacing it would change every untextured surface in the game.
- **UV island borders are padded, never read as relief** (`compose.gutter_fill`, 2026-10-25). The
  AI saw each island's edge against the empty sheet as a step and put a ridge on it; on Guinaifen's
  stockings that showed as a crease down the inner and outer side of each leg, where the front and
  back halves meet. The AI input and the finished maps repeat the island edges across a gutter band
  of 1/128 of the sheet, and class roughness means count only texels on the mesh. This is a bug
  fix, not a new look: models generated before it keep their old maps (and their seams) until they
  are generated again.
