"""Compiled Source models (.mdl) as input, beside Model Hotloader imports.

Some characters reach the game as a compiled addon (a QC compile of the PMX:
``models/<path>.mdl`` with VMT/VTF materials, e.g. sheepylord's ports) rather
than through Model Hotloader. The PMX still holds the UVs, material names and
original images, so only the link from a PMX material to the game's texture
changes: the MDL lists its materials and their folders ($cdmaterials), each
VMT names its $basetexture, and that VTF is what Remix hashes. The compile
names its materials after the PMX ones, so they are matched by name (Robin,
robin_zzz.mdl, 2026-10-25: 11 of 11).

Garry's Mod mounts legacy folder addons over ``garrysmod/``, so files are
looked up in the MDL's own addon first, then in every other folder addon,
then in ``garrysmod/`` itself.
"""

from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path

from . import config
from .hotloader import HotloaderAsset, HotloaderTexture
from .pmx import PmxModel
from .remixhash import read_vtf_header

_BASETEXTURE = re.compile(r'"?\$basetexture"?\s+"?([^"\s}]+)"?', re.IGNORECASE)
_REGISTRY = config.HOME / "compiled_models.json"  # PMX path -> MDL, so later commands need no --mdl


def _norm_mdl(mdl: str) -> str:
    mdl = mdl.replace("\\", "/").strip().lower()
    return mdl if mdl.startswith("models/") else f"models/{mdl}"


def _roots(game_root: Path, first: Path | None = None) -> list[Path]:
    garrysmod = game_root / "garrysmod"
    addons = sorted(p for p in (garrysmod / "addons").glob("*") if p.is_dir())
    roots = [first] if first else []
    return roots + [p for p in addons if p != first] + [garrysmod]


def _find(roots: list[Path], relative: str) -> Path | None:
    for root in roots:
        path = root / relative
        if path.is_file():
            return path
    return None


def read_mdl_materials(path: Path) -> tuple[list[str], list[str]]:
    """(material names, material folders) from a studio model header (MDL v44-49)."""
    blob = path.read_bytes()
    if blob[:4] != b"IDST":
        raise ValueError(f"{path} is not a Source model")

    def cstr(offset: int) -> str:
        return blob[offset:blob.index(b"\0", offset)].decode("latin-1")

    count, index, cd_count, cd_index = struct.unpack_from("<4i", blob, 204)
    names = [cstr(index + 64 * i + struct.unpack_from("<i", blob, index + 64 * i)[0]) for i in range(count)]
    folders = [cstr(struct.unpack_from("<i", blob, cd_index + 4 * i)[0]) for i in range(cd_count)]
    return names, [f.replace("\\", "/").strip("/") for f in folders]


def remember(pmx_path: Path, mdl: str) -> None:
    saved = json.loads(_REGISTRY.read_text(encoding="utf-8")) if _REGISTRY.exists() else {}
    saved[str(pmx_path.resolve())] = _norm_mdl(mdl)
    _REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    _REGISTRY.write_text(json.dumps(saved, ensure_ascii=False, indent=1), encoding="utf-8")


def remembered(pmx_path: Path) -> str | None:
    if not _REGISTRY.exists():
        return None
    return json.loads(_REGISTRY.read_text(encoding="utf-8")).get(str(pmx_path.resolve()))


def load_compiled(game_root: Path, pmx_path: Path, model: PmxModel, mdl: str, log=print) -> HotloaderAsset:
    mdl = _norm_mdl(mdl)
    mdl_file = _find(_roots(game_root), mdl)
    if mdl_file is None:
        raise FileNotFoundError(f"{mdl} is in no folder addon under {game_root / 'garrysmod' / 'addons'}")
    addon = mdl_file.parents[len(Path(mdl).parts) - 1]
    roots = _roots(game_root, addon)
    names, folders = read_mdl_materials(mdl_file)

    by_name: dict[str, list[int]] = {}
    for material in model.materials:
        for text in {material.name, material.name_en}:
            if text:
                by_name.setdefault(text.casefold(), []).append(material.index)

    textures: dict[str, HotloaderTexture] = {}
    vmts: dict[int, str] = {}
    bases: dict[int, str] = {}
    vtf_files: dict[str, Path] = {}
    unmatched = []
    for name in names:
        indices = sorted(set(by_name.get(name.casefold(), []) or by_name.get(Path(name).name.casefold(), [])))
        vmt = next((f"{folder}/{name}".lstrip("/") for folder in folders
                    if _find(roots, f"materials/{folder}/{name}.vmt".replace("//", "/"))), None)
        if not indices or vmt is None:
            unmatched.append(name)
            continue
        found = _BASETEXTURE.search(_find(roots, f"materials/{vmt}.vmt").read_text(encoding="utf-8", errors="replace"))
        if not found:
            unmatched.append(name)
            continue
        base = found.group(1).replace("\\", "/").lower().removesuffix(".vtf")
        vtf = _find(roots, f"materials/{base}.vtf")
        if vtf is None:
            raise FileNotFoundError(f"{vmt}.vmt names $basetexture {base}, which no addon provides")
        blob = vtf.read_bytes()
        key = hashlib.sha256(blob).hexdigest()[:16]  # content-addressed, like Model Hotloader's VTF names
        for index in indices:
            material = model.materials[index]
            vmts[index], bases[index] = vmt.lower(), base
            texture = textures.get(key)
            if texture is None:
                header = read_vtf_header(blob)
                texture = HotloaderTexture(key=key, vtf=base, source=model.texture_path(material.texture),
                                           width=header.width, height=header.height)
                textures[key], vtf_files[key] = texture, vtf
            elif model.texture_path(material.texture) != texture.source:
                log(f"note: {base} serves PMX images {texture.source.name} and "
                    f"{model.texture_path(material.texture).name}; maps follow {texture.source.name}")
            texture.materials.append(index)
    if unmatched:
        log(f"note: MDL materials without a PMX material or VMT of the same name: {', '.join(unmatched)}")
    missing = [m.name for m in model.materials if m.index not in vmts]
    if missing:
        log(f"note: PMX materials not in {mdl}: {', '.join(missing)}")
    if not textures:
        raise ValueError(f"no PMX material of {pmx_path.name} matches a material of {mdl}")
    asset_id = hashlib.sha1(mdl.encode()).hexdigest()
    return HotloaderAsset(asset_id=asset_id, folder=addon, manifest={"mdl": mdl}, vmts=vmts, base_textures=bases,
                          textures=textures, vtf_files=vtf_files, mdl=mdl)
