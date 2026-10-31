"""Minimal PMX 2.0/2.1 reader.

Only what texture work needs is decoded: UVs, vertex positions (to tell where
a UV island sits on the body), triangles, the texture table and the materials
(with their face ranges, sphere maps and flags). Bones, morphs and physics are
skipped over, never parsed.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

# Signed struct codes for texture/material indices, unsigned for vertex
# indices of width 1 and 2 (PMX spec: vertex index 4 is signed int32).
_SIGNED = {1: "b", 2: "h", 4: "i"}
_VERTEX = {1: np.uint8, 2: np.uint16, 4: np.int32}


@dataclass
class PmxMaterial:
    index: int
    name: str
    name_en: str
    diffuse: tuple[float, float, float, float]
    specular: tuple[float, float, float]
    specular_power: float
    ambient: tuple[float, float, float]
    flags: int
    texture: int
    sphere: int
    sphere_mode: int
    toon_shared: bool
    toon: int
    memo: str
    face_start: int  # first triangle
    face_count: int  # number of triangles

    @property
    def two_sided(self) -> bool:
        return bool(self.flags & 0x01)


@dataclass
class PmxModel:
    path: Path
    name: str
    name_en: str
    uv: np.ndarray  # (V, 2) float32, DirectX convention (v = 0 at the top)
    faces: np.ndarray  # (F, 3) int64
    textures: list[str]  # paths relative to the PMX folder, as authored
    materials: list[PmxMaterial]
    positions: np.ndarray | None = None  # (V, 3) float32, model units, Y up, front towards -Z

    def texture_path(self, index: int) -> Path | None:
        if index < 0 or index >= len(self.textures):
            return None
        return (self.path.parent / self.textures[index].replace("\\", "/")).resolve()

    def material_triangles(self, material: PmxMaterial) -> np.ndarray:
        return self.faces[material.face_start : material.face_start + material.face_count]


class _Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0
        self.encoding = "utf-16-le"

    def unpack(self, fmt: str):
        values = struct.unpack_from("<" + fmt, self.data, self.pos)
        self.pos += struct.calcsize("<" + fmt)
        return values

    def skip(self, count: int):
        self.pos += count

    def text(self) -> str:
        (length,) = self.unpack("i")
        raw = self.data[self.pos : self.pos + length]
        self.pos += length
        return raw.decode(self.encoding, errors="replace")


def read_pmx(path: str | Path) -> PmxModel:
    path = Path(path)
    r = _Reader(path.read_bytes())
    if r.data[:4] != b"PMX ":
        raise ValueError(f"{path} is not a PMX file")
    r.skip(4)
    (version,) = r.unpack("f")
    if version < 2.0:
        raise ValueError(f"unsupported PMX version {version}")
    (global_count,) = r.unpack("B")
    globals_ = r.unpack(f"{global_count}B")
    r.encoding = "utf-8" if globals_[0] == 1 else "utf-16-le"
    extra_uv, vsize, tsize, msize, bsize = globals_[1], globals_[2], globals_[3], globals_[4], globals_[5]

    name = r.text()
    name_en = r.text()
    r.text()  # comment
    r.text()  # comment (en)

    (vertex_count,) = r.unpack("i")
    uv = np.empty((vertex_count, 2), dtype=np.float32)
    positions = np.empty((vertex_count, 3), dtype=np.float32)
    # Fixed part per vertex: position, normal, uv, extra uvs. The deform block
    # length depends on its type byte, so vertices are walked one by one.
    fixed = 32 + 16 * extra_uv
    deform_size = {0: bsize, 1: 2 * bsize + 4, 2: 4 * bsize + 16, 3: 2 * bsize + 40, 4: 4 * bsize + 16}
    data = r.data
    pos = r.pos
    unpack_uv = struct.Struct("<2f").unpack_from
    unpack_position = struct.Struct("<3f").unpack_from
    for i in range(vertex_count):
        positions[i] = unpack_position(data, pos)
        uv[i] = unpack_uv(data, pos + 24)
        pos += fixed
        kind = data[pos]
        pos += 1 + deform_size[kind] + 4  # deform + edge scale
    r.pos = pos

    (index_count,) = r.unpack("i")
    dtype = _VERTEX[vsize]
    indices = np.frombuffer(r.data, dtype=dtype, count=index_count, offset=r.pos).astype(np.int64)
    r.skip(index_count * vsize)
    faces = indices.reshape(-1, 3)

    (texture_count,) = r.unpack("i")
    textures = [r.text() for _ in range(texture_count)]

    tcode = _SIGNED[tsize]
    (material_count,) = r.unpack("i")
    materials: list[PmxMaterial] = []
    face_cursor = 0
    for index in range(material_count):
        mname = r.text()
        mname_en = r.text()
        diffuse = r.unpack("4f")
        specular = r.unpack("3f")
        (power,) = r.unpack("f")
        ambient = r.unpack("3f")
        (flags,) = r.unpack("B")
        r.skip(16 + 4)  # edge colour, edge size
        (texture,) = r.unpack(tcode)
        (sphere,) = r.unpack(tcode)
        (sphere_mode,) = r.unpack("B")
        (toon_shared,) = r.unpack("B")
        if toon_shared:
            (toon,) = r.unpack("B")
        else:
            (toon,) = r.unpack(tcode)
        memo = r.text()
        (count,) = r.unpack("i")
        triangles = count // 3
        materials.append(
            PmxMaterial(
                index=index,
                name=mname,
                name_en=mname_en,
                diffuse=diffuse,
                specular=specular,
                specular_power=power,
                ambient=ambient,
                flags=flags,
                texture=texture,
                sphere=sphere,
                sphere_mode=sphere_mode,
                toon_shared=bool(toon_shared),
                toon=toon,
                memo=memo,
                face_start=face_cursor,
                face_count=triangles,
            )
        )
        face_cursor += triangles
    del msize  # material index width is only needed past the material table

    return PmxModel(path=path, name=name, name_en=name_en, uv=uv, faces=faces, textures=textures, materials=materials,
                    positions=positions)
