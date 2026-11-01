"""Drive Garry's Mod sessions on the PoC install for acceptance tests, without anyone at the keyboard.

Installs the bootstrap and a config, launches the game, waits for the map, takes screenshots of the
game window, records the loaded modules, ends the game with a normal "quit" (console text sent to
the game's window), collects the logs and uninstalls again. Nothing is written into the game folder
for that: client Lua goes through the console too. Every step writes evidence under the folder given
with --evidence. See poc_session.py.md.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import threading
import time
from ctypes import wintypes
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod_PoC")
FIELD_ROOT = Path(r"H:\SteamLibrary\steamapps\common\GarrysMod")
MAP_MARKER = re.compile(r"(?m)^Clientside Lua startup!\s*$")
MOUNT_MARKER = re.compile(r"(?m)^NL_SESSION_MOUNT true")
EYE_MARKER = re.compile(r"(?m)^NL_SESSION_EYE ")
FPS_MARKER = re.compile(r"(?m)^NL_SESSION_FPS (\{.*\})\s*$")
LUA_MARKER = re.compile(r"(?m)^NL_SESSION_LUA (\d+)\s*$")
SHOT_MARKER = re.compile(r"(?m)^NL_SHOT ([A-Za-z0-9_.-]{1,48})\s*$")
SHOTS_DONE_MARKER = re.compile(r"(?m)^NL_SHOT_DONE\s*$")
WORKSHOP_MOUNTED = re.compile(r"(?m)^Mounted (\d+) of (\d+) workshop addons!")
WORKSHOP_REMOUNTING = re.compile(r"(?m)^Addons have changes - remounting")
# How long a first mount of some but not all subscriptions waits for GMod's remount before it counts as
# the last: with Steam's list already in hand there may be no remount (R3-013).
PARTIAL_MOUNT_GRACE = 20.0
LUA_HEX_CHUNK = 200  # hex digits per console line, far below Source's 512-byte command limit
FILE_ATTRIBUTE_REPARSE_POINT = 0x400
WATCHDOG_INTERVAL = 1.0
HANG_GRACE = 20.0
FAILURE_EXIT_TIMEOUT = 60.0
SCREENSHOT_TIMEOUT = 5.0
DEVICE_LOST = re.compile(r"VK_ERROR_DEVICE_LOST|Exiting after GPU device loss")
EXIT_NAMES = {
    0x60D0DEAD: "Remix GPU-crash exit",
    0xCFFFFFFF: "Windows closed a not-responding program",
}


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


def read_shared(path: Path, offset: int = 0) -> str:
    """Reads a file the game may hold open for writing (Python opens with read/write sharing), from a
    byte offset."""
    try:
        with open(path, "rb") as handle:
            handle.seek(offset)
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


def powershell_environment() -> dict[str, str]:
    """This process's environment without PSModulePath, for a Windows PowerShell child. Windows
    PowerShell 5.1 then builds its own module path. Inherited from PowerShell 7 (a Python started from
    pwsh), the path lists PowerShell 7's modules first, and 5.1 cannot load Get-FileHash from them,
    which install-loader.ps1 needs (R1-029)."""
    return {name: value for name, value in os.environ.items() if name.upper() != "PSMODULEPATH"}


def powershell(script: Path, *arguments: str) -> subprocess.CompletedProcess:
    """Runs a script in Windows PowerShell; every PowerShell child of this script starts here."""
    command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), *arguments]
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          env=powershell_environment())


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
kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
kernel32.GetSystemTimeAsFileTime.restype = None
kernel32.GetSystemTimeAsFileTime.argtypes = [ctypes.POINTER(wintypes.FILETIME)]
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
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


def process_entries() -> list[tuple[int, int, str]]:
    """(PID, parent PID, image name) of every running process, from one Toolhelp32 snapshot."""
    snapshot = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snapshot or snapshot == INVALID_HANDLE_VALUE:
        return []
    entries = []
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(entry)
    try:
        ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while ok:
            entries.append((entry.th32ProcessID, entry.th32ParentProcessID, entry.szExeFile))
            ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return entries


def game_processes(root: Path) -> list[int]:
    """PIDs of every gmod.exe running from this game folder (the game and its Chromium helpers)."""
    target = os.path.normcase(str(root / "bin" / "win64" / "gmod.exe"))
    return [pid for pid, _, name in process_entries()
            if name.lower() == "gmod.exe" and os.path.normcase(process_path(pid) or "") == target]


def process_parents() -> dict[int, int]:
    """{PID: parent PID} of every running process."""
    return {pid: parent for pid, parent, _ in process_entries()}


def filetime(value: wintypes.FILETIME) -> int:
    return (value.dwHighDateTime << 32) | value.dwLowDateTime


def filetime_now() -> int:
    """The system time in 100 ns units since 1601: the clock Windows stamps process creation with."""
    value = wintypes.FILETIME()
    kernel32.GetSystemTimeAsFileTime(ctypes.byref(value))
    return filetime(value)


def handle_created(handle) -> int | None:
    times = [wintypes.FILETIME() for _ in range(4)]
    if not kernel32.GetProcessTimes(handle, *(ctypes.byref(value) for value in times)):
        return None
    return filetime(times[0])


def process_created(pid: int) -> int | None:
    """When the process with this PID was created (filetime_now's units), or None if it cannot be opened."""
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return None
    try:
        return handle_created(handle)
    finally:
        kernel32.CloseHandle(handle)


def descends(pid: int, created: int, launched_pid: int, launched_at: int, parents: dict[int, int], created_of) -> bool:
    """Whether `pid` (created at `created`) is the launched process or one of its descendants: its
    parent chain reaches `launched_pid`, and every process on the chain was created at or after the
    launch and no later than its child. A PID Windows recycled for another process breaks the chain."""
    seen = set()
    while pid != launched_pid:
        if pid in seen:
            return False
        seen.add(pid)
        parent = parents.get(pid)
        parent_created = created_of(parent) if parent else None
        if parent_created is None or parent_created < launched_at or parent_created > created:
            return False
        pid, created = parent, parent_created
    return True


def classify(candidates, launched_pid: int, launched_at: int, parents: dict[int, int], created_of):
    """Splits same-root game PIDs into ours ({PID: creation time}: the launched game and its
    descendants, see descends) and others (a sorted list: games this invocation did not start).
    created_of(pid) gives a creation time, or None when it is unknown (then the PID is not ours)."""
    ours, others = {}, []
    for pid in sorted(set(candidates)):
        created = created_of(pid)
        if created is not None and created >= launched_at and \
                descends(pid, created, launched_pid, launched_at, parents, created_of):
            ours[pid] = created
        else:
            others.append(pid)
    return ours, others


def terminate(expected: dict[int, int]) -> list[int]:
    """Terminates each PID while it is still the process that was classified, checked on the handle
    that terminates it: the same creation time (a recycled PID is left alone). Returns those terminated."""
    done = []
    for pid, created in expected.items():
        handle = kernel32.OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            continue
        try:
            if handle_created(handle) == created and kernel32.TerminateProcess(handle, 1):
                done.append(pid)
        finally:
            kernel32.CloseHandle(handle)
    return done


def stop_ours(process, root: Path, launched_at: int) -> tuple[list[int], list[int]]:
    """Ends the game this invocation launched (through its own process handle) and every same-root
    gmod.exe descended from it: the game starts its Chromium helpers as its children. Returns
    (terminated, others); others are same-root games this invocation did not start, left running."""
    def created_of(pid):
        # The launched game is pinned by its Popen handle, so its PID cannot be recycled meanwhile.
        return launched_at if pid == process.pid else process_created(pid)

    ours, others = classify(game_processes(root), process.pid, launched_at, process_parents(), created_of)
    ours.pop(process.pid, None)
    stopped = []
    if process.poll() is None:
        process.kill()
        stopped.append(process.pid)
    return stopped + terminate(ours), others


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
user32.IsHungAppWindow.argtypes = [wintypes.HWND]
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


CRASH_PROMPT_TITLE = "RTX Remix Crash Report"
WM_COMMAND, IDOK, IDNO = 0x0111, 1, 7
SMTO_ABORTIFHUNG = 0x0002
user32.SendMessageTimeoutW.restype = ctypes.c_ssize_t
user32.SendMessageTimeoutW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, ctypes.c_void_p, wintypes.UINT,
                                       wintypes.UINT, ctypes.POINTER(ctypes.c_size_t)]


def window_hung(hwnd: int) -> bool:
    """A non-blocking check; a busy map load may report hung until its message loop resumes."""
    return bool(user32.IsHungAppWindow(hwnd))


def crash_prompts(pid: int) -> list[int]:
    """The Remix runtime's "RTX Remix Crash Report" message boxes open in the game process `pid`."""
    found = []

    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(hwnd, title, 256)
            if title.value == CRASH_PROMPT_TITLE:
                found.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(visit), 0)
    return found


def decline_crash_prompts(pid: int) -> int:
    """Answers the runtime's crash-report prompts after a crash with No, never with Yes: the start
    after a crash otherwise waits on "upload crash data?" (and then on a notice that pending reports
    could not be removed) until the run times out. A message box takes its button's id through
    WM_COMMAND, so this works in any Windows language: IDNO declines the upload, IDOK closes a notice.
    Consent is never given (RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES would grant it)."""
    answered = 0
    for command in (IDNO, IDOK):
        for hwnd in crash_prompts(pid):
            result = ctypes.c_size_t()
            if user32.SendMessageTimeoutW(hwnd, WM_COMMAND, command, None, SMTO_ABORTIFHUNG, 1000, ctypes.byref(result)):
                answered += 1
    return answered


def keep_crash_reports(root: Path, target: Path, errors: list[str] | None = None) -> list[str]:
    """Copies the minidumps waiting under the install's rtx-remix\\logs\\.sentry-native into `target`
    and returns their names. The next start's prompt is declined (decline_crash_prompts) and Remix then
    deletes the reports, which took the only evidence of a crash with it (R4, 2026-10-31)."""
    folder = root / "rtx-remix" / "logs" / ".sentry-native"
    kept = []
    for dump in sorted(folder.rglob("*.dmp")) if folder.is_dir() else []:
        name = dump.name if dump.parent == folder else f"{dump.parent.name}-{dump.name}"
        target.mkdir(parents=True, exist_ok=True)
        temporary = target / f"{name}.{threading.get_ident()}.tmp"
        try:
            shutil.copy2(dump, temporary)
            os.replace(temporary, target / name)
            kept.append(name)
        except OSError as error:
            # The crash handler may still be writing a dump, or remove it as a prompt closes. Keep
            # collecting the other evidence; the watchdog and the final collection can retry it.
            if errors is not None:
                errors.append(f"{name}: {error}")
        finally:
            temporary.unlink(missing_ok=True)
    return kept


class CrashPromptWatchdog:
    """Declines prompts throughout a run, including console sends, captures and the exit grace."""

    def __init__(self, process, root: Path, evidence: Path):
        self.process, self.root, self.evidence = process, root, evidence
        self.answered = 0
        self.reports: set[str] = set()
        self.errors: list[str] = []
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self.run, name="crash-prompt-watchdog", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def run(self) -> None:
        while not self.stopped.is_set() and self.process.poll() is None:
            try:
                # Declining a live device-loss prompt can delete this run's reports too.
                if crash_prompts(self.process.pid):
                    self.reports.update(keep_crash_reports(self.root, self.evidence / "crash-reports", self.errors))
                if not self.stopped.is_set() and self.process.poll() is None:
                    self.answered += decline_crash_prompts(self.process.pid)
            except Exception as error:
                self.errors.append(str(error))
            if self.stopped.wait(WATCHDOG_INTERVAL):
                break

    def close(self) -> None:
        self.stopped.set()
        self.thread.join(timeout=3)


class RunHealth:
    """Cooperative checks between all run steps; never sends a message to test responsiveness."""

    def __init__(self, process, remix_log: Path, remix_before: str, record: dict):
        self.process, self.remix_log, self.remix_before, self.record = process, remix_log, remix_before, record
        self.hung_since: dict[int, float] = {}

    def check(self, hwnd: int | None = None) -> None:
        try:
            text = read_shared(self.remix_log)
        except OSError as error:
            self.record["remix_log_read_error"] = str(error)
            text = self.remix_before  # retry next check; still detect a hung window below
        # Remix normally truncates its log at start. Also support an appended log without reading
        # an earlier run's device-loss marker as this run's failure.
        fresh = text[len(self.remix_before):] if text.startswith(self.remix_before) else text
        marker = DEVICE_LOST.search(fresh)
        if marker:
            self.record["device_lost"] = True
            self.record["device_lost_marker"] = marker.group()
            raise Failure(f"GPU device lost ({marker.group()} in remix-dxvk.log)")
        if self.process.poll() is not None:
            return
        if hwnd is None:
            hwnd = console_window(self.process.pid) or game_window(self.process.pid)
        if hwnd and window_hung(hwnd):
            since = self.hung_since.setdefault(hwnd, time.monotonic())
            seconds = time.monotonic() - since
            if seconds >= HANG_GRACE:
                self.record["hung_seconds"] = round(seconds, 1)
                raise Failure(f"game window hung for {seconds:.1f} s")
        else:
            self.hung_since.pop(hwnd, None)

    def before_window(self, hwnd: int) -> None:
        """Waits out a short load stall, or fails after HANG_GRACE; no sends or capture while hung."""
        while True:
            self.check(hwnd)
            if self.process.poll() is not None:
                raise Failure("game exited before the next window operation")
            if not window_hung(hwnd):
                return
            time.sleep(0.5)

    def sleep(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        self.check()
        while self.process.poll() is None and time.monotonic() < deadline:
            time.sleep(min(0.5, max(0, deadline - time.monotonic())))
            self.check()


def wait_exit(process, seconds: float, check=None) -> bool:
    """A bounded exit wait that lets a healthy run keep checking its log/window while quitting."""
    deadline = time.monotonic() + seconds
    while process.poll() is None:
        if check:
            check()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(0.5, remaining))
    if check:
        check()  # include a device-loss marker written just before the exit
    return True


def describe_exit(record: dict) -> None:
    code = record.get("exit")
    if isinstance(code, int):
        unsigned = code & 0xFFFFFFFF
        record["exit_hex"] = f"0x{unsigned:08X}"
        if unsigned in EXIT_NAMES:
            record["exit_name"] = EXIT_NAMES[unsigned]
            record["normal_quit"] = False
            record.setdefault("failed", EXIT_NAMES[unsigned])
        if unsigned == 0x60D0DEAD:
            record["device_lost"] = True


def screenshot(hwnd: int, destination: Path) -> dict:
    """A hung window is refused; a freeze racing the check cannot hold the caller in PrintWindow.
    Only the caller writes the image, so an abandoned capture never writes late evidence."""
    if window_hung(hwnd):
        raise Failure("cannot capture a hung game window")
    done, result, errors = threading.Event(), [], []

    def capture():
        try:
            result.append(capture_window(hwnd))
        except Exception as error:
            errors.append(error)
        finally:
            done.set()

    threading.Thread(target=capture, name="window-capture", daemon=True).start()
    if not done.wait(SCREENSHOT_TIMEOUT):
        raise Failure(f"screenshot timed out after {SCREENSHOT_TIMEOUT:g} s")
    if errors:
        raise Failure(f"screenshot failed: {errors[0]}") from errors[0]
    image, details = result[0]
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)
    return {"file": destination.name, **details}


def capture_window(hwnd: int) -> tuple:
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
    mean = ImageStat.Stat(image).mean
    return image, {"width": width, "height": height, "method": method,
                   "mean_rgb": [round(value, 1) for value in mean]}


# ---------------------------------------------------------------- console text through WM_COPYDATA

# Source runs the payload of a WM_COPYDATA message sent to its "Valve001" window as console text (the
# mechanism behind -hijack). It works in single-player, unlike the TCP remote console, and "quit" this
# way ends the session normally. GMod refuses "quit" from Lua.
WM_COPYDATA = 0x004A
SMTO_NORMAL = 0x0000


class COPYDATASTRUCT(ctypes.Structure):
    _fields_ = [("dwData", ctypes.c_size_t), ("cbData", wintypes.DWORD), ("lpData", ctypes.c_void_p)]


user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]


def console_window(pid: int) -> int | None:
    found = []

    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            name = ctypes.create_unicode_buffer(64)
            user32.GetClassNameW(hwnd, name, 64)
            if name.value == "Valve001":
                found.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(visit), 0)
    return found[0] if found else None


def console(hwnd: int, command: str, attempts: int = 6, check=None) -> bool:
    payload = command.encode("utf-8") + b"\0"
    buffer = ctypes.create_string_buffer(payload, len(payload))
    data = COPYDATASTRUCT(0, len(payload), ctypes.cast(buffer, ctypes.c_void_p))
    result = ctypes.c_size_t(0)
    for attempt in range(attempts):
        if check:
            check(hwnd)
        elif window_hung(hwnd):
            return False
        # Loading a map, or the RTX fixes reloading models after it, can stall the message loop for
        # many seconds; that is not a hang, so wait for it (not SMTO_ABORTIFHUNG, which gives up at once).
        if user32.SendMessageTimeoutW(hwnd, WM_COPYDATA, 0, ctypes.byref(data), SMTO_NORMAL, 10000, ctypes.byref(result)):
            return True
        if check:
            check(hwnd)
        if attempt + 1 < attempts:
            time.sleep(3)
    return False


def client_lua_lines(name: str, code: str) -> list[str]:
    """The console lines that run `code` as the client Lua chunk "nl_session_<name>". Source's console
    splits text at ';' and line breaks and drops what follows '//', so the code travels hex-encoded
    (digits and a-f only) in the global NL_S, at most LUA_HEX_CHUNK digits a line, and the last line
    decodes and runs it. Nothing is written into the game folder."""
    if not re.fullmatch(r"[a-z0-9_]{1,32}", name):
        raise ValueError(f"chunk name {name!r}: 1-32 characters of a-z 0-9 _")
    data = code.encode("utf-8").hex()
    lines = ['lua_run_cl NL_S=""']
    lines += [f'lua_run_cl NL_S=NL_S.."{data[start:start + LUA_HEX_CHUNK]}"' for start in range(0, len(data), LUA_HEX_CHUNK)]
    lines.append('lua_run_cl RunString((NL_S:gsub("..",function(h) return string.char(tonumber(h,16)) end)),'
                 f'"nl_session_{name}")')
    return lines


def client_lua(hwnd: int, name: str, code: str, check=None) -> bool:
    """Runs `code` on the client through the console (client_lua_lines). False as soon as one line is
    not delivered; the lines after it, the one that runs the chunk included, are then not sent."""
    return all(console(hwnd, line, **({"check": check} if check else {})) for line in client_lua_lines(name, code))


def mount_lua(item: str) -> str:
    """Client Lua that mounts one installed Workshop item (a legacy item comes back decompressed)."""
    return (f'steamworks.DownloadUGC("{item}", function(path) print("NL_SESSION_UGC " .. tostring(path)) '
            'if path then print("NL_SESSION_MOUNT " .. tostring(game.MountGMA(path))) end end)\n')


def camera_lua(camera: list[float] | None, hide_hud: bool) -> str:
    code = ""
    if camera:
        x, y, z, pitch, yaw, roll = camera[:6]
        fov = camera[6] if len(camera) > 6 else 75
        code += (f'hook.Add("CalcView","nl_session",function() return {{origin=Vector({x},{y},{z}),'
                 f'angles=Angle({pitch},{yaw},{roll}),fov={fov},drawviewer=false}} end)\n')
    if hide_hud:
        # Also close Derma frames (add-ons' notices), now and for a while, so nothing covers the frame.
        code += ('hook.Add("HUDShouldDraw","nl_session",function() return false end)\n'
                 'hook.Add("PreDrawViewModel","nl_session",function() return true end)\n'
                 'local function nl_close() for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do '
                 'if IsValid(p) and p:IsVisible() and (p.GetTitle or (p.IsModal and p:IsModal())) then p:Remove() end end '
                 'gui.EnableScreenClicker(false) end\n'
                 'nl_close() timer.Create("nl_session_close", 0.5, 0, nl_close)\n')
    # Where the player's own view is, for pinning another install to the same camera.
    code += ('local nl_ply = LocalPlayer() if IsValid(nl_ply) then local e, a = nl_ply:EyePos(), nl_ply:EyeAngles() '
             'print(string.format("NL_SESSION_EYE %.3f,%.3f,%.3f,%.3f,%.3f,%.3f", e.x, e.y, e.z, a.p, a.y, a.r)) end\n')
    return code


def fps_lua(seconds: float) -> str:
    """Client Lua that times every frame (a PostRender hook) for `seconds`, then prints one
    NL_SESSION_FPS line with a JSON object: frames, seconds, fps, median_ms, p99_ms, max_ms."""
    return ('local nl_times, nl_last, nl_began = {}, SysTime(), SysTime()\n'
            'hook.Add("PostRender", "nl_session_fps", function()\n'
            '  local now = SysTime()\n'
            '  nl_times[#nl_times + 1] = now - nl_last\n'
            '  nl_last = now\n'
            f'  if now - nl_began < {seconds:.3f} then return end\n'
            '  hook.Remove("PostRender", "nl_session_fps")\n'
            '  local total, n = 0, #nl_times\n'
            '  for _, t in ipairs(nl_times) do total = total + t end\n'
            '  table.sort(nl_times)\n'
            '  local function at(q) return nl_times[math.max(1, math.ceil(n * q))] * 1000 end\n'
            '  print(string.format(\'NL_SESSION_FPS {"frames":%d,"seconds":%.3f,"fps":%.2f,"median_ms":%.3f,'
            '"p99_ms":%.3f,"max_ms":%.3f}\', n, total, n / total, at(0.5), at(0.99), nl_times[n] * 1000))\n'
            'end)\n')


def file_lua(index: int, code: str) -> str:
    """A --lua file as sent: a first line that prints NL_SESSION_LUA <index>, so the run can tell the
    chunk arrived and started (RunString compiles it whole first, so a syntax error prints nothing)."""
    return f'print("NL_SESSION_LUA {index}")\n' + code


# ---------------------------------------------------------------- steps

def nlctl_path(config: str) -> Path:
    return REPO / "out" / "build" / f"win64-{config.lower()}" / "loader" / "cli" / "nlctl.exe"


def config_path(root: Path) -> Path:
    return root / "native-loader" / "config.json"


def config_content(args) -> tuple[dict, bytes]:
    """The config.json that the install and config steps write, as a value and as the exact bytes
    on disk (line breaks as the text-mode write has always made them)."""
    value = {"schema": 1, "enabled": True,
             "allow": {"workshop": args.allow_workshop, "local": args.allow_local, "dev_folders": args.allow_dev},
             "remix": {"enabled": args.remix == "on"}, "patch_sets": {"require_insecure": args.require_insecure == "yes"}}
    if getattr(args, "reshade", None):
        value["remix"]["reshade"] = args.reshade  # loader 0.5.0 (ADR 0028); left out, the loader's default (auto)
    # Loader 0.11.0 (ADR 0062, 0063), each left out unless given: an older loader rejects these keys.
    if getattr(args, "performance_tier", None):
        value["remix"]["performance_tier"] = args.performance_tier
    diagnostics = {key: getattr(args, key) for key in ("gpu_crash_dumps", "memory_telemetry") if getattr(args, key, None)}
    if diagnostics:
        value["diagnostics"] = diagnostics
    return value, json.dumps(value, indent=2).replace("\n", os.linesep).encode("utf-8")


def write_config(root: Path, data: bytes) -> None:
    target = config_path(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".json.tmp")
    temporary.write_bytes(data)
    os.replace(temporary, target)


def existing_config(target: Path) -> bytes | None:
    """The bytes of an existing config.json, None when there is none; refuses anything but a plain file."""
    try:
        info = os.lstat(target)
    except (FileNotFoundError, NotADirectoryError):
        return None
    except OSError as error:
        raise Failure(f"cannot read {target}: {error}") from error
    if not stat.S_ISREG(info.st_mode) or getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT:
        raise Failure(f"{target} is not a plain file; nothing was changed")
    return target.read_bytes()


def backup_config(data: bytes, evidence: Path) -> dict:
    """Saves a config about to be replaced as <evidence>\\config.json.before-<UTC time>, beside the
    session record (not beside the config: uninstall -RemoveConfig deletes native-loader\\ with
    everything in it), and checks the copy. Returns its path and SHA-256."""
    digest = hashlib.sha256(data).hexdigest()
    stamp = _dt.datetime.now(_dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence.mkdir(parents=True, exist_ok=True)
    for attempt in range(100):
        copy = evidence / (f"config.json.before-{stamp}" + (f"-{attempt}" if attempt else ""))
        try:
            with open(copy, "xb") as handle:
                handle.write(data)
            break
        except FileExistsError:
            continue
    else:
        raise Failure(f"no free name for config.json.before-{stamp} in {evidence}; nothing was replaced")
    if hashlib.sha256(copy.read_bytes()).hexdigest() != digest:
        raise Failure(f"the backup {copy} does not match the config; nothing was replaced")
    return {"path": str(copy), "sha256": digest}


def step_install(args) -> dict:
    root = Path(args.root)
    if game_processes(root):
        raise Failure("a game from this install is running")
    config, data = config_content(args)
    target = config_path(root)
    before = existing_config(target)
    if before is not None and before != data and not args.replace_config:
        raise Failure(f"{target} exists (SHA-256 {hashlib.sha256(before).hexdigest()}) and differs from the config "
                      "this install would write; nothing was changed. --replace-config backs it up into the evidence "
                      "folder and replaces it.")
    result = powershell(REPO / "tools" / "install-loader.ps1", "-GameRoot", str(root), "-Config", args.config,
                        *(["-AllowSteamManaged"] if args.allow_steam_managed else []))
    if result.returncode != 0:
        raise Failure("install-loader.ps1 failed: " + (result.stderr or result.stdout)[-2000:])
    record = {"step": "install", "config": config, "installer": result.stdout.strip()[-500:]}
    if existing_config(target) != before:
        raise Failure(f"{target} changed while the installer ran; it was not replaced")
    if before is not None and before != data:
        try:
            record["config_backup"] = backup_config(before, Path(args.evidence))
        except OSError as error:
            raise Failure(f"could not back up {target} ({error}); nothing was replaced") from error
    write_config(root, data)
    return record


def step_config(args) -> dict:
    config, data = config_content(args)
    write_config(Path(args.root), data)
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
    console_log = root / "garrysmod" / "console.log"
    # A reference install or one Steam manages is the user's: its console.log is read from where it
    # ends now, never moved. The PoC's is moved into the evidence first.
    keep_log = args.reference or args.allow_steam_managed
    offset = console_log.stat().st_size if (keep_log and console_log.exists()) else 0
    if not keep_log and console_log.exists():
        shutil.move(str(console_log), str(evidence / "console-before-run.log"))
    remix_log = root / "rtx-remix" / "logs" / "remix-dxvk.log"
    remix_mtime_before = remix_log.stat().st_mtime_ns if remix_log.exists() else None
    remix_before = read_shared(remix_log)
    window = [] if args.no_window else ["-windowed", "-w", str(args.width), "-h", str(args.height)]
    # -multirun: the user may be playing another install meanwhile, and Source otherwise ends a second
    # instance at once (exit -1, nothing in the log). This install's own game is still refused above.
    arguments = ["-game", "garrysmod", "-multirun", "-console", *window,
                 "-condebug", *([] if args.workshop else ["-noworkshop"]), *([] if args.addons else ["-noaddons"]),
                 *args.extra, "+maxplayers", str(args.players), "+mat_dxlevel"]
    # Workshop add-ons mount twice at start: before Steam has listed the subscriptions ("Mounted 0 of 755
    # workshop addons!") and again once it has ("Addons have changes - remounting", then "Mounted 752 of
    # 755 ..."). A map asked for in between waits on that fetch ("Waiting for Steam Workshop to
    # finish...") and the window stops answering. So with --workshop the game starts at the menu, and the
    # map is asked for through the console once the Workshop is mounted.
    menu_first = bool(args.workshop and args.map)
    arguments += ["+map", args.map] if args.map and not menu_first else []
    arguments += args.post
    environment = dict(os.environ)
    environment.pop("NATIVE_LOADER_DISABLE", None)
    environment.pop("RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES", None)  # would grant upload consent
    record = {"step": "run", "name": args.name, "root": str(root), "started": now(), "arguments": arguments}
    # This start declines the crash-report prompt of an earlier crash, and Remix then deletes the report:
    # keep its minidumps first.
    waiting = keep_crash_reports(root, evidence / "crash-reports-before")
    if waiting:
        record["crash_reports_before"] = waiting

    def log_text() -> str:
        return read_shared(console_log, offset)

    def send(hwnd: int, command: str) -> bool:
        health.before_window(hwnd)
        return console(hwnd, command, check=health.before_window)

    def lua(hwnd: int, name: str, code: str) -> bool:
        health.before_window(hwnd)
        return client_lua(hwnd, name, code, check=health.before_window)

    def take_screenshot(window: int, destination: Path) -> dict:
        health.before_window(window)
        result = screenshot(window, destination)
        health.check(window)
        return result

    def wait_for(marker: re.Pattern, count: int, deadline: float) -> bool:
        while time.monotonic() < deadline:
            health.check()
            if process.poll() is not None:
                return False
            if len(marker.findall(log_text())) >= count:
                return True
            health.sleep(0.5)
        return False

    def wait_for_map(count: int, deadline: float) -> bool:
        return wait_for(MAP_MARKER, count, deadline)

    def wait_for_lua(index: int, count: int, deadline: float) -> bool:
        """Waits until the --lua file `index` has printed its first line `count` times in all."""
        while time.monotonic() < deadline and process.poll() is None:
            health.check()
            if LUA_MARKER.findall(log_text()).count(str(index)) >= count:
                return True
            health.sleep(0.5)
        return False

    def lua_shots(window: int | None, limit: float) -> tuple[list[dict], bool]:
        """One screenshot for each "NL_SHOT <label>" line the Lua prints, in order, each answered with
        the console command "nl_shot_taken <n>" so the Lua can go on to its next view; until it prints
        NL_SHOT_DONE, the game exits or `limit` seconds pass. Returns the shots and whether it was done."""
        shots, seen, began_shots = [], 0, time.monotonic()
        record["lua_shots"], record["lua_shots_done"] = shots, False
        while time.monotonic() < began_shots + limit and process.poll() is None:
            health.check()
            text = log_text()
            for label in SHOT_MARKER.findall(text)[seen:]:
                seen += 1
                if window:
                    shot = take_screenshot(window, evidence / f"shot-{seen:02d}-{label}.png")
                    shot.update(label=label, seconds=round(time.monotonic() - began_shots, 1))
                    shots.append(shot)
                if hwnd:
                    send(hwnd, f"nl_shot_taken {seen}")
            if SHOTS_DONE_MARKER.search(text):
                return shots, True
            health.sleep(0.25)
        return shots, False

    def wait_quiet(seconds: float, limit: float) -> bool:
        """Waits until the console log has not grown for `seconds` (at most `limit` seconds)."""
        deadline, size, since = time.monotonic() + limit, -1, time.monotonic()
        while time.monotonic() < deadline and process.poll() is None:
            health.check()
            now_size = console_log.stat().st_size if console_log.exists() else 0
            if now_size != size:
                size, since = now_size, time.monotonic()
            elif time.monotonic() - since >= seconds:
                return True
            health.sleep(0.5)
        return False

    def wait_workshop(deadline: float) -> dict:
        """Waits for the Workshop mount that follows Steam's list of subscriptions (see menu_first): a
        second "Mounted N of M workshop addons!"; a first that mounted all M or had none to mount; or a
        first that mounted some but not all, once PARTIAL_MOUNT_GRACE seconds pass without GMod starting
        a remount. Then waits for the log to be quiet for 5 s."""
        found: list[tuple[str, str]] = []
        first_seen = None

        def ready_by(text: str) -> str | None:
            if len(found) >= 2:
                return "the remount"
            if not found:
                return None
            mounted, total = int(found[0][0]), int(found[0][1])
            if not total or mounted >= total:
                return "a complete first mount"
            if mounted and not WORKSHOP_REMOUNTING.search(text) and time.monotonic() - first_seen >= PARTIAL_MOUNT_GRACE:
                return f"a partial first mount, and no remount within {PARTIAL_MOUNT_GRACE:.0f} s"
            return None  # 0 of M: Steam has not listed the subscriptions yet, a remount follows

        rule = None
        while time.monotonic() < deadline and process.poll() is None:
            health.sleep(0.5)
            text = log_text()
            found = WORKSHOP_MOUNTED.findall(text)
            if found and first_seen is None:
                first_seen = time.monotonic()
            rule = ready_by(text)
            if rule:
                break
        ready = rule is not None
        return {"workshop_mounted": [f"{n} of {m}" for n, m in found], "workshop_ready": ready, "workshop_ready_by": rule,
                "quiet_before_map": ready and wait_quiet(5, 60), "seconds_to_workshop": round(time.monotonic() - began, 1)}

    not_ours: set[int] = set()

    def stop() -> list[int]:
        """Ends the launched game and its descendants; other same-root games keep running (recorded)."""
        stopped, others = stop_ours(process, root, launched_at)
        not_ours.update(others)
        return stopped

    began = time.monotonic()
    launched_at = filetime_now()
    process = subprocess.Popen([str(root / "bin" / "win64" / "gmod.exe"), *arguments], cwd=str(root), env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record["pid"] = process.pid
    health = RunHealth(process, remix_log, remix_before, record)
    watchdog = CrashPromptWatchdog(process, root, evidence)
    modules = []
    watchdog.start()
    try:
        health.check()
        if menu_first:
            record.update(wait_workshop(began + args.timeout))
            if args.menu_shot and record["workshop_ready"]:
                # The main menu as the player sees it (the loader's diagnostics panel, the native add-on
                # cards, the startup text), before the map is asked for.
                menu_window = game_window(process.pid)
                record["menu_screenshot"] = take_screenshot(menu_window, evidence / "menu.png") if menu_window else None
            hwnd = console_window(process.pid) if record["workshop_ready"] else None
            record["map_command"] = bool(hwnd) and send(hwnd, f"map {args.map}")
        loaded = wait_for_map(1, began + args.timeout) if not menu_first or record["map_command"] else False
        record["map_loaded"] = loaded
        record["seconds_to_map"] = round(time.monotonic() - began, 1)
        health.check()
        modules = modules_of(process.pid) if process.poll() is None else []
        record["early_exit"] = process.poll() is not None
        hwnd = console_window(process.pid) if loaded else None
        record["console_window"] = bool(hwnd)
        if loaded and (args.load_save or args.change_map) and hwnd:
            record["quiet_before_save"] = wait_quiet(5, 90)
            if args.mount_workshop:
                # The save's (or the next) map is a Workshop item, and Workshop add-ons are not mounted
                # (-noworkshop): mount the items named (the map, a library an add-on needs), as GMod's
                # own loading of a Workshop save does.
                mounted = []
                for item in args.mount_workshop:
                    for _ in range(3):
                        if lua(hwnd, "mount", mount_lua(item)) and \
                                wait_for(MOUNT_MARKER, len(mounted) + 1, time.monotonic() + 60):
                            mounted.append(item)
                            break
                record["workshop_mounted_items"] = mounted
                record["workshop_mounted"] = len(mounted) == len(args.mount_workshop)
            # gm_load prints nothing when it cannot find the save's map; the record says whether the
            # command went through and whether the map came up.
            if args.load_save:
                record["save_command"] = send(hwnd, f'gm_load "{args.load_save}"')
                record["save_loaded"] = record["save_command"] and wait_for_map(2, time.monotonic() + args.timeout)
            else:
                record["map_command"] = send(hwnd, f"map {args.change_map}")
                record["map_changed"] = record["map_command"] and wait_for_map(2, time.monotonic() + args.timeout)
            hwnd = console_window(process.pid) or hwnd
        if args.console and hwnd:
            # As for the camera below: text sent while the RTX fixes reload models is lost.
            record["quiet_before_console"] = wait_quiet(5, 90)
        for command in args.console:
            if hwnd:
                send(hwnd, command)
        if loaded and process.poll() is None:
            if (args.camera or args.hide_hud) and hwnd:
                # Commands sent while the RTX fixes still reload models after a map change can be lost
                # without a word: wait for the console to go quiet, then check the Lua ran (it prints
                # the eye position) and send it again if not.
                record["quiet_after_map"] = wait_quiet(5, 90)
                record["camera"] = False
                for _ in range(3):
                    printed = len(EYE_MARKER.findall(log_text()))
                    if lua(hwnd, "camera", camera_lua(args.camera, args.hide_hud)) and \
                            wait_for(EYE_MARKER, printed + 1, time.monotonic() + 20):
                        record["camera"] = True
                        break
                if args.hide_hud:
                    # Add-ons may answer HUDShouldDraw first; these two are not archived (config.cfg
                    # holds neither) and are set back before quitting.
                    send(hwnd, "cl_drawhud 0")
                    send(hwnd, "r_drawviewmodel 0")
            if args.lua and hwnd:
                # Lua sent while the RTX fixes reload models is lost as the camera's is: wait for quiet
                # (done above with a camera), and send a file again until its first line has printed.
                if not (args.camera or args.hide_hud):
                    record["quiet_before_lua"] = wait_quiet(5, 90)
                record["lua"] = []
                for index, path in enumerate(args.lua, 1):
                    code = file_lua(index, Path(path).read_text(encoding="utf-8"))
                    started = False
                    for _ in range(3):
                        printed = LUA_MARKER.findall(log_text()).count(str(index))
                        if lua(hwnd, f"lua{index}", code) and \
                                wait_for_lua(index, printed + 1, time.monotonic() + 20):
                            started = True
                            break
                    record["lua"].append({"file": str(path), "started": started})
            health.sleep(args.settle)
            if args.fps and hwnd and process.poll() is None:
                # Timed in the game, frame by frame, before the screenshots (a capture can stall a frame).
                # Lua lost while the game is busy is sent once more; its hook replaces the first one.
                record["fps"] = None
                for _ in range(2):
                    printed = len(FPS_MARKER.findall(log_text()))
                    if lua(hwnd, "fps", fps_lua(args.fps)) and \
                            wait_for(FPS_MARKER, printed + 1, time.monotonic() + args.fps + 30):
                        record["fps"] = json.loads(FPS_MARKER.findall(log_text())[-1])
                        break
            window = game_window(process.pid)
            if args.lua_shots and process.poll() is None:
                record["lua_shots"], record["lua_shots_done"] = lua_shots(window, args.lua_shots)
            shots = []
            record["screenshots"] = shots
            for index in range(args.screenshots):
                if window and process.poll() is None:
                    shots.append(take_screenshot(window, evidence / f"screenshot-{index + 1}.png"))
                    health.sleep(args.shot_interval)
            modules = modules_of(process.pid) or modules
        health.check()
        if process.poll() is None:
            hwnd = console_window(process.pid)
            if hwnd and args.hide_hud:
                send(hwnd, "cl_drawhud 1")
                send(hwnd, "r_drawviewmodel 1")
            record["quit"] = "console" if hwnd and send(hwnd, "quit") else "console unavailable"
            if wait_exit(process, args.quit_timeout, health.check):
                record["normal_quit"] = record["quit"] == "console" and process.returncode == 0
            else:
                record["terminated_processes"] = stop()
                wait_exit(process, 5)
                record["normal_quit"] = False
        else:
            record["normal_quit"] = False
    except Failure as error:
        record["failed"], record["normal_quit"] = str(error), False
        record["quit"] = "skipped after failure"
        # Keep the watchdog alive while Aftermath/Sentry finish and Remix declines its own dialog.
        # No more console text or screenshots, even if the window briefly starts answering again.
        since = time.monotonic()
        if not wait_exit(process, FAILURE_EXIT_TIMEOUT):
            record["terminated_processes"] = stop()
            wait_exit(process, 5)
        record["failure_exit_wait_seconds"] = round(time.monotonic() - since, 1)
    finally:
        try:
            time.sleep(2)
            leftovers = stop()
            if leftovers:
                record["terminated_helpers"] = leftovers
        finally:
            watchdog.close()
    record["exit"] = process.poll()
    if record["exit"] is None:
        record["failed"], record["normal_quit"] = "game did not exit after bounded shutdown", False
    try:
        health.check()  # catch a marker written during the exit grace, including an early crash
    except Failure as error:
        record.setdefault("failed", str(error))
        record["normal_quit"] = False
    describe_exit(record)
    if watchdog.answered:
        record["declined_crash_prompts"] = watchdog.answered
    if watchdog.errors:
        record["crash_watchdog_errors"] = watchdog.errors
    if watchdog.thread.is_alive():
        record["crash_watchdog_stop_timed_out"] = True
    write_json(evidence / "modules.json", modules)
    record["d3d9"] = next((m for m in modules if os.path.basename(m).lower() == "d3d9.dll"), None)
    record["stdshader_dx6"] = next((m for m in modules if os.path.basename(m).lower() == "stdshader_dx6.dll"), None)
    if not_ours:
        record["not_ours"] = sorted(not_ours)  # same-root games this run did not start: left running
    if not record.get("normal_quit"):
        errors = []
        crashed = sorted(watchdog.reports | set(keep_crash_reports(root, evidence / "crash-reports", errors)))
        if crashed:
            record["crash_reports"] = crashed
        if errors:
            record["crash_report_errors"] = errors
    text = log_text()
    (evidence / "console.log").write_text(text, encoding="utf-8", newline="")
    dxlevel = re.search(r'"mat_dxlevel" = "(\d+)"', text)
    record["mat_dxlevel"] = dxlevel.group(1) if dxlevel else None
    record["lua_errors"] = len(re.findall(r"(?m)^\[ERROR\]|lua_run_cl.*error", text))
    eye = re.search(r"NL_SESSION_EYE ([-\d.,]+)", text)
    record["eye"] = eye.group(1) if eye else None
    if not args.reference:
        copy_if_present(root / "native-loader" / "logs" / "loader.log", evidence / "loader.log")
        copy_if_present(root / "garrysmod" / "data" / "native-loader" / "session.json", evidence / "session.json")
        if copy_if_present(root / "garrysmod" / "data" / "native-loader" / "status.json", evidence / "status.json"):
            status = json.loads((evidence / "status.json").read_text(encoding="utf-8"))
            record["status_pid_matches"] = status.get("process_id") == process.pid
            activation = status.get("activation", {})
            runtime = activation.get("runtime") if isinstance(activation.get("runtime"), dict) else {}
            record["activation"] = {"outcome": activation.get("outcome"), "reason": activation.get("reason"),
                                    "runtime_version": runtime.get("version")}
            record["deployment"] = {key: status.get("deployment", {}).get(key)
                                    for key in ("outcome", "reason", "blocked_by", "generation", "change_count", "skipped")}
            record["session"] = status.get("session")
            record["status_errors"] = status.get("errors", [])
    if remix_log.exists() and remix_log.stat().st_mtime_ns != remix_mtime_before:
        copy_if_present(remix_log, evidence / "remix-dxvk.log")
        record["remix_log"] = True
    record["finished"] = now()
    return record


def step_uninstall(args) -> dict:
    root = Path(args.root)
    if game_processes(root):
        raise Failure("a game from this install is running")
    result = powershell(REPO / "tools" / "uninstall-loader.ps1", "-GameRoot", str(root), "-Config", args.config, "-RemoveConfig",
                        *(["-AllowSteamManaged"] if args.allow_steam_managed else []))
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
    parser.add_argument("--allow-steam-managed", action="store_true",
                        help="install into or uninstall from an install Steam manages (the field install: M7, after a snapshot)")
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("install", "config"):
        command = sub.add_parser(name)
        command.add_argument("--allow-local", action="append", default=[], help="allowlist a .gma/.bin (repeatable)")
        command.add_argument("--allow-dev", action="append", default=[], help="allowlist a package folder (repeatable)")
        command.add_argument("--allow-workshop", action="append", default=[], help="allowlist a Workshop item id (repeatable)")
        command.add_argument("--remix", choices=["on", "off"], default="on")
        command.add_argument("--reshade", choices=["auto", "on", "off"],
                             help="write remix.reshade (loader 0.5.0); left out by default")
        command.add_argument("--performance-tier", choices=["auto", "high", "medium", "low"],
                             help="write remix.performance_tier (loader 0.11.0); left out by default")
        command.add_argument("--gpu-crash-dumps", choices=["off", "next_start", "always"],
                             help="write diagnostics.gpu_crash_dumps (loader 0.11.0); left out by default")
        command.add_argument("--memory-telemetry", choices=["on", "off"],
                             help="write diagnostics.memory_telemetry (loader 0.11.0); left out by default")
        command.add_argument("--require-insecure", choices=["yes", "no"], default="yes")
        if name == "install":
            command.add_argument("--replace-config", action="store_true",
                                 help="replace an existing config.json that differs, after saving it in the evidence folder")
    run = sub.add_parser("run")
    run.add_argument("--name", required=True, help="step name: the evidence subfolder")
    run.add_argument("--map", default="gm_construct")
    run.add_argument("--extra", action="append", default=[], help="argument before +map (repeatable)")
    run.add_argument("--post", action="append", default=[], help="argument after +map, e.g. a console command (repeatable)")
    run.add_argument("--width", type=int, default=1280)
    run.add_argument("--height", type=int, default=720)
    run.add_argument("--no-window", action="store_true",
                     help="leave out -windowed -w -h: the game's saved video settings (and the loader) decide")
    run.add_argument("--timeout", type=int, default=300, help="seconds to wait for the map")
    run.add_argument("--settle", type=int, default=20, help="seconds after the map before screenshots")
    run.add_argument("--screenshots", type=int, default=1)
    run.add_argument("--shot-interval", type=float, default=2.0)
    run.add_argument("--quit-timeout", type=int, default=90)
    run.add_argument("--players", type=int, default=1, help="maxplayers (1: single-player)")
    run.add_argument("--addons", action="store_true", help="mount local add-ons (leave out -noaddons)")
    run.add_argument("--workshop", action="store_true", help="mount Workshop add-ons (leave out -noworkshop)")
    run.add_argument("--menu-shot", action="store_true",
                     help="with --workshop and --map: a screenshot of the main menu (menu.png) once the Workshop is "
                          "mounted, before the map is asked for")
    later = run.add_mutually_exclusive_group()
    later.add_argument("--load-save", help="after the first map, gm_load this save (path relative to garrysmod/)")
    later.add_argument("--change-map", help="after the first map, change to this map (with --mount-workshop for a Workshop map)")
    run.add_argument("--mount-workshop", type=lambda text: str(int(text)), metavar="ID", action="append",
                     help="with --load-save or --change-map: first mount this installed Workshop item from client Lua "
                          "(repeatable: the map, then libraries add-ons need)")
    run.add_argument("--camera", type=lambda text: [float(v) for v in text.split(",")],
                     help="x,y,z,pitch,yaw,roll[,fov]: pin the view with a client CalcView hook before screenshots")
    run.add_argument("--hide-hud", action="store_true", help="hide the HUD and view model (client hooks, no cvars)")
    run.add_argument("--fps", type=float, metavar="SECONDS",
                     help="after --settle, time every frame for SECONDS in client Lua (record: fps)")
    run.add_argument("--console", action="append", default=[], help="console command after the map (repeatable)")
    run.add_argument("--lua", action="append", default=[], metavar="FILE",
                     help="client Lua file run after the map and the camera, through the console (repeatable)")
    run.add_argument("--lua-shots", type=float, metavar="SECONDS",
                     help="after --settle, a screenshot for each 'NL_SHOT <label>' the Lua prints, until NL_SHOT_DONE "
                          "(at most SECONDS)")
    run.add_argument("--reference", action="store_true",
                     help="a reference install: never move its console.log or read the loader's files")
    nl = sub.add_parser("nlctl", help="run nlctl; '{root}' in the arguments becomes the game root")
    nl.add_argument("rest", nargs=argparse.REMAINDER)
    sub.add_parser("uninstall")
    args = parser.parse_args(argv)
    if args.action == "run" and args.menu_shot and not (args.workshop and args.map):
        parser.error("--menu-shot needs --workshop and --map: only then does the run wait at the menu")
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
        code = 1 if record.get("failed") else 0
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
