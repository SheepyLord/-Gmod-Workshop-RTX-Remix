"""Snapshot an install before the native loader goes into it, and roll it back with one command.

`snapshot` records what the loader and a test session can change in a game install: every file
directly inside the folders packages and sessions write to (the root, garrysmod, garrysmod/cfg,
bin/win64, garrysmod/lua/bin) that no Steam depot lists, by copy (the user's DXVK d3d9.dll and
vulkan-1.dll, the MMD Hot Loader and Jolt files, configs, logs, databases), and the user's loader
allowlist native-loader/config.json; the entries of those folders and of garrysmod/addons,
garrysmod/data and crashes, each with its kind (file, folder or link); size and time of every file
below garrysmod/data and garrysmod/settings; and GMod's shared registry settings with the export's
SHA-256. It refuses a Steam-managed install whose depot manifests it cannot read (--no-depot-check
overrides that) and a snapshot folder on another volume. `rollback` first checks every saved copy
and stops, changing nothing, if one is damaged. Then it uninstalls the loader, moves every entry that
was not there before, or is now of another kind (a folder replaced by a link), into the snapshot's
debris folder (a rename: links move as links and are never followed; nothing is ever deleted, and an
entry that cannot be moved stays where it is and is reported), writes back every kept file that
changed (never through a link, never over a file a Steam depot lists), makes the registry key equal
to the export again (pruning only after a verified import), and checks the listings, the kept files,
the registry and Steam's depot files. See field_snapshot.py.md.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as _dt
import hashlib
import json
import msvcrt
import os
import re
import shutil
import subprocess
import sys
from ctypes import wintypes
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools" / "steam"))
from steam_manifest import locate_install, parse_manifest  # noqa: E402
from verify_install import verify as verify_depots  # noqa: E402

SCHEMA = 3
DEFAULT_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod")
REGISTRY_KEY = r"HKCU\Software\Valve\Source\garrysmod"
# Folders whose files (directly inside) are kept by copy, unless a Steam depot lists them.
KEPT = (".", "garrysmod", "garrysmod/cfg", "bin/win64", "garrysmod/lua/bin")
# Kept by copy even when a depot lists them (Steam's user-config files) or when absent (then a new
# one is moved out by rollback). native-loader/config.json is the user's allowlist: the uninstaller
# that rollback runs removes native-loader with it, and a session may rewrite it.
VOLATILE = ("garrysmod/cfg/config.cfg", "garrysmod/cfg/client.vdf", "garrysmod/cfg/server.vdf", "garrysmod/cfg/autoexec.cfg",
            "garrysmod/cfg/mountdepots.txt", "garrysmod/cfg/addonnomount.txt", "user.conf", "rtx.conf", "dxvk.conf", "imgui.ini",
            "native-loader/config.json")
# Folders whose entries (names and kinds) must match again after rollback; a new entry is moved to
# the debris folder.
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


class LinkedPath(OSError):
    """A write that would have gone through a link."""


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


def kind(path: Path) -> str | None:
    """"link", "folder" or "file" for what is at path (a link is never followed), or None."""
    if is_link(path):
        return "link"
    if path.is_dir():
        return "folder"
    return "file" if os.path.lexists(path) else None


def listing(base: Path) -> dict[str, str | None] | None:
    """{entry name: kind} of a folder, or None when there is no folder."""
    if not base.is_dir():
        return None
    return {entry.name: kind(entry) for entry in sorted(base.iterdir())}


def linked_component(root: Path, rel: str) -> str | None:
    """The first link among the install root and the components of rel below it ("." for the root),
    or None when each one that exists is an ordinary folder or file."""
    if is_link(root):
        return "."
    path, parts = root, PurePosixPath(rel).parts
    for index, part in enumerate(parts):
        path = path / part
        if is_link(path):
            return "/".join(parts[:index + 1])
    return None


def volume(path: Path) -> int:
    """The volume a path is on, or would be created on: os.stat's st_dev of the path or of its nearest
    existing parent (links followed, so a folder linked to another drive counts as that drive)."""
    path = Path(os.path.abspath(path))
    while not os.path.exists(path) and path.parent != path:
        path = path.parent
    return os.stat(path).st_dev


def free_name(target: Path) -> Path:
    """target, or the first of target.1, target.2, ... that nothing has taken."""
    candidate, number = target, 0
    while os.path.lexists(candidate):
        number += 1
        candidate = target.with_name(f"{target.name}.{number}")
    return candidate


def move_out(path: Path, target: Path) -> Path:
    """Moves a new entry to target in the debris folder, or to target.1, target.2, ... when that name
    is taken. A rename, so a link moves as a link. Returns where the entry went. Never deletes: when
    the rename fails (another volume, a file in use), OSError is raised and the entry stays put."""
    target.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(100):
        destination = free_name(target)
        try:
            os.rename(path, destination)
            return destination
        except FileExistsError:
            continue  # taken since free_name looked
    raise OSError(f"no free name for {target.name} in {target.parent}")


_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_kernel32.GetFinalPathNameByHandleW.argtypes = [wintypes.HANDLE, wintypes.LPWSTR, wintypes.DWORD, wintypes.DWORD]
_kernel32.GetFinalPathNameByHandleW.restype = wintypes.DWORD


def final_path(descriptor: int) -> str:
    """The path Windows resolved an open file to, through every link on the way."""
    size = 1024
    while True:
        buffer = ctypes.create_unicode_buffer(size)
        length = _kernel32.GetFinalPathNameByHandleW(msvcrt.get_osfhandle(descriptor), buffer, size, 0)
        if not length:
            raise ctypes.WinError(ctypes.get_last_error())
        if length < size:
            break
        size = length + 1
    path = buffer.value
    if path.startswith("\\\\?\\UNC\\"):
        return "\\\\" + path[8:]
    return path[4:] if path.startswith("\\\\?\\") else path


def write_in_place(copy: Path, root: Path, rel: str) -> None:
    """Writes a saved copy over root/rel in place (a hard-linked file stays linked), creating missing
    folders as ordinary ones. Never through a link: each folder on the way must be an ordinary one,
    and the opened file must resolve to root/rel itself before anything is written."""
    parts = PurePosixPath(rel).parts
    folder = root
    for part in parts[:-1]:
        folder = folder / part
        try:
            os.mkdir(folder)
        except FileExistsError:
            pass
        if is_link(folder) or not folder.is_dir():
            raise LinkedPath(f"{folder.relative_to(root).as_posix()} is a link or not a folder")
    path = root / rel
    flags = os.O_RDWR | os.O_BINARY | os.O_NOINHERIT
    created = False
    try:
        descriptor = os.open(path, flags)  # no truncation before the check below
    except FileNotFoundError:
        descriptor, created = os.open(path, flags | os.O_CREAT | os.O_EXCL), True
    with open(descriptor, "r+b") as target:
        where = final_path(descriptor)
        if os.path.normcase(where) != os.path.normcase(os.path.join(os.path.abspath(root), *parts)):
            raise LinkedPath(f"it opened as {where}, through a link; nothing was written"
                             + (" (an empty file was created there)" if created else ""))
        target.truncate(0)
        with open(copy, "rb") as source:
            shutil.copyfileobj(source, target, 1 << 20)
    shutil.copystat(copy, path)


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


def steam_manager(root: Path) -> str | None:
    """The app manifest (appmanifest_*.acf in the library's steamapps folder) whose installdir is this
    install's folder, or None when Steam does not manage the install."""
    if root.parent.name.lower() != "common" or root.parent.parent.name.lower() != "steamapps":
        return None
    for acf in sorted(root.parent.parent.glob("appmanifest_*.acf")):
        found = re.search(r'"installdir"\s+"([^"\r\n]*)"', acf.read_text(encoding="utf-8", errors="replace"), re.IGNORECASE)
        if found and found.group(1).lower() == root.name.lower():
            return acf.name
    return None


def depot_inventory(root: Path, manifests_from: str | None) -> tuple[dict[str, bool] | None, list[Path], str]:
    """({lower-case path: user-config flag} of every file Steam's depots list for the install, the
    manifests, ""), or (None, [], why not) when they cannot be read."""
    try:
        manifests = list(locate_install(manifests_from or root).manifests)
        if not manifests:
            raise ValueError("the app manifest lists no installed depot")
        files: dict[str, bool] = {}
        for path in manifests:
            manifest = parse_manifest(path)
            if manifest.filenames_encrypted:
                raise ValueError(f"{path} has encrypted file names")
            files.update((f.path.replace("\\", "/").lower(), f.is_userconfig) for f in manifest.files if not f.is_dir)
        return files, manifests, ""
    except Exception as error:  # whatever stops them being read leaves the depot check undone
        return None, [], str(error) or type(error).__name__


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
    lines = text.lstrip("\ufeff").split("\r\n")
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
    if volume(folder) != volume(root):
        raise Failure("the snapshot folder must be on the install's volume: rollback renames what a session added into it, "
                      "and a rename cannot cross volumes")
    if game_running(root):
        raise Failure("a game from this install is running")
    manager = steam_manager(root)
    inventory, why = None, "--no-depot-check"
    if not args.no_depot_check:
        inventory, _, why = depot_inventory(root, args.manifests_from)
        if inventory is None and (manager or args.manifests_from):
            source = f"Steam manages {root} ({manager})" if manager else f"--manifests-from {args.manifests_from} was given"
            raise Failure(f"{source}, but its depot manifests cannot be read: {why}. Without them the snapshot cannot tell "
                          "Steam's files from yours. Let Steam finish updating or verifying the game so it caches them, or "
                          "pass --no-depot-check (recorded in the snapshot; its rollback never reports clean unless the "
                          "manifests can be read by then).")
    key_exists = subprocess.run(["reg", "query", args.registry_key], capture_output=True).returncode == 0
    folder.mkdir(parents=True, exist_ok=True)
    state: dict = {"schema": SCHEMA, "root": str(root), "taken": stamp(), "manifests_from": args.manifests_from,
                   "steam_managed": manager, "depot_check": inventory is not None, "no_depot_check": bool(args.no_depot_check),
                   "kept": {}, "listed": {}, "watched": {}, "loader_paths": {},
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
                if inventory is None or name.lower() not in inventory:
                    names.add(name)
    for rel in sorted(names):
        path, found = root / rel, kind(root / rel)
        if found is None:
            state["kept"][rel] = None
            continue
        if found != "file":
            continue  # a link or folder in a kept file's place: its listing records its kind
        size = path.stat().st_size
        entry = {"sha256": sha256(path), "size": size, "copied": size <= MAX_COPY}
        if entry["copied"]:
            copy = folder / "files" / rel
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, copy)
            if sha256(copy) != entry["sha256"]:
                raise Failure(f"{rel} changed while it was copied; close what writes it and snapshot into a new folder")
        if inventory is not None and inventory.get(rel.lower()) is False:
            entry["steam"] = True  # a depot file, not a user-config one: rollback never writes it back
        state["kept"][rel] = entry
    for rel in LISTED:
        state["listed"][rel] = listing(root / rel)
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
            "registry_exported": state["registry"]["existed"], "steam_managed": manager,
            "depot_check": state["depot_check"], "no_depot_check": state["no_depot_check"]}


def rollback(args) -> dict:
    folder = Path(args.snapshot)
    if not (folder / "snapshot.json").is_file():
        raise Failure(f"{folder} holds no snapshot.json")
    state = json.loads((folder / "snapshot.json").read_text(encoding="utf-8"))
    schema = state.get("schema")
    if schema != SCHEMA:
        age = "a newer" if isinstance(schema, int) and schema > SCHEMA else "an older"
        raise Failure(f"the snapshot was written by {age} field_snapshot.py (schema {schema}); this one rolls back schema "
                      f"{SCHEMA} only, which records the entry kinds and hashes a safe rollback needs. Nothing was changed: "
                      "roll it back with the field_snapshot.py that took it, or take a new snapshot")
    root = Path(state["root"])
    if not root.is_dir():
        raise Failure(f"{root} is not a folder")
    if game_running(root):
        raise Failure("a game from this install is running")
    if volume(folder) != volume(root):
        raise Failure("the snapshot folder is no longer on the install's volume, so what a session added cannot be renamed "
                      "into it; move it back first. Nothing was changed")
    manager = steam_manager(root) or state["steam_managed"]
    depots_expected = bool(manager or state["manifests_from"])
    inventory, manifests, why = depot_inventory(root, state["manifests_from"])

    def unwritable(rel: str, info: dict) -> str | None:
        """Why a kept file must not be written back, or None."""
        if info.get("steam") or (inventory is not None and inventory.get(rel.lower()) is False):
            return "steam"  # Steam's: the depot check below verifies it instead
        if inventory is None and depots_expected and not state["depot_check"] and rel not in VOLATILE:
            return ("not restored: neither the snapshot nor this rollback could read the depot manifests, so it may be "
                    "Steam's file; run rollback again once Steam has cached them")
        return None

    # Every saved copy that may be written back is checked before anything changes (R1-013).
    damaged = []
    for rel, info in state["kept"].items():
        if not info or not info["copied"] or unwritable(rel, info):
            continue
        copy = folder / "files" / rel
        if not copy.is_file():
            damaged.append(f"{rel}: the copy is missing")
        elif copy.stat().st_size != info["size"]:
            damaged.append(f"{rel}: the copy has {copy.stat().st_size} bytes, not {info['size']}")
        elif sha256(copy) != info["sha256"]:
            damaged.append(f"{rel}: the copy's SHA-256 is not the recorded one")
    if damaged:
        raise Failure(f"{len(damaged)} saved copies are damaged, so nothing was changed: " + "; ".join(damaged[:REPORT_LIMIT]))

    report: dict = {"uninstall": None, "debris": None, "moved": [], "moved_as": {}, "left_in_place": {}, "restored": [],
                    "steam_files_not_restored": [], "errors": [], "registry": None, "listing_differences": {},
                    "kept_differences": [], "watched": {}, "steam_managed": manager, "depot_check": inventory is not None,
                    "depot_check_skipped": None if inventory is not None else why, "no_depot_check": state["no_depot_check"],
                    "verify": None}
    if (root / "bin/win64/winmm.dll").exists() and not state["loader_paths"]["bin/win64/winmm.dll"]:
        result = powershell("-ExecutionPolicy", "Bypass", "-File", str(REPO / "tools" / "uninstall-loader.ps1"),
                            "-GameRoot", str(root), "-Config", args.config, "-RemoveConfig", "-AllowSteamManaged")
        report["uninstall"] = result.returncode
        if result.returncode != 0:
            raise Failure("uninstall-loader.ps1 failed: " + (result.stdout + result.stderr)[-1500:])
    debris = free_name(folder.resolve() / "debris" / stamp())
    report["debris"] = str(debris)

    def take_out(path: Path) -> bool:
        """Moves a new entry into the debris folder; one inside a link, or one the rename fails for,
        stays where it is and is reported."""
        rel = path.relative_to(root).as_posix()
        linked = linked_component(root, PurePosixPath(rel).parent.as_posix())
        if linked is not None:
            report["left_in_place"][rel] = f"inside the link {linked}, which is never followed"
            return False
        try:
            where = move_out(path, debris / rel)
        except OSError as error:
            report["left_in_place"][rel] = f"could not be moved: {error}"
            return False
        report["moved"].append(rel)
        if where != debris / rel:
            report["moved_as"][rel] = where.relative_to(debris).as_posix()
        return True

    # 1. Entries that are new in the listed folders, or of another kind than before (a folder
    # replaced by a link moves out as a link), shallowest folders first; a listed folder (or link) that
    # was not there goes as a whole. Then kept files that were not there (native-loader/config.json).
    for rel in sorted(state["listed"], key=lambda r: len(PurePosixPath(r).parts)):
        before, base = state["listed"][rel], root / rel
        if before is None:
            if rel != "." and kind(base) in ("folder", "link"):
                take_out(base)
            continue
        for entry in sorted(base.iterdir()) if base.is_dir() else ():
            if before.get(entry.name) != kind(entry):
                take_out(entry)
    for rel, info in state["kept"].items():
        if info is None and os.path.lexists(root / rel):
            take_out(root / rel)
    # 2. Files and folders that are new below the watched folders (inside entries that were there
    # before); a new folder goes as a whole.
    for rel, before in state["watched"].items():
        now = tree_stats(root / rel)
        taken: list[str] = []
        for name in sorted(set(now) - set(before)):
            if not any(name.startswith(prefix) for prefix in taken):
                take_out(root / rel / name.rstrip("/"))
                if name.endswith("/"):
                    taken.append(name)
    # 3. Kept files that changed: written back in place, so a hard-linked file stays linked; never
    # through a link, and never over Steam's own files.
    for rel, info in state["kept"].items():
        if not info:
            continue
        path = root / rel
        now = kind(path)
        if now == "file" and sha256(path) == info["sha256"]:
            continue
        reason = unwritable(rel, info)
        if reason == "steam":
            report["steam_files_not_restored"].append(rel)
            continue
        if reason:
            report["errors"].append(f"{rel}: {reason}")
            continue
        if not info["copied"]:
            report["errors"].append(f"{rel}: changed, and too large to have been copied")
            continue
        if now not in (None, "file") and not take_out(path):
            continue  # a folder or link in its place that could not be moved (see left_in_place)
        linked = linked_component(root, PurePosixPath(rel).parent.as_posix())
        if linked is not None:
            report["errors"].append(f"{rel}: not restored, because {linked} is a link (never written through)")
            continue
        try:
            write_in_place(folder / "files" / rel, root, rel)
            report["restored"].append(rel)
        except OSError as error:
            report["errors"].append(f"{rel}: not restored: {error}")
    # 4. The registry key, exactly as exported.
    report["registry"] = restore_registry(folder, state["registry"])
    # 5. Checks.
    for rel, names in state["listed"].items():
        now = listing(root / rel)
        if now != names:
            old, new = names or {}, now or {}
            difference = {"added": sorted(set(new) - set(old)), "missing": sorted(set(old) - set(new)),
                          "changed": sorted(name for name in set(old) & set(new) if old[name] != new[name])}
            if (now is None) != (names is None):
                difference["folder"] = "missing" if now is None else "present, absent at the snapshot"
            report["listing_differences"][rel] = difference
    for rel, info in state["kept"].items():
        path = root / rel
        if info is None:
            if os.path.lexists(path):
                report["kept_differences"].append(f"{rel}: present, absent at the snapshot")
        elif rel in report["steam_files_not_restored"]:
            continue  # Steam's file: the depot check verifies it
        elif kind(path) is None:
            report["kept_differences"].append(f"{rel}: missing")
        elif kind(path) != "file":
            report["kept_differences"].append(f"{rel}: a {kind(path)}, not a file")
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
    verified = True
    if inventory is not None:
        found = verify_depots(root, manifests)
        failures = {key: found[key] for key in ("missing", "size_mismatch", "hash_mismatch")}
        report["verify"] = {"ok": found["ok"], **{key: value[:REPORT_LIMIT] for key, value in failures.items()}}
        verified = not any(failures.values())
    report["clean"] = (not report["listing_differences"] and not report["kept_differences"] and not report["errors"]
                       and not report["left_in_place"] and report["registry"]["error"] is None
                       and report["registry"]["differences"] == [] and verified
                       and (report["depot_check"] or not depots_expected)
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
    s.add_argument("--no-depot-check", action="store_true",
                   help="snapshot without reading Steam's depot manifests, even when Steam manages the install (recorded; "
                        "its rollback is never clean unless it can read them)")
    r = sub.add_parser("rollback")
    r.add_argument("--config", default="Release", choices=["Debug", "Release"], help="build whose uninstaller identity to use")
    args = parser.parse_args(argv)
    try:
        result = snapshot(args) if args.action == "snapshot" else rollback(args)
    except (Failure, OSError, ValueError) as error:
        print(f"field_snapshot: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=1))
    return 0 if args.action == "snapshot" or result["clean"] else 1


if __name__ == "__main__":
    sys.exit(main())
