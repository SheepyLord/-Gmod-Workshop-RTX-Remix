"""Offline Remix texture hashes for Model Hotloader's uncompressed VTFs.

dxvk-remix (``D3D9CommonTexture::SetupForRtxFrom``) hashes the CPU buffer of
subresource 0 - the top mip as uploaded - with ``XXH64(data, size, 0)`` when
``rtx.useObsoleteHashOnTextureUpload`` is true, otherwise ``XXH3_64bits``.

How Source uploads RGBA8888 was measured against hashes reported by the
running game (Hyacine, 2026-10-24, 10 of 12 textures reproduced):

* VTFs with an alpha flag go up as A8R8G8B8: BGRA bytes (5 of 5).
* VTFs without one mostly go up as X8R8G8B8 with a zero pad byte: BGR0 (4 of
  7). The face sheet went up as BGRA, and the body and hair sheets matched no
  layout at any mip level.
* So live hashes stay authoritative; prediction is the fallback for materials
  that are not drawn yet (hidden by default, toggled by morphs). An override
  for a hash nothing uses is inert, so every plausible candidate is written.

Compiled addons ship block-compressed VTFs, whose blocks go up unchanged: the
top mip's raw DXT5 data reproduced all 3 live hashes of Robin's robin_zzz.mdl
(2026-10-25). DXT1 and DXT3 are hashed the same way.
"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import xxhash

ALPHA_FLAGS = 0x1000 | 0x2000  # TEXTUREFLAGS_ONEBITALPHA | TEXTUREFLAGS_EIGHTBITALPHA


@dataclass
class Vtf:
    width: int
    height: int
    flags: int
    format: int
    mips: int
    frames: int
    data_end: int


def read_vtf_header(blob: bytes) -> Vtf:
    if blob[:4] != b"VTF\0":
        raise ValueError("not a VTF")
    width, height, flags, frames = struct.unpack_from("<HHIH", blob, 16)
    image_format = struct.unpack_from("<i", blob, 52)[0]
    return Vtf(width, height, flags, image_format, blob[56], max(1, frames), len(blob))


def top_mip_rgba(blob: bytes, vtf: Vtf) -> np.ndarray:
    """Mip 0 of an RGBA8888 VTF. The chain is stored smallest first, so it is the tail."""
    if vtf.format != 0:
        raise ValueError(f"VTF format {vtf.format} is not RGBA8888")
    size = vtf.width * vtf.height * 4
    return np.frombuffer(blob, np.uint8, size, vtf.data_end - size * vtf.frames).reshape(-1, 4)


def _digest(data: bytes, obsolete: bool) -> str:
    value = xxhash.xxh64_intdigest(data, seed=0) if obsolete else xxhash.xxh3_64_intdigest(data)
    return f"0x{value:016X}"


BLOCK_BYTES = {13: 8, 14: 16, 15: 16, 20: 8}  # DXT1, DXT3, DXT5, DXT1_ONEBITALPHA: bytes per 4x4 block


def predict(blob: bytes, obsolete: bool = True) -> list[str]:
    """Candidate Remix hashes for a VTF, most likely first."""
    vtf = read_vtf_header(blob)
    if vtf.format in BLOCK_BYTES:
        size = max(1, (vtf.width + 3) // 4) * max(1, (vtf.height + 3) // 4) * BLOCK_BYTES[vtf.format]
        start = vtf.data_end - size * vtf.frames
        return [_digest(blob[start:start + size], obsolete)]
    rgba = top_mip_rgba(blob, vtf)
    bgra = np.ascontiguousarray(rgba[:, [2, 1, 0, 3]])
    candidates = []
    if not vtf.flags & ALPHA_FLAGS:
        bgr0 = bgra.copy()
        bgr0[:, 3] = 0
        candidates.append(_digest(bgr0.tobytes(), obsolete))
    candidates.append(_digest(bgra.tobytes(), obsolete))
    return list(dict.fromkeys(candidates))


def read_obsolete_hash_option(game_root: Path) -> bool:
    """``rtx.useObsoleteHashOnTextureUpload`` from rtx.conf (Remix default: False)."""
    conf = game_root / "rtx.conf"
    if conf.exists():
        m = re.search(
            r"^\s*rtx\.useObsoleteHashOnTextureUpload\s*=\s*(\w+)",
            conf.read_text(encoding="utf-8", errors="replace"),
            re.MULTILINE | re.IGNORECASE,
        )
        if m:
            return m.group(1).strip().lower() in ("true", "1", "yes")
    return False
