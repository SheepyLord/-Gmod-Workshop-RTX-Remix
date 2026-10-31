# Guinevere (桂乃芬.pmx): what each texture is for

Review date: 2026-10-25. Only the textures present in `星穹铁道-桂乃芬\tex` are processed. The PMX
also references `inmon.png`, `asanawa.png`, `乳贴.png` and `Blindfold Text.png`, which are not in
the folder and are left alone. (`口球.png` arrived in the folder during the review and was
processed. It is byte-identical to Hyacine's and Firefly's copies, so Firefly's layer wins that
hash.)

Images: `uv_<texture>.jpg` outline each material's UV islands. The fills are tinted, so judge colours
from `gold_trim_regions.jpg`, which shows the raw sheets. In that image cyan marks texels the
region rules turn into metal, and dimmed texels are not used by any mesh.

| Texture | What it contains | PMX materials | Decision |
| --- | --- | --- | --- |
| `Body.png` 2048² | Skin atlas: body front and back, arms, hands, feet. Very pale base (255, 247, 240) with soft pink shading painted into knees, elbows, toes, knuckles and creases | Body, Arm | skin: **left to Remix** (no override; decided by the full-body AABB, see [Body skin](#body-skin)) |
| `Body normal.png` 2048² | Anatomical normal map in `Body.png`'s layout (detail sits inside the body islands, see `body_normal_vs_uv.jpg`). Stored with a constant bias: flat = (176,176,241), not (128,128,255) | not referenced by the PMX | **Not used.** After removing the bias it is faint (1.0° mean tilt, p99 4.3°). With no height map, its Y convention cannot be measured (curl test: 0.00283 vs 0.00292), so a guess could invert the relief |
| `衣.png` 2048² | Top: red heart bodice with gold trim, white petal panels, dark bra cups, pink panels with gold swirls (胸罩), lavender knot bands (裙結帶), dark-brown dress with gold border (衣服), green glove pieces, teal jade bar with a bead | 衣2, 胸罩, 裙結帶, 衣服, 手套+, 首饰1, 裙飾帶, 脖子 | cloth. 首饰1 → **gem** (jade). 脖子 → skin (skin matcap). **Gold trim → metal** (region rule) |
| `衣内.png` 2048² | Inner faces of the `衣.png` layout | 衣2+, 裙飾帶+, 裙結帶+ | cloth, **gold trim → metal** |
| `衣2.png` 2048² | Skirt and props: maroon skirt panels with gold embroidery (裙摆), flame-motif band (袖带), bronze **gong** (鑼), gold ornaments (衣金屬, 胸饰铁, 首饰2, 腿环, two pieces of 衣1), red lacquer **mallet** head and patterned grip (錘), dark boots with gold trim (靴), white skirt hem | 裙摆, 袖带, 鑼, 衣金屬, 胸饰铁, 首饰2, 腿环, 衣1, 錘, 靴 | cloth panels. **metal**: gong (new 鑼 rule), ornaments, 首饰 (new rule), 衣1 (pinned). 錘 → glossy lacquer (leather class, pinned). 靴 → leather. **Gold embroidery and trim → metal** |
| `衣2内.png` 2048² | Alternate/inner version of `衣2`: red flame petals with gold edges (the headdress), inner skirt, mallet inner side | 头饰, 裙摆+, 錘+ | 头饰 and 錘+ → glossy lacquer (leather class, pinned). **Gold edges → metal** |
| `siwa.png` 2048² | Sheer dark nylon: pantyhose (siwa1), gusset (siwa2), reinforced toes (siwa3), sheer gloves (手套) | siwa1-3, 手套 | **stockings** (new romanised `siwa` rule; 手套 pinned) |
| `baisiwa.png` 2048² | White stocking variant (hidden, alpha 0) | siwa1+-3+ | stockings |
| `髪.png` 2048² | Peach-pink hair strands | 髪 | hair |
| `颜.png` 1024² | Face and ears, gold iris (目), eye whites (白目), highlight (目光), lashes and brows (眉目), eyeliner (眼线内), mouth (口), teeth and tongue (舌齿) | 颜, 目, 白目, 目光, 眉目, 眼线内, 口, 舌齿 | Anime-safe face classes, see [Face and eyes](#face-and-eyes-close-up): face matte, iris mirror-smooth with a faint glow, **sclera** soft with a slight glow, **highlight** emissive, 眉目 and 眼线内 → **lash** (matte ink), mouth, teeth and tongue matte |
| `bq.png` 512² | Expression decals; byte-identical to Hyacine's | biaoq | face (Hyacine's layer wins this shared hash) |
| `颜赤.png` 2048² | Blush overlay (hidden); identical to Firefly's | Shy | face (Firefly's layer wins) |
| `sita.png` 1024² | Tongue; identical to Firefly's | mat1 | mouth (Firefly's layer wins) |
| `灰.jpg` 520² | Grey eye-shadow overlay; identical to Firefly's | 目影 | face (Firefly's layer wins) |
| `口球.png` 640×480 | Ball gag; identical to Hyacine's and Firefly's | 口球 | rubber (Firefly's layer wins) |
| `颜赤.tga`, `眼睛.png`, `表情.png` | Alternate copies, not referenced by the PMX | none | not processed |
| `スフィアガラス.png` | Used as the heels' sphere map, not as a base texture | none (heels are untextured) | not processed |

The untextured materials (高跟鞋, 高跟鞋内, 高跟鞋闪光, 口枷金属, 眼罩金属) use the engine's shared
white texture. Replacing that hash would change every untextured surface in the game, so they are
never overridden.

Style: `presets/aggressive.json`, through `presets/models/new_mmd_model_9cdc990f.json`.

## Result in game (same camera, `compare.jpg`, crops `ab_*.jpg`)

14 overrides published: 16 live hashes and 2 predicted (hidden blush, white stockings).
Mean |AI − original| over 255:

| Region | Change | What you see |
| --- | --- | --- |
| Skirt panel, gold embroidery | 17.3 | Painted beige-gold becomes polished metal reflecting the room |
| Bodice | 11.4 | Gold buckle, swirls and shoulder piece turn metal; satin sheen on red |
| Boots | 10.1 / 11.3 | Patent-leather reflections, polished gold trim |
| Stockings | 7.8 | Glossy nylon highlights |
| Head | 6.7 | Glossy hair, lacquered headdress |

The floor corner changed by 4.2/255 between the shots. Model edges line up in the crops, so this is
lighting variation, not motion.

## Face and eyes (close-up)

`颜.png` is cel art in the Star Rail style:

- **Iris (目):** a disc with a thick dark limbal ring and a gradient from brown under the lid to a
  bright cream glow at the bottom. It has a diamond pupil outlined in rust and three painted
  catchlight blobs.
- **Eye white (白目):** a flat near-white ellipse (248, 244, 239) with no painted shadow.
- **Highlight (目光):** its own small white ellipse, drawn as a separate mesh in front of the iris.
- **Lashes, brows and eyeliner:** painted dark brown on a dark island.
- **Mouth:** teeth are two pure white strips, the tongue is flat pink, and the mouth interior is flat maroon.

Nothing on the sheet has real surface detail, so every face class gets flat normals and no AI
roughness variation.

The aggressive maps made the eye whites grey-green. A close-up from the camera above her face
(same pose, fixed patches) showed the eye white is grey from lighting alone: at roughness 0.25
and at Remix's legacy 0.7 it measures the same 134/255. So it now emits a little of its own colour.

| Patch (sRGB /255) | Original materials | Final |
| --- | --- | --- |
| Eye whites (4 patches) | 63–165 | 190–208 |
| Cheek | 217 | 217 |
| Catchlight | 209 | 254 |
| Iris, upper (R, G, B) | 221, 191, 69 | 238, 217, 103 |
| Teeth / tongue / mouth interior | 187 / 48 / 88 | 190 / 55 / 81 |
| Hair / floor (references) | 225 / 76 | 224 / 76 |

Images: `face_ab.jpg` (whole face), `eyes_ab.jpg` (eyes at 2×), and `eye_emission_sweep.jpg`. The
sweep is the first emission weights (eye white 0.06, iris 0.15, highlight 1.0) scaled ×0 to ×1,
taken under the earlier, brighter light. The first weights made the iris glow pale, so the final
weights are lower (0.025 / 0.04 / 0.6). The iris stays mirror-smooth: at 0.18 the bright light above
veils it white (saturation 0.47 vs 0.62), and 0.5 is no better (0.57). The tongue was first left at
the wet class's 0.12, where its grazing surface mirrors the dark mouth cavity (mouth patch 81 → 43).
At the face's 0.60 it matches the original.

## Body skin

**Decision (2026-10-25): body skin stays as Remix renders it.** `Body.png` gets no override. The
neck, on `衣.png`, keeps its original colours at Remix's legacy roughness 0.7.

A first test on the arms and lower legs favoured removing half of the painted joint shading
(`skin_ab.jpg`). It was rejected as a standard because it had not been checked on the body, and
the body and neck detail faded. The full-body AABB that followed compared four variants, each shot
twice back to back from scripted cameras on the neck and collarbones, the abdomen and two arm views.
Saved frames avoid the chest and pelvis. The measurements are in `aabb_metrics.json`, and the
images are `aabb_neck.jpg`, `aabb_abdomen.jpg`, `aabb_arm_top.jpg` and `aabb_arm_side.jpg`.

| Variant | Mean change vs A (/255) | Painted detail kept (neck / abdomen / arm) | Peak pink (neck) |
| --- | --- | --- | --- |
| A original Remix | 0 (repeat noise 0.5–1.0) | 100 / 100 / 100% | 48 |
| B PBR roughness 0.50, original colours | 1.4–2.2 | 99 / 95 / 97% | 45 |
| C B + 25% de-light | 1.8–2.3 | 96 / 88 / 88% | 38.5 |
| D B + 50% de-light | 2.4–2.5 | 94 / 84 / 82% | 34 |

"Painted detail" is the spread of band-passed redness, R − (G+B)/2, on skin (σ 2 to 40 px), relative
to A. D's arm-side pair is missing: the game stopped responding after D's arm-top pair.

- The AI found nothing on the body sheets of any of the three models (raw roughness 0.70 ± 0.03,
  normals under 1.6°). So the only PBR left for skin was roughness, and that measured as no visible
  change (B).
- De-lighting softens the joint blush that path tracing exaggerates. But it fades the anatomical
  paint (collarbones, neck shading, the line below the navel) in proportion, so it is not a
  standard step.
- Subsurface scattering, the PBR feature that could change skin meaningfully, works in this runtime
  only with the material forced opaque and the skin colour given as the transmittance texture
  (`sss_test.jpg`; details in the README). It has not been tuned, so it is not part of the standard.
