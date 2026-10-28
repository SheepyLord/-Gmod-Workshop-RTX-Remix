"""Give the PoC the reference install's user content for a like-for-like comparison, then take it away.

The loader's packages bring the runtime and the RTX fixes; what else makes a frame in the reference
install (GarrysMod_RTX_c) is the user's own: Remix's user.conf, the fixes' saved Lua settings
(cfg/client.vdf, server.vdf), mounted games (cfg/mountdepots.txt), the user's Remix mods, a save and
its Workshop map, and on request the user's local add-on folders and named native files (the MMD Hot
Loader's modules). `prepare` copies those into the PoC (copies, never links: nothing can write back
into the reference install) and records every file it adds or replaces; `restore` undoes exactly
that. See poc_parity.py.md.
"""
from __future__ import annotations

import argparse
import json
import lzma
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_REFERENCE = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c")
DEFAULT_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_PoC")
WORKSHOP = Path(r"H:\SteamLibrary\steamapps\workshop\content\4000")
# Mods the fixes package deploys itself.
FIXES_MODS = ("base_mod", "gm_poolrooms_rtx", "rtx_water", "~gmod_topbr")
REPLACED_FILES = ("user.conf", "garrysmod/cfg/client.vdf", "garrysmod/cfg/server.vdf", "garrysmod/cfg/mountdepots.txt")


class Failure(Exception):
    pass


def game_running(root: Path) -> bool:
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq gmod.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
    if "gmod.exe" not in out.lower():
        return False
    ps = subprocess.run(["powershell", "-NoProfile", "-Command",
                         "Get-Process gmod -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"], capture_output=True, text=True).stdout
    prefix = os.path.join(os.path.normcase(str(root)), "")  # GarrysMod must not match GarrysMod_PoC
    return any(os.path.normcase(line.strip()).startswith(prefix) for line in ps.splitlines() if line.strip())


def is_link(path: Path) -> bool:
    """A symbolic link or junction (any reparse point that is a directory)."""
    try:
        return path.is_symlink() or bool(os.lstat(path).st_file_attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT
    except OSError:
        return False


def tree_size(folder: Path) -> int:
    """Bytes under `folder`, never following links (os.walk's default)."""
    total = 0
    for base, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if not is_link(Path(base) / d)]
        for name in files:
            path = Path(base) / name
            if not is_link(path):
                total += path.stat().st_size
    return total


def copy_tree(source: Path, target: Path, exclude_dirs: tuple[str, ...] = ()) -> None:
    # /XJ: never follow a junction or symbolic link inside the tree. A link can lead back up the tree
    # (one of the user's mods does) and robocopy follows links by default.
    excluded = ["/XD", *exclude_dirs] if exclude_dirs else []
    result = subprocess.run(["robocopy", str(source), str(target), "/E", "/XJ", *excluded, "/MT:16", "/R:1", "/W:1", "/NFL", "/NDL",
                             "/NJH", "/NJS", "/NP"], capture_output=True, text=True)
    if result.returncode >= 8:
        raise Failure(f"robocopy {source} failed ({result.returncode}): {result.stdout[-500:]}")


def copy_plain(source: Path, target: Path) -> list[str]:
    """Copies the regular files and folders below `source`, never following or copying a link of any
    kind (Python's own walk, so nothing depends on how robocopy treats symbolic links); returns the
    links left out."""
    skipped = []
    for base, dirs, files in os.walk(source):
        here = Path(base)
        rel = here.relative_to(source)
        skipped += [(rel / d).as_posix() for d in dirs if is_link(here / d)]
        dirs[:] = [d for d in dirs if not is_link(here / d)]
        (target / rel).mkdir(parents=True, exist_ok=True)
        for name in files:
            if is_link(here / name):
                skipped.append((rel / name).as_posix())
            else:
                shutil.copy2(here / name, target / rel / name)
    return skipped


def extract_map(item: Path, name: str, target: Path) -> None:
    """maps/<name>.bsp out of a Workshop item: a plain .gma, or an LZMA-wrapped *_legacy.bin (LZMA-alone
    stream, then GMod's 8-byte footer: RESEARCH.md section 5)."""
    archives = sorted(item.glob("*.gma")) + sorted(item.glob("*_legacy.bin"))
    if len(archives) != 1:
        raise Failure(f"{item}: expected one archive, found {len(archives)}")
    data = archives[0].read_bytes()
    if archives[0].suffix.lower() == ".bin":
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
        data = decoder.decompress(data)
    with tempfile.TemporaryDirectory(dir=REPO / "out" / "tmp") as scratch:
        gma = Path(scratch) / "item.gma"
        gma.write_bytes(data)
        folder = Path(scratch) / "x"
        done = subprocess.run([sys.executable, str(REPO / "tools" / "gmapack" / "gmapack.py"), "extract", "-file", str(gma), "-out", str(folder), "--quiet"],
                              capture_output=True, text=True)
        if done.returncode != 0:
            raise Failure(f"gmapack extract failed: {done.stderr[-500:]}")
        found = [p for p in folder.rglob("*.bsp") if p.stem.lower() == name.lower()]
        if not found:
            raise Failure(f"{name}.bsp is not in Workshop item {item.name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(found[0], target)


def prepare(args) -> dict:
    reference, root, evidence = Path(args.reference), Path(args.root), Path(args.evidence)
    state_file = evidence / "parity.json"
    if state_file.exists():
        raise Failure(f"{state_file} exists: restore that session first")
    if game_running(root):
        raise Failure("a game from the PoC is running")
    state = {"reference": str(reference), "root": str(root), "created": [], "replaced": []}
    backup = evidence / "parity-backup"
    try:
        for rel in REPLACED_FILES if args.files else ():
            source, target = reference / rel, root / rel
            if not source.exists():
                continue
            entry = {"path": rel, "backup": None}
            if target.exists():
                entry["backup"] = str(backup / rel)
                (backup / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup / rel)
            state["replaced"].append(entry)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        excluded = {name.lower() for name in FIXES_MODS + tuple(args.exclude_mod)}
        mods = reference / "rtx-remix" / "mods"
        chosen = []
        state["skipped_links"] = []
        state["skipped_mods"] = []
        for folder in sorted(p for p in mods.iterdir() if p.is_dir()) if args.mods else []:
            if folder.name.lower() in excluded:
                continue
            if (root / "rtx-remix" / "mods" / folder.name).exists():
                state["skipped_mods"].append(folder.name)  # an earlier layer's, or the PoC's own
                continue
            if is_link(folder) and not args.copy_linked_mods:
                # A linked mod would have to be followed into another folder (possibly a cycle) or
                # linked back into the reference install; neither is a copy. Reported, left out.
                state["skipped_links"].append(folder.name)
                continue
            chosen.append(folder)
        # Add-on folders the PoC does not have: the ones a package deployed there are the package's.
        addons = []
        state["skipped_addons"] = []
        state["followed_links"] = []
        for folder in sorted(p for p in (reference / "garrysmod" / "addons").iterdir() if p.is_dir()) if args.addons else []:
            if (root / "garrysmod" / "addons" / folder.name).exists():
                state["skipped_addons"].append(folder.name)
            elif is_link(folder) and not args.copy_linked_addons:
                state["skipped_links"].append("addons/" + folder.name)
            else:
                addons.append(folder)
        # A linked add-on is the user's working copy elsewhere: its contents are copied (without .git).
        sources = {folder: Path(os.path.realpath(folder)) if is_link(folder) else folder for folder in addons}
        needed = sum(tree_size(folder) for folder in chosen) + sum(tree_size(source) for source in sources.values())
        free = shutil.disk_usage(root).free
        state["mods_bytes"] = needed
        if needed + (20 << 30) > free:
            raise Failure(f"the copies need {needed >> 30} GiB and {free >> 30} GiB is free (20 GiB kept spare)")
        for folder in chosen:
            target = root / "rtx-remix" / "mods" / folder.name
            state["created"].append(str(target.relative_to(root)))
            if is_link(folder):
                # What the link points to, file by file; links inside (one of the user's mods links
                # back to the whole rtx-remix folder) are left out and listed.
                source = Path(os.path.realpath(folder))
                left_out = copy_plain(source, target)
                state["followed_links"].append({"mod": folder.name, "target": str(source), "links_left_out": left_out})
            else:
                copy_tree(folder, target)
        for folder, source in sources.items():
            target = root / "garrysmod" / "addons" / folder.name
            state["created"].append(str(target.relative_to(root)))
            if source != folder:
                state["followed_links"].append({"addon": folder.name, "target": str(source)})
                copy_tree(source, target, exclude_dirs=(".git",))
            else:
                copy_tree(folder, target)
        for name in args.data:
            source, target = reference / "garrysmod" / "data" / name, root / "garrysmod" / "data" / name
            if not source.is_dir() or is_link(source):
                raise Failure(f"{source} is not a folder")
            if target.exists():
                raise Failure(f"{target} exists: the PoC has its own")
            state["created"].append(f"garrysmod/data/{name}")
            copy_tree(source, target)
        for rel in args.native:
            source, target = reference / rel, root / rel
            if not source.is_file():
                raise Failure(f"{source} is not a file")
            if target.exists():
                raise Failure(f"{target} exists: the PoC has its own")
            target.parent.mkdir(parents=True, exist_ok=True)
            state["created"].append(Path(rel).as_posix())
            shutil.copy2(source, target)
        configs = reference / "garrysmod" / "data" / "remix_map_configs"
        if configs.is_dir() and not (root / "garrysmod" / "data" / "remix_map_configs").exists():
            state["created"].append("garrysmod/data/remix_map_configs")
            copy_tree(configs, root / "garrysmod" / "data" / "remix_map_configs")
        if args.save:
            for suffix in (".gms", ".jpg"):
                rel = Path("garrysmod/saves") / (args.save + suffix)
                if (reference / rel).exists() and not (root / rel).exists():
                    (root / rel).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(reference / rel, root / rel)
                    state["created"].append(rel.as_posix())
        if args.map:
            item, name = args.map.split(":", 1)
            rel = Path("garrysmod/maps") / (name + ".bsp")
            if not (root / rel).exists():
                state["created"].append(rel.as_posix())
                extract_map(WORKSHOP / item, name, root / rel)
    finally:
        evidence.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return state


def restore(args) -> dict:
    evidence = Path(args.evidence)
    state_file = evidence / "parity.json"
    if not state_file.exists():
        raise Failure(f"{state_file} does not exist")
    state = json.loads(state_file.read_text(encoding="utf-8"))
    root = Path(state["root"])
    if game_running(root):
        raise Failure("a game from the PoC is running")
    for rel in reversed(state["created"]):
        target = root / rel
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()
    for entry in state["replaced"]:
        target = root / entry["path"]
        if entry["backup"]:
            shutil.copy2(entry["backup"], target)
        elif target.exists():
            target.unlink()
    state_file.rename(evidence / "parity-restored.json")
    return {"restored": len(state["created"]) + len(state["replaced"])}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--evidence", required=True, help="session folder; parity.json there records what was done")
    sub = parser.add_subparsers(dest="action", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--reference", default=str(DEFAULT_REFERENCE))
    p.add_argument("--root", default=str(DEFAULT_ROOT))
    p.add_argument("--no-mods", dest="mods", action="store_false", help="copy no Remix mods")
    p.add_argument("--no-files", dest="files", action="store_false",
                   help="leave user.conf, client.vdf, server.vdf and mountdepots.txt alone (a second layer)")
    p.add_argument("--addons", action="store_true", help="copy the reference's add-on folders the PoC does not have")
    p.add_argument("--copy-linked-addons", action="store_true",
                   help="with --addons: copy what a linked add-on folder points to (without .git) instead of leaving it out")
    p.add_argument("--data", action="append", default=[], metavar="NAME",
                   help="copy the reference's garrysmod/data/NAME folder (an add-on's saved state) when the PoC has none (repeatable)")
    p.add_argument("--native", action="append", default=[], metavar="REL",
                   help="copy this install-relative file when the PoC has none, e.g. garrysmod/lua/bin/gmcl_x_win64.dll (repeatable)")
    p.add_argument("--exclude-mod", action="append", default=[], help="a mod folder to leave out (repeatable)")
    p.add_argument("--copy-linked-mods", action="store_true",
                   help="copy what a linked mod folder points to, file by file, leaving out every link inside it")
    p.add_argument("--save", help="save name under garrysmod/saves, without .gms")
    p.add_argument("--map", help="<workshop id>:<map name>: extract maps/<map>.bsp from that Workshop item")
    sub.add_parser("restore")
    args = parser.parse_args(argv)
    try:
        result = prepare(args) if args.action == "prepare" else restore(args)
    except Failure as error:
        print(f"poc_parity: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
