"""Read Model Hotloader's cache to learn how a PMX appears inside the game.

Model Hotloader imports a PMX into ``garrysmod/data/mmd_hotloader/assets/<id>/``:
a manifest, the PMX copy and a GMA with one VMT per PMX material
(``materials/mmd/<id16>/<name>_<index+1>.vmt``) and one uncompressed VTF per
unique base texture (``materials/mmd/t/<sha16>.vtf``). Remix hashes the GPU
texture, so every PMX material sharing a texture file shares one Remix hash.
"""

from __future__ import annotations

import hashlib
import json
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path

DEBUG_WHITE = "models/debug/debugwhite"


@dataclass
class HotloaderTexture:
    key: str  # sha16, the VTF name under materials/mmd/t/
    vtf: str  # Source texture name, e.g. "mmd/t/358bb1b694585ff4"
    source: Path | None  # original image next to the PMX
    width: int = 0
    height: int = 0
    materials: list[int] = field(default_factory=list)  # PMX material indices


@dataclass
class HotloaderAsset:
    asset_id: str
    folder: Path
    manifest: dict
    vmts: dict[int, str]  # PMX material index -> Source material name (no "materials/", no ".vmt")
    base_textures: dict[int, str]  # PMX material index -> $basetexture
    textures: dict[str, HotloaderTexture]  # sha16 -> texture
    # A compiled addon instead of an import (sourcemodel.py): its model path and VTF files by key.
    vtf_files: dict[str, Path] = field(default_factory=dict)
    mdl: str | None = None

    @property
    def short_id(self) -> str:
        return self.asset_id[:16]

    def iter_vtf_data(self):
        """(key, texture, VTF bytes) per texture, one at a time (Model Hotloader's are 64 MB each)."""
        if self.vtf_files:
            for key, texture in self.textures.items():
                yield key, texture, self.vtf_files[key].read_bytes()
            return
        gma = sorted(self.folder.glob("materials-v*.gma"))[-1]
        index = _read_gma(gma)
        with gma.open("rb") as f:
            for key, texture in self.textures.items():
                offset, size = index[f"materials/{texture.vtf}.vtf"]
                f.seek(offset)
                yield key, texture, f.read(size)


def _norm(path: str | Path) -> str:
    return str(Path(path)).replace("/", "\\").casefold()


def find_asset_id(game_root: Path, pmx_path: Path) -> str:
    """Return the newest imported asset of this PMX: by registered path, else by content.

    The registry stores the path at import time, so a renamed or moved folder
    loses that match. Each manifest's ``sourceHash`` is the SHA-256 of the PMX
    bytes (checked on Hyacine and Firefly), which survives the move.
    """
    data_dir = game_root / "garrysmod" / "data" / "mmd_hotloader"
    registry = json.loads((data_dir / "sources.local.json").read_text(encoding="utf-8-sig"))
    want = _norm(pmx_path.resolve())
    candidates = []
    for asset_id, entry in registry.items():
        source = entry.get("source") if isinstance(entry, dict) else None
        if not source or _norm(source) != want:
            continue
        manifest = data_dir / "assets" / asset_id / "manifest.json"
        if manifest.exists():
            candidates.append((manifest.stat().st_mtime, asset_id))
    if not candidates:
        digest = hashlib.sha256(pmx_path.read_bytes()).hexdigest()
        for manifest in (data_dir / "assets").glob("*/manifest.json"):
            try:
                source_hash = json.loads(manifest.read_text(encoding="utf-8-sig")).get("sourceHash")
            except (OSError, ValueError):
                continue
            if source_hash == digest:
                candidates.append((manifest.stat().st_mtime, manifest.parent.name))
    if not candidates:
        raise FileNotFoundError(
            f"Model Hotloader has no cached import of {pmx_path}. Import it in game (Q > MMD) first."
        )
    return max(candidates)[1]


def _read_gma(path: Path) -> dict[str, tuple[int, int]]:
    """Index a GMA: file name -> (absolute offset, size)."""
    with path.open("rb") as f:
        if f.read(4) != b"GMAD":
            raise ValueError(f"{path} is not a GMA archive")
        version = f.read(1)[0]
        f.read(16)  # steam id, timestamp

        def cstr() -> str:
            out = bytearray()
            while (c := f.read(1)) not in (b"", b"\0"):
                out += c
            return out.decode("utf-8", errors="replace")

        if version > 1:
            while cstr():  # required content list
                pass
        cstr(), cstr(), cstr()  # name, description, author
        f.read(4)  # addon version
        entries = []
        while struct.unpack("<I", f.read(4))[0] != 0:
            name = cstr()
            size, _crc = struct.unpack("<qI", f.read(12))
            entries.append((name, size))
        offset = f.tell()
    index = {}
    for name, size in entries:
        index[name] = (offset, size)
        offset += size
    return index


_BASETEXTURE = re.compile(r'"\$basetexture"\s+"([^"]+)"', re.IGNORECASE)
_VMT_INDEX = re.compile(r"_(\d+)\.vmt$")


def load_asset(game_root: Path, pmx_path: Path, asset_id: str | None = None) -> HotloaderAsset:
    asset_id = asset_id or find_asset_id(game_root, pmx_path)
    folder = game_root / "garrysmod" / "data" / "mmd_hotloader" / "assets" / asset_id
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8-sig"))
    gma_files = sorted(folder.glob("materials-v*.gma"))
    if not gma_files:
        raise FileNotFoundError(f"no materials GMA in {folder}")
    gma = gma_files[-1]
    index = _read_gma(gma)

    vmts: dict[int, str] = {}
    bases: dict[int, str] = {}
    with gma.open("rb") as f:
        for name, (offset, size) in index.items():
            if not name.endswith(".vmt"):
                continue
            m = _VMT_INDEX.search(name)
            if not m:
                continue
            material_index = int(m.group(1)) - 1
            f.seek(offset)
            text = f.read(size).decode("utf-8", errors="replace")
            base = _BASETEXTURE.search(text)
            vmts[material_index] = name[len("materials/") : -len(".vmt")]
            bases[material_index] = base.group(1) if base else ""

    textures: dict[str, HotloaderTexture] = {}
    pmx_dir = pmx_path.parent
    vtf_sizes = {}
    with gma.open("rb") as f:
        for name, (offset, size) in index.items():
            if name.startswith("materials/mmd/t/") and name.endswith(".vtf"):
                f.seek(offset)
                header = f.read(20)
                width, height = struct.unpack_from("<HH", header, 16)
                vtf_sizes[name[len("materials/") : -len(".vtf")]] = (width, height)

    for material_index, base in bases.items():
        if not base.startswith("mmd/t/"):
            continue  # untextured slots use a shared engine texture; never replace it
        key = base.rsplit("/", 1)[-1]
        texture = textures.get(key)
        if texture is None:
            authored = manifest["materials"][material_index].get("base") or ""
            source = (pmx_dir / authored.replace("\\", "/")).resolve() if authored else None
            width, height = vtf_sizes.get(base, (0, 0))
            texture = HotloaderTexture(key=key, vtf=base, source=source, width=width, height=height)
            textures[key] = texture
        texture.materials.append(material_index)

    return HotloaderAsset(
        asset_id=asset_id, folder=folder, manifest=manifest, vmts=vmts, base_textures=bases, textures=textures
    )
