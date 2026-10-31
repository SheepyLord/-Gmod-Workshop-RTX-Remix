# Reviewing a character's textures before generating

MMD sheets are shared atlases: one cloth sheet can hold dozens of materials, including metal
fittings, gems and skin (the neck). Remix replaces per texture hash, so the review decides what each
texel of each sheet is. `example-texture-analysis.md` is the full review of Guinevere and the model
for the write-up.

## Steps

1. **Inventory.**
   - Which textures does the PMX reference, and which of them exist in the folder? Missing ones are
     skipped (`skip ... source image missing`).
   - Note files in the folder that the PMX does not reference (alternate copies, sphere maps,
     unreferenced normal maps). They are not processed.
   - Only process the textures the user means. Guinevere's request was "for the texture provided in
     the folder only".
2. **Run `rpai hashes`, then `rpai generate`** once with the defaults or the chosen style. Read:
   - `work/<key>/classes.json`: class and reason per PMX material;
   - `work/<key>/masks/<texture key>_classes.png`: classes over the albedo;
   - `work/<key>/preview.jpg`: albedo, classes, normal, roughness, metallic and emissive per
     texture.
3. **Outline UV islands per material.** Draw each material's UV triangles in a distinct colour over
   the raw sheet (`rpai.pmx.read_pmx`, `model.material_triangles(material)`, `model.uv`). This
   shows which material owns which island, for example 目 (iris), 白目 (eye white) and 目光
   (highlight) on a face sheet.
4. **Judge colours from the raw sheet, not the tinted class preview.** A tinted overlay once made
   maroon panels look navy and produced a wrong "silver" rule.
5. **Decide per material and region:**
   - Wrong class from a name? Pin it: `"_materials": {"38": "metal"}`. Keys are 0-based PMX
     material indices.
   - Paint that is a different material (gold trim on cloth)? Add a region rule (HSV,
     `within` classes, optional `rect`).
   - One material that is many things (game rips: Robin's single `Body` material is dress, skin,
     gold, crystals and shoes on one sheet)? Profile its UV islands first: per island the share of
     skin, gold, purple and white texels and the centroid on the body (`uvmask.islands` gives both;
     Robin's skin islands scored 0.99-1.0 skin, the shoes and straps sat below 2.6 of 20.9 units).
     Then use island rules (`"islands": 0.6`, optionally `"box"` for where on the body and `rect`
     for one island), in order: skin, then gold, then what sits inside the gold. Per-texel colour
     rules mix up champagne gold and skin shading (hue 20-35 at low saturation in both).
   - The model ships a game normal map (`_N`, `_Normal`)? Use it as the sheet's `normal_map` with
     its classes at `normal` 1.0, and check its log line: the convention is measured, and z is
     rebuilt when blue holds a mask. Skin stays flat at its class strength 0.
   - A sheet that needs its full resolution (fine mesh, small UV cells)? Use
     `"textures": {"name.png": {"max_size": "source"}}`.
   - Hidden parts (alpha-0 materials, morph-toggled overlays) have no live hash until shown in game.
6. **Write it down.** Keep a table of texture → content → materials → decision, plus the reasons for
   pins and regions, in the per-model preset's `doc` field and a short analysis file. Keep the
   analysis alongside the package or the user's model folder, not in the skill.

## Name rules that already exist (`classify.py`)

Rules match CJK substrings and whole English words, and the first match wins. Covered so far:

- gem first for 宝石 / 寶石 names, so 耳环宝石 and 衣链宝石 are not taken for metal by 环 / 链
- metal: 金属, 铁, 银, 链, 环, 扣, 鑼, 首饰…
- gem: 玻璃, 镜片, glasses (眼镜, 墨镜; Kafka's sunglasses had become an emissive iris)…
- leather: 眼罩, 项圈, 鞋, 靴, 皮带…
- garments that contain body-part characters: 手套, 胸罩, 绳, 腿带, and the band-aid 创口贴 (it was mouth)…
- eye parts: 目光 / ハイライト → highlight, 白目 / 眼白 → sclera, 眉 / 睫 / 眼线 → lash, 目 / 瞳 → eye
- rubber: 口球, 乳胶…
- mouth: 口, 齿, 舌, sita
- face: 颜, 脸, 表情, 目影, 赤, tear overlays (淚, 涙, 泪), shy
- hair: 髪, 发
- stockings: 袜, siwa
- skin: 肌, 体, 手, 足, 腿, 淫纹…
- cloth: 衣, 服, 裙, 带, 饰, 纱 (veils and gauze)…

The sphere map decides before the texture name (a skin matcap marks a neck on a clothes sheet). Add
new words to `classify.py` when a new model's naming misses, and check that existing models still
classify the same (the 2026-10-25 additions left all 280 materials of the four earlier models
unchanged; `%USERPROFILE%\.rpai\work\_batch_20261025\classify_before.json` / `classify_after.json`).

Names can still mislead in ways no rule should guess. On Kafka, Cyrene and Castorice the in-game
check found two: a metal-named material holding non-metal ornaments (Cyrene's 首饰 "Jewelry" was
only white rose petals and leaves, which rendered as dark chrome) and a metal earring with a white
pearl (a dark chrome ball). Look at what every metal material covers on the raw sheet, and split
white or pastel ornaments off with a pin or a region rule (`within: ["metal"]`, low saturation,
high value → a dielectric class).
