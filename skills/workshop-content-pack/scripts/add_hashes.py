"""Add Remix texture hashes to an rpai layer, or check which live hashes a layer (or mod) covers.

Remix keys a replacement material by the hash of the texture the game uploads: `over "mat_<HASH>"`.
The same sheet can upload with a new hash in another session or install (Guinaifen, 2026-10-29:
the face sheet and the mouth). Adding duplicates the sheet's `over "mat_<OLD>"` block under the NEW
hash, right after it, and keeps the old block, so both get the PBR.

Prefer the upstream fix when the game is running: spawn the model, `rpai hashes`, `rpai publish`,
then stage the mod again. Use this on a layer that is already staged (pbr_<name>\\models\\<key>.usda).

Usage:

    python -I add_hashes.py <layer.usda> OLD=NEW [OLD=NEW ...] [--dry-run] [--backup FILE] [--allow-game-install]
    python -I add_hashes.py <layer.usda | mod folder | mods folder> --list
    python -I add_hashes.py <layer.usda | mod folder | mods folder> --check HASH [HASH ...]
    python -I add_hashes.py <layer.usda | mod folder | mods folder> --check-json <rpai work\\<key>\\hashes.json> [--key KEY] [--strict]

Hashes may be written 0x37B3BC9B48184AA9, 37b3bc9b48184aa9 or mat_37B3BC9B48184AA9.

  OLD=NEW      copy the block of OLD (a hash the layer has) as NEW; a NEW already there is skipped
  --dry-run    report what would be added; write nothing
  --backup F   copy the layer to F (which must not exist) before writing
  --list       print every material hash with the first texture it references
  --check      report for each given hash which layer has it; exit 1 if one is missing
  --check-json read rpai's hashes.json (live and predicted hashes per texture) and, when it lies
               beside it, generated.json (which sheets got PBR maps); report each live hash as
               ok, only in another layer, MISSING (the sheet has maps), or left to Remix (no maps);
               exit 1 if one is MISSING (--strict: also if one is only in another layer)
  --key KEY    the model's own layer for --check-json (default: the hashes.json folder name)

A mod folder means every models\\*.usda in it; a mods folder (<game root>\\rtx-remix\\mods) every
<mod>\\models\\*.usda below it, named <mod>:<key>. Check against the install's mods folder to see
which hashes only another character's layer covers on this machine (Robin, 2026-10-30: 7 sheets), or
against the staged pbr_<name> mod to see what the package itself covers.

Exit codes: 0 done, 1 refused, failed or a check failed (see above), 2 bad command line.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import sys

HASH = re.compile(r"^(?:0x|mat_)?([0-9A-Fa-f]{16})$")
MATERIAL = re.compile(r'over "mat_([0-9A-Fa-f]{16})"')
REFERENCE = re.compile(r"@([^@]+)@")


class HashError(Exception):
    """A refusal or failure: printed as "error: ...", exit code 1."""


def normal(value: str) -> str:
    m = HASH.match(value.strip())
    if not m:
        raise HashError("%r is not a Remix texture hash (16 hex digits)" % value)
    return m.group(1).upper()


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


def read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def layers_of(target: str) -> dict:
    """{layer key: text} of a layer file, of every models/*.usda of a mod folder, or of every
    <mod>/models/*.usda of a mods folder (keys then read <mod>:<key>)."""
    if os.path.isfile(target):
        return {os.path.splitext(os.path.basename(target))[0]: read(target)}
    files = sorted(glob.glob(os.path.join(target, "models", "*.usda")))
    if files:
        return {os.path.splitext(os.path.basename(f))[0]: read(f) for f in files}
    files = sorted(glob.glob(os.path.join(target, "*", "models", "*.usda")))
    if not files:
        raise HashError("%s is neither a layer file, a mod folder with models\\*.usda nor a mods folder" % target)
    return {"%s:%s" % (os.path.basename(os.path.dirname(os.path.dirname(f))), os.path.splitext(os.path.basename(f))[0]): read(f)
            for f in files}


def block(text: str, digest: str):
    """The `over "mat_<digest>"` block, from its line to its closing brace at the same indent."""
    return re.search(r'(\n(?P<indent>[ \t]*)over "mat_%s"[ \t]*\n(?P=indent)\{\n.*?\n(?P=indent)\}\n)' % digest,
                     text, re.S | re.I)


def add(args) -> int:
    layer = os.path.abspath(args.target)
    if not os.path.isfile(layer):
        raise HashError("adding needs a layer file, not %s" % layer)
    root = game_root_of(layer)
    if root and not args.allow_game_install and not args.dry_run:
        raise HashError("%s is inside the game install %s (rpai owns its ai_pbr mod and overwrites edits); "
                        "edit the staged copy, or pass --allow-game-install only when the user asked for it" % (layer, root))
    pairs = []
    for spec in args.pairs:
        old, sep, new = spec.partition("=")
        if not sep:
            raise HashError("%s: expected OLD=NEW" % spec)
        pairs.append((normal(old), normal(new)))
    text = read(layer)
    added = 0
    for old, new in pairs:
        if re.search(r'over "mat_%s"' % new, text, re.I):
            print("%s: already there" % new)
            continue
        m = block(text, old)
        if not m:
            raise HashError("the layer has no block for %s" % old)
        copy = re.sub("mat_" + old, "mat_" + new, m.group(1), flags=re.I)
        text = text[:m.end()] + copy + text[m.end():]
        added += 1
        print("%s -> %s: %s" % (old, new, "would be added" if args.dry_run else "added"))
    count = len(MATERIAL.findall(text))
    if args.dry_run or not added:
        print("%d materials%s" % (count, " (dry run, nothing written)" if args.dry_run else ""))
        return 0
    if args.backup:
        if os.path.lexists(args.backup):
            raise HashError("--backup %s exists" % args.backup)
        shutil.copy2(layer, args.backup)
    temporary = layer + ".tmp-%d" % os.getpid()
    with open(temporary, "x", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(temporary, layer)
    print("%d materials" % count)
    return 0


def list_layers(args) -> int:
    for key, text in layers_of(args.target).items():
        hashes = MATERIAL.findall(text)
        print("%s: %d materials" % (key, len(hashes)))
        for digest in hashes:
            m = block(text, digest)
            refs = [r for r in REFERENCE.findall(m.group(1)) if not r.lower().endswith(".mdl")] if m else []
            print("  mat_%s  %s" % (digest.upper(), os.path.basename(refs[0]) if refs else "-"))
    return 0


def owners(layers: dict) -> dict:
    found = {}
    for key, text in layers.items():
        for digest in MATERIAL.findall(text):
            found.setdefault(digest.upper(), []).append(key)
    return found


def check(args) -> int:
    found = owners(layers_of(args.target))
    missing = 0
    for value in args.check:
        digest = normal(value)
        where = found.get(digest)
        print("%s  %s" % (digest, "in " + ", ".join(where) if where else "MISSING"))
        missing += not where
    print("%d of %d hashes covered" % (len(args.check) - missing, len(args.check)))
    return 1 if missing else 0


def check_json(args) -> int:
    path = os.path.abspath(args.check_json)
    try:
        with open(path, encoding="utf-8") as fh:
            record = json.load(fh)
    except (OSError, ValueError) as error:
        raise HashError("%s cannot be read: %s" % (path, error))
    textures = record.get("textures") if isinstance(record, dict) else None
    if not isinstance(textures, dict):
        raise HashError("%s is not an rpai hashes.json (no textures)" % path)
    key = args.key or os.path.basename(os.path.dirname(path))
    # generated.json (which sheets got maps) lies beside hashes.json, or in the model's own work
    # folder when hashes.json comes from a re-import (rpai hashes --asset).
    generated = None
    for candidate in (os.path.join(os.path.dirname(path), "generated.json"),
                      os.path.join(os.path.dirname(os.path.dirname(path)), key, "generated.json")):
        if os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as fh:
                generated = json.load(fh)
            break
    found = owners(layers_of(args.target))
    counts = {"ok": 0, "other": 0, "missing": 0, "remix": 0, "predicted": 0}
    for tex, info in textures.items():
        name = os.path.basename(str(info.get("source", tex)).replace("\\", "/"))
        live = [normal(h) for h in info.get("live") or []]
        has_maps = None if generated is None else bool((generated.get(tex) or {}).get("maps"))
        if not live:
            predicted = ["%s%s" % (h, " in " + ", ".join(found[h]) if h in found else "")
                         for h in (normal(v) for v in info.get("predicted") or [])]
            print("%-24s predicted only (%s): show the part in game and run rpai hashes"
                  % (name[:24], "; ".join(predicted) or "-"))
            counts["predicted"] += 1
            continue
        for digest in live:
            where = found.get(digest, [])
            if any(w == key or w.split(":")[-1] == key for w in where):
                status, bucket = "ok", "ok"
            elif where:
                status, bucket = "only in " + ", ".join(where), "other"
            elif has_maps:
                status, bucket = "MISSING: the sheet has maps but no material for this hash", "missing"
            elif has_maps is None:
                status, bucket = "not in any layer (no generated.json to tell whether it has maps)", "missing"
            else:
                status, bucket = "left to Remix (no maps)", "remix"
            counts[bucket] += 1
            print("%-24s %s  %s" % (name[:24], digest, status))
    print("live hashes: %d ok, %d only in another layer, %d missing, %d left to Remix; %d textures predicted only"
          % (counts["ok"], counts["other"], counts["missing"], counts["remix"], counts["predicted"]))
    if counts["missing"] or (args.strict and counts["other"]):
        return 1
    return 0


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Add Remix texture hashes to an rpai layer, or check its coverage.",
                                 epilog="See add_hashes.py.md beside this script.")
    ap.add_argument("target", help="a layer .usda, or (for --list and the checks) a mod folder")
    ap.add_argument("pairs", nargs="*", metavar="OLD=NEW", help="copy the block of OLD as NEW")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--backup", metavar="FILE")
    ap.add_argument("--allow-game-install", action="store_true")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--check", nargs="+", metavar="HASH")
    mode.add_argument("--check-json", metavar="HASHES_JSON")
    ap.add_argument("--key", help="the model's own layer key for --check-json")
    ap.add_argument("--strict", action="store_true", help="--check-json: fail on a hash only another layer covers")
    args = ap.parse_args(argv)
    try:
        if args.list or args.check or args.check_json:
            if args.pairs:
                ap.error("OLD=NEW pairs cannot be combined with --list or a check")
            return list_layers(args) if args.list else check(args) if args.check else check_json(args)
        if not args.pairs:
            ap.error("give OLD=NEW pairs, --list, --check or --check-json")
        return add(args)
    except (HashError, OSError, ValueError) as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
