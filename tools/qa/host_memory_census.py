"""Turn the runtime's host memory census (R13-B, runtime patch 0023) into an account.

Reads one session's remix-dxvk.log. Every census the runtime wrote (rtx.profiler.memory.requestSnapshot)
becomes one snapshot: Vulkan memory types with their chunks and dedicated allocations, the process
counters, the committed address space by protection with the part DXVK's own mappings cover, and, when
the memory profiler ran from launch, the allocation groups by purpose. The account splits the committed
private address space into texture CPU copies, other DXVK host memory, staging, Remix's own host
memory and what the driver maps (device-local memory shows as write-combined private memory).

  python tools/qa/host_memory_census.py <remix-dxvk.log> [--out account.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HOST = re.compile(r"^\[(\d\d:\d\d:\d\d\.\d+)\] info:\s+\[RTX Host Memory\] (\{.*\})\s*$")
ALLOCATION = re.compile(r"^\[(\d\d:\d\d:\d\d\.\d+)\] info:\s+\[RTX Allocation\] (\{.*\})\s*$")
MANAGED = re.compile(r"^\[(\d\d:\d\d:\d\d\.\d+)\] info:\s+\[RTX Managed Textures\] (.*)$")
BUDGET = re.compile(r"^\[(\d\d:\d\d:\d\d\.\d+)\] info:\s+\[RTX Texture Budget\] (\{.*\})\s*$")

HOST_VISIBLE, HOST_COHERENT, HOST_CACHED, DEVICE_LOCAL = 0x2, 0x4, 0x8, 0x1
PAGE_READWRITE, PAGE_READWRITE_WRITECOMBINE = 0x4, 0x404
CATEGORIES = {0: 'invalid', 1: 'app_buffer', 2: 'app_texture', 3: 'replacement_geometry', 4: 'rtx_buffer',
              5: 'acceleration_structure', 6: 'opacity_micromap', 7: 'replacement_texture', 8: 'render_target'}
TEXTURE_COPY_NAMES = ('d3d9 texture copy',)
STAGING_WORDS = ('staging', 'temp buffer', 'upload', 'readback')


def flags_text(flags: int) -> str:
    parts = [name for bit, name in ((DEVICE_LOCAL, 'device_local'), (HOST_VISIBLE, 'host_visible'),
                                    (HOST_COHERENT, 'host_coherent'), (HOST_CACHED, 'host_cached')) if flags & bit]
    return '|'.join(parts) or 'none'


def parse(text: str) -> dict:
    snapshots: dict[int, dict] = {}
    managed, budget = [], []
    for line in text.splitlines():
        if match := HOST.match(line):
            row = json.loads(match[2])
            snap = snapshots.setdefault(row['frame'], dict(frame=row['frame'], time=match[1], memory_types=[],
                                                           mappings=[], address_space=[], groups=[], complete=False))
            event = row['event']
            if event == 'memory_type':
                snap['memory_types'].append(row)
            elif event == 'host_mapping':
                snap['mappings'].append(row)
            elif event == 'process':
                snap['process'] = row
            elif event == 'address_space':
                snap['address_space'].append(row)
            elif event == 'end':
                snap['complete'] = True
        elif match := ALLOCATION.match(line):
            row = json.loads(match[2])
            snap = snapshots.get(row['frame'])
            if snap is not None and row['event'] == 'group':
                snap['groups'].append(row)
            elif snap is not None and row['event'] == 'begin':
                snap['expected_groups'] = row['groups']
        elif match := MANAGED.match(line):
            body = match[2].strip()
            managed.append(dict(time=match[1], **(json.loads(body) if body.startswith('{') else dict(text=body))))
        elif match := BUDGET.match(line):
            budget.append(dict(time=match[1], **json.loads(match[2])))
    return dict(snapshots=[snapshots[k] for k in sorted(snapshots)], managed=managed, budget=budget)


def account(snap: dict) -> dict:
    types = {row['type']: row for row in snap['memory_types']}
    space = defaultdict(lambda: dict(committed=0, dxvk=0, by_type={}))
    for row in snap['address_space']:
        if row['kind'] != 'private':
            continue
        key = 'rw' if row['protect'] == PAGE_READWRITE else 'wc' if row['protect'] == PAGE_READWRITE_WRITECOMBINE else hex(row['protect'])
        entry = space[key]
        entry['committed'] += row['committed']
        for type_id, nbytes in row['dxvk_by_type'].items():
            entry['by_type'][type_id] = entry['by_type'].get(type_id, 0) + nbytes
            entry['dxvk'] += nbytes
    for entry in space.values():
        entry['other'] = entry['committed'] - entry['dxvk']

    purposes = defaultdict(lambda: dict(bytes=0, count=0))
    for group in snap['groups']:
        flags = group.get('memory_flags', 0)
        key = (group.get('name', '?'), CATEGORIES.get(group['category'], str(group['category'])), flags,
               bool(group.get('released')))
        purposes[key]['bytes'] += group['bytes']
        purposes[key]['count'] += group['count']
    rows = [dict(name=k[0], category=k[1], memory_flags=k[2], memory=flags_text(k[2]), released=k[3], **v)
            for k, v in purposes.items()]
    rows.sort(key=lambda r: r['bytes'], reverse=True)

    host = [r for r in rows if r['memory_flags'] & HOST_VISIBLE and not r['memory_flags'] & DEVICE_LOCAL]
    # Each host row counts once: texture copies, then staging (by name), then Remix's own categories.
    buckets = defaultdict(int)
    for r in host:
        if r['name'] in TEXTURE_COPY_NAMES:
            buckets['texture_cpu_copies'] += r['bytes']
        elif any(w in r['name'].lower() for w in STAGING_WORDS):
            buckets['staging_and_upload'] += r['bytes']
        elif r['category'] not in ('app_buffer', 'app_texture'):
            buckets['remix_host_memory'] += r['bytes']
        else:
            buckets['other_dxvk_host_memory'] += r['bytes']
    texture_copies, staging = buckets['texture_cpu_copies'], buckets['staging_and_upload']
    remix, other_host = buckets['remix_host_memory'], buckets['other_dxvk_host_memory']
    released = sum(r['bytes'] for r in rows if r['released'])
    result = dict(
        frame=snap['frame'], time=snap['time'], complete=snap['complete'], process=snap.get('process', {}),
        memory_types=[dict(type=t['type'], heap=t['heap'], memory=flags_text(t['flags']), chunks=t['chunks'],
                           chunk_bytes=t['chunk_bytes'], chunk_used=t['chunk_used'], dedicated=t['dedicated'],
                           dedicated_bytes=t['dedicated_bytes']) for t in types.values()],
        private_address_space=dict(space),
        purposes_available=bool(snap['groups']),
        host_visible_purposes=host[:25], device_local_purposes=[r for r in rows if r['memory_flags'] & DEVICE_LOCAL][:25],
        account=dict(texture_cpu_copies=texture_copies, staging_and_upload=staging, remix_host_memory=remix,
                     other_dxvk_host_memory=other_host,
                     released_images_still_held=released,
                     rw_not_dxvk=space['rw']['other'] if 'rw' in space else None,
                     wc_not_dxvk_driver_mapped=space['wc']['other'] if 'wc' in space else None))
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('log', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args(argv)
    parsed = parse(args.log.read_text(encoding='utf-8', errors='replace'))
    result = dict(log=str(args.log), snapshots=[account(s) for s in parsed['snapshots']],
                  managed=parsed['managed'], texture_budget=parsed['budget'])
    text = json.dumps(result, indent=1)
    if args.out:
        args.out.write_text(text, encoding='utf-8')
    else:
        print(text)
    incomplete = [s['frame'] for s in parsed['snapshots'] if not s['complete']]
    if incomplete:
        print(f'host_memory_census: incomplete snapshots {incomplete}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
