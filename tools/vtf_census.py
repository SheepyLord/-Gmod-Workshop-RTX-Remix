"""Read only hotloader GMA indexes/VTF headers, not image payloads; see vtf_census.py.md."""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import struct
import tempfile

try:
    from gmapack import gmapack
except ImportError:
    # The repository's other tools may already have imported the vendored single-file module.
    import gmapack


def rgba_header(header, file_bytes):
    if len(header) < 80 or header[:4] != b"VTF\0":
        return None
    major, minor, size = struct.unpack_from("<III", header, 4)
    width, height, flags, frames = struct.unpack_from("<HHIH", header, 16)
    image_format = struct.unpack_from("<I", header, 52)[0]
    depth = struct.unpack_from("<H", header, 63)[0]
    mips = header[56]
    if (major, minor, size, image_format, frames, depth) != (7, 2, 80, 0, 1, 1):
        return None
    if not 0 < width <= 16384 or not 0 < height <= 16384 or not 0 < mips <= 15 or flags & 0x4000:
        return None
    w, h, logical = width, height, 0
    for _ in range(mips):
        logical += w * h * 4
        w, h = max(1, w // 2), max(1, h // 2)
    if file_bytes != 80 + logical:
        return None
    return dict(width=width, height=height, mips=mips, format="RGBA8888", logical_bytes=logical)


def scan(folder, all_versions=False):
    scratch = Path(__file__).resolve().parents[1] / "out/tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vtf-census-", dir=scratch) as directory:
        previous = tempfile.tempdir
        tempfile.tempdir = directory
        try:
            return scan_archives(folder, all_versions)
        finally:
            tempfile.tempdir = previous


def scan_archives(folder, all_versions=False):
    paths = sorted(folder.glob("*/materials-v*.gma"))
    if not all_versions:
        latest = {}
        for path in paths:
            try:
                version = int(path.stem.split("-v")[1])
            except ValueError:
                continue
            if path.parent not in latest or version > latest[path.parent][0]:
                latest[path.parent] = (version, path)
        paths = [value[1] for value in latest.values()]
    textures, assets, unsupported = {}, [], []
    for path in paths:
        names = []
        with gmapack.read_gma(str(path)) as archive:
            for entry in archive.files:
                name = entry["name"].lower().replace("\\", "/")
                if not name.startswith("materials/mmd/t/") or not name.endswith(".vtf"):
                    continue
                archive.fh.seek(entry["offset"])
                header = archive.fh.read(min(80, entry["size"]))
                row = rgba_header(header, entry["size"])
                if row is None:
                    unsupported.append(dict(archive=str(path), name=name, bytes=entry["size"]))
                    continue
                key = (name, entry["size"], entry["crc"])
                if key not in textures:
                    textures[key] = dict(name=name, file_bytes=entry["size"], crc32=entry["crc"],
                                         **row, archives=[])
                textures[key]["archives"].append(str(path))
                names.append(key)
        assets.append(dict(archive=str(path), archive_bytes=path.stat().st_size,
                           texture_records=len(names), logical_bytes=sum(textures[key]["logical_bytes"] for key in set(names))))
    formats = defaultdict(lambda: dict(count=0, logical_bytes=0))
    for row in textures.values():
        key = f"{row['width']}x{row['height']} {row['mips']}m RGBA8888"
        formats[key]["count"] += 1
        formats[key]["logical_bytes"] += row["logical_bytes"]
    by_name = defaultdict(int)
    for key in textures:
        by_name[key[0]] += 1
    return dict(archives=len(paths), archive_bytes=sum(row["archive_bytes"] for row in assets),
                texture_variants=len(textures), logical_bytes=sum(row["logical_bytes"] for row in textures.values()),
                conflicting_names=[name for name, count in by_name.items() if count > 1],
                formats=dict(formats), assets=assets, textures=list(textures.values()), unsupported=unsupported)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("--all-versions", action="store_true")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    result = scan(args.assets, args.all_versions)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key not in ("textures", "assets")}, indent=2))


if __name__ == "__main__":
    main()
