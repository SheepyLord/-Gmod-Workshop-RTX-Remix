"""Compare the members of two .gma archives by name and by the SHA-256 of their bytes.

Written to tell whether two Model Hotloader imports of the same PMX carry the same textures: their
generated archives (<cache>\\assets\\<id>\\materials-v5.gma) name members after the asset
(materials/mmd/<first 16 hex digits of the id>/...). That folder is replaced by a placeholder by
default, so two imports compare by content. Guinaifen, 2026-10-29: the classic import 1c2ed2fc and
the user's re-import bf8aee59 had 77 of 77 members and 14 of 14 VTF textures identical, so the
PBR's texture hashes did not depend on which import was spawned.

It reads any plain GMAD v1-v3 archive, streaming (archives of several GB are fine), for example a
package build and the copy Steam downloaded. It does not read LZMA-wrapped Workshop *_legacy.bin.

Usage:

    python -I gma_diff.py <a.gma> <b.gma> [--no-strip] [--all]

  --no-strip  compare member names exactly, without replacing the materials/mmd/<16 hex>/ folder
  --all       list every differing member (default: the first 20 of each kind)

Prints the first member names of both, a summary line ("members A/B; same bytes N; vtf V, vtf same
S") and the differing members. Exit codes: 0 the same members with the same bytes, 1 they differ,
2 bad command line, unreadable file or not a GMA.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys

ASSET_FOLDER = re.compile(r"^materials/mmd/[0-9a-f]{16}/", re.I)


class GmaError(Exception):
    """Not a readable GMA: printed as "error: ...", exit code 2."""


def cstring(fh) -> str:
    data = bytearray()
    while True:
        byte = fh.read(1)
        if not byte:
            raise GmaError("truncated header")
        if byte == b"\0":
            return data.decode("utf-8", "replace")
        data += byte
        if len(data) > 65536:
            raise GmaError("a header string is longer than 64 KB")


def members(path: str) -> dict:
    """{member name: SHA-256 of its bytes}, in archive order."""
    with open(path, "rb") as fh:
        if fh.read(4) != b"GMAD":
            raise GmaError("%s is not a plain GMA (no GMAD header)" % path)
        version = fh.read(1)[0]
        if version > 3:
            raise GmaError("%s: unknown GMAD version %d" % (path, version))
        fh.read(16)                               # steamid, timestamp
        if version > 1:
            for _ in range(256):                  # required content, empty-string terminated
                if not cstring(fh):
                    break
        cstring(fh), cstring(fh), cstring(fh)     # title, description, author
        fh.read(4)                                # addon version
        index = []
        while True:
            raw = fh.read(4)
            if len(raw) != 4:
                raise GmaError("%s: truncated file index" % path)
            if not struct.unpack("<I", raw)[0]:
                break
            name = cstring(fh)
            size, _crc = struct.unpack("<qI", fh.read(12))
            if size < 0:
                raise GmaError("%s: negative member size" % path)
            index.append((name, size))
        out = {}
        for name, size in index:
            digest, left = hashlib.sha256(), size
            while left:
                chunk = fh.read(min(left, 1 << 22))
                if not chunk:
                    raise GmaError("%s: truncated at %s" % (path, name))
                digest.update(chunk)
                left -= len(chunk)
            out[name] = digest.hexdigest()
        return out


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="Compare two .gma archives member by member (SHA-256).",
                                 epilog="See gma_diff.py.md beside this script.")
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--no-strip", action="store_true", help="compare names exactly")
    ap.add_argument("--all", action="store_true", help="list every differing member")
    args = ap.parse_args(argv)
    try:
        a, b = members(args.a), members(args.b)
    except (GmaError, OSError, IndexError, struct.error) as error:
        print("error: %s" % error, file=sys.stderr)
        return 2
    print("names A:", list(a)[:3])
    print("names B:", list(b)[:3])

    def keyed(found: dict) -> dict:
        if args.no_strip:
            return dict(found)
        return {ASSET_FOLDER.sub("materials/mmd/<asset>/", name): digest for name, digest in found.items()}

    ka, kb = keyed(a), keyed(b)
    same = [n for n in ka if kb.get(n) == ka[n]]
    differ = [n for n in ka if n in kb and kb[n] != ka[n]]
    only_a = [n for n in ka if n not in kb]
    only_b = [n for n in kb if n not in ka]
    vtf = [n for n in ka if n.lower().endswith(".vtf")]
    print("members %d/%d; same bytes%s %d; vtf %d, vtf same %d" % (
        len(a), len(b), "" if args.no_strip else " (folder stripped)", len(same), len(vtf),
        sum(1 for n in vtf if kb.get(n) == ka[n])))
    limit = None if args.all else 20
    for label, names in (("differs", differ), ("only in A", only_a), ("only in B", only_b)):
        for name in names[:limit]:
            print("  %s: %s" % (label, name))
        if limit is not None and len(names) > limit:
            print("  ... %d more %s (--all lists them)" % (len(names) - limit, label))
    return 0 if not (differ or only_a or only_b) and len(ka) == len(a) == len(b) == len(kb) else 1


if __name__ == "__main__":
    sys.exit(main())
