"""Surface classes for MMD materials, from their names and sphere maps.

Remix replaces by texture hash, and MMD atlases are shared: on Hyacine one
cloth sheet serves 39 materials, eight of them metal fittings. So a class is
decided per PMX material and later rasterised into texture space (uvmask.py),
which lets one generated texture be metal in some texels and cloth in others.

Rules run in order and the first match wins. CJK terms match as substrings;
English terms match whole words, so "bell" does not catch "belly".
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# rough: base roughness; rough_ai: how much of the AI roughness map's local
# variation is kept; metal: metallic; normal: AI normal strength (0 = flat,
# above 1 amplifies); height: AI height strength; emissive (optional, 0 when
# absent): light emitted as a multiple of the linear albedo, at Remix
# emissive_intensity 1; delight (optional, 0 when absent): fraction of the
# broad shading painted into the albedo that is removed (compose.delight);
# original (optional): leave these texels as Remix renders them by default (a
# texture made only of such classes gets no override at all); aniso (optional,
# 0 when absent): Remix anisotropy, -1..1, written as an anisotropy texture.
# Remix's tangent follows the texture's U axis, so on a leg unwrapped with V
# down the leg (Guinaifen's stockings) a negative value stretches highlights
# along the leg, the nylon streak; positive widens them around it (in-game
# probe at +-0.7, 2026-10-25). f0 (optional, 0 when absent): lift the class's
# median linear luminance on the mesh to this reflectance (compose.lift_reflectance);
# opt-in. On Robin R18 (2026-10-26) f0 0.74 brought satin gold to -10%..+4% of the
# original brightness (satin alone -12%..-25%), with a paler halo.
# Gold type per character (2026-10-26, references/standards.md): painted golds
# (F0 0.17-0.55) mirror a dim room as dark bronze at the aggressive 0.12, so
# most per-model presets set the metal class to satin 0.30-0.36.
# Cloth and leather were raised 1.6x (from 0.9 / 0.7)
# after an in-game A/B on Hyacine (2026-10-25): the extra relief lands on trims,
# seams and stitching while flat painted fabric stays flat.
# presets/mild_normals.json restores the old values.
#
# Anime faces are cel art, so the face classes are tuned to keep the drawing
# intact rather than to look physically rich. Measured on a close-up of
# Guinevere against the original Remix materials (2026-10-25):
# - face, mouth and lash get no generated relief and no AI roughness variation,
#   which would turn painted blush and shading into bumps and oily blotches.
#   The face is matte (no plastic hot spots on nose and cheeks); lashes and
#   brows are ink and never glint. Mouth, teeth and tongue are as matte as the
#   face: glossier, the tongue mirrors the dark mouth cavity at grazing angles
#   and its pink reads as shadow (patch 81 -> 43 at roughness 0.12).
# - The eye white stays grey in the socket at any roughness (134 vs 134), so
#   it emits a little of its own colour (63-165 -> 190-208, still just below
#   the cheek's 217; more would glow in dark maps, where auto-exposure lifts
#   emission against lit skin). The iris is mirror-smooth with a faint glow:
#   roughness 0.18 veils it white (saturation 0.47) where 0.06 keeps it vivid
#   (0.62). The highlight (catchlight) mesh emits enough to read pure white.
#
# Body skin stays exactly as Remix renders it (decided 2026-10-25 after a
# full-body AABB on Guinevere: neck, abdomen and arms, each variant shot twice,
# repeat noise 0.5-1.0/255). On all three models' skin sheets the AI gives
# nothing (raw roughness 0.70 +- 0.03, normals under 1.6 degrees), and a PBR
# skin at roughness 0.50 was indistinguishable from the original (1.4-2.2/255,
# 95-101% of the painted detail). De-lighting the painted shading softened the
# rash-like knee blush but cost 4-18% of the painted body and neck detail
# (collarbones, the line below the navel), so it is not a standard step; the
# delight parameter remains for presets. The legacy look is roughness 0.7
# (rtx.legacyMaterial.roughnessConstant), flat, original colours, which is what
# skin texels get on sheets that also carry other classes (Guinevere's neck).
CLASSES: dict[str, dict[str, float]] = {
    "default":   {"rough": 0.65, "rough_ai": 0.6, "metal": 0.0, "normal": 0.7, "height": 0.6},
    "cloth":     {"rough": 0.78, "rough_ai": 0.6, "metal": 0.0, "normal": 1.44, "height": 0.8},
    "stockings": {"rough": 0.55, "rough_ai": 0.4, "metal": 0.0, "normal": 0.5, "height": 0.3},
    "leather":   {"rough": 0.42, "rough_ai": 0.5, "metal": 0.0, "normal": 1.12, "height": 0.6},
    "rubber":    {"rough": 0.22, "rough_ai": 0.2, "metal": 0.0, "normal": 0.3, "height": 0.2},
    "hair":      {"rough": 0.40, "rough_ai": 0.35, "metal": 0.0, "normal": 0.35, "height": 0.2},
    "skin":      {"rough": 0.70, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0, "original": 1},
    "mouth":     {"rough": 0.60, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0},
    "face":      {"rough": 0.60, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0},
    "lash":      {"rough": 0.85, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0},
    "nail":      {"rough": 0.25, "rough_ai": 0.1, "metal": 0.0, "normal": 0.1, "height": 0.0},
    # No rule assigns wet any more (tongues are mouth); kept for presets and pins.
    "wet":       {"rough": 0.15, "rough_ai": 0.1, "metal": 0.0, "normal": 0.2, "height": 0.0},
    "gem":       {"rough": 0.05, "rough_ai": 0.0, "metal": 0.0, "normal": 0.2, "height": 0.0},
    "metal":     {"rough": 0.28, "rough_ai": 0.5, "metal": 1.0, "normal": 0.6, "height": 0.4},
    "sclera":    {"rough": 0.25, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0, "emissive": 0.025},
    "eye":       {"rough": 0.06, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0, "emissive": 0.04},
    "highlight": {"rough": 0.50, "rough_ai": 0.0, "metal": 0.0, "normal": 0.0, "height": 0.0, "emissive": 0.6},
}

# Rasterisation order: a later class wins where two materials share texels.
PRIORITY = ["default", "cloth", "stockings", "leather", "rubber", "hair", "skin", "mouth", "face", "lash", "nail",
            "wet", "gem", "metal", "sclera", "eye", "highlight"]
CLASS_ID = {name: i + 1 for i, name in enumerate(PRIORITY)}  # 0 = no material covers the texel


@dataclass(frozen=True)
class Rule:
    cls: str
    cjk: tuple[str, ...] = ()
    words: tuple[str, ...] = ()
    unless: tuple[str, ...] = ()  # removed from the name before matching
    skip: tuple[str, ...] = ()  # the rule does not apply to names containing these


RULES = [
    # A gem named after its setting (耳环宝石 earring gems, 衣链宝石 chain gems on
    # Cyrene) is still a gem; the metal rule would take it for its 环/链.
    Rule("gem", ("宝石", "寶石")),
    Rule("metal",
         ("金属", "金屬", "金具", "鉄", "铁", "鐵", "钢", "鋼", "銀", "银", "铃", "鈴", "链", "鏈", "鎖", "锁", "环", "環",
          "扣", "钉", "釘", "ピアス", "チェーン", "鑼", "锣", "首饰", "首飾"),
         ("metal", "metallic", "gold", "silver", "steel", "iron", "chrome", "chain", "bell", "ring", "rings", "earring",
          "buckle", "pierce", "piercing", "zipper")),
    # Glasses (眼镜, Kafka's tinted sunglasses) before the iris rule sees 眼;
    # 眼镜金属 frames still match metal above.
    Rule("gem", ("水晶", "玻璃", "ガラス", "硝子", "镜片", "鏡片", "眼镜", "眼鏡", "墨镜", "墨鏡"),
         ("gem", "jewel", "crystal", "glass", "lens", "glasses", "sunglasses", "spectacles")),
    Rule("leather",
         ("眼罩", "眼帯", "目罩", "项圈", "項圈", "首輪", "口球带", "口球帶", "鞋", "靴", "皮带", "皮帶", "皮革", "革"),
         ("blindfold", "collar", "choker", "shoe", "shoes", "boot", "boots", "leather", "belt")),
    # Garments and ropes whose names contain a body part (手套 gloves, 胸罩 bra,
    # 手繩 wrist rope, 腿带 leg strap) must be caught before the skin and eye
    # rules see 手/胸/腿, and the band-aid (创口贴) before the mouth rule sees 口.
    Rule("cloth", ("手套", "手袋", "胸罩", "文胸", "胸衣", "绳", "繩", "縄", "外套", "腿带", "腿帶",
                   "创口贴", "創口貼", "绷带", "繃帶", "包帯"),
         ("glove", "gloves", "rope", "bra", "coat", "bandage", "bandaid")),
    # Eye parts before the iris rule, whose 目/眼 they all contain (白目 eye
    # white, 目光 highlight, 眉目 brows and lashes, 眼线 eyeliner).
    Rule("highlight", ("目光", "眼光", "瞳光", "高光", "ハイライト"), ("highlight", "highlights", "catchlight"),
         skip=("髪", "髮", "发", "hair")),
    Rule("sclera", ("白目", "白眼", "眼白"), ("sclera", "eyewhite", "eyewhites", "shirome")),
    Rule("lash", ("眉", "睫", "眼线", "眼線", "まつ毛", "まつげ", "まゆ"),
         ("brow", "brows", "eyebrow", "eyebrows", "lash", "lashes", "eyelash", "eyelashes", "eyeliner", "mayu")),
    Rule("eye", ("瞳", "虹彩", "目", "眼"), ("eye", "eyes", "iris", "pupil"), unless=("眼鏡", "目影")),
    Rule("rubber", ("口球", "口枷", "乳胶", "乳膠", "ラテックス"), ("gag", "latex", "rubber")),
    Rule("mouth", ("口腔", "齿", "歯", "牙", "舌", "口"), ("mouth", "teeth", "tooth", "tongue", "sita", "shita"),
         unless=("袖口",)),
    Rule("nail", ("指甲", "ネイル", "爪"), ("nail", "nails")),
    # Tear and drool overlays (淚) are face decals: matte like the face, so the
    # painted white streaks are not swapped for reflections of the dark face.
    Rule("face", ("颜", "顔", "脸", "臉", "頬", "表情", "目影", "赤", "淚", "涙", "泪"),
         ("face", "blush", "cheek", "expression", "biaoq", "shy", "tear", "tears")),
    Rule("hair", ("髪", "髮", "头发", "頭髮", "发"), ("hair", "bang", "bangs", "ahoge", "ponytail"),
         unless=("发圈", "发带", "髪飾", "发饰", "髮飾", "发卡")),
    Rule("stockings", ("袜", "襪", "ストッキング", "タイツ"),
         ("stocking", "stockings", "tights", "pantyhose", "sock", "socks", "siwa", "baisiwa", "heisiwa")),
    Rule("skin", ("肌", "皮肤", "皮膚", "体", "體", "身体", "胸", "腕", "手", "足", "脚", "腿", "淫纹", "淫紋"),
         ("skin", "body", "arm", "arms", "hand", "hands", "leg", "legs", "foot", "feet", "breast", "inmon", "tattoo")),
    Rule("cloth",
         ("衣", "服", "裙", "裤", "褲", "袖", "披", "领", "領", "结", "結", "带", "帶", "帽", "饰", "飾", "花边", "蕾丝",
          "レース", "リボン", "胖次", "下着", "发圈", "乳贴", "绳", "縄", "纱", "紗"),
         ("cloth", "clothes", "dress", "skirt", "shirt", "sleeve", "cape", "coat", "hat", "ribbon", "lace", "bow",
          "panties", "underwear", "bra", "strap", "rope")),
]

SPHERE_HINTS = [
    ("metal", ("金属", "金屬", "metal", "gold", "silver", "chrome")),
    ("gem", ("ガラス", "glass", "crystal")),
    ("skin", ("skin",)),
]


def _matches(rule: Rule, text: str) -> bool:
    if any(term in text.lower() for term in rule.skip):
        return False
    if any(term in text for term in rule.unless):
        stripped = text
        for term in rule.unless:
            stripped = stripped.replace(term, " ")
        text = stripped
    if any(term in text for term in rule.cjk):
        return True
    words = set(re.findall(r"[a-z]+", text.lower()))
    return any(word in words for word in rule.words)


def classify(name: str, name_en: str = "", sphere: str = "", texture: str = "") -> tuple[str, str]:
    """Return (class, reason) for one PMX material.

    Names decide first. The sphere map comes before the texture name: it is
    chosen per material (Firefly's neck uses the skin matcap on the clothes
    sheet), while a texture name is shared by every material on the atlas.
    """
    for text, label in ((name, "name"), (name_en, "english name")):
        if not text:
            continue
        for rule in RULES:
            if _matches(rule, text):
                return rule.cls, f"{label} '{text}'"
    sphere_lower = sphere.lower()
    for cls, terms in SPHERE_HINTS:
        if any(term in sphere_lower for term in terms):
            return cls, f"sphere map '{sphere}'"
    if texture:
        for rule in RULES:
            if _matches(rule, texture):
                return rule.cls, f"texture name '{texture}'"
    return "default", "no rule matched"


def class_params(cls: str, presets: dict | None = None) -> dict[str, float]:
    params = dict(CLASSES[cls])
    if presets and cls in presets:
        params.update(presets[cls])
    return params
