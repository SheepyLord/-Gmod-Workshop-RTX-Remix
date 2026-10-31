"""Stage a stand-alone Remix mod folder for a Workshop package from rpai's live mod (ai_pbr).

Copies the named rpai model layer(s) (models/<key>.usda) and exactly the files they reference
(their DDS maps), checks every copy by SHA-256 and writes a mod.usda that lists only those layers.
The folder is the --mod input of package_content.py, which deploys it to rtx-remix/mods/<folder name>.

FALLBACK route: stage_pbr_mod.py in the mmd-remix-pbr skill does the same job and is the stager the
current recipe names. This script is the earlier one (Guinaifen, Robin), kept for when that skill is
not at hand.

Usage:

    python -I pbr_mod.py <mod folder> <model key> <out mod folder> <label>
        [--layer KEY]... [--dry-run] [--replace] [--allow-game-install]

  <mod folder>      rpai's live mod, <game root>\\rtx-remix\\mods\\ai_pbr (read only)
  <model key>       the rpai model key, the layer's file name: models/<key>.usda (rpai status lists them)
  <out mod folder>  the mod folder to write, named pbr_<name>; must not exist (see --replace)
  <label>           the character's name for the mod.usda doc string ("Robin")

  --layer KEY           another layer in the same mod (repeatable): several characters in one package
  --dry-run             list what would be copied and its size; write nothing
  --replace             replace an earlier staged mod folder at <out mod folder> (only such a folder)
  --allow-game-install  allow <out mod folder> inside a game install (only when the user asked)

Exit codes: 0 done, 1 refused or failed (reason on stderr), 2 bad command line.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import sys

# Remix data a content package may deploy under rtx-remix/mods (docs/PACKAGE_FORMAT.md, ADR 0027).
REMIX_DATA = {".usd", ".usda", ".usdc", ".usdz", ".dds", ".png", ".jpg", ".jpeg", ".tga", ".bmp", ".exr", ".hdr",
              ".mdl", ".json", ".txt"}
REFERENCE = re.compile(r"@([^@]+)@")
MATERIAL = re.compile(r'over "mat_[0-9A-Fa-f]{16}"')
KEY = re.compile(r"^[A-Za-z0-9_.-]{1,96}$")
MOD_USDA = '''#usda 1.0
(
    customLayerData = {
        string lightspeed_game_name = "Garry's Mod (x64)"
        string lightspeed_layer_type = "replacement"
    }
    doc = "%s"
    metersPerUnit = 0.01
    subLayers = [
%s
    ]
    timeCodesPerSecond = 24
    upAxis = "Z"
)
'''


class StageError(Exception):
    """A refusal or failure: printed as "error: ...", exit code 1."""


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def joined(words):
    return words[0] if len(words) == 1 else ", ".join(words[:-1]) + " and " + words[-1]


def plan(src: str, keys: list):
    """{key: (layer path, material count, {mod path: source path})} for every layer."""
    layers = {}
    for key in keys:
        if not KEY.match(key):
            raise StageError("model key %r: expected an rpai key such as robin_r18_f9c3e4b4" % key)
        layer = os.path.join(src, "models", key + ".usda")
        if not os.path.isfile(layer):
            raise StageError("no layer %s" % layer)
        with open(layer, encoding="utf-8") as fh:
            text = fh.read()
        copies = {}
        for ref in sorted(set(REFERENCE.findall(text))):
            if not ref.startswith("../"):
                if not ref.lower().endswith(".mdl"):  # Remix's built-in shaders, such as AperturePBR_Opacity.mdl
                    raise StageError("%s: reference %r is neither a ../ path nor a Remix shader (.mdl)" % (key, ref))
                continue
            rel = os.path.normpath(os.path.join("models", ref))
            if os.path.isabs(rel) or rel.startswith(".."):
                raise StageError("%s: reference %r leaves the mod folder" % (key, ref))
            if os.path.splitext(rel)[1].lower() not in REMIX_DATA:
                raise StageError("%s: %s is not Remix data; a content package could not deploy it" % (key, ref))
            if not rel.isascii():
                raise StageError("%s: %s is not an ASCII path; the loader deploys only ASCII paths" % (key, ref))
            source = os.path.join(src, rel)
            if not os.path.isfile(source):
                raise StageError("%s references %s, which is missing" % (key, source))
            copies[rel] = source
        layers[key] = (layer, len(MATERIAL.findall(text)), copies)
    return layers


def looks_like_staged_mod(folder: str) -> bool:
    """Only an earlier output of this script (or of stage_pbr_mod.py) may be replaced."""
    if not os.path.isdir(folder):
        return False
    top = {n.lower() for n in os.listdir(folder)}
    return "mod.usda" in top and top <= {"mod.usda", "models", "textures"}


def stage(args) -> int:
    src, out = os.path.abspath(args.src), os.path.abspath(args.out)
    if not os.path.isdir(os.path.join(src, "models")):
        raise StageError("%s has no models folder: give rpai's mod, <game root>\\rtx-remix\\mods\\ai_pbr" % src)
    if inside(out, src) or inside(src, out):
        raise StageError("the output %s must be outside %s" % (out, src))
    root = game_root_of(out)
    if root and not args.allow_game_install and not args.dry_run:
        raise StageError("%s is inside the game install %s; pass --allow-game-install only when the user asked for it" % (out, root))
    name = os.path.basename(out.rstrip("\\/"))
    if not re.fullmatch(r"pbr_[a-z0-9_]+", name) or re.search(r"(^|_)r18(_|$)", name):
        print("  warning: the folder %s is deployed as rtx-remix/mods/%s; name it pbr_<name> in lowercase ASCII, without r18" % (name, name))
    keys = [args.key] + [k for k in args.layer if k != args.key]
    layers = plan(src, keys)
    total_files = sum(len(c) for _, _, c in layers.values())
    total_bytes = sum(os.path.getsize(s) for _, _, c in layers.values() for s in c.values())
    if args.dry_run:
        for key, (_, materials, copies) in layers.items():
            print("%s: %d textures (%.0f MB), %d materials" % (key, len(copies), sum(map(os.path.getsize, copies.values())) / 1e6, materials))
        print("dry run: would write %s, %d files, %.0f MB" % (out, total_files + len(layers) + 1, total_bytes / 1e6))
        return 0
    if os.path.lexists(out):
        if not args.replace:
            raise StageError("%s exists (--replace rebuilds an earlier staged mod folder)" % out)
        if not looks_like_staged_mod(out):
            raise StageError("%s is not a staged mod folder; not replacing it" % out)
    partial = out + ".partial-%d" % os.getpid()
    if os.path.lexists(partial):
        raise StageError("%s is in the way; delete it" % partial)
    os.makedirs(os.path.join(partial, "models"))
    try:
        done = set()
        for key, (layer, materials, copies) in layers.items():
            shutil.copy2(layer, os.path.join(partial, "models", key + ".usda"))
            size = 0
            for rel, source in sorted(copies.items()):
                target = os.path.join(partial, rel)
                if rel.lower() not in done:
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    shutil.copy2(source, target)
                    if sha256_of(source) != sha256_of(target):
                        raise StageError("copy differs from its source: %s" % source)
                    done.add(rel.lower())
                size += os.path.getsize(target)
            print("%s%d textures (%.0f MB), %d materials" % ("" if len(layers) == 1 else key + ": ", len(copies), size / 1e6, materials))
        label = args.label.replace('"', "'")
        doc = "%s RTX PBR (rpai layer%s %s), packaged for the Workshop." % (label, "" if len(keys) == 1 else "s", joined(keys))
        sub = ",\n".join("        @./models/%s.usda@" % key for key in keys)
        with open(os.path.join(partial, "mod.usda"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(MOD_USDA % (doc, sub))
        if os.path.lexists(out):
            shutil.rmtree(out)
        os.replace(partial, out)
        partial = None
    finally:
        if partial and os.path.isdir(partial):
            shutil.rmtree(partial)
    if len(layers) > 1:
        print("staged %s: %d layers, %d textures (%.0f MB)" % (out, len(layers), len(done), total_bytes / 1e6))
    return 0


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Stage a stand-alone Remix mod folder from rpai's ai_pbr mod.",
                                 epilog="See pbr_mod.py.md beside this script.")
    ap.add_argument("src", help="rpai's live mod folder, <game root>\\rtx-remix\\mods\\ai_pbr (read only)")
    ap.add_argument("key", help="the rpai model key (models/<key>.usda)")
    ap.add_argument("out", help="the mod folder to write (pbr_<name>)")
    ap.add_argument("label", help="the character's name for the mod.usda doc string")
    ap.add_argument("--layer", action="append", default=[], metavar="KEY", help="another layer in the same mod (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be copied; write nothing")
    ap.add_argument("--replace", action="store_true", help="replace an earlier staged mod folder at the output")
    ap.add_argument("--allow-game-install", action="store_true", help="allow an output inside a game install")
    args = ap.parse_args(argv)
    try:
        return stage(args)
    except (StageError, OSError) as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
