"""Check a staged Workshop content pack before it is uploaded. Read only: it writes nothing.

It checks, for one build folder (or the parts given one by one):

  names        mmdhl_<n> and pbr_<n> with the same <n>, package id <n>-rtx, no r18 anywhere
  Hotloader    the Model Hotloader package as workshop.lua ValidatePackage checks it on install
               (format, ids, sizes, packet bounds, the .dat files), the display names English readers
               will see (names.lua), the default bodygroup preset, terms that mention restrictions;
               --deep also unpacks every packet and compares its SHA-256 (Windows)
  Remix mod    mod.usda and its layers, every referenced file present, only Remix data, ASCII
               paths, unreferenced files; --hashes-json checks the live texture hashes rpai
               recorded against the layers (a sheet with maps but no material for its hash fails)
  archive      the .gma header (type, tags, title), its native/manifest.json is content only
               (lua-addon and root-files under rtx-remix/mods and garrysmod/addons), and, when nlctl
               is found or given, nlctl manifest and nlctl verify
  icon         a 512x512 baseline JPEG (what worked for gmpublish)
  description  names the RTX package 3829070317 and the loader, no straight double quotes

Usage:

    python -I check_pack.py <build folder> [--nlctl <nlctl.exe>] [--deep] [--hashes-json FILE]...
    python -I check_pack.py --addon DIR --mod DIR [--gma FILE] [--icon FILE] [--description FILE] [...]

A build folder holds one mmdhl_<n> folder, one pbr_<n> folder (a folder with mod.usda), one .gma,
icon.jpg and description.txt, as out\\packages\\<n>\\ does. Each found part is checked; a part given
explicitly wins over the found one. Without --nlctl it looks for out\\build\\win64-release (or
win64-debug)\\loader\\cli\\nlctl.exe in the folders above the archive.

Prints "ok", "WARN" and "ERROR" lines and a total. Exit codes: 0 no errors (warnings allowed),
1 errors, 2 bad command line.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import math
import os
import re
import struct
import subprocess
import sys

RTX_PACKAGE_ITEM = "3829070317"
R18 = re.compile(r"(^|[^a-z0-9])r-?18([^a-z0-9]|$)", re.I)
HEX32, HEX64 = re.compile(r"^[0-9a-f]{32}$"), re.compile(r"^[0-9a-f]{64}$")
MATERIAL = re.compile(r'over "mat_([0-9A-Fa-f]{16})"')
REFERENCE = re.compile(r"@([^@]+)@")
REMIX_DATA = {".usd", ".usda", ".usdc", ".usdz", ".dds", ".png", ".jpg", ".jpeg", ".tga", ".bmp", ".exr", ".hdr",
              ".mdl", ".json", ".txt"}
ADDON_TYPES = ("gamemode", "map", "weapon", "vehicle", "npc", "entity", "tool", "effects", "model", "servercontent")
ADDON_TAGS = ("fun", "roleplay", "scenic", "movie", "realism", "cartoon", "water", "comic", "build")
PLACEHOLDER = re.compile(r"^(new\s+)?(mmd\s+)?model(\s*\d+)?$|^untitled|^unnamed|^character$", re.I)
CONTENT_KINDS = {"lua-addon", "root-files"}
NATIVE_KEYS = ("remix", "reshade", "patch_sets", "module_overrides", "session_cvars", "module_dependencies")
RESTRICTION = re.compile(r"禁止|禁転載|二次配布|再配布|prohibit|forbid|not allowed|do not (re)?distribut|no redistribut|"
                         r"redistribution is|unauthori[sz]ed|permission", re.I)
BLOCK = 1 << 20


class Report:
    def __init__(self):
        self.errors = self.warnings = 0

    def ok(self, text):
        print("ok    " + text)

    def info(self, text):
        print("      " + text)

    def warn(self, text):
        self.warnings += 1
        print("WARN  " + text)

    def error(self, text):
        self.errors += 1
        print("ERROR " + text)


def ascii_text(text: str) -> bool:
    return not re.search(r"[^\x00-\x7f]", text)


def load_json(path: str):
    with open(path, encoding="utf-8-sig") as fh:
        return json.load(fh)


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ---- names -------------------------------------------------------------------------------------

def check_names(r: Report, addon, mod, package_id, hotloader: bool):
    suffixes = {}
    for label, folder, prefix in (("add-on", addon, "mmdhl_"), ("mod", mod, "pbr_")):
        if not folder:
            continue
        name = os.path.basename(os.path.normpath(folder))
        if R18.search(name):
            r.error("%s folder %s carries r18: name it %s<name> (the user, Robin 2026-10-30)" % (label, name, prefix))
        if not hotloader:  # a map remaster keeps its own folder names (modern_house_rtx)
            continue
        if re.fullmatch(prefix + r"[a-z0-9_]+", name):
            suffixes[label] = name[len(prefix):]
        else:
            r.warn("%s folder %s: name it %s<name> in lowercase ASCII" % (label, name, prefix))
    if len(set(suffixes.values())) > 1:
        r.warn("the add-on and the mod have different names: %s" % ", ".join(sorted(suffixes.values())))
    elif suffixes:
        r.ok("folder names: %s" % ", ".join("%s%s" % ("mmdhl_" if k == "add-on" else "pbr_", v) for k, v in sorted(suffixes.items())))
    if package_id:
        if R18.search(package_id):
            r.error("package id %s carries r18" % package_id)
        if suffixes:
            expected = next(iter(suffixes.values())).replace("_", "-") + "-rtx"
            if package_id == expected:
                r.ok("package id %s" % package_id)
            else:
                r.warn("package id %s; the convention is %s" % (package_id, expected))


# ---- the Model Hotloader package ---------------------------------------------------------------

def file_limit(path: str) -> int:
    if re.fullmatch(r"assets/[0-9a-f]{64}/manifest\.json", path):
        return 64 << 20
    if re.fullmatch(r"assets/[0-9a-f]{64}/model\.bin", path) or re.fullmatch(r"textures/[0-9a-f]{64}\.png", path):
        return 1 << 30
    if re.fullmatch(r"static/assets/[0-9a-f]{64}\.gmdl", path):
        return 2 << 30
    return 0


class Decoder:
    """Windows' XPRESS Huffman decoder (cabinet.dll), for --deep."""

    def __init__(self):
        import ctypes
        self.ctypes = ctypes
        dll = ctypes.WinDLL("cabinet.dll", use_last_error=True)
        dll.CreateDecompressor.argtypes = [ctypes.c_uint32, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        dll.Decompress.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
                                   ctypes.POINTER(ctypes.c_size_t)]
        self.dll, self.handle = dll, ctypes.c_void_p()
        if not dll.CreateDecompressor(4, None, ctypes.byref(self.handle)):
            raise OSError("CreateDecompressor failed")
        self.buffer = ctypes.create_string_buffer(BLOCK)

    def unpack(self, packet: bytes, size: int) -> bytes:
        ct = self.ctypes
        if packet[:8] != b"MMDPACK2" or struct.unpack_from("<Q", packet, 8)[0] != size:
            raise ValueError("bad header")
        raw, at = bytearray(), 80
        while len(raw) < size:
            count, stored = struct.unpack_from("<II", packet, at)
            at += 8
            flagged, stored = bool(stored & 0x80000000), stored & 0x7FFFFFFF
            data = packet[at:at + stored]
            at += stored
            if flagged:
                raw += data
            else:
                written = ct.c_size_t(0)
                if not self.dll.Decompress(self.handle, data, len(data), self.buffer, count, ct.byref(written)) or written.value != count:
                    raise ValueError("a block does not decompress")
                raw += ct.string_at(self.buffer, count)
        if at != len(packet):
            raise ValueError("trailing bytes")
        return bytes(raw)


def check_hotloader(r: Report, addon: str, deep: bool):
    metadata = os.path.join(addon, "addon.json")
    if not os.path.isfile(metadata):
        r.warn("%s has no addon.json" % addon)
    else:
        try:
            load_json(metadata)
        except ValueError as error:
            r.error("addon.json is not valid JSON: %s" % error)
    packages = sorted(glob.glob(os.path.join(addon, "data_static", "mmdhl", "packages", "*.json")))
    if not packages:
        r.error("no data_static/mmdhl/packages/<id>.json in %s" % addon)
        return
    if len(packages) > 1:
        r.warn("%d package manifests (a stale one from an earlier build?): %s" % (len(packages), ", ".join(map(os.path.basename, packages))))
    file_dir = os.path.join(addon, "data_static", "mmdhl", "files")
    listed_dats = set()
    decoder = Decoder() if deep else None
    for path in packages:
        pid = os.path.splitext(os.path.basename(path))[0]
        if not HEX32.match(pid):
            r.error("package file %s: the name must be 32 hex digits" % os.path.basename(path))
            continue
        if os.path.getsize(path) > 4 << 20:
            r.error("package manifest over 4 MiB: installers refuse it")
        try:
            p = load_json(path)
        except ValueError as error:
            r.error("package manifest is not JSON: %s" % error)
            continue
        if p.get("format") != "mmdhl-package" or p.get("version") != 1 or p.get("id") != pid:
            r.error("package %s: format, version or id does not match (mmdhl-package, 1, the file name)" % pid)
        if p.get("install") not in ("workshop", "user"):
            r.error("package %s: install must be workshop or user" % pid)
        for key, limit in (("title", 128), ("author", 128), ("description", 8000)):
            value = p.get(key) or ""
            if len(str(value).encode("utf-8")) > limit:
                r.warn("package %s is over %d bytes; Model Hotloader clips it" % (key, limit))
        if not (p.get("title") or "").strip():
            r.warn("package title is empty; Model Hotloader shows the id instead")
        files, items = p.get("files"), p.get("items")
        if not isinstance(files, dict) or not isinstance(items, list) or not 1 <= len(items) <= 1000:
            r.error("package %s lists no models or no files" % pid)
            continue
        total, bad = 0, 0
        for rel, f in files.items():
            if not isinstance(f, dict):
                bad += 1
                continue
            size, sha, packed = f.get("size"), f.get("sha256"), f.get("packed")
            if not (isinstance(size, int) and 0 <= size <= 0xFFFFFFFF and isinstance(sha, str) and HEX64.match(sha)
                    and isinstance(packed, int) and 80 <= packed <= 0xFFFFFFFF
                    and packed <= size + 80 + 8 * math.ceil(size / BLOCK)):
                r.error("invalid file entry %s" % rel)
                bad += 1
                continue
            limit = file_limit(rel)
            if not limit:
                r.error("a path no package may list: %s" % rel)
                bad += 1
            elif size > limit:
                r.error("%s is larger than players can install (%d MB)" % (rel, limit >> 20))
                bad += 1
            if size > max(BLOCK, packed * 256):
                r.error("%s inflates more than 256 times its packet" % rel)
                bad += 1
            total += size
            dat = os.path.join(file_dir, sha + ".dat")
            listed_dats.add(sha + ".dat")
            if not os.path.isfile(dat):
                r.error("missing data_static/mmdhl/files/%s.dat (%s)" % (sha, rel))
                bad += 1
            elif os.path.getsize(dat) != packed:
                r.error("%s.dat is %d bytes, the manifest says %d" % (sha[:12], os.path.getsize(dat), packed))
                bad += 1
            elif decoder:
                with open(dat, "rb") as fh:
                    packet = fh.read()
                try:
                    if hashlib.sha256(decoder.unpack(packet, size)).hexdigest() != sha:
                        raise ValueError("SHA-256 differs")
                except (ValueError, struct.error) as error:
                    r.error("%s.dat does not unpack to its file: %s" % (sha[:12], error))
                    bad += 1
        if total > 16 << 30:
            r.error("the package holds more than 16 GB")
        if not bad:
            r.ok("package %s: %d files, %.1f MB raw, every entry within the installers' limits%s"
                 % (pid, len(files), total / 1e6, ", every packet unpacked to its SHA-256" if deep else ""))
        for item in items:
            check_item(r, item, files)
    extra = sorted(set(os.listdir(file_dir)) - listed_dats) if os.path.isdir(file_dir) else []
    if extra:
        r.warn("%d .dat files no manifest lists (left from an earlier build?)" % len(extra))


def check_item(r: Report, item: dict, files: dict):
    if not isinstance(item, dict) or item.get("kind") not in ("character", "static") or not HEX64.match(str(item.get("asset", ""))):
        r.error("invalid model entry")
        return
    asset, listed = item["asset"], item.get("files") or []
    if any(path not in files for path in listed):
        r.error("model %s lists a file the package does not have" % asset[:12])
    if item["kind"] == "character":
        need = {"assets/%s/manifest.json" % asset, "assets/%s/model.bin" % asset}
        if not need <= set(listed):
            r.error("model %s lacks its manifest.json or model.bin" % asset[:12])
        for path in listed:
            if path not in need and not re.fullmatch(r"textures/[0-9a-f]{64}\.png", path):
                r.error("model %s lists a forbidden file %s" % (asset[:12], path))
            if path.startswith("textures/") and path in files and files[path].get("sha256") + ".png" != path.split("/")[-1]:
                r.error("texture %s does not match its hash" % path)
    name = str(item.get("name") or "")
    terms = item.get("terms") if isinstance(item.get("terms"), dict) else {}
    embedded = terms.get("embedded") if isinstance(terms.get("embedded"), dict) else {}
    english = embedded.get("nameEnglish") if isinstance(embedded.get("nameEnglish"), str) else ""
    label = "model %s %r" % (asset[:8], name)
    if len(name.encode("utf-8")) > 100:
        r.warn("%s: the name is over 100 bytes; Model Hotloader clips it" % label)
    if R18.search(name):
        r.warn("%s: the display name carries R18" % label)
    # The pack's display name is the character's plain ASCII name (Robin), never the PMX's own:
    # the Evernight and March 7th pack shipped 長夜月 and 三月七 (the user, 2026-10-31).
    if ascii_text(name) and name.strip() and not PLACEHOLDER.match(name.strip()):
        r.ok("%s: plain ASCII display name, shown as written" % label)
    elif ascii_text(name):
        r.error("%s: a placeholder display name; give the character's plain name (Robin)" % label)
    elif english and ascii_text(english) and english != name and not (R18.search(english) or PLACEHOLDER.match(english.strip())):
        r.error("%s: non-ASCII display name; give the character's plain ASCII name (English readers would see "
                "the PMX English name %r, others the PMX name)" % (label, english))
    else:
        r.error("%s: non-ASCII display name; give the character's plain ASCII name (Robin)" % label)
    settings = item.get("settings") if isinstance(item.get("settings"), dict) else {}
    groups = settings.get("bodygroups")
    if item["kind"] == "character":
        if not isinstance(groups, dict) or not groups.get("presets"):
            r.info("%s: no bodygroup presets (spawns with the authored look)" % label)
        else:
            presets, default = groups.get("presets"), groups.get("default")
            if isinstance(presets, list):
                r.warn("%s: presets are a JSON array; they install as presets named 1, 2, ..." % label)
                names = [str(i + 1) for i in range(len(presets))]
            else:
                names = [str(k) for k in presets]
            if not isinstance(default, str) or default not in names:
                r.warn("%s: no valid default preset (%r); it spawns with the authored look" % (label, default))
            elif default.isdigit():
                r.warn("%s: the default preset is named %r, easy to miss (Robin: renamed Default)" % (label, default))
            else:
                r.ok("%s: default bodygroup preset %r of %d" % (label, default, len(names)))
    notes = " ".join(str(embedded.get(k) or "") for k in ("comment", "commentEnglish", "copyright"))
    notes += " " + " ".join(str(x.get("text") or "") for x in terms.get("readmes") or [] if isinstance(x, dict))
    hit = RESTRICTION.search(notes)
    if hit:
        snippet = re.sub(r"\s+", " ", notes[max(0, hit.start() - 40):hit.end() + 40]).strip()
        r.warn("%s: its terms mention restrictions (...%s...): review before any public release" % (label, snippet))
    elif not terms:
        # Every packed model carries its terms of use (March 7th went out without; the user,
        # 2026-10-31): record them in Model Hotloader (the import's terms dialog) and pack again.
        r.error("%s: no terms-of-use record; record the model's terms in Model Hotloader and pack again" % label)


# ---- the Remix mod -----------------------------------------------------------------------------

def check_mod(r: Report, mod: str, hashes_files):
    mod_usda = os.path.join(mod, "mod.usda")
    if not os.path.isfile(mod_usda):
        r.error("%s has no mod.usda" % mod)
        return
    with open(mod_usda, encoding="utf-8") as fh:
        text = fh.read()
    sub = re.search(r"subLayers\s*=\s*\[(.*?)\]", text, re.S)
    layers = [ref for ref in REFERENCE.findall(sub.group(1))] if sub else []
    if not layers:
        r.error("mod.usda lists no subLayers")
    used = {"mod.usda"}
    found = {}
    for ref in layers:
        rel = os.path.normpath(ref).replace("\\", "/")
        path = os.path.join(mod, rel)
        if rel.startswith("..") or not os.path.isfile(path):
            r.error("mod.usda lists %s, which is not in the mod" % ref)
            continue
        used.add(rel.lower())
        with open(path, encoding="utf-8") as fh:
            layer = fh.read()
        key = os.path.splitext(os.path.basename(rel))[0]
        size, count, bad = 0, 0, 0
        for target in sorted(set(REFERENCE.findall(layer))):
            if not target.startswith("../"):
                if not target.lower().endswith(".mdl"):
                    r.error("%s references %r, neither a ../ path nor a Remix shader" % (key, target))
                    bad += 1
                continue
            inner = os.path.normpath(os.path.join(os.path.dirname(rel), target)).replace("\\", "/")
            if inner.startswith(".."):
                r.error("%s references %s outside the mod" % (key, target))
                bad += 1
                continue
            if not os.path.isfile(os.path.join(mod, inner)):
                r.error("%s references %s, which is missing" % (key, inner))
                bad += 1
                continue
            used.add(inner.lower())
            size += os.path.getsize(os.path.join(mod, inner))
            count += 1
        for digest in MATERIAL.findall(layer):
            found.setdefault(digest.upper(), []).append(key)
        if not bad:
            r.ok("layer %s: %d materials, %d textures, %.0f MB, every reference present"
                 % (key, len(MATERIAL.findall(layer)), count, size / 1e6))
    unused, unused_bytes = 0, 0
    for folder, _, names in os.walk(mod):
        for name in names:
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, mod).replace("\\", "/")
            if os.path.splitext(name)[1].lower() not in REMIX_DATA:
                r.error("%s is not Remix data: a content package may not deploy it" % rel)
            if not ascii_text(rel):
                r.error("%s is not an ASCII path: the loader deploys only ASCII paths" % rel)
            if rel.lower() not in used:
                unused += 1
                unused_bytes += os.path.getsize(path)
    if unused:
        r.warn("%d files (%.0f MB) in the mod that no layer references; stage only referenced files" % (unused, unused_bytes / 1e6))
    for hashes_json in hashes_files or []:
        check_hashes(r, hashes_json, found)


def check_hashes(r: Report, path: str, found: dict):
    try:
        record = load_json(path)
    except (OSError, ValueError) as error:
        r.error("%s cannot be read: %s" % (path, error))
        return
    key = os.path.basename(os.path.dirname(os.path.abspath(path)))
    generated = None
    for candidate in (os.path.join(os.path.dirname(path), "generated.json"),):
        if os.path.isfile(candidate):
            generated = load_json(candidate)
    ok, bare = 0, []
    for tex, info in (record.get("textures") or {}).items():
        name = os.path.basename(str(info.get("source", tex)).replace("\\", "/"))
        live = [h[2:].upper() if h.lower().startswith("0x") else h.upper() for h in info.get("live") or []]
        if not live:
            r.warn("%s %s: only predicted hashes (the part was hidden); show it in game and run rpai hashes" % (key, name))
            continue
        maps = None if generated is None else bool((generated.get(tex) or {}).get("maps"))
        for digest in live:
            if digest in found:
                ok += 1
            elif maps:
                r.error("%s %s: live hash %s has no material, but the sheet has PBR maps (add it: add_hashes.py)" % (key, name, digest))
            elif maps is None:
                r.warn("%s %s: live hash %s is in no layer (no generated.json to tell whether that is meant)" % (key, name, digest))
            elif name not in bare:
                bare.append(name)
    r.ok("%s: %d live hashes have a material in this mod" % (key, ok))
    if bare:
        r.warn("%s: no material and no maps of its own for %s: body skin left to Remix, or a sheet another "
               "character's layer covers on this machine only (check: add_hashes.py <game root>\\rtx-remix\\mods "
               "--check-json %s); tell the user which sheets players get as plain Remix" % (key, ", ".join(bare), path))


# ---- the archive -------------------------------------------------------------------------------

def read_gma(path: str):
    """(title, description JSON text, author, {name: (offset, size)})."""
    with open(path, "rb") as fh:
        head = fh.read(4 << 20)
    if head[:4] != b"GMAD":
        raise ValueError("not a plain GMA")
    version, at = head[4], 21

    def text():
        nonlocal at
        end = head.index(b"\0", at)
        value = head[at:end].decode("utf-8", "replace")
        at = end + 1
        return value

    if version > 1:
        while text():
            pass
    title, description, author = text(), text(), text()
    at += 4
    index = []
    while True:
        (number,) = struct.unpack_from("<I", head, at)
        at += 4
        if not number:
            break
        name = text()
        size, _ = struct.unpack_from("<qI", head, at)
        at += 12
        index.append((name, size))
    entries, offset = {}, at
    for name, size in index:
        entries[name] = (offset, size)
        offset += size
    return title, description, author, entries


def find_nlctl(start: str):
    here = os.path.dirname(os.path.abspath(start))
    while True:
        for preset in ("win64-release", "win64-debug"):
            candidate = os.path.join(here, "out", "build", preset, "loader", "cli", "nlctl.exe")
            if os.path.isfile(candidate):
                return candidate
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def check_gma(r: Report, gma: str, addon, mod, nlctl):
    try:
        title, description, author, entries = read_gma(gma)
    except (OSError, ValueError, struct.error) as error:
        r.error("%s cannot be read: %s" % (gma, error))
        return None
    size = os.path.getsize(gma)
    r.ok("archive %s: %d members, %.1f MB, title %r" % (os.path.basename(gma), len(entries), size / 1e6, title))
    if R18.search(title):
        r.warn("the archive title carries R18; gmpublish create sets the Workshop title from it and update never changes it")
    try:
        meta = json.loads(description)
        if meta.get("type") not in ADDON_TYPES:
            r.error("addon type %r is not a GMod add-on type" % meta.get("type"))
        tags = meta.get("tags") or []
        if len(tags) > 2 or any(t not in ADDON_TAGS for t in tags):
            r.error("tags %r: at most two GMod tags" % tags)
    except ValueError:
        r.error("the archive description is not addon.json JSON")
    if size > 4 * 1000 ** 3:
        r.warn("the archive is over 4 GB, the Workshop's size guideline")
    if "native/manifest.json" not in entries:
        r.error("the archive has no native/manifest.json: the loader would not see it")
        return None
    offset, length = entries["native/manifest.json"]
    with open(gma, "rb") as fh:
        fh.seek(offset)
        manifest = json.loads(fh.read(length))
    kinds = set(manifest.get("kinds") or [])
    content_only = True
    if not kinds <= CONTENT_KINDS:
        r.error("kinds %s: only lua-addon and root-files deploy from a subscription without the allowlist" % sorted(kinds))
        content_only = False
    if any(k in manifest for k in NATIVE_KEYS) or any(p.startswith("native/payload/") for p in manifest.get("files") or {}):
        r.error("the manifest carries native settings or payload files: it would need the allowlist")
        content_only = False
    roots = [f.get("path", "") for f in manifest.get("root_files") or []]
    for root in roots:
        if not (root.startswith("rtx-remix/mods/") or root.startswith("garrysmod/addons/")):
            r.error("root file %s is outside rtx-remix/mods and garrysmod/addons" % root)
            content_only = False
    if content_only:
        r.ok("content only: %s %s, kinds %s, requires_remix %s, root files %s" % (
            manifest.get("id"), manifest.get("version"), ", ".join(manifest.get("kinds") or []),
            str(manifest.get("requires_remix", False)).lower(), ", ".join(roots)))
    staged = [("garrysmod/addons/", addon), ("rtx-remix/mods/", mod)]
    for prefix, folder in staged:
        if folder and prefix + os.path.basename(os.path.normpath(folder)) not in roots:
            r.warn("the archive does not deploy %s%s: was it built from these folders?" % (prefix, os.path.basename(os.path.normpath(folder))))
    checker = nlctl or find_nlctl(gma)
    if not checker:
        r.warn("nlctl.exe not found: run nlctl manifest and nlctl verify on the archive yourself")
    else:
        for command in ("manifest", "verify"):
            done = subprocess.run([checker, command, gma], capture_output=True, text=True, errors="replace")
            last = (done.stdout.strip().splitlines() or [""])[-1]
            if done.returncode:
                r.error("nlctl %s: %s" % (command, (done.stdout + done.stderr).strip()[-400:]))
            else:
                r.ok("nlctl %s: %s" % (command, last))
    return manifest.get("id")


# ---- icon and description ----------------------------------------------------------------------

def check_icon(r: Report, icon: str):
    with open(icon, "rb") as fh:
        data = fh.read()
    if data[:2] != b"\xff\xd8":
        r.error("%s is not a JPEG" % icon)
        return
    at, found = 2, None
    while at + 4 <= len(data):
        if data[at] != 0xFF:
            break
        marker = data[at + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            at += 2
            continue
        (length,) = struct.unpack(">H", data[at + 2:at + 4])
        if marker in (0xC0, 0xC1, 0xC2, 0xC3):
            height, width = struct.unpack(">HH", data[at + 5:at + 9])
            found = (width, height, {0xC0: "baseline", 0xC1: "extended", 0xC2: "progressive", 0xC3: "lossless"}[marker])
            break
        at += 2 + length
    if not found:
        r.error("%s: no JPEG frame header found" % icon)
        return
    width, height, kind = found
    if (width, height, kind) == (512, 512, "baseline"):
        r.ok("icon %dx%d %s JPEG, %d KB" % (width, height, kind, len(data) // 1024))
    else:
        r.warn("icon is %dx%d %s; what worked for gmpublish is a 512x512 baseline JPEG" % (width, height, kind))
    if len(data) > 1 << 20:
        r.warn("icon is over 1 MB (Steam's preview limit is believed to be 1 MB; unverified)")


def check_description(r: Report, path: str):
    with open(path, encoding="utf-8-sig") as fh:
        text = fh.read()
    if RTX_PACKAGE_ITEM in text:
        r.ok("description names the RTX package %s" % RTX_PACKAGE_ITEM)
    else:
        r.error("description does not name the RTX package (Workshop item %s), a required item" % RTX_PACKAGE_ITEM)
    if not re.search(r"winmm\.dll|native loader", text, re.I):
        r.warn("description does not say that the GMod native loader (bin\\win64\\winmm.dll) is needed")
    if "mount" not in text.lower():
        r.warn("description does not say that GMod itself cannot mount the item (the harmless console line, ADR 0015)")
    if '"' in text:
        r.warn("description holds straight double quotes; PowerShell 5.1 drops them when it passes "
               "the text to package_content.py --description (Robin's \"Default\" lost them)")
    if len(text.strip().encode("utf-8")) > 8000:
        r.warn("description is over 8000 bytes")


# ---- main --------------------------------------------------------------------------------------

def discover(folder: str) -> dict:
    found = {}
    subfolders = [os.path.join(folder, n) for n in sorted(os.listdir(folder)) if os.path.isdir(os.path.join(folder, n))]
    addons = [d for d in subfolders if os.path.isdir(os.path.join(d, "data_static", "mmdhl")) or os.path.basename(d).lower().startswith("mmdhl_")]
    mods = [d for d in subfolders if os.path.isfile(os.path.join(d, "mod.usda"))]
    gmas = [f for f in glob.glob(os.path.join(folder, "*.gma")) if ".partial-" not in f and ".unchecked-" not in f]
    for key, hits in (("addon", addons), ("mod", mods), ("gma", gmas)):
        if len(hits) == 1:
            found[key] = hits[0]
        elif len(hits) > 1:
            found[key + "_ambiguous"] = hits
    for key, name in (("icon", "icon.jpg"), ("description", "description.txt")):
        if os.path.isfile(os.path.join(folder, name)):
            found[key] = os.path.join(folder, name)
    return found


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Check a staged Workshop content pack (read only).",
                                 epilog="See check_pack.py.md beside this script.")
    ap.add_argument("build", nargs="?", help="a build folder (out\\packages\\<n>)")
    ap.add_argument("--addon", help="the Model Hotloader package add-on folder (mmdhl_<n>) or a Lua add-on")
    ap.add_argument("--mod", help="the Remix mod folder (pbr_<n>)")
    ap.add_argument("--gma", help="the built archive")
    ap.add_argument("--icon", help="the Workshop icon")
    ap.add_argument("--description", help="the description text file")
    ap.add_argument("--hashes-json", action="append", default=[], metavar="FILE",
                    help="rpai work\\<key>\\hashes.json of a packed model (repeatable)")
    ap.add_argument("--nlctl", help="nlctl.exe (default: found above the archive)")
    ap.add_argument("--deep", action="store_true", help="unpack every Hotloader packet and compare its SHA-256")
    args = ap.parse_args(argv)
    if args.build and not os.path.isdir(args.build):
        ap.error("%s is not a folder" % args.build)
    parts = discover(args.build) if args.build else {}
    for key in ("addon", "mod", "gma", "icon", "description"):
        if getattr(args, key):
            parts[key] = getattr(args, key)
    r = Report()
    for key in ("addon", "mod", "gma"):
        if parts.get(key + "_ambiguous") and key not in parts:
            r.error("%d candidates for the %s in the build folder; give --%s" % (len(parts[key + "_ambiguous"]), key, key))
    if not any(parts.get(k) for k in ("addon", "mod", "gma")):
        ap.error("nothing to check: give a build folder or --addon/--mod/--gma")
    addon, mod = parts.get("addon"), parts.get("mod")
    hotloader = bool(addon and os.path.isdir(os.path.join(addon, "data_static", "mmdhl")))
    package_id = None
    if parts.get("gma"):
        print("== archive")
        package_id = check_gma(r, parts["gma"], addon, mod, args.nlctl)
    print("== names")
    check_names(r, addon, mod, package_id, hotloader)
    if hotloader:
        print("== Model Hotloader package")
        check_hotloader(r, addon, args.deep)
    elif addon:
        r.info("%s has no data_static/mmdhl: checked as a plain Lua add-on (map remaster)" % addon)
    if mod:
        print("== Remix mod")
        check_mod(r, mod, args.hashes_json)
    print("== icon and description")
    if parts.get("icon"):
        check_icon(r, parts["icon"])
    else:
        r.warn("no icon.jpg (gmpublish create needs -icon)")
    if parts.get("description"):
        check_description(r, parts["description"])
    else:
        r.warn("no description.txt to check")
    print("%d errors, %d warnings" % (r.errors, r.warnings))
    return 1 if r.errors else 0


if __name__ == "__main__":
    sys.exit(main())
