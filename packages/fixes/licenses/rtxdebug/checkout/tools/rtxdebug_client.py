"""Call RTXDebug functions in a running Garry's Mod from outside the game.

    python tools/rtxdebug_client.py Status
    python tools/rtxdebug_client.py Engine.GetConVar mat_queue_mode
    python tools/rtxdebug_client.py Interfaces.Materials models/ 0 50

Each call writes garrysmod/data/rtx_debug/requests/<id>.json, sends
``rtx_debug_request <id>`` as console text in a WM_COPYDATA message to the
game's Valve001 window (the -hijack mechanism) and reads the result file the
companion addon writes. Arguments are parsed as JSON where possible, so 0,
true and null are not strings; quote them ('"0"') to pass strings. Windows
only, standard library only.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import sys
import time
import uuid
from pathlib import Path

WM_COPYDATA = 0x004A
SMTO_ABORTIFHUNG = 0x0002
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def _windows_apis():
    """Use pointer-sized signatures on x64; HWND and HANDLE are not C ints."""
    user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32
    kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
    kernel32.OpenProcess.restype = wt.HANDLE
    kernel32.CloseHandle.argtypes = [wt.HANDLE]
    kernel32.CloseHandle.restype = wt.BOOL
    kernel32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR, ctypes.POINTER(wt.DWORD)]
    kernel32.QueryFullProcessImageNameW.restype = wt.BOOL
    user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
    user32.GetWindowThreadProcessId.restype = wt.DWORD
    user32.GetClassNameW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
    user32.GetClassNameW.restype = ctypes.c_int
    user32.SendMessageTimeoutW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, ctypes.c_void_p,
                                          wt.UINT, wt.UINT, ctypes.POINTER(ctypes.c_size_t)]
    user32.SendMessageTimeoutW.restype = ctypes.c_ssize_t
    return user32, kernel32


class _CopyData(ctypes.Structure):
    _fields_ = [("dwData", ctypes.c_size_t), ("cbData", wt.DWORD), ("lpData", ctypes.c_void_p)]


def _process_image(pid: int) -> Path | None:
    _, kernel32 = _windows_apis()
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    try:
        size = wt.DWORD(1024)
        buffer = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return Path(buffer.value)
    finally:
        kernel32.CloseHandle(handle)
    return None


def _select_game(candidates, *, pid: int | None = None, root: Path | str | None = None) -> tuple[int, Path]:
    wanted = Path(root).resolve() if root is not None else None
    selected = {}
    for hwnd, exe, process_id in candidates:
        if pid is not None and process_id != pid:
            continue
        game_root = next((p for p in exe.parents if (p / 'garrysmod').is_dir()), None)
        if game_root is None or (wanted is not None and game_root.resolve() != wanted):
            continue
        selected.setdefault(process_id, (hwnd, game_root))
    if not selected:
        raise RuntimeError("No Garry's Mod client window matches the requested PID/root")
    if len(selected) != 1:
        raise RuntimeError("Multiple Garry's Mod clients match; select --pid or --root (PIDs: "
                           + ', '.join(map(str, sorted(selected))) + ')')
    return next(iter(selected.values()))


def find_game(*, pid: int | None = None, root: Path | str | None = None) -> tuple[int, Path]:
    """The Valve001 window of a running gmod.exe and that game's root folder."""
    user32, _ = _windows_apis()
    found: list[tuple[int, Path, int]] = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def visit(hwnd, _):
        name = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(hwnd, name, 64)
        if name.value == "Valve001":
            pid = wt.DWORD()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            exe = _process_image(pid.value)
            if exe and exe.name.lower() == "gmod.exe":
                found.append((hwnd, exe, pid.value))
        return True

    user32.EnumWindows(visit, 0)
    if not found:
        raise RuntimeError("Garry's Mod is not running (no Valve001 window owned by gmod.exe)")
    return _select_game(found, pid=pid, root=root)


def _window_pid(hwnd: int) -> int:
    user32, _ = _windows_apis()
    process_id = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
    return process_id.value


def send_console(hwnd: int, command: str) -> bool:
    user32, _ = _windows_apis()
    payload = command.encode("utf-8") + b"\0"
    buffer = ctypes.create_string_buffer(payload, len(payload))
    data = _CopyData(0, len(payload), ctypes.cast(buffer, ctypes.c_void_p))
    result = ctypes.c_size_t(0)
    # A map load can stall the message loop for a few seconds; retry.
    for _ in range(3):
        if user32.SendMessageTimeoutW(hwnd, WM_COPYDATA, 0, ctypes.byref(data),
                                     SMTO_ABORTIFHUNG, 5000, ctypes.byref(result)):
            return True
        time.sleep(2)
    return False


def _decode_response(raw: str, request_id: str, process_id: int) -> dict:
    result = json.loads(raw)
    if not isinstance(result, dict) or result.get('id') != request_id:
        raise RuntimeError('RTXDebug response has an invalid or mismatched request ID')
    if result.get('process_id') != process_id:
        raise RuntimeError('RTXDebug response does not belong to the selected process; update the companion addon')
    return result


def call(method: str, *args, timeout: float = 30.0,
         pid: int | None = None, root: Path | str | None = None) -> dict:
    """Run RTXDebug.<method>(*args) in the client realm and return the result file.

    The result has ``ok`` and either ``result`` or ``error``.
    """
    hwnd, root = find_game(pid=pid, root=root)
    process_id = _window_pid(hwnd)
    if not process_id or (pid is not None and process_id != pid):
        raise RuntimeError('The selected game window changed process')
    data = root / "garrysmod" / "data" / "rtx_debug"
    request_id = "c" + uuid.uuid4().hex[:16]
    request = data / "requests" / f"{request_id}.json"
    response = data / "results" / f"{request_id}.json"
    request.parent.mkdir(parents=True, exist_ok=True)
    request.write_text(json.dumps({"id": request_id, "method": method, "args": list(args), "process_id": process_id}),
                       encoding="utf-8")
    try:
        if not send_console(hwnd, f"rtx_debug_request {request_id}"):
            raise RuntimeError("the game window did not accept the console message")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if response.exists():
                try:
                    return _decode_response(response.read_text(encoding="utf-8"), request_id, process_id)
                except (OSError, ValueError):
                    pass  # Still being written.
            time.sleep(0.1)
        raise TimeoutError(
            "no result; check that a map is loaded, the rtx_debug addon is installed "
            "and garrysmod/console.log for [RTXDebug] lines")
    finally:
        for path in (request, response):
            try:
                path.unlink()
            except OSError:
                pass


def _parse_argument(text: str):
    try:
        return json.loads(text)
    except ValueError:
        return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("method", help="RTXDebug function, e.g. Status or Engine.World")
    parser.add_argument("args", nargs="*", help="arguments, parsed as JSON where possible")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--pid", type=int, help="target this client process (required when multiple clients match)")
    parser.add_argument("--root", type=Path, help="target this game installation")
    options = parser.parse_args()
    result = call(options.method, *map(_parse_argument, options.args), timeout=options.timeout,
                  pid=options.pid, root=options.root)
    json.dump(result, sys.stdout, indent=2)
    print()
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
