"""R14-H: clicks and scrolls in Remix's own menu (Alt+X) for the guide's pictures, which Lua cannot do.
It runs beside a tools/poc_session.py run, watches the game's console log for the lines
tools/qa/guide_shots.lua prints, and posts the mouse messages to the game window (the runtime fork
passes them to its menu when no raw input arrived just before). See guide_input.py.md.

  python tools/qa/guide_input.py [--root <game>] [--timeout 1200]
  NL_INPUT <n> click <x> <y>          a left click at client pixel (x, y)
  NL_INPUT <n> wheel <x> <y> <notches> the mouse over (x, y), then the wheel (negative: down)
"""
from __future__ import annotations

import argparse
import ctypes
import re
import sys
import time
from ctypes import wintypes
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import poc_session as poc  # noqa: E402

INPUT = re.compile(r'(?m)^NL_INPUT (\d+) (click|wheel|key) (-?\d+) (-?\d+)(?: (-?\d+))?\s*$')
DONE = re.compile(r'(?m)^NL_SHOT_DONE\s*$')
WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEWHEEL = 0x0200, 0x0201, 0x0202, 0x020A
WM_KEYDOWN, WM_KEYUP = 0x0100, 0x0101
MK_LBUTTON, WHEEL_DELTA = 0x0001, 120
EXTENDED = {0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28}  # PageUp/Down, End, Home, arrows

user32 = ctypes.windll.user32
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]


def lparam(x: int, y: int) -> int:
    return (y & 0xFFFF) << 16 | (x & 0xFFFF)


def move(hwnd: int, x: int, y: int) -> None:
    user32.PostMessageW(hwnd, WM_MOUSEMOVE, 0, lparam(x, y))
    time.sleep(0.12)


def click(hwnd: int, x: int, y: int) -> None:
    move(hwnd, x, y)
    user32.PostMessageW(hwnd, WM_LBUTTONDOWN, MK_LBUTTON, lparam(x, y))
    time.sleep(0.12)  # a frame between press and release
    user32.PostMessageW(hwnd, WM_LBUTTONUP, 0, lparam(x, y))


def wheel(hwnd: int, x: int, y: int, notches: int) -> None:
    move(hwnd, x, y)
    point = wintypes.POINT(x, y)
    user32.ClientToScreen(hwnd, ctypes.byref(point))  # the wheel message carries screen coordinates
    step = -1 if notches < 0 else 1
    for _ in range(abs(notches)):
        user32.PostMessageW(hwnd, WM_MOUSEWHEEL, ((step * WHEEL_DELTA) & 0xFFFF) << 16, lparam(point.x, point.y))
        time.sleep(0.03)


def key(hwnd: int, vk: int, count: int) -> None:
    """A key press and release, `count` times: the menu's keyboard navigation (arrows, Space, End)."""
    scan = user32.MapVirtualKeyW(vk, 0) & 0xFF
    flags = scan << 16 | (1 << 24 if vk in EXTENDED else 0)
    for _ in range(max(1, count)):
        user32.PostMessageW(hwnd, WM_KEYDOWN, vk, flags | 1)
        time.sleep(0.12)
        user32.PostMessageW(hwnd, WM_KEYUP, vk, flags | 1 | 0xC0000000)
        time.sleep(0.25)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--root', type=Path, default=poc.DEFAULT_ROOT, help='the game install (default: the PoC)')
    parser.add_argument('--timeout', type=float, default=1200, help='seconds before it gives up')
    args = parser.parse_args(argv)
    ctypes.windll.user32.SetProcessDPIAware()  # client pixels are the game's pixels
    log = args.root / 'garrysmod' / 'console.log'
    deadline = time.monotonic() + args.timeout
    done, seen_game = 0, False
    while time.monotonic() < deadline:
        pids = poc.game_processes(args.root)
        if not pids:
            if seen_game:
                print('the game exited', flush=True)
                return 0
            time.sleep(0.5)  # before the launch the log is the last session's: poc_session moves it away
            continue
        seen_game = True
        hwnd = next((h for h in (poc.game_window(pid) for pid in pids) if h), None)
        text = poc.read_shared(log) if log.exists() else ''
        for number, kind, x, y, extra in INPUT.findall(text):
            if int(number) <= done or not hwnd:
                continue
            if kind == 'click':
                click(hwnd, int(x), int(y))
            elif kind == 'key':
                key(hwnd, int(x), int(y))  # NL_INPUT <n> key <virtual key> <count>
            else:
                wheel(hwnd, int(x), int(y), int(extra or -10))
            done = int(number)
            print(f'{number} {kind} {x} {y} {extra}', flush=True)
        if DONE.search(text):
            print('done', flush=True)
            return 0
        time.sleep(0.2)
    print('timed out', flush=True)
    return 1


if __name__ == '__main__':
    sys.exit(main())
