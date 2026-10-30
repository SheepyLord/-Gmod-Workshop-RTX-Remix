"""The runtime's night-sky textures from NightSky HD LE (PraedythXVI; FullNebula
from Era-7's nebula images). The star sphere and the galaxy band keep the mod's own DDS (the shader
maps them as the mod's stars.nif does). The constellations (58 triangles of their own atlas) are baked
into the nebula's longitude/latitude map, added as Skyrim adds sky layers: colour times alpha, in
gamma space. Usage:
  python -I tools/sky/bake_nightsky.py <mod folder> <stars_nif.json> <out folder> <nebula option 1-4> <stars option>
See bake_nightsky.py.md.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# NVIDIA Texture Tools Exporter: the one in the RTX Remix app unless NVTT_EXPORT names another.
NVTT = os.environ.get('NVTT_EXPORT', r'C:\Program Files\NVIDIA Corporation\RTX Remix\exts\omni.flux.resources\deps\tools\nvtt\nvtt_export.exe')
mod, nif_json, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
nebula_option, stars_option = sys.argv[4], sys.argv[5]
out.mkdir(parents=True, exist_ok=True)
work = out / 'src'
work.mkdir(exist_ok=True)


def load_rgba(path):
    with Image.open(path) as im:
        im.load()
        return np.asarray(im.convert('RGBA'), dtype=np.float32) / 255.0


info = json.load(open(nif_json))
block = info['blocks'][5]  # ConstellationsCombined
verts = np.array(block['v'], dtype=np.float64).reshape(-1, 3)
uvs = np.array(block['uv'], dtype=np.float64).reshape(-1, 2)
tris = np.array(block['t']).reshape(-1, 3)

nebula = load_rgba(mod / f'00Data/tex/FullNebula{nebula_option}/textures/sky/FullNebula.dds')
H, W, _ = nebula.shape
result = nebula[..., :3] * nebula[..., 3:4]

atlas = load_rgba(mod / '00Data/tex/Textures/Sky/skyrimconstellations.dds')
# The atlas is drawn about 110 texels a degree and the map holds 23-45: pre-filter it once (premultiplied).
premul = np.concatenate([atlas[..., :3] * atlas[..., 3:4], atlas[..., 3:4]], axis=-1)
ah, aw = premul.shape[0] // 2, premul.shape[1] // 2
premul = premul.reshape(ah, 2, aw, 2, 4).mean(axis=(1, 3))
del atlas


def sample(u, v):
    """Bilinear, clamped, from the pre-filtered premultiplied atlas."""
    x = np.clip(u * aw - 0.5, 0, aw - 1.001)
    y = np.clip(v * ah - 0.5, 0, ah - 1.001)
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    p = premul
    return ((p[y0, x0] * (1 - fx) + p[y0, x0 + 1] * fx) * (1 - fy)
            + (p[y0 + 1, x0] * (1 - fx) + p[y0 + 1, x0 + 1] * fx) * fy)


def lonlat_of(p):
    return np.arctan2(p[..., 1], p[..., 0]), np.arcsin(np.clip(p[..., 2] / np.linalg.norm(p, axis=-1), -1, 1))


covered = 0
for tri in tris:
    a, b, c = verts[tri]
    ta, tb, tc = uvs[tri]
    lon, lat = lonlat_of(np.stack([a, b, c]))
    # Texel box in the map; a triangle across the +-180 seam is handled in unwrapped longitude.
    lon_u = np.unwrap(lon)
    xs = (0.5 + lon_u / (2 * np.pi)) * W
    ys = (0.5 - lat / np.pi) * H
    x0, x1 = int(np.floor(xs.min())) - 1, int(np.ceil(xs.max())) + 1
    y0, y1 = max(int(np.floor(ys.min())) - 1, 0), min(int(np.ceil(ys.max())) + 1, H - 1)
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    lon_t = ((gx + 0.5) / W - 0.5) * 2 * np.pi
    lat_t = (0.5 - (gy + 0.5) / H) * np.pi
    d = np.stack([np.cos(lat_t) * np.cos(lon_t), np.cos(lat_t) * np.sin(lon_t), np.sin(lat_t)], axis=-1)
    # Ray from the centre through the planar triangle (what the GPU rasterises), barycentric UV.
    n = np.cross(b - a, c - a)
    denom = d @ n
    with np.errstate(divide='ignore', invalid='ignore'):
        t = (a @ n) / denom
    p = d * t[..., None]
    v0, v1 = b - a, c - a
    v2 = p - a
    d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
    d20, d21 = v2 @ v0, v2 @ v1
    inv = 1.0 / (d00 * d11 - d01 * d01)
    w1 = (d11 * d20 - d01 * d21) * inv
    w2 = (d00 * d21 - d01 * d20) * inv
    w0 = 1 - w1 - w2
    inside = (t > 0) & (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    if not inside.any():
        continue
    uv = w0[inside, None] * ta + w1[inside, None] * tb + w2[inside, None] * tc
    s = sample(uv[:, 0], uv[:, 1])
    rows, cols = gy[inside], np.mod(gx[inside], W)
    result[rows, cols] += s[:, :3]
    covered += inside.sum()
print('constellation texels baked', covered)

png = work / f'nebula{nebula_option}_constellations.png'
Image.fromarray((np.clip(result, 0, 1) * 255 + 0.5).astype(np.uint8)).save(png)
# Gamma-space values, sampled raw and turned linear in the shader after the layers are added (as
# Skyrim composites its sky): UNORM, and mips without gamma correction.
cmd = [NVTT, str(png), '-o', str(out / 'nebula.dds'), '--dx10', '-f', 'bc7', '--export-transfer-function', 'linear',
       '-q', 'production', '--mip-filter', 'box', '--no-mip-gamma-correct']
print(' '.join(cmd))
subprocess.run(cmd, check=True)
shutil.copyfile(mod / f'00Data/tex/{stars_option}/textures/sky/skystars.dds', out / 'stars.dds')
shutil.copyfile(mod / '00Data/tex/Textures/Sky/skyrimgalaxy.dds', out / 'galaxy.dds')
for name in ('stars.dds', 'galaxy.dds', 'nebula.dds'):
    print(name, (out / name).stat().st_size)
