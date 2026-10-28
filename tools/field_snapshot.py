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
GAME_CHECK = ("$ErrorActionPreference = 'Stop'; try { Get-Process -Name gmod -ErrorAction SilentlyContinue | "
              "ForEach-Object { $_.Path }; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 3 }")


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


def powershell_env() -> dict[str, str]:
    """This environment without PSModulePath, for a child Windows PowerShell, which then builds its own
    module path. Inherited from PowerShell 7, the variable makes 5.1 find 7's modules first and fail to
    load cmdlets such as Get-FileHash (R1-029)."""
    return {name: value for name, value in os.environ.items() if name.upper() != "PSMODULEPATH"}


def powershell(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["powershell", "-NoProfile", *args], capture_output=True, text=True, errors="replace",
                          env=powershell_env())


def game_running(root: Path) -> bool:
    """Whether a gmod.exe from this install runs. A check that cannot run raises Failure."""
    done = powershell("-Command", GAME_CHECK)
    if done.returncode != 0:
        raise Failure("could not check whether the game is running: " + (done.stdout + done.stderr).strip()[-500:])
    prefix = os.path.join(os.path.normcase(str(root)), "")  # GarrysMod must not match GarrysMod_PoC
    return any(os.path.normcase(line.strip()).startswith(prefix) for line in done.stdout.splitlines() if line.strip())


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

REG_HEADER = "Windows Registry Editor Version 5.00"
REG_ROOTS = {"HKCU": "HKEY_CURRENT_USER", "HKLM": "HKEY_LOCAL_MACHINE", "HKCR": "HKEY_CLASSES_ROOT", "HKU": "HKEY_USERS",
             "HKCC": "HKEY_CURRENT_CONFIG"}


class RegParseError(ValueError):
    pass


def reg_name(key: str) -> str:
    return key.replace("HKEY_CURRENT_USER", "HKCU", 1)


def reg_full(key: str) -> str:
    """A key as `reg export` writes it: HKCU\\... becomes HKEY_CURRENT_USER\\..."""
    head, sep, rest = key.partition("\\")
    return REG_ROOTS.get(head.upper(), head) + sep + rest


def holds_key(keys: dict, key: str) -> bool:
    return reg_full(key).upper() in {name.upper() for name in keys}


def reg_export(key: str, target: Path) -> bool:
    return subprocess.run(["reg", "export", key, str(target), "/y"], capture_output=True, text=True).returncode == 0


def _quoted(lines: list[str], index: int, line: str) -> tuple[str, str, str, int]:
    """Reads the quoted string that opens line (it may run over several lines: a value holding a line
    break). Returns (its text with escapes undone, its text as written, the rest of the line it ends
    on, the index of the line after that one)."""
    text, raw, position = [], ['"'], 1
    while True:
        if position >= len(line):
            if index >= len(lines):
                raise RegParseError("a quoted string runs past the end of the file")
            text.append("\r\n")
            raw.append("\r\n")
            line, position, index = lines[index], 0, index + 1
        elif line[position] == "\\" and position + 1 < len(line):
            text.append(line[position + 1])
            raw.append(line[position:position + 2])
            position += 2
        elif line[position] == '"':
            raw.append('"')
            return "".join(text), "".join(raw), line[position + 1:], index
        else:
            text.append(line[position])
            raw.append(line[position])
            position += 1


def read_reg(path: Path) -> dict[str, dict[str, str]]:
    """Keys and values of a `reg export` file: {key: {value name ("@" = default): data as written}}.
    Strict, so a damaged or cut-off export is never read as a smaller key: anything but the header,
    key lines and whole values (strings may run over lines, hex data goes on after a trailing
    backslash) raises RegParseError."""
    try:
        text = path.read_bytes().decode("utf-16")
    except UnicodeDecodeError as error:
        raise RegParseError(f"not UTF-16 text ({error})") from None
    lines = text.lstrip("﻿").split("\r\n")
    if lines[0] != REG_HEADER:
        raise RegParseError(f"the first line is not {REG_HEADER!r}")
    if lines[-1] != "":
        raise RegParseError("the last line breaks off")
    keys: dict[str, dict[str, str]] = {}
    current = None
    index = 1
    while index < len(lines):
        line, number = lines[index], index + 1
        index += 1
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            keys.setdefault(current, {})
            continue
        if current is None:
            raise RegParseError(f"line {number}: a value before the first key")
        if line.startswith("@="):
            name, rest = "@", line[2:]
        elif line.startswith('"'):
            name, _, rest, index = _quoted(lines, index, line)
            if not rest.startswith("="):
                raise RegParseError(f"line {number}: no '=' after the value name")
            rest = rest[1:]
        else:
            raise RegParseError(f"line {number}: neither a key nor a value: {line[:80]!r}")
        if rest.startswith('"'):
            _, data, after, index = _quoted(lines, index, rest)
            if after:
                raise RegParseError(f"line {number}: text after a quoted value")
        else:
            data = rest
            while data.endswith("\\"):  # hex data continues on the next, indented line
                if index >= len(lines) or not lines[index].startswith(" ") or not lines[index].strip():
                    raise RegParseError(f"line {number}: hex data breaks off")
                data = data[:-1] + lines[index].strip()
                index += 1
            if not data or data.endswith(","):
                raise RegParseError(f"line {number}: incomplete value data")
        keys[current][name] = data
    return keys


def reg_differences(before: dict, after: dict) -> list[str]:
    """What differs between two exports. Key and value names compare without case, as in Windows."""
    def fold(keys: dict) -> dict:
        return {key.upper(): (key, {name.upper(): (name, data) for name, data in values.items()}) for key, values in keys.items()}
    old, new = fold(before), fold(after)
    found = []
    for key in sorted(set(old) | set(new)):
        if key not in new:
            found.append(f"missing key {old[key][0]}")
        elif key not in old:
            found.append(f"extra key {new[key][0]}")
        else:
            was, now = old[key][1], new[key][1]
            for name in sorted(set(was) | set(now)):
                if was.get(name, (0, None))[1] != now.get(name, (0, None))[1]:
                    label = (was.get(name) or now.get(name))[0]
                    found.append(f"{old[key][0]} {label}: {was.get(name, (0, None))[1]} -> {now.get(name, (0, None))[1]}")
    return found


def restore_registry(folder: Path, info: dict) -> dict:
    """Makes the key equal to the snapshot's export: imports it, then deletes the values and subkeys
    it does not have. Nothing is imported unless registry.reg has its recorded SHA-256 and parses, and
    nothing is pruned unless the import succeeded and the key's export after it parsed. "error" says
    why the key was left as it was (the rollback is then not clean)."""
    key = info["key"]
    result: dict = {"key": key, "error": None, "pruned": [], "differences": []}
    if not info["existed"]:
        if subprocess.run(["reg", "query", key], capture_output=True).returncode == 0:
            subprocess.run(["reg", "delete", key, "/f"], capture_output=True)
            result["deleted_key"] = True
        still = subprocess.run(["reg", "query", key], capture_output=True).returncode == 0
        result["differences"] = ["the key exists and did not before"] if still else []
        return result

    def failed(message: str) -> dict:
        result["error"] = message
        result["differences"] = None
        return result

    snapshot_file = folder / "registry.reg"
    if not snapshot_file.is_file() or sha256(snapshot_file) != info.get("sha256"):
        return failed("registry.reg is missing or does not have the SHA-256 snapshot.json records; the key was left as it is")
    try:
        before = read_reg(snapshot_file)
    except RegParseError as error:
        return failed(f"registry.reg cannot be read ({error}); the key was left as it is")
    if not holds_key(before, key):
        return failed("registry.reg does not hold the key; the key was left as it is")
    done = subprocess.run(["reg", "import", str(snapshot_file)], capture_output=True, text=True)
    result["import_exit"] = done.returncode
    if done.returncode != 0:
        return failed(f"reg import exited {done.returncode} ({(done.stdout + done.stderr).strip()[-300:]}); nothing was pruned")
    current_file = folder / "registry-after.reg"
    try:
        if not reg_export(key, current_file):
            return failed("the key could not be exported after the import; nothing was pruned")
        now = read_reg(current_file)
    except RegParseError as error:
        return failed(f"the key's export after the import cannot be read ({error}); nothing was pruned")
    if not holds_key(now, key):
        return failed("the key's export after the import does not hold the key; nothing was pruned")
    known = {name.upper(): {value.upper() for value in values} for name, values in before.items()}
    for name in sorted(now, key=len, reverse=True):  # deepest first
        if name.upper() not in known:
            subprocess.run(["reg", "delete", reg_name(name), "/f"], capture_output=True)
            result["pruned"].append(name)
            continue
        for value in sorted(now[name]):
            if value.upper() not in known[name.upper()]:
                selector = ["/ve"] if value == "@" else ["/v", value]
                subprocess.run(["reg", "delete", reg_name(name), *selector, "/f"], capture_output=True)
                result["pruned"].append(f"{name} {value}")
    try:
        if not reg_export(key, current_file):
            return failed("the key could not be exported to check it after pruning")
        result["differences"] = reg_differences(before, read_reg(current_file))
    except RegParseError as error:
        return failed(f"the key's export after pruning cannot be read ({error})")
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
                   "verify": depot is not None, "kept": {}, "listed": {}, "watched": {}, "loader_paths": {},
                   "registry": {"key": args.registry_key, "existed": key_exists}}
    # A key that exists but cannot be exported must not later count as absent (rollback deletes those);
    # one rollback could not read back would leave it unrestorable.
    if key_exists:
        export = folder / "registry.reg"
        if not reg_export(args.registry_key, export):
            raise Failure(f"could not export {args.registry_key}")
        try:
            if not holds_key(read_reg(export), args.registry_key):
                raise RegParseError("it does not hold the key")
        except RegParseError as error:
            raise Failure(f"the export of {args.registry_key} cannot be read back ({error}), so rollback could not restore it")
        state["registry"].update(sha256=sha256(export), size=export.stat().st_size)
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
        result = powershell("-ExecutionPolicy", "Bypass", "-File", str(REPO / "tools" / "uninstall-loader.ps1"),
                            "-GameRoot", str(root), "-Config", args.config, "-RemoveConfig", "-AllowSteamManaged")
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
                       and report["registry"]["error"] is None and report["registry"]["differences"] == []
                       and report["verify_exit"] in (0, None)
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
