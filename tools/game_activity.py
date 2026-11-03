"""Read-only Windows field-game activity gate; see game_activity.py.md."""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import time

import poc_session as session


class LastInput(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.UINT), ("dwTime", wintypes.DWORD)]


def busy(field_pids, unknown_pids, foreground_pid, idle_seconds):
    return bool(unknown_pids) or bool(field_pids) and (foreground_pid in field_pids or idle_seconds < 600)


def probe():
    entries = session.process_entries()
    if not entries:
        raise RuntimeError("Process inventory unavailable; refusing game launch")
    field, unknown = [], []
    target = os.path.normcase(str(session.FIELD_ROOT / "bin/win64/gmod.exe"))
    for pid, _, name in entries:
        if name.lower() != "gmod.exe":
            continue
        path = session.process_path(pid)
        if path is None:
            unknown.append(pid)
        elif os.path.normcase(path) == target:
            field.append(pid)
    user, kernel = session.user32, session.kernel32
    user.GetLastInputInfo.argtypes = [ctypes.POINTER(LastInput)]
    user.GetLastInputInfo.restype = wintypes.BOOL
    user.GetForegroundWindow.argtypes = []
    user.GetForegroundWindow.restype = wintypes.HWND
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetTickCount.argtypes = []
    kernel.GetTickCount.restype = wintypes.DWORD
    last = LastInput(ctypes.sizeof(LastInput), 0)
    if not user.GetLastInputInfo(ctypes.byref(last)):
        raise ctypes.WinError(ctypes.get_last_error())
    idle = ((kernel.GetTickCount() - last.dwTime) & 0xffffffff) / 1000
    foreground = wintypes.DWORD()
    window = user.GetForegroundWindow()
    if window and not user.GetWindowThreadProcessId(window, ctypes.byref(foreground)):
        raise ctypes.WinError(ctypes.get_last_error())
    return dict(at=session.now(), field_pids=sorted(field), unknown_gmod_pids=sorted(unknown),
                foreground_pid=foreground.value, last_input_seconds=round(idle, 3),
                busy=busy(field, unknown, foreground.value, idle))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--wait", action="store_true", help="check every five minutes until clear")
    args = parser.parse_args()
    checks = []
    while True:
        check = probe()
        checks.append(check)
        if args.evidence:
            session.write_json(args.evidence, dict(checks=checks, clear=not check["busy"]))
        print(json.dumps(check), flush=True)
        if not check["busy"] or not args.wait:
            return 3 if check["busy"] else 0
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            time.sleep(min(30, max(0, deadline - time.monotonic())))


if __name__ == "__main__":
    raise SystemExit(main())
