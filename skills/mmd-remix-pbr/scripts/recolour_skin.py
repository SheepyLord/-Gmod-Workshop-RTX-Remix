"""Recolour a skin sheet to a reference skin tone (made for Evernight, on the user's request).

The base tone (median of bright, low-chroma texels) of the source moves to the reference's in CIELAB
a*/b*; lightness is kept unless --match-lightness. Shading and blush keep --keep of their chroma
around the base, and texels far from skin (lips, nipples, red inner parts) take only part of the
shift, fading with their chroma distance from the base. Alpha is copied unchanged.

    python recolour_skin.py --src body.png --ref <ref folder or images> --out body_whitened.png \
        --pmx model.pmx --materials 0,1,2,3,4

With --pmx and --materials the source base is measured only where those materials' UV triangles
lie; without them the sheet's background fill counts too (Evernight's peach fill pushed the base
to b* 9.3 against 6.0 on the mesh, and the body came out cool). The result goes to a per-texture
"albedo_source" in the model's preset (README, "Recoloured albedo").
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOOL = Path(__file__).resolve().parents[1] / "tool"
sys.path.insert(0, str(TOOL))

_M = np.array([[0.4124564, 0.3575761, 0.1804375],
               [0.2126729, 0.7151522, 0.0721750],
               [0.0193339, 0.1191920, 0.9503041]], np.float32)
_MI = np.linalg.inv(_M).astype(np.float32)
_WHITE = np.array([0.95047, 1.0, 1.08883], np.float32)


def rgb2lab(rgb8: np.ndarray) -> np.ndarray:
    c = rgb8.astype(np.float32) / 255
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = lin @ _M.T / _WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab2rgb(lab: np.ndarray) -> np.ndarray:
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    xyz = np.where(f ** 3 > 216 / 24389, f ** 3, (116 * f - 16) / (24389 / 27)) * _WHITE
    c = np.clip(xyz @ _MI.T, 0, 1)
    srgb = np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
    return (srgb * 255 + 0.5).astype(np.uint8)


def skin_base(rgba: np.ndarray, sample: int = 4, mask: np.ndarray | None = None) -> np.ndarray:
    """Median Lab of bright, low-chroma, opaque texels (the painted skin base), inside ``mask``."""
    lab = rgb2lab(rgba[::sample, ::sample, :3])
    keep = (rgba[::sample, ::sample, 3] > 200) & (lab[..., 0] > 80) & (np.hypot(lab[..., 1], lab[..., 2]) < 15)
    if mask is not None:
        keep &= mask
    if not keep.any():
        raise ValueError("no skin-like texels (L > 80, chroma < 15)")
    return np.median(lab[keep], 0)


def recolour(rgba: np.ndarray, base: np.ndarray, target: np.ndarray, keep: float, reach: float,
             match_lightness: bool, rows: int = 512) -> np.ndarray:
    out = rgba.copy()
    for y in range(0, rgba.shape[0], rows):
        lab = rgb2lab(rgba[y:y + rows, :, :3])
        d = lab[..., 1:] - base[1:]
        near = np.exp(-np.sum(d * d, -1) / (reach * reach))[..., None]
        shift = (target[1:] - base[1:]) * (0.4 + 0.6 * near) + (keep - 1) * d * near
        lab[..., 1:] += shift
        if match_lightness:
            lab[..., 0] += (target[0] - base[0]) * near[..., 0]
        out[y:y + rows, :, :3] = lab2rgb(lab)
    return out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--src", type=Path, required=True)
    p.add_argument("--ref", type=Path, nargs="+", required=True, help="reference images or folders of them")
    p.add_argument("--ref-glob", default="*", help="file pattern inside reference folders")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--keep", type=float, default=0.75, help="share of shading chroma kept around the base")
    p.add_argument("--reach", type=float, default=18.0, help="chroma distance (Lab) over which the full shift fades")
    p.add_argument("--match-lightness", action="store_true")
    p.add_argument("--pmx", type=Path, help="measure the source base on these materials' UV islands")
    p.add_argument("--materials", help="0-based PMX material indices, comma separated (with --pmx)")
    a = p.parse_args()

    refs = []
    for r in a.ref:
        refs += sorted(f for f in r.glob(a.ref_glob) if f.suffix.lower() in (".png", ".jpg")) if r.is_dir() else [r]
    bases = []
    for r in refs:
        rgba = np.asarray(Image.open(r).convert("RGBA"))
        try:
            bases.append(skin_base(rgba))
            print(f"ref  {r.name}: Lab {np.round(bases[-1], 1)}")
        except ValueError:
            pass
    target = np.median(np.array(bases), 0)
    src = np.asarray(Image.open(a.src).convert("RGBA"))
    mask = None
    if a.pmx:
        from rpai.pmx import read_pmx
        from rpai import uvmask
        model = read_pmx(a.pmx)
        height, width = src[::4, ::4].shape[:2]
        _, mask = uvmask.rasterize(model, {int(i): "skin" for i in a.materials.split(",")}, width, height)
    base = skin_base(src, mask=mask)
    print(f"src  {a.src.name}: Lab {np.round(base, 1)}  ->  target {np.round(target, 1)}")
    out = recolour(src, base, target, a.keep, a.reach, a.match_lightness)
    print(f"out  {a.out.name}: Lab {np.round(skin_base(out, mask=mask), 1)}")
    a.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(a.out, compress_level=1)


if __name__ == "__main__":
    main()
