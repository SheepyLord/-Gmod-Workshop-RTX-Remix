"""Builds the runtime's Moon textures from NASA's CGI Moon Kit (https://svs.gsfc.nasa.gov/4720):

  moon_albedo.dds  2048x1024 BC7 sRGB + mips, near-side mean linear luminance scaled to 0.25
  moon_normal.dds  1440x720  BC5 tangent-space normal (x east, y north) + mips, from the LDEM

Usage: python -I tools/sky/make_moon_textures.py <lroc_color_poles_4k.tif> <ldem_4.tif> <out dir>
See make_moon_textures.py.md.
"""
import os
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# NVIDIA Texture Tools Exporter: the one in the RTX Remix app unless NVTT_EXPORT names another.
NVTT = os.environ.get('NVTT_EXPORT', r'C:\Program Files\NVIDIA Corporation\RTX Remix\exts\omni.flux.resources\deps\tools\nvtt\nvtt_export.exe')
MOON_RADIUS_KM = 1737.4
NEAR_SIDE_MEAN = 0.25  # the shader divides by this (atmosphere_sky.slangh evalTexturedMoon)

moon_path, ldem_path, out = map(Path, sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
work = out / 'src'
work.mkdir(exist_ok=True)


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def resize_float(a, size):
    return np.stack([np.asarray(Image.fromarray(a[..., i]).resize(size, Image.LANCZOS)) for i in range(a.shape[-1])], -1)


def nvtt(src, dst, *args):
    cmd = [NVTT, str(src), '-o', str(dst), '--dx10', *args]
    print(' '.join(cmd))
    subprocess.run(cmd, check=True)


def dds_info(path):
    head = path.read_bytes()[:148]
    height, width = struct.unpack_from('<II', head, 12)
    mips = struct.unpack_from('<I', head, 28)[0]
    fourcc = head[84:88]
    dxgi = struct.unpack_from('<I', head, 128)[0] if fourcc == b'DX10' else None
    return width, height, mips, fourcc, dxgi, path.stat().st_size


# --- Moon albedo -------------------------------------------------------------
with Image.open(moon_path) as im:
    moon = srgb_to_linear(np.asarray(im.convert('RGB'), dtype=np.float32) / 255.0).astype(np.float32)
moon = np.clip(resize_float(moon, (2048, 1024)), 0.0, None)
h, w, _ = moon.shape
lum = moon @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
lon = ((np.arange(w) + 0.5) / w - 0.5) * 2 * np.pi
# Near side as seen from Earth: weight by the projected area towards the sub-Earth point.
weight = np.clip(np.cos(lat)[:, None] * np.cos(lon)[None, :], 0.0, None) * np.cos(lat)[:, None]
near_mean = float((lum * weight).sum() / weight.sum())
scale = NEAR_SIDE_MEAN / near_mean
scaled = moon * scale
print(f'moon: near-side mean linear lum {near_mean:.4f}, scale {scale:.3f}, '
      f'p99.9 after {float(np.percentile(scaled @ np.array([0.2126, 0.7152, 0.0722]), 99.9)):.3f}, '
      f'clipped {float((scaled > 1).mean() * 100):.3f} %')
png = work / 'moon_albedo.png'
Image.fromarray((np.clip(linear_to_srgb(np.clip(scaled, 0, 1)), 0, 1) * 255 + 0.5).astype(np.uint8)).save(png)
nvtt(png, out / 'moon_albedo.dds', '-f', 'bc7', '--export-transfer-function', 'srgb', '-q', 'production',
     '--mip-filter', 'kaiser')

# --- Moon relief -> normal map ------------------------------------------------
with Image.open(ldem_path) as im:
    height_km = np.asarray(im, dtype=np.float64)
rows, cols = height_km.shape
lat = (0.5 - (np.arange(rows) + 0.5) / rows) * np.pi
px_km = 2 * np.pi * MOON_RADIUS_KM / cols  # one pixel along a parallel at the equator, and along a meridian
east = (np.roll(height_km, -1, axis=1) - np.roll(height_km, 1, axis=1)) / (2 * px_km * np.maximum(np.cos(lat), 0.02)[:, None])
up = np.vstack([height_km[:1], height_km[:-1]])     # row above = further north
down = np.vstack([height_km[1:], height_km[-1:]])
north = (up - down) / (2 * px_km)
normal = np.stack([-east, -north, np.ones_like(east)], -1)
normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
slope = np.hypot(east, north)
print(f'relief: slope p50 {np.percentile(slope, 50):.3f}, p90 {np.percentile(slope, 90):.3f}, '
      f'p99 {np.percentile(slope, 99):.3f}, max {slope.max():.3f}')
png = work / 'moon_normal.png'
Image.fromarray((np.clip(normal * 0.5 + 0.5, 0, 1) * 255 + 0.5).astype(np.uint8)).save(png)
nvtt(png, out / 'moon_normal.dds', '-f', 'bc5', '--export-transfer-function', 'linear', '-q', 'production',
     '--mip-filter', 'kaiser', '--no-mip-gamma-correct')

for name in ('moon_albedo.dds', 'moon_normal.dds'):
    print(name, dds_info(out / name))
