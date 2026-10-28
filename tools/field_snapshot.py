"""Snapshot an install before the native loader goes into it, and roll it back with one command.

`snapshot` records what the loader and a test session can change in a game install: every file
directly inside the folders packages and sessions write to (the root, garrysmod, garrysmod/cfg,
bin/win64, garrysmod/lua/bin) that no Steam depot lists, by copy (the user's DXVK d3d9.dll and
vulkan-1.dll, the MMD Hot Loader and Jolt files, configs, logs, databases); the entry names of those
folders and of garrysmod/addons, garrysmod/data and crashes; size and time of every file below
garrysmod/data and garrysmod/settings; and GMod's shared registry settings. `rollback` uninstalls the
loader, moves every entry that was not there before into the snapshot's debris folder (links are
moved, never followed), puts back every kept file that changed, makes the registry key equal to the
export again, and checks the listings, the kept files, the registry and Steam's depot files. See
field_snapshot.py.md.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools" / "steam"))
from steam_manifest import locate_install, parse_manifest  # noqa: E402

SCHEMA = 2
DEFAULT_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod")
REGISTRY_KEY = r"HKCU\Software\Valve\Source\garrysmod"
# Folders whose files (directly inside) are kept by copy, unless a Steam depot lists them.
KEPT = (".", "garrysmod", "garrysmod/cfg", "bin/win64", "garrysmod/lua/bin")
# Kept by copy even when a depot lists them (Steam's user-config files) or when absent (then a new
# one is moved out by rollback).
VOLATILE = ("garrysmod/cfg/config.cfg", "garrysmod/cfg/client.vdf", "garrysmod/cfg/server.vdf", "garrysmod/cfg/autoexec.cfg",
            "garrysmod/cfg/mountdepots.txt", "garrysmod/cfg/addonnomount.txt", "user.conf", "rtx.conf", "dxvk.conf", "imgui.ini")
# Folders whose entry names must match again after rollback; a new entry is moved to the debris folder.
LISTED = KEPT + ("garrysmod/addons", "garrysmod/data", "crashes")
# Below these, every file's size and time is recorded (too many to copy): new files are moved out,
# changed and missing ones are reported.
WATCHED = ("garrysmod/data", "garrysmod/settings")
# The loader's own paths, reported by snapshot; a bootstrap that was absent is uninstalled by rollback.
LOADER_PATHS = ("bin/win64/winmm.dll", "native-loader", "rtx-remix", "garrysmod/data/native-loader")
MAX_COPY = 2 << 30  # bigger non-depot files are hashed, not copied
REPORT_LIMIT = 200


class Failure(Exception):
    pass


def stamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_link(path: Path) -> bool:
    try:
        return path.is_symlink() or bool(os.lstat(path).st_file_attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT
    except OSError:
        return False


def remove(path: Path) -> None:
    """Deletes a file or a folder tree without following links (rmdir /s does not traverse them)."""
    if is_link(path) or path.is_file():
        if path.is_dir():
            os.rmdir(path)  # the link itself
        else:
            path.unlink()
    elif path.is_dir():
        subprocess.run(["cmd", "/c", "rmdir", "/s", "/q", str(path)], check=True)


def move_out(path: Path, target: Path) -> str:
    """Moves a new entry into the debris folder (a rename: a link moves as a link); deletes it when the
    debris folder is on another volume."""
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.rename(path, target)
        return "moved"
    except OSError:
        remove(path)
        return "deleted"


def game_running(root: Path) -> bool:
    out = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "Get-Process gmod -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }"], capture_output=True, text=True).stdout
    prefix = os.path.join(os.path.normcase(str(root)), "")  # GarrysMod must not match GarrysMod_PoC
    return any(os.path.normcase(line.strip()).startswith(prefix) for line in out.splitlines() if line.strip())


def depot_files(root: Path, manifests_from: str | None) -> set[str] | None:
    """Lower-case paths of every file Steam's depots list for the install, or None when it is not a
    Steam install (then nothing is excluded from copying and the depot check is skipped)."""
    try:
        manifests = locate_install(manifests_from or root).manifests
    except FileNotFoundError:
        return None
    listed: set[str] = set()
    for path in manifests:
        listed.update(f.path.replace("\\", "/").lower() for f in parse_manifest(path).files)
    return listed


def tree_stats(base: Path) -> dict[str, list[int]]:
    """{path relative to base: [size, mtime_ns]} for every file below base; folders end in "/" with
    [-1, 0], links to folders with [-2, 0] (never followed)."""
    stats: dict[str, list[int]] = {}
    if not base.is_dir():
        return stats
    for folder, dirs, files in os.walk(base):
        rel = Path(folder).relative_to(base).as_posix()
        prefix = "" if rel == "." else rel + "/"
        links = [d for d in dirs if is_link(Path(folder) / d)]
        dirs[:] = [d for d in dirs if d not in links]
        stats.update({prefix + d + "/": [-2, 0] for d in links})
        stats.update({prefix + d + "/": [-1, 0] for d in dirs})
        for name in files:
            path = Path(folder) / name
            try:
                info = path.stat()
            except OSError:
                continue
            stats[path.relative_to(base).as_posix()] = [info.st_size, info.st_mtime_ns]
    return stats


# ---------------------------------------------------------------- registry

def reg_name(key: str) -> str:
    return key.replace("HKEY_CURRENT_USER", "HKCU", 1)


def reg_export(key: str, target: Path) -> bool:
    return subprocess.run(["reg", "export", key, str(target), "/y"], capture_output=True, text=True).returncode == 0


def read_reg(path: Path) -> dict[str, dict[str, str]]:
    """Keys and values of a `reg export` file: {key: {value name ("@" = default): data as written}}."""
    keys: dict[str, dict[str, str]] = {}
    current = None
    lines = path.read_text(encoding="utf-16").splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].rstrip()
        index += 1
        while line.endswith("\\") and index < len(lines):  # hex data continues on the next line
            line = line[:-1] + lines[index].strip()
            index += 1
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            keys.setdefault(current, {})
        elif current is not None and line.startswith("@="):
            keys[current]["@"] = line[2:]
        elif current is not None and line.startswith('"'):
            position, name = 1, []
            while position < len(line) and line[position] != '"':
                if line[position] == "\\" and position + 1 < len(line):
                    position += 1
                name.append(line[position])
                position += 1
            if line[position + 1:position + 2] == "=":
                keys[current]["".join(name)] = line[position + 2:]
    return keys


def reg_differences(before: dict, after: dict) -> list[str]:
    found = []
    for key in sorted(set(before) | set(after)):
        if key not in after:
            found.append(f"missing key {key}")
        elif key not in before:
            found.append(f"extra key {key}")
        else:
            for name in sorted(set(before[key]) | set(after[key])):
                if before[key].get(name) != after[key].get(name):
                    found.append(f"{key} {name}: {before[key].get(name)} -> {after[key].get(name)}")
    return found


def restore_registry(folder: Path, info: dict) -> dict:
    key = info["key"]
    result: dict = {"key": key}
    if not info["existed"]:
        if subprocess.run(["reg", "query", key], capture_output=True).returncode == 0:
            subprocess.run(["reg", "delete", key, "/f"], capture_output=True)
            result["deleted_key"] = True
        still = subprocess.run(["reg", "query", key], capture_output=True).returncode == 0
        result["differences"] = ["the key exists and did not before"] if still else []
        return result
    snapshot_file = folder / "registry.reg"
    result["import_exit"] = subprocess.run(["reg", "import", str(snapshot_file)], capture_output=True, text=True).returncode
    before = read_reg(snapshot_file)
    current_file = folder / "registry-after.reg"
    if not reg_export(key, current_file):
        result["differences"] = ["the key could not be exported after the import"]
        return result
    now = read_reg(current_file)
    pruned = []
    for name in sorted(now, key=len, reverse=True):  # deepest first
        if name not in before:
            subprocess.run(["reg", "delete", reg_name(name), "/f"], capture_output=True)
            pruned.append(name)
            continue
        for value in sorted(set(now[name]) - set(before[name])):
            selector = ["/ve"] if value == "@" else ["/v", value]
            subprocess.run(["reg", "delete", reg_name(name), *selector, "/f"], capture_output=True)
            pruned.append(f"{name} {value}")
    result["pruned"] = pruned
    reg_export(key, current_file)
    result["differences"] = reg_differences(before, read_reg(current_file))
    return result


# ---------------------------------------------------------------- steps

def snapshot(args) -> dict:
    root, folder = Path(args.root).resolve(), Path(args.snapshot)
    if (folder / "snapshot.json").exists():
        raise Failure(f"{folder} already holds a snapshot")
    if not root.is_dir():
        raise Failure(f"{root} is not a folder")
    if os.path.normcase(str(folder.resolve())).startswith(os.path.join(os.path.normcase(str(root)), "")):
        raise Failure("the snapshot folder must be outside the install")
    if game_running(root):
        raise Failure("a game from this install is running")
    key_exists = subprocess.run(["reg", "query", args.registry_key], capture_output=True).returncode == 0
    depot = depot_files(root, args.manifests_from)
    folder.mkdir(parents=True, exist_ok=True)
    state: dict = {"schema": SCHEMA, "root": str(root), "taken": stamp(), "manifests_from": args.manifests_from,
                   "verify": depot is not None, "kept": {}, "listed": {}, "watched": {}, "loader_paths": {}}
    names = set(VOLATILE)
    for rel in KEPT:
        base = root / rel
        for entry in base.iterdir() if base.is_dir() else ():
            if entry.is_file() and not is_link(entry):
                name = entry.relative_to(root).as_posix()
                if depot is None or name.lower() not in depot:
                    names.add(name)
    for rel in sorted(names):
        path = root / rel
        if not path.is_file():
            state["kept"][rel] = None
            continue
        size = path.stat().st_size
        copied = size <= MAX_COPY
        if copied:
            (folder / "files" / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, folder / "files" / rel)
        state["kept"][rel] = {"sha256": sha256(path), "size": size, "copied": copied}
    for rel in LISTED:
        base = root / rel
        state["listed"][rel] = sorted(p.name for p in base.iterdir()) if base.is_dir() else None
    for rel in WATCHED:
        state["watched"][rel] = tree_stats(root / rel)
    for rel in LOADER_PATHS:
        state["loader_paths"][rel] = (root / rel).exists() or is_link(root / rel)
    # A key that exists but cannot be exported must not later count as absent (rollback deletes those).
    if key_exists and not reg_export(args.registry_key, folder / "registry.reg"):
        raise Failure(f"could not export {args.registry_key}")
    state["registry"] = {"key": args.registry_key, "existed": key_exists}
    (folder / "snapshot.json").write_text(json.dumps(state, indent=1), encoding="utf-8")
    kept = [v for v in state["kept"].values() if v]
    return {"snapshot": str(folder), "root": str(root), "kept_files": len(kept), "kept_bytes": sum(v["size"] for v in kept),
            "not_copied": [k for k, v in state["kept"].items() if v and not v["copied"]],
            "watched_files": {k: len(v) for k, v in state["watched"].items()},
            "loader_paths_present": [k for k, v in state["loader_paths"].items() if v],
            "registry_exported": state["registry"]["existed"], "depot_check": state["verify"]}


def rollback(args) -> dict:
    folder = Path(args.snapshot)
    state = json.loads((folder / "snapshot.json").read_text(encoding="utf-8"))
    if state.get("schema") != SCHEMA:
        raise Failure("the snapshot was written by an older field_snapshot.py")
    root = Path(state["root"])
    if game_running(root):
        raise Failure("a game from this install is running")
    report: dict = {"uninstall": None, "moved": [], "deleted": [], "restored": [], "errors": [], "registry": None,
                    "listing_differences": {}, "kept_differences": [], "watched": {}}
    if (root / "bin/win64/winmm.dll").exists() and not state["loader_paths"]["bin/win64/winmm.dll"]:
        result = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                 str(REPO / "tools" / "uninstall-loader.ps1"), "-GameRoot", str(root), "-Config", args.config,
                                 "-RemoveConfig", "-AllowSteamManaged"], capture_output=True, text=True)
        report["uninstall"] = result.returncode
        if result.returncode != 0:
            raise Failure("uninstall-loader.ps1 failed: " + (result.stdout + result.stderr)[-1500:])
    debris = folder / "debris" / stamp()

    def take_out(path: Path) -> None:
        rel = path.relative_to(root).as_posix()
        try:
            report["moved" if move_out(path, debris / rel) == "moved" else "deleted"].append(rel)
        except (OSError, subprocess.CalledProcessError) as error:
            report["errors"].append(f"{rel}: {error}")

    # 1. Entries that are new in the listed folders, deepest folders first.
    for rel in sorted(state["listed"], key=lambda r: len(Path(r).parts), reverse=True):
        before, base = state["listed"][rel], root / rel
        for entry in sorted(base.iterdir()) if base.is_dir() and not is_link(base) else ():
            if before is None or entry.name not in before:
                take_out(entry)
    # 2. Files and folders that are new below the watched folders (inside entries that were there
    # before); a new folder goes as a whole.
    for rel, before in state["watched"].items():
        now = tree_stats(root / rel)
        taken: list[str] = []
        for name in sorted(set(now) - set(before)):
            if not any(name.startswith(folder) for folder in taken):
                take_out(root / rel / name.rstrip("/"))
                if name.endswith("/"):
                    taken.append(name)
    # 3. Kept files that changed: written back in place, so a hard-linked file stays linked.
    for rel, info in state["kept"].items():
        path = root / rel
        if info is None or (path.is_file() and sha256(path) == info["sha256"]):
            continue
        if not info["copied"]:
            report["errors"].append(f"{rel}: changed, and too large to have been copied")
            continue
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(folder / "files" / rel, path)
            report["restored"].append(rel)
        except OSError as error:
            report["errors"].append(f"{rel}: {error}")
    # 4. The registry key, exactly as exported.
    report["registry"] = restore_registry(folder, state["registry"])
    # 5. Checks.
    for rel, names in state["listed"].items():
        base = root / rel
        now = sorted(p.name for p in base.iterdir()) if base.is_dir() else None
        if now != names:
            report["listing_differences"][rel] = {"added": sorted(set(now or []) - set(names or [])),
                                                   "missing": sorted(set(names or []) - set(now or []))}
    for rel, info in state["kept"].items():
        path = root / rel
        if info is None:
            if path.exists():
                report["kept_differences"].append(f"{rel}: present, absent at the snapshot")
        elif not path.is_file():
            report["kept_differences"].append(f"{rel}: missing")
        elif sha256(path) != info["sha256"]:
            report["kept_differences"].append(f"{rel}: content differs")
    for rel, before in state["watched"].items():
        now = tree_stats(root / rel)
        changed = sorted(name for name in set(now) & set(before) if now[name] != before[name])
        missing = sorted(set(before) - set(now))
        added = sorted(set(now) - set(before))
        report["watched"][rel] = {"changed": len(changed), "missing": len(missing), "added": len(added),
                                  "changed_files": changed[:REPORT_LIMIT], "missing_files": missing[:REPORT_LIMIT],
                                  "added_files": added[:REPORT_LIMIT]}
    if state["verify"]:
        command = [sys.executable, str(REPO / "tools" / "steam" / "verify_install.py"), str(root), "--quiet"]
        if state.get("manifests_from"):
            command += ["--manifests-from", state["manifests_from"]]
        verify = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        report["verify_exit"] = verify.returncode
        report["verify"] = verify.stdout[-800:]
    else:
        report["verify_exit"] = None
    report["clean"] = (not report["listing_differences"] and not report["kept_differences"] and not report["errors"]
                       and not report["registry"]["differences"] and report["verify_exit"] in (0, None)
                       and not any(v["added"] for v in report["watched"].values()))
    (folder / "rollback.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--snapshot", required=True, help="folder holding the snapshot (created by snapshot)")
    sub = parser.add_subparsers(dest="action", required=True)
    s = sub.add_parser("snapshot")
    s.add_argument("--root", default=str(DEFAULT_ROOT), help="the install (default: the field install)")
    s.add_argument("--registry-key", default=REGISTRY_KEY, help="registry key exported and restored (default: GMod's settings)")
    s.add_argument("--manifests-from", help="the Steam install whose depot manifests describe this one (for a copy such as the PoC)")
    r = sub.add_parser("rollback")
    r.add_argument("--config", default="Release", choices=["Debug", "Release"], help="build whose uninstaller identity to use")
    args = parser.parse_args(argv)
    try:
        result = snapshot(args) if args.action == "snapshot" else rollback(args)
    except (Failure, subprocess.CalledProcessError, OSError) as error:
        print(f"field_snapshot: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=1))
    return 0 if args.action == "snapshot" or result["clean"] else 1


if __name__ == "__main__":
    sys.exit(main())
