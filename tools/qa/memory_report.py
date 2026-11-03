"""One game session's memory, read-only (R13, ADR 0101).

RAM comes from the loader's memory telemetry (native-loader/logs/memory.csv and memory.1.csv, every
10 seconds, ADR 0063), VRAM from the companion's (garrysmod/data/native-loader/vram.csv and
vram.previous.csv, every 30 seconds). Each named phase reports the peak and the last sample of every
measure inside its window. --census-pid adds an address-space census of a running game: committed
memory by type and protection, and its private allocations by size (VirtualQueryEx; no memory is read).
"""
import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

RAM_FILES = ('native-loader/logs/memory.1.csv', 'native-loader/logs/memory.csv')
VRAM_FILES = ('garrysmod/data/native-loader/vram.previous.csv', 'garrysmod/data/native-loader/vram.csv')
RAM = {'private': 'private_bytes', 'working_set': 'working_set_bytes', 'system_commit': 'system_commit_bytes',
       'gpu_local_usage': 'gpu_local_usage_bytes', 'gpu_local_budget': 'gpu_local_budget_bytes'}
VRAM = {'driver_allocated': 'driverAllocatedBytes', 'driver_budget': 'driverBudgetBytes',
        'dxvk_allocated': 'totalAllocatedBytes', 'dxvk_used': 'totalUsedBytes',
        'game_textures': 'usedAppTextureBytes', 'replacement_textures': 'usedMaterialTextureBytes',
        'render_targets': 'usedRenderTargetBytes', 'acceleration_structures': 'usedAccelerationStructureBytes',
        'opacity_micromaps': 'usedOpacityMicromapBytes', 'buffers': 'usedBufferBytes'}


class ReportError(Exception):
    pass


def utc(text):
    try:
        value = datetime.strptime(text, '%Y-%m-%dT%H:%M:%SZ')
    except ValueError as error:
        raise ReportError(f'not a UTC time like 2026-11-03T10:00:00Z: {text}') from error
    return value.replace(tzinfo=timezone.utc)


def rows(root, names, columns):
    """Every sample of the files, oldest first, with the named columns as integers (None if empty)."""
    found = []
    for name in names:
        path = Path(root) / name
        if not path.is_file():
            continue
        with path.open(encoding='utf-8-sig', newline='') as handle:
            for row in csv.DictReader(handle):
                try:
                    time = utc(row['time_utc'])
                except (KeyError, ReportError):
                    continue
                found.append((time, {key: int(row[column]) if row.get(column) else None for key, column in columns.items()}))
    found.sort(key=lambda item: item[0])
    return found


def window(samples, start, end):
    inside = [values for time, values in samples if start <= time and (end is None or time <= end)]
    result = {}
    for key in (inside[0] if inside else {}):
        values = [sample[key] for sample in inside if sample[key] is not None]
        if values:
            result[key] = {'peak_gb': round(max(values) / 1e9, 3), 'last_gb': round(values[-1] / 1e9, 3)}
    return len(inside), result


def census(pid):
    """Committed memory of a process by type and protection, and its private allocations by size."""
    import ctypes
    from ctypes import wintypes

    class MBI(ctypes.Structure):
        _fields_ = [('BaseAddress', ctypes.c_void_p), ('AllocationBase', ctypes.c_void_p),
                    ('AllocationProtect', wintypes.DWORD), ('PartitionId', wintypes.WORD),
                    ('RegionSize', ctypes.c_size_t), ('State', wintypes.DWORD), ('Protect', wintypes.DWORD),
                    ('Type', wintypes.DWORD)]

    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.VirtualQueryEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
    kernel32.VirtualQueryEx.restype = ctypes.c_size_t
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel32.OpenProcess(0x0400, False, pid)  # PROCESS_QUERY_INFORMATION only: nothing is read
    if not handle:
        raise ReportError(f'cannot open process {pid} (Windows error {ctypes.get_last_error()})')
    types = {0x20000: 'private', 0x40000: 'mapped', 0x1000000: 'image'}
    protections = {0x04: 'read-write', 0x404: 'read-write write-combined', 0x204: 'read-write uncached',
                   0x02: 'read-only', 0x20: 'execute-read', 0x40: 'execute-read-write', 0x08: 'write-copy'}
    by_type, by_protection, allocations = Counter(), Counter(), defaultdict(int)
    address, mbi = 0, MBI()
    try:
        while address < 1 << 47 and kernel32.VirtualQueryEx(handle, ctypes.c_void_p(address), ctypes.byref(mbi), ctypes.sizeof(mbi)):
            if mbi.State == 0x1000:  # MEM_COMMIT
                kind = types.get(mbi.Type, hex(mbi.Type))
                by_type[kind] += mbi.RegionSize
                if kind == 'private':
                    by_protection[protections.get(mbi.Protect, hex(mbi.Protect))] += mbi.RegionSize
                    allocations[mbi.AllocationBase or 0] += mbi.RegionSize
            address = (mbi.BaseAddress or 0) + mbi.RegionSize
    finally:
        kernel32.CloseHandle(handle)
    buckets = Counter()
    for size in allocations.values():
        mib = size / (1 << 20)
        buckets['256 MiB or more' if mib >= 256 else '64-256 MiB' if mib >= 64 else '16-64 MiB' if mib >= 16
                else '1-16 MiB' if mib >= 1 else 'under 1 MiB'] += size
    gb = lambda counter: {key: round(value / 1e9, 3) for key, value in counter.most_common()}
    return {'pid': pid, 'committed_gb': gb(by_type), 'private_by_protection_gb': gb(by_protection),
            'private_allocations': len(allocations), 'private_by_allocation_size_gb': gb(buckets)}


def report(root, since, until, phases, census_pid=None):
    ram, vram = rows(root, RAM_FILES, RAM), rows(root, VRAM_FILES, VRAM)
    result = {'root': str(root), 'since': since, 'until': until, 'phases': {}}
    start, end = utc(since), utc(until) if until else None
    for name, (phase_start, phase_end) in [('session', (start, end)), *phases]:
        ram_count, ram_values = window(ram, phase_start, phase_end)
        vram_count, vram_values = window(vram, phase_start, phase_end)
        result['phases'][name] = {'ram_samples': ram_count, 'ram': ram_values, 'vram_samples': vram_count, 'vram': vram_values}
    if not result['phases']['session']['ram_samples'] and not result['phases']['session']['vram_samples']:
        raise ReportError(f'no memory or VRAM samples in {root} since {since}')
    if census_pid is not None:
        result['census'] = census(census_pid)
    return result


def phase(text):
    name, separator, span = text.partition('=')
    if not separator or not name:
        raise argparse.ArgumentTypeError('a phase is NAME=START or NAME=START/END, in UTC')
    first, _, last = span.partition('/')
    try:
        return name, (utc(first), utc(last) if last else None)
    except ReportError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--root', required=True, type=Path, help='the game root (the folder with gmod.exe)')
    parser.add_argument('--since', required=True, help='session start, UTC: 2026-11-03T10:00:00Z')
    parser.add_argument('--until', help='session end, UTC (default: the last sample)')
    parser.add_argument('--phase', action='append', type=phase, default=[], help='NAME=START[/END], UTC; repeatable')
    parser.add_argument('--census-pid', type=int, help='also census this running process')
    parser.add_argument('--out', type=Path, help='also write the report here')
    args = parser.parse_args(argv)
    try:
        result = report(args.root, args.since, args.until, args.phase, args.census_pid)
    except (ReportError, OSError) as error:
        print(f'memory_report: {error}', file=sys.stderr)
        return 1
    text = json.dumps(result, indent=1, ensure_ascii=False)
    print(text)
    if args.out:
        args.out.write_text(text + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
