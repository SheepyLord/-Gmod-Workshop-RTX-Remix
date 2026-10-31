"""Build a Model Hotloader Workshop package as an add-on folder, offline, from a Model Hotloader cache.

The folder holds what Model Hotloader's own exporter puts in its .gma (native/packages.cpp
exportPackage, native/sharing.cpp packSharedBytes), plus an addon.json:

    addon.json
    data_static/mmdhl/packages/<32 hex>.json    the package manifest
    data_static/mmdhl/files/<sha256>.dat         one MMDPACK2 packet per distinct cache file

package_content.py (tools/ in the native loader repository) takes the folder as --addon. Every
packet is unpacked again with Windows' own Decompress and checked against its SHA-256 before the
folder is moved into place.

FALLBACK route. When the game is running with the model in Model Hotloader's library, prefer
hotloader_export.py from the mmd-remix-pbr skill: it runs Model Hotloader's own exporter.

Usage (Windows only: the codec is cabinet.dll's XPRESS Huffman, as in Model Hotloader):

    python -I mmdhl_pack.py <cache> <asset> <out folder> <title> <item name> <author> <description file>
        [<release json>] [--item ASSET=NAME]... [--tag TAG]... [--default-preset-name NAME]
        [--replace] [--allow-game-install]

  <cache>           <game root>\\garrysmod\\data\\mmd_hotloader of the install holding the import (read only)
  <asset>           the model's asset id: 64 hex digits, or a unique prefix of 8 or more
  <out folder>      the add-on folder to write, named mmdhl_<name>; must not exist (see --replace)
  <title>           the package title Model Hotloader shows, at most 128 bytes
  <item name>       the model's display name in Model Hotloader's library, at most 100 bytes; use
                    plain ASCII ("Robin"), see references/model-hotloader-package.md
  <author>          at most 128 bytes
  <description file> UTF-8 text, at most 8000 bytes
  <release json>    a JSON file with "release" and "build" for the package's generator field
                    (default: <game root>\\garrysmod\\lua\\bin\\mmdhl-native-release.json beside the cache)

  --item ASSET=NAME          another character in the same package (repeatable)
  --tag TAG                  a Workshop tag for addon.json, at most two (default: cartoon)
  --default-preset-name NAME rename the default bodygroup preset (Robin: "1" became "Default");
                             the environment variable MMDHL_DEFAULT_PRESET_NAME does the same
  --replace                  replace an earlier package folder at <out folder> (only such a folder)
  --allow-game-install       allow <out folder> inside a game install (only when the user asked)

Prints one line per packed file and a JSON summary last. Exit codes: 0 done, 1 refused or failed
(reason on stderr), 2 bad command line.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import re
import secrets
import shutil
import struct
import sys
import time

MAGIC = b"MMDPACK2"
HEADER_BYTES = 80            # magic (8), raw size (u64), the SHA-256 as 64 hex digits
BLOCK = 1 << 20              # SharedBlockSize, native/sharing.hpp
RAW_FLAG = 0x80000000        # block stored uncompressed
EXPANSION_LIMIT = 256        # PackageExpansionLimit: installers refuse a file that inflates more than
EXPANSION_FLOOR = 1 << 20    # 256 times its packet once it is over 1 MiB (PackageExpansionFloor)
MANIFEST_LIMIT = 4 << 20     # PackageManifestLimit, workshop.lua MaxPackageBytes
TOTAL_LIMIT = 16 << 30       # PackageTotalLimit
TAGS = ("fun", "roleplay", "scenic", "movie", "realism", "cartoon", "water", "comic", "build")
TERMS_KEYS = ("name", "nameEnglish", "comment", "commentEnglish", "copyright")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class PackError(Exception):
    """A refusal or failure: printed as "error: ...", exit code 1."""


# ---- the MMDPACK2 codec ------------------------------------------------------------------------

class Codec:
    """Windows' Compression API with XPRESS Huffman (COMPRESS_ALGORITHM_XPRESS_HUFF), buffer mode."""

    XPRESS_HUFF = 4

    def __init__(self):
        if os.name != "nt":
            raise PackError("this packer needs Windows: it uses cabinet.dll's XPRESS Huffman codec, as Model Hotloader does")
        dll = ctypes.WinDLL("cabinet.dll", use_last_error=True)
        handle = ctypes.c_void_p
        for name in ("CreateCompressor", "CreateDecompressor"):
            fn = getattr(dll, name)
            fn.argtypes = [ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(handle)]
            fn.restype = ctypes.c_int
        for name in ("Compress", "Decompress"):
            fn = getattr(dll, name)
            fn.argtypes = [handle, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
                           ctypes.POINTER(ctypes.c_size_t)]
            fn.restype = ctypes.c_int
        self.dll = dll
        self.compressor, self.decompressor = handle(), handle()
        if not dll.CreateCompressor(self.XPRESS_HUFF, None, ctypes.byref(self.compressor)):
            raise PackError("CreateCompressor failed (Windows error %d)" % ctypes.get_last_error())
        if not dll.CreateDecompressor(self.XPRESS_HUFF, None, ctypes.byref(self.decompressor)):
            raise PackError("CreateDecompressor failed (Windows error %d)" % ctypes.get_last_error())
        self.encoded = ctypes.create_string_buffer(BLOCK + 65536)
        self.decoded = ctypes.create_string_buffer(BLOCK)

    def compress(self, chunk: bytes):
        """The encoding of one block, or None when it does not shrink (the block is then stored raw)."""
        written = ctypes.c_size_t(0)
        ok = self.dll.Compress(self.compressor, chunk, len(chunk), self.encoded, len(self.encoded), ctypes.byref(written))
        if ok and written.value < len(chunk):
            return ctypes.string_at(self.encoded, written.value)
        return None

    def decompress(self, data: bytes, size: int) -> bytes:
        written = ctypes.c_size_t(0)
        if not self.dll.Decompress(self.decompressor, data, len(data), self.decoded, size, ctypes.byref(written)) \
                or written.value != size:
            raise PackError("a packed block does not decompress")
        return ctypes.string_at(self.decoded, size)


def pack(codec: Codec, raw: bytes, digest: str, compress: bool = True) -> bytes:
    """One MMDPACK2 packet (packSharedBytes): the 80-byte header, then per 1 MiB block its raw size
    (u32), its stored size (u32, high bit set when stored raw) and its bytes."""
    out = bytearray(MAGIC + struct.pack("<Q", len(raw)) + digest.encode("ascii"))
    view = memoryview(raw)
    for at in range(0, len(raw), BLOCK):
        chunk = bytes(view[at:at + BLOCK])
        encoded = codec.compress(chunk) if compress else None
        if encoded is not None:
            out += struct.pack("<II", len(chunk), len(encoded)) + encoded
        else:
            out += struct.pack("<II", len(chunk), len(chunk) | RAW_FLAG) + chunk
    return bytes(out)


def unpack(codec: Codec, packet: bytes, size: int, digest: str) -> bytes:
    """The raw bytes of a packet, with the checks of unpackSharedFile; raises PackError otherwise."""
    if len(packet) < HEADER_BYTES or packet[:8] != MAGIC or struct.unpack_from("<Q", packet, 8)[0] != size \
            or packet[16:80] != digest.encode("ascii"):
        raise PackError("packet header does not match the file")
    raw, at = bytearray(), HEADER_BYTES
    while len(raw) < size:
        if at + 8 > len(packet):
            raise PackError("truncated packet")
        count, stored = struct.unpack_from("<II", packet, at)
        at += 8
        flagged = bool(stored & RAW_FLAG)
        stored &= ~RAW_FLAG & 0xFFFFFFFF
        if not count or count > BLOCK or count > size - len(raw) or not stored or stored > count \
                or stored > len(packet) - at or (flagged and stored != count):
            raise PackError("invalid packet block")
        data = packet[at:at + stored]
        at += stored
        raw += data if flagged else codec.decompress(data, count)
    if at != len(packet) or hashlib.sha256(raw).hexdigest() != digest:
        raise PackError("packet does not unpack to its SHA-256")
    return bytes(raw)


# ---- inputs ------------------------------------------------------------------------------------

def clip(text: str, limit: int) -> str:
    """At most `limit` bytes of UTF-8, never cutting a character (terms.lua clip)."""
    data = text.encode("utf-8")
    if len(data) <= limit:
        return text
    return data[:limit].decode("utf-8", "ignore")


def clean_text(label: str, value: str, limit: int, multiline: bool = False, required: bool = False) -> str:
    """As packages.cpp text(): trimmed, at most `limit` bytes, no control characters (tab, CR and LF
    allowed in multi-line text)."""
    value = (value or "").strip(" \t\r\n")
    if required and not value:
        raise PackError("%s is required" % label)
    if len(value.encode("utf-8")) > limit:
        raise PackError("%s is longer than %d bytes" % (label, limit))
    for ch in value:
        code = ord(ch)
        if code == 0x7F or (code < 0x20 and not (multiline and ch in "\n\r\t")):
            raise PackError("%s contains a control character" % label)
    return value


def load_json(path: str):
    try:
        with open(path, encoding="utf-8-sig") as fh:
            return json.load(fh)
    except (OSError, ValueError) as error:
        raise PackError("%s cannot be read: %s" % (path, error))


def hash_file(path: str):
    digest, size = hashlib.sha256(), 0
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            digest.update(chunk)
            size += len(chunk)
    return size, digest.hexdigest()


def inside(path: str, folder: str) -> bool:
    path, folder = os.path.normcase(os.path.abspath(path)), os.path.normcase(os.path.abspath(folder))
    try:
        return os.path.commonpath([path, folder]) == folder
    except ValueError:
        return False


def game_root_of(path: str):
    """The game install `path` lies in (a folder with garrysmod\\ and gmod.exe), or None."""
    here = os.path.abspath(path)
    while True:
        if os.path.isdir(os.path.join(here, "garrysmod")) and any(
                os.path.isfile(os.path.join(here, *exe)) for exe in (("bin", "win64", "gmod.exe"), ("gmod.exe",), ("hl2.exe",))):
            return here
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def resolve_asset(cache: str, given: str) -> str:
    given = given.strip().lower()
    folder = os.path.join(cache, "assets")
    if HEX64.match(given):
        if not os.path.isdir(os.path.join(folder, given)):
            raise PackError("asset %s is not in %s" % (given, folder))
        return given
    if not re.fullmatch(r"[0-9a-f]{8,63}", given):
        raise PackError("asset %r: give its id, 64 hex digits, or a unique prefix of 8 or more" % given)
    hits = [n for n in os.listdir(folder) if n.startswith(given) and HEX64.match(n)]
    if len(hits) != 1:
        raise PackError("asset prefix %s matches %d assets in %s" % (given, len(hits), folder))
    return hits[0]


def bodygroups(library: dict, rename, notes: list):
    """The library's bodygroup presets with string names. util.TableToJSON writes presets named
    "1", "2", ... as a JSON array; Model Hotloader reads them back by name (W.ItemSettings)."""
    b = library.get("bodygroups")
    if not isinstance(b, dict) or not b.get("presets"):
        notes.append("no bodygroup presets: the model spawns with its authored look")
        return None
    presets = b["presets"]
    if isinstance(presets, list):
        presets = {str(i + 1): p for i, p in enumerate(presets)}
    elif isinstance(presets, dict):
        presets = {str(k): v for k, v in presets.items()}
    else:
        notes.append("bodygroup presets are neither a list nor an object; left out")
        return None
    default = b.get("default")
    if isinstance(default, float) and default.is_integer():
        default = int(default)
    default = None if default is None else str(default)
    if rename and default in presets:
        presets = {(rename if k == default else k): v for k, v in presets.items()}
        default = rename
    if default is not None and default not in presets:
        notes.append("default preset %r names no preset; Model Hotloader will ignore it" % default)
    if default is None:
        notes.append("no default bodygroup preset: the model spawns with its authored look")
    print("  bodygroups: presets %s, default %r" % (sorted(presets), default))
    return {"presets": presets, "default": default}


def terms_record(cache: str, asset: str, notes: list):
    """The model's terms-of-use record, reduced as terms.lua T.Clean and T.ForPackage reduce it."""
    path = os.path.join(cache, "terms", asset + ".json")
    if not os.path.isfile(path):
        return None
    record = load_json(path)
    embedded = record.get("embedded") if isinstance(record.get("embedded"), dict) else {}
    out = {"file": clip(str(record.get("file") or ""), 200),
           "embedded": {k: clip(embedded[k], 48 << 10) for k in TERMS_KEYS if isinstance(embedded.get(k), str) and embedded[k]},
           "readmes": []}
    for readme in record.get("readmes") or []:
        if len(out["readmes"]) >= 8:
            break
        if isinstance(readme, dict) and readme.get("matched") is True and isinstance(readme.get("text"), str) and readme["text"]:
            readme = dict(readme)
            if len(readme["text"].encode("utf-8")) > 32 << 10:
                readme["text"], readme["truncated"] = clip(readme["text"], 32 << 10), True
            out["readmes"].append(readme)
    while len(json.dumps(out, ensure_ascii=False).encode("utf-8")) > 240 << 10 and out["readmes"]:
        out["readmes"].pop()
    if len(json.dumps(out, ensure_ascii=False).encode("utf-8")) > 240 << 10:
        out["embedded"] = {k: clip(v, 16 << 10) for k, v in out["embedded"].items()}
    if "vrm" in record:
        notes.append("the terms record holds a VRM licence, which this packer does not carry; use hotloader_export.py")
    return out


def arms_parts(cache: str, asset: str):
    """First-person arm parts (arms/<asset>.json), cleaned as materials.lua CleanArmsParts does."""
    path = os.path.join(cache, "arms", asset + ".json")
    if not os.path.isfile(path):
        return None
    value = load_json(path)
    pairs = enumerate(value, start=1) if isinstance(value, list) else value.items() if isinstance(value, dict) else ()
    out = {}
    for key, mode in pairs:
        try:
            slot = int(str(key))
        except ValueError:
            continue
        if 0 <= slot < 4096 and mode in (-1, 0, 1) and not isinstance(mode, bool) and len(out) < 1024:
            out[str(slot)] = mode
    return out or None


def collect(cache: str, asset: str, name: str, rename, notes: list):
    """The package item of one character and its files {package path: (size, sha256, source)}."""
    folder = os.path.join(cache, "assets", asset)
    manifest = load_json(os.path.join(folder, "manifest.json"))
    paths = {"assets/%s/manifest.json" % asset: os.path.join(folder, "manifest.json"),
             "assets/%s/model.bin" % asset: os.path.join(folder, "model.bin")}
    # The raw import only, as sharedManifest(..., sourceOnly=true): generated archives are rebuilt locally.
    for material in manifest.get("textures") or []:
        for key in ("base", "sphere", "toon"):
            texture = material.get(key) if isinstance(material, dict) else None
            if texture:
                if not HEX64.match(texture):
                    raise PackError("asset %s lists an invalid texture id %r" % (asset[:12], texture))
                paths["textures/%s.png" % texture] = os.path.join(cache, "textures", texture + ".png")
    files = {}
    for rel in sorted(paths):
        source = paths[rel]
        if not os.path.isfile(source):
            raise PackError("%s is missing from the cache (%s)" % (rel, source))
        size, sha = hash_file(source)
        if rel.startswith("textures/") and rel != "textures/%s.png" % sha:
            raise PackError("%s does not match its SHA-256 (%s)" % (rel, sha))
        files[rel] = (size, sha, source)
    library_path = os.path.join(cache, "library", asset + ".json")
    if not os.path.isfile(library_path):
        raise PackError("asset %s has no library entry (%s): is the model in Model Hotloader's library?" % (asset[:12], library_path))
    library = load_json(library_path)
    settings = {"spawn": library["spawn"] if isinstance(library.get("spawn"), dict) else {"scaleMultiplier": 1}}
    groups = bodygroups(library, rename, notes)
    if groups:
        settings["bodygroups"] = groups
    item = {"kind": "character", "asset": asset, "name": name, "files": sorted(paths), "settings": settings}
    terms = terms_record(cache, asset, notes)
    if terms:
        item["terms"] = terms
    fit_path = os.path.join(cache, "fit_overrides", asset + ".json")
    if os.path.isfile(fit_path):
        fit = load_json(fit_path)
        if isinstance(fit, dict):
            # Who saved a physics default stays on this computer (workshop_export.lua).
            if isinstance(fit.get("editor"), dict):
                fit["editor"].pop("savedBy", None)
                fit["editor"].pop("savedByName", None)
            item["fit"] = fit
    arms = arms_parts(cache, asset)
    if arms:
        item["arms"] = arms
    return item, files


def file_limit(path: str) -> int:
    """The largest file an installer accepts for a path (workshop.lua fileLimit, Model Hotloader 2.3.1)."""
    if re.fullmatch(r"assets/[0-9a-f]{64}/manifest\.json", path):
        return 64 << 20
    if re.fullmatch(r"assets/[0-9a-f]{64}/model\.bin", path) or re.fullmatch(r"textures/[0-9a-f]{64}\.png", path):
        return 1 << 30
    return 0


def read_release(given, cache: str):
    candidates = [given] if given else [os.path.join(os.path.dirname(os.path.dirname(cache)), "lua", "bin", "mmdhl-native-release.json")]
    for path in candidates:
        if path and os.path.isfile(path):
            data = load_json(path)
            return {"release": str(data.get("release", "")), "build": str(data.get("build", ""))}, path
        if given:
            raise PackError("release file %s not found" % given)
    return {"release": "", "build": ""}, None


def looks_like_package_folder(folder: str) -> bool:
    """Only an earlier output of this packer (or of hotloader_export.py) may be replaced."""
    if not os.path.isdir(folder):
        return False
    top = {n.lower() for n in os.listdir(folder)}
    if not top <= {"addon.json", "data_static"} or "data_static" not in top:
        return False
    inner = os.path.join(folder, "data_static")
    return {n.lower() for n in os.listdir(inner)} <= {"mmdhl"}


# ---- build -------------------------------------------------------------------------------------

def build(args) -> dict:
    cache = os.path.abspath(args.cache)
    if not os.path.isdir(os.path.join(cache, "assets")):
        raise PackError("%s has no assets folder: give <game root>\\garrysmod\\data\\mmd_hotloader" % cache)
    out = os.path.abspath(args.out)
    if inside(out, cache) or inside(cache, out):
        raise PackError("the output %s must be outside the cache %s" % (out, cache))
    root = game_root_of(out)
    if root and not args.allow_game_install:
        raise PackError("%s is inside the game install %s; pass --allow-game-install only when the user asked for it" % (out, root))
    if os.path.lexists(out):
        if not args.replace:
            raise PackError("%s exists (--replace rebuilds an earlier package folder)" % out)
        if not looks_like_package_folder(out):
            raise PackError("%s is not a Model Hotloader package folder; not replacing it" % out)
    title = clean_text("title", args.title, 128, required=True)
    author = clean_text("author", args.author, 128)
    try:
        with open(args.description_file, encoding="utf-8-sig") as fh:
            description = clean_text("description", fh.read(), 8000, multiline=True)
    except OSError as error:
        raise PackError("description file: %s" % error)
    tags = []
    for tag in args.tag or ["cartoon"]:
        if tag not in tags:
            tags.append(tag)
    if len(tags) > 2:
        raise PackError("at most two --tag")
    rename = args.default_preset_name if args.default_preset_name is not None else os.environ.get("MMDHL_DEFAULT_PRESET_NAME")
    if rename is not None:
        rename = clean_text("--default-preset-name", rename, 64, required=True)

    requests = [(args.asset, args.name)]
    for spec in args.item:
        asset, sep, name = spec.partition("=")
        if not sep or not asset or not name:
            raise PackError("--item %s: expected ASSET=NAME" % spec)
        requests.append((asset, name))
    items, files, notes, seen = [], {}, [], set()
    for given, name in requests:
        asset = resolve_asset(cache, given)
        if asset in seen:
            raise PackError("asset %s is given twice" % asset[:12])
        seen.add(asset)
        name = clean_text("item name", name, 100) or asset[:12]
        print("%s %s" % (asset[:12], name))
        item, item_files = collect(cache, asset, name, rename, notes)
        items.append(item)
        files.update(item_files)
    for path, (size, _, _) in files.items():
        limit = file_limit(path)
        if not limit:
            raise PackError("%s: a path no package may list" % path)
        if size > limit:
            raise PackError("%s is %d MB, more than the %d MB players can install" % (path, size >> 20, limit >> 20))
    if sum(size for size, _, _ in files.values()) > TOTAL_LIMIT:
        raise PackError("the models hold more than the 16 GB players can install from one package")
    generator, release_path = read_release(args.release_json, cache)
    if not release_path:
        notes.append("no mmdhl-native-release.json found; the generator field is empty")
    sources = {}
    for size, sha, source in files.values():
        sources.setdefault(sha, (size, source))

    codec = Codec()
    pid = secrets.token_hex(16)
    partial = out + ".partial-%d" % os.getpid()
    if os.path.lexists(partial):
        raise PackError("%s is in the way; delete it" % partial)
    file_dir = os.path.join(partial, "data_static", "mmdhl", "files")
    package_dir = os.path.join(partial, "data_static", "mmdhl", "packages")
    os.makedirs(file_dir)
    os.makedirs(package_dir)
    try:
        packed = {}
        for sha in sorted(sources):
            size, source = sources[sha]
            with open(source, "rb") as fh:
                raw = fh.read()
            if len(raw) != size or hashlib.sha256(raw).hexdigest() != sha:
                raise PackError("%s changed while packing; run again" % source)
            packet = pack(codec, raw, sha)
            # Installers refuse a file that inflates more than 256 times its packet: store it raw.
            if len(raw) > max(EXPANSION_FLOOR, len(packet) * EXPANSION_LIMIT):
                packet = pack(codec, raw, sha, compress=False)
            if len(packet) > len(raw) + HEADER_BYTES + 8 * -(-len(raw) // BLOCK):
                raise PackError("%s: packet over the transfer bound" % sha[:12])
            if unpack(codec, packet, len(raw), sha) != raw:
                raise PackError("%s: packet does not round-trip" % sha[:12])
            with open(os.path.join(file_dir, sha + ".dat"), "xb") as fh:
                fh.write(packet)
            packed[sha] = len(packet)
            print("  %s %10d -> %10d" % (sha[:12], len(raw), len(packet)))
        package = {"format": "mmdhl-package", "version": 1, "id": pid, "title": title, "author": author,
                   "description": description, "created": int(time.time()), "install": "workshop",
                   "generator": generator, "items": items,
                   "files": {p: {"size": files[p][0], "sha256": files[p][1], "packed": packed[files[p][1]]} for p in sorted(files)}}
        text = json.dumps(package, ensure_ascii=False, separators=(",", ":"))
        if len(text.encode("utf-8")) > MANIFEST_LIMIT:
            raise PackError("the package manifest is over the 4 MB players can install; pack fewer models")
        with open(os.path.join(package_dir, pid + ".json"), "x", encoding="utf-8", newline="") as fh:
            fh.write(text)
        with open(os.path.join(partial, "addon.json"), "x", encoding="utf-8", newline="\n") as fh:
            json.dump({"title": title, "type": "model", "tags": tags, "ignore": []}, fh, indent=1)
        if os.path.lexists(out):
            shutil.rmtree(out)
        os.replace(partial, out)
        partial = None
    finally:
        if partial and os.path.isdir(partial):
            shutil.rmtree(partial)
    for note in notes:
        print("  note: " + note)
    return {"package": pid, "files": len(files), "blobs": len(packed), "raw": sum(s for s, _ in sources.values()),
            "packed": sum(packed.values()), "folder": out, "generator": generator, "release_from": release_path,
            "items": [{"asset": i["asset"], "name": i["name"],
                       "default_preset": (i["settings"].get("bodygroups") or {}).get("default")} for i in items]}


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Build a Model Hotloader Workshop package add-on folder offline.",
                                 epilog="See mmdhl_pack.py.md beside this script.")
    ap.add_argument("cache", help="<game root>\\garrysmod\\data\\mmd_hotloader (read only)")
    ap.add_argument("asset", help="asset id or a unique prefix of 8+ hex digits")
    ap.add_argument("out", help="the add-on folder to write (mmdhl_<name>)")
    ap.add_argument("title", help="package title, at most 128 bytes")
    ap.add_argument("name", help="the model's display name, at most 100 bytes (plain ASCII recommended)")
    ap.add_argument("author", help="package author, at most 128 bytes")
    ap.add_argument("description_file", help="UTF-8 text file, at most 8000 bytes")
    ap.add_argument("release_json", nargs="?", help="JSON with release and build (default: the install's mmdhl-native-release.json)")
    ap.add_argument("--item", action="append", default=[], metavar="ASSET=NAME", help="another character (repeatable)")
    ap.add_argument("--tag", action="append", choices=TAGS, help="addon.json tag, at most two (default cartoon)")
    ap.add_argument("--default-preset-name", metavar="NAME", help="rename the default bodygroup preset")
    ap.add_argument("--replace", action="store_true", help="replace an earlier package folder at the output")
    ap.add_argument("--allow-game-install", action="store_true", help="allow an output inside a game install")
    args = ap.parse_args(argv)
    try:
        summary = build(args)
    except (PackError, OSError) as error:
        print("error: %s" % error, file=sys.stderr)
        return 1
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
