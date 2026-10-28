"""Drive Garry's Mod sessions on the PoC install for acceptance tests, without anyone at the keyboard.

Installs the bootstrap and a config, launches the game, waits for the map, takes screenshots of the
game window, records the loaded modules, ends the game with a normal "quit" (a test-only server
autorun file that watches a flag in garrysmod/data), collects the logs and uninstalls again. Every
step writes evidence under the folder given with --evidence. See poc_session.py.md.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as _dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_PoC")
FIELD_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod")
MAP_MARKER = re.compile(r"(?m)^Clientside Lua startup!\s*$")


class Failure(Exception):
    pass


# ---------------------------------------------------------------- small helpers

def now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def read_shared(path: Path) -> str:
    """Reads a file the game may hold open for writing (Python opens with read/write sharing)."""
    try:
        with open(path, "rb") as handle:
            return handle.read().decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


def copy_if_present(source: Path, destination: Path) -> bool:
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        with open(source, "rb") as reader, open(destination, "wb") as writer:
            shutil.copyfileobj(reader, writer)
        return True
    except FileNotFoundError:
        return False


def powershell(script: Path, *arguments: str) -> subprocess.CompletedProcess:
    command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), *arguments]
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")


# ---------------------------------------------------------------- Win32 (processes, windows, screenshots)

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
PROCESS_TERMINATE = 0x0001
TH32CS_SNAPPROCESS = 0x2

kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
psapi.EnumProcessModulesEx.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.HMODULE), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.DWORD]
psapi.GetModuleFileNameExW.argtypes = [wintypes.HANDLE, wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.c_void_p), ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD),
                ("szExeFile", wintypes.WCHAR * 260)]


kernel32.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
kernel32.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]


def process_path(pid: int) -> str | None:
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    try:
        size = wintypes.DWORD(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return None
        return buffer.value
    finally:
        kernel32.CloseHandle(handle)


def game_processes(root: Path) -> list[int]:
    """PIDs of every gmod.exe running from this game folder (the game and its Chromium helpers)."""
    target = os.path.normcase(str(root / "bin" / "win64" / "gmod.exe"))
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    pids = []
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(entry)
    try:
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.lower() == "gmod.exe":
                path = process_path(entry.th32ProcessID)
                if path and os.path.normcase(path) == target:
                    pids.append(entry.th32ProcessID)
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return pids


def terminate(pids: list[int]) -> None:
    for pid in pids:
        handle = kernel32.OpenProcess(PROCESS_TERMINATE, False, pid)
        if handle:
            kernel32.TerminateProcess(handle, 1)
            kernel32.CloseHandle(handle)


def modules_of(pid: int) -> list[str]:
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return []
    try:
        count = 2048
        array = (wintypes.HMODULE * count)()
        needed = wintypes.DWORD()
        if not psapi.EnumProcessModulesEx(handle, array, ctypes.sizeof(array), ctypes.byref(needed), 3):
            return []
        result = []
        for index in range(min(count, needed.value // ctypes.sizeof(wintypes.HMODULE))):
            buffer = ctypes.create_unicode_buffer(32768)
            if psapi.GetModuleFileNameExW(handle, array[index], buffer, 32768):
                result.append(buffer.value)
        return result
    finally:
        kernel32.CloseHandle(handle)


WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user32.EnumWindows.argtypes = [WNDENUMPROC, wintypes.LPARAM]
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
user32.GetDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wintypes.HDC]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", ctypes.c_long), ("biHeight", ctypes.c_long),
                ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", ctypes.c_long), ("biYPelsPerMeter", ctypes.c_long),
                ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]


gdi32.GetDIBits.argtypes = [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT, wintypes.UINT, ctypes.c_void_p,
                            ctypes.POINTER(BITMAPINFOHEADER), wintypes.UINT]


def game_window(pid: int) -> int | None:
    found = []

    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(hwnd, title, 256)
            if "Garry's Mod" in title.value:
                found.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(visit), 0)
    return found[0] if found else None


def screenshot(hwnd: int, destination: Path) -> dict:
    """Captures the window's client area through DWM (PrintWindow with PW_RENDERFULLCONTENT), so the
    window need not be in front. Falls back to a screen grab of its rectangle if that comes back black."""
    from PIL import Image, ImageGrab, ImageStat  # Pillow; only needed for screenshots

    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    width, height = rect.right - rect.left, rect.bottom - rect.top
    if width <= 0 or height <= 0:
        raise Failure("the game window has no client area")
    window_dc = user32.GetDC(hwnd)
    memory_dc = gdi32.CreateCompatibleDC(window_dc)
    bitmap = gdi32.CreateCompatibleBitmap(window_dc, width, height)
    previous = gdi32.SelectObject(memory_dc, bitmap)
    method = "PrintWindow"
    try:
        user32.PrintWindow(hwnd, memory_dc, 0x1 | 0x2)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
        header = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
        pixels = ctypes.create_string_buffer(width * height * 4)
        gdi32.GetDIBits(memory_dc, bitmap, 0, height, pixels, ctypes.byref(header), 0)
        image = Image.frombuffer("RGB", (width, height), pixels.raw, "raw", "BGRX", 0, 1)
    finally:
        gdi32.SelectObject(memory_dc, previous)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(memory_dc)
        user32.ReleaseDC(hwnd, window_dc)
    if max(ImageStat.Stat(image).extrema[channel][1] for channel in range(3)) < 8:
        origin = wintypes.POINT(0, 0)
        user32.ClientToScreen(hwnd, ctypes.byref(origin))
        image = ImageGrab.grab(bbox=(origin.x, origin.y, origin.x + width, origin.y + height), all_screens=True)
        method = "screen grab"
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)
    mean = ImageStat.Stat(image).mean
    return {"file": destination.name, "width": width, "height": height, "method": method,
            "mean_rgb": [round(value, 1) for value in mean]}


# ---------------------------------------------------------------- a normal quit through RCON

def rcon(port: int, password: str, command: str, timeout: float = 5.0) -> str:
    """Runs one console command through Source's TCP remote console on this machine. GMod blocks
    "quit" from Lua, so this is how the driver ends a session normally (config written, logs closed)."""
    import socket
    import struct

    def packet(request: int, kind: int, body: str) -> bytes:
        data = struct.pack("<ii", request, kind) + body.encode("ascii") + b"\x00\x00"
        return struct.pack("<i", len(data)) + data

    def receive(sock) -> tuple[int, int, str]:
        header = b""
        while len(header) < 4:
            chunk = sock.recv(4 - len(header))
            if not chunk:
                raise ConnectionError("remote console closed the connection")
            header += chunk
        (size,) = struct.unpack("<i", header)
        data = b""
        while len(data) < size:
            chunk = sock.recv(size - len(data))
            if not chunk:
                raise ConnectionError("remote console closed the connection")
            data += chunk
        request, kind = struct.unpack("<ii", data[:8])
        return request, kind, data[8:-2].decode("utf-8", "replace")

    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.sendall(packet(1, 3, password))  # SERVERDATA_AUTH
        while True:
            request, kind, _ = receive(sock)
            if kind == 2:  # SERVERDATA_AUTH_RESPONSE
                if request == -1:
                    raise PermissionError("remote console refused the password")
                break
        sock.sendall(packet(2, 2, command))  # SERVERDATA_EXECCOMMAND
        try:
            return receive(sock)[2]
        except (OSError, ConnectionError):
            return ""  # "quit" closes the connection before answering


# ---------------------------------------------------------------- steps

def nlctl_path(config: str) -> Path:
    return REPO / "out" / "build" / f"win64-{config.lower()}" / "loader" / "cli" / "nlctl.exe"


def write_config(root: Path, local: list[str], dev: list[str], workshop: list[str], remix: bool, require_insecure: bool) -> dict:
    value = {"schema": 1, "enabled": True,
             "allow": {"workshop": workshop, "local": local, "dev_folders": dev},
             "remix": {"enabled": remix}, "patch_sets": {"require_insecure": require_insecure}}
    target = root / "native-loader" / "config.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, target)
    return value


def step_install(args) -> dict:
    root = Path(args.root)
    if game_processes(root):
        raise Failure("a game from this install is running")
    result = powershell(REPO / "tools" / "install-loader.ps1", "-GameRoot", str(root), "-Config", args.config)
    if result.returncode != 0:
        raise Failure("install-loader.ps1 failed: " + (result.stderr or result.stdout)[-2000:])
    config = write_config(root, args.allow_local, args.allow_dev, args.allow_workshop, args.remix == "on", args.require_insecure == "yes")
    return {"step": "install", "config": config, "installer": result.stdout.strip()[-500:]}


def step_config(args) -> dict:
    config = write_config(Path(args.root), args.allow_local, args.allow_dev, args.allow_workshop, args.remix == "on", args.require_insecure == "yes")
    return {"step": "config", "config": config}


def step_nlctl(args) -> dict:
    command = [str(nlctl_path(args.config)), *args.rest]
    command = [str(Path(args.root)) if part == "{root}" else part for part in command]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return {"step": "nlctl", "command": command[1:], "exit": result.returncode, "stdout": result.stdout[-4000:], "stderr": result.stderr[-2000:]}


def step_run(args) -> dict:
    root = Path(args.root)
    evidence = Path(args.evidence) / args.name
    evidence.mkdir(parents=True, exist_ok=True)
    if game_processes(root):
        raise Failure("a game from this install is already running")
    console = root / "garrysmod" / "console.log"
    if console.exists():
        shutil.move(str(console), str(evidence / "console-before-run.log"))
    remix_log = root / "rtx-remix" / "logs" / "remix-dxvk.log"
    remix_before = remix_log.stat().st_mtime if remix_log.exists() else None
    password = os.urandom(8).hex()
    arguments = ["-game", "garrysmod", "-console", "-windowed", "-w", str(args.width), "-h", str(args.height),
                 "-condebug", "-noworkshop", "-noaddons", "-usercon", "-ip", "127.0.0.1", "-port", str(args.port),
                 *args.extra, "+rcon_password", password, "+maxplayers", str(args.players), "+mat_dxlevel"]
    arguments += ["+map", args.map] if args.map else []
    arguments += args.post
    environment = dict(os.environ)
    environment.pop("NATIVE_LOADER_DISABLE", None)
    record = {"step": "run", "name": args.name, "started": now(), "arguments": arguments}
    began = time.monotonic()
    process = subprocess.Popen([str(root / "bin" / "win64" / "gmod.exe"), *arguments], cwd=str(root), env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record["pid"] = process.pid
    try:
        loaded = False
        while time.monotonic() - began < args.timeout:
            if process.poll() is not None:
                break
            if MAP_MARKER.search(read_shared(console)):
                loaded = True
                break
            time.sleep(0.5)
        record["map_loaded"] = loaded
        record["seconds_to_map"] = round(time.monotonic() - began, 1)
        modules = modules_of(process.pid) if process.poll() is None else []
        record["early_exit"] = process.poll() is not None
        if loaded and process.poll() is None:
            time.sleep(args.settle)
            hwnd = game_window(process.pid)
            shots = []
            for index in range(args.screenshots):
                if hwnd and process.poll() is None:
                    shots.append(screenshot(hwnd, evidence / f"screenshot-{index + 1}.png"))
                    time.sleep(args.shot_interval)
            record["screenshots"] = shots
            modules = modules_of(process.pid) or modules
        write_json(evidence / "modules.json", modules)
        record["d3d9"] = next((m for m in modules if os.path.basename(m).lower() == "d3d9.dll"), None)
        record["stdshader_dx6"] = next((m for m in modules if os.path.basename(m).lower() == "stdshader_dx6.dll"), None)
        if process.poll() is None:
            try:
                rcon(args.port, password, "quit")
                record["quit"] = "rcon"
            except (OSError, ConnectionError, PermissionError) as error:
                record["quit"] = f"rcon failed: {error}"
            try:
                process.wait(timeout=args.quit_timeout)
                record["exit"] = process.returncode
                record["normal_quit"] = record["quit"] == "rcon"
            except subprocess.TimeoutExpired:
                terminate(game_processes(root))
                process.wait(timeout=30)
                record["exit"] = "terminated"
                record["normal_quit"] = False
        else:
            record["exit"] = process.returncode
            record["normal_quit"] = False
        time.sleep(2)
        leftovers = game_processes(root)
        if leftovers:
            terminate(leftovers)
            record["terminated_helpers"] = leftovers
    finally:
        if process.poll() is None:
            terminate(game_processes(root))
    text = read_shared(console)
    copy_if_present(console, evidence / "console.log")
    dxlevel = re.search(r'"mat_dxlevel" = "(\d+)"', text)
    record["mat_dxlevel"] = dxlevel.group(1) if dxlevel else None
    copy_if_present(root / "native-loader" / "logs" / "loader.log", evidence / "loader.log")
    if copy_if_present(root / "garrysmod" / "data" / "native-loader" / "status.json", evidence / "status.json"):
        status = json.loads((evidence / "status.json").read_text(encoding="utf-8"))
        record["status_pid_matches"] = status.get("process_id") == process.pid
        activation = status.get("activation", {})
        runtime = activation.get("runtime") if isinstance(activation.get("runtime"), dict) else {}
        record["activation"] = {"outcome": activation.get("outcome"), "reason": activation.get("reason"),
                                "runtime_version": runtime.get("version")}
        record["deployment"] = {key: status.get("deployment", {}).get(key)
                                for key in ("outcome", "reason", "blocked_by", "generation", "change_count", "skipped")}
        record["status_errors"] = status.get("errors", [])
    if remix_log.exists() and remix_log.stat().st_mtime != remix_before:
        copy_if_present(remix_log, evidence / "remix-dxvk.log")
        record["remix_log"] = True
    record["finished"] = now()
    return record


def step_uninstall(args) -> dict:
    root = Path(args.root)
    if game_processes(root):
        raise Failure("a game from this install is running")
    result = powershell(REPO / "tools" / "uninstall-loader.ps1", "-GameRoot", str(root), "-Config", args.config, "-RemoveConfig")
    record = {"step": "uninstall", "exit": result.returncode, "output": (result.stdout + result.stderr)[-3000:]}
    verify = subprocess.run([sys.executable, str(REPO / "tools" / "steam" / "verify_install.py"), str(root),
                             "--manifests-from", str(FIELD_ROOT)], capture_output=True, text=True, encoding="utf-8", errors="replace")
    record["verify_exit"] = verify.returncode
    record["verify"] = verify.stdout[-1500:]
    return record


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=str(DEFAULT_ROOT), help="game install (default: the PoC)")
    parser.add_argument("--config", default="Release", choices=["Debug", "Release"], help="which loader build to use")
    parser.add_argument("--evidence", required=True, help="session evidence folder (created if missing)")
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("install", "config"):
        command = sub.add_parser(name)
        command.add_argument("--allow-local", action="append", default=[], help="allowlist a .gma/.bin (repeatable)")
        command.add_argument("--allow-dev", action="append", default=[], help="allowlist a package folder (repeatable)")
        command.add_argument("--allow-workshop", action="append", default=[], help="allowlist a Workshop item id (repeatable)")
        command.add_argument("--remix", choices=["on", "off"], default="on")
        command.add_argument("--require-insecure", choices=["yes", "no"], default="yes")
    run = sub.add_parser("run")
    run.add_argument("--name", required=True, help="step name: the evidence subfolder")
    run.add_argument("--map", default="gm_construct")
    run.add_argument("--extra", action="append", default=[], help="argument before +map (repeatable)")
    run.add_argument("--post", action="append", default=[], help="argument after +map, e.g. a console command (repeatable)")
    run.add_argument("--width", type=int, default=1280)
    run.add_argument("--height", type=int, default=720)
    run.add_argument("--timeout", type=int, default=300, help="seconds to wait for the map")
    run.add_argument("--settle", type=int, default=20, help="seconds after the map before screenshots")
    run.add_argument("--screenshots", type=int, default=1)
    run.add_argument("--shot-interval", type=float, default=2.0)
    run.add_argument("--quit-timeout", type=int, default=90)
    run.add_argument("--port", type=int, default=27199, help="local port for the game and its remote console")
    run.add_argument("--players", type=int, default=2,
                     help="maxplayers; the remote console (and so a normal quit) needs a listen server, 2 or more")
    nl = sub.add_parser("nlctl", help="run nlctl; '{root}' in the arguments becomes the game root")
    nl.add_argument("rest", nargs=argparse.REMAINDER)
    sub.add_parser("uninstall")
    args = parser.parse_args(argv)
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass
    steps = {"install": step_install, "config": step_config, "run": step_run, "nlctl": step_nlctl, "uninstall": step_uninstall}
    evidence = Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    log = evidence / "session.json"
    history = json.loads(log.read_text(encoding="utf-8")) if log.exists() else []
    try:
        record = steps[args.action](args)
        code = 0
    except Failure as error:
        record = {"step": args.action, "failed": str(error)}
        code = 1
    record.setdefault("at", now())
    history.append(record)
    write_json(log, history)
    print(json.dumps(record, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
