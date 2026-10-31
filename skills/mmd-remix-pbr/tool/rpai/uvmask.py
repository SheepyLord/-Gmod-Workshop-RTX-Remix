"""Rasterise PMX material classes into texture space.

Every material's UV triangles are drawn into a class-id image the size of the
generated maps, lowest priority first (classify.PRIORITY), so the texels of a
shared atlas learn which kind of surface they belong to. Texels no triangle
covers take the nearest covered class, so mip levels and bilinear filtering
never pull in an unrelated default along island borders.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from .classify import CLASS_ID, PRIORITY
from .pmx import PmxModel

PALETTE = {
    "default": (128, 128, 128), "cloth": (70, 130, 220), "stockings": (150, 110, 230), "leather": (140, 80, 40),
    "rubber": (230, 60, 160), "hair": (240, 200, 60), "skin": (250, 170, 140), "mouth": (220, 60, 60),
    "face": (255, 220, 200), "lash": (60, 30, 20), "nail": (255, 120, 200), "wet": (255, 40, 90),
    "gem": (60, 240, 240), "metal": (230, 230, 230), "sclera": (200, 255, 255), "eye": (40, 220, 90),
    "highlight": (255, 255, 0),
}


def rasterize(model: PmxModel, materials: dict[int, str], width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    """Return (class ids filled everywhere, covered mask) for the given {material index: class}."""
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    order = sorted(materials.items(), key=lambda item: PRIORITY.index(item[1]))
    for index, cls in order:
        material = model.materials[index]
        triangles = model.material_triangles(material)
        if not len(triangles):
            continue
        uv = model.uv[triangles].astype(np.float64)  # (n, 3, 2)
        # MMD UVs may tile; bring each triangle back to the unit square by its
        # centroid and repeat the ones that straddle an edge.
        uv -= np.floor(uv.mean(axis=1, keepdims=True))
        xy = uv * (width, height)
        straddle = (uv.min(axis=(1, 2)) < 0) | (uv.max(axis=(1, 2)) > 1)
        fill = CLASS_ID[cls]
        for tri in xy:
            draw.polygon([tuple(p) for p in tri], fill=fill)
        for tri in xy[straddle]:
            for dx in (-width, 0, width):
                for dy in (-height, 0, height):
                    if dx or dy:
                        draw.polygon([(x + dx, y + dy) for x, y in tri], fill=fill)
    ids = np.asarray(image, dtype=np.uint8).copy()
    covered = ids > 0
    if not covered.any():
        ids[:] = CLASS_ID["default"]
        return ids, covered
    if not covered.all():
        # Nearest-class fill on a quarter-size grid is plenty for gutters.
        step = 4 if min(width, height) >= 1024 else 1
        small = ids[::step, ::step]
        empty = small == 0
        if empty.all():
            small = np.where(empty, CLASS_ID["default"], small)
        else:
            nearest = ndimage.distance_transform_edt(empty, return_distances=False, return_indices=True)
            small = small[nearest[0], nearest[1]]
        grown = np.repeat(np.repeat(small, step, axis=0), step, axis=1)[:height, :width]
        ids = np.where(covered, ids, grown)
    return ids, covered


def islands(model: PmxModel, materials: list[int], width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    """(UV island id per texel, 0 where no triangle lies; centroid per island id) for the given materials.

    An island is a set of triangles connected through shared vertices. PMX splits
    vertices along UV seams, so each island is one piece of the unwrap: a leg, a
    shoe, one gold star. Robin's single Body material holds 622 of them, skin and
    dress and gold alike. Where islands overlap (mirrored halves), the later one
    keeps the texel. Centroids are in model units (row 0 unused), so a rule can ask
    where an island sits on the body: Robin's shoes and ankle straps are 18
    islands spread over the sheet, all below 2.6 units.
    """
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components

    parts = [model.material_triangles(model.materials[i]) for i in materials]
    triangles = np.concatenate(parts) if parts else np.zeros((0, 3), np.int64)
    image = Image.new("I", (width, height), 0)
    centroids = np.full((1, 3), np.nan)
    if len(triangles):
        count = len(triangles)
        vertices, inverse = np.unique(triangles.ravel(), return_inverse=True)
        graph = coo_matrix((np.ones(3 * count, np.int8), (np.repeat(np.arange(count), 3), count + inverse)),
                           shape=(count + len(vertices),) * 2)
        labels = connected_components(graph, directed=False)[1][:count]
        labels = np.unique(labels, return_inverse=True)[1] + 1
        if model.positions is not None:
            centres = model.positions[triangles].mean(axis=1)
            sizes = np.bincount(labels).astype(np.float64)
            centroids = np.stack([np.bincount(labels, centres[:, c]) for c in range(3)], 1) / np.maximum(sizes, 1)[:, None]
            centroids[0] = np.nan
        uv = model.uv[triangles].astype(np.float64)
        uv -= np.floor(uv.mean(axis=1, keepdims=True))
        draw = ImageDraw.Draw(image)
        for tri, label in zip(uv * (width, height), labels):
            draw.polygon([tuple(p) for p in tri], fill=int(label))
    return np.asarray(image, np.int32), centroids


def _hsv(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Vectorised RGB [0, 1] -> hue in degrees, saturation, value."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rc = nz & (mx == r)
    gc = nz & ~rc & (mx == g)
    bc = nz & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    return h * 60, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx


def apply_regions(ids: np.ndarray, rgba: np.ndarray, rules: list[dict], covered: np.ndarray | None = None,
                  island_map: tuple[np.ndarray, np.ndarray] | None = None) -> np.ndarray:
    """Reclassify parts of a material by the painted colour beneath them.

    Anime sheets paint gold trim and silver embroidery straight onto cloth, so a
    per-material class cannot make them metal. A rule selects texels by class
    (``within``), an optional UV rectangle (``rect``, fractions x0 y0 x1 y1) and
    HSV ranges (``hue`` degrees, may wrap; ``sat``/``val`` 0-1), then sets
    ``class``. One opening drops speckle; one dilation, kept inside the
    selection's classes, recovers anti-aliased edges. With ``covered``, only
    texels a UV triangle touches are matched: the gutter fill would otherwise
    pick up unused artwork (15% of a sheet on Guinevere's 衣2内.png).

    ``"islands": f`` (with ``island_map`` from islands()) takes whole UV islands
    instead: those whose texels within the rule's classes match the colours (and
    lie in ``rect``) for at least the fraction f. Robin's body sheet is one
    material whose skin, gold and dress differ per island, while texel colours
    overlap: the champagne gold and the skin's warm shading both read as hue
    20-35 at low saturation. ``"box": [x0, y0, z0, x1, y1, z1]`` (model units, Y
    up) further keeps only islands whose centroid lies inside it.
    """
    if not rules:
        return ids
    h, w = ids.shape
    if rgba.shape[:2] != (h, w):
        rgba = np.asarray(Image.fromarray(rgba, "RGBA").resize((w, h), Image.BILINEAR))
    hue, sat, val = _hsv(rgba[..., :3].astype(np.float32) / 255)
    opaque = rgba[..., 3] > 64
    if covered is not None:
        opaque &= covered
    out = ids.copy()
    for rule in rules:
        # Rules apply in order, each on the classes the rules before it left: Robin's gold islands
        # become metal, then the white crystal facets inside them become gem.
        within = np.isin(out, [CLASS_ID[c] for c in rule.get("within", list(CLASS_ID))])
        mask = within & opaque
        eligible = mask.copy()
        if "rect" in rule:
            x0, y0, x1, y1 = rule["rect"]
            box = np.zeros_like(mask)
            box[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)] = True
            mask &= box
        if "hue" in rule:
            lo, hi = rule["hue"]
            mask &= ((hue >= lo) & (hue <= hi)) if lo <= hi else ((hue >= lo) | (hue <= hi))
        if "sat" in rule:
            mask &= (sat >= rule["sat"][0]) & (sat <= rule["sat"][1])
        if "val" in rule:
            mask &= (val >= rule["val"][0]) & (val <= rule["val"][1])
        if "islands" in rule:
            if island_map is None:
                raise ValueError("an 'islands' region rule needs the UV island map")
            island_ids, centroids = island_map
            total = np.bincount(island_ids[eligible], minlength=len(centroids))
            hits = np.bincount(island_ids[mask], minlength=len(total))
            keep = (hits >= rule["islands"] * np.maximum(total, 1)) & (total > 0)
            if "box" in rule:
                lo, hi = np.asarray(rule["box"][:3]), np.asarray(rule["box"][3:])
                keep &= np.all((centroids >= lo) & (centroids <= hi), axis=1)
            taken = np.nonzero(keep)[0]
            mask = np.isin(island_ids, taken[taken > 0]) & within
        else:
            mask = ndimage.binary_opening(mask, iterations=1)
            mask = ndimage.binary_dilation(mask, iterations=1) & within
        out[mask] = CLASS_ID[rule["class"]]
    return out


def preview(ids: np.ndarray, albedo: np.ndarray | None = None, size: int = 1024) -> Image.Image:
    """Class colours over the albedo, for checking the classification by eye."""
    lut = np.zeros((256, 3), dtype=np.uint8)
    for name, cid in CLASS_ID.items():
        lut[cid] = PALETTE[name]
    colour = lut[ids]
    if albedo is not None:
        base = albedo[..., :3].astype(np.float32)
        if base.shape[:2] != colour.shape[:2]:
            base = np.asarray(Image.fromarray(albedo[..., :3]).resize(colour.shape[1::-1], Image.BILINEAR), np.float32)
        colour = (0.55 * colour + 0.45 * base).astype(np.uint8)
    image = Image.fromarray(colour)
    scale = size / max(image.size)
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.NEAREST)
    return image
