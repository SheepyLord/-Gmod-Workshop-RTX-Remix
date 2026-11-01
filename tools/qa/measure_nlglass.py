"""Compare saved R7 and current offline glass workloads. Never starts GMod or reads an install."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def fields(line):
    return {key: float(value) for key, value in re.findall(r'(\w+)=(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)', line)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-lua', required=True, type=Path)
    parser.add_argument('--before-native', required=True, type=Path)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--out', type=Path, default=ROOT / 'out/r8-g/measurements')
    args = parser.parse_args()
    destination = args.out.resolve()
    if not destination.is_relative_to(ROOT / 'out') or not 1 <= args.runs <= 10:
        parser.error('outputs must stay in this worktree/out; runs must be 1-10')
    lua = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
    current_native = ROOT / 'out/build/win64-release/glass/native/nl_glass_tests.exe'
    destination.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TEMP=str(scratch), TMP=str(scratch))
    samples = {}

    def record(key, row):
        samples.setdefault(key, []).append(row)

    def run(label, argv):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT, env=env,
                                capture_output=True, encoding='utf-8', errors='replace', timeout=180)
        (destination / (label + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise RuntimeError(f'{label} failed with {result.returncode}; see its log')
        return result.stdout.splitlines()

    for iteration in range(args.runs):
        print(f'measuring interleaved run {iteration + 1}/{args.runs}', flush=True)
        for phase in ('loadperf', 'interactionoffperf', 'interactionperf'):
            for label, source in (('before', args.before_lua), ('after', ROOT / 'glass/addon/lua')):
                rows = run(f'{phase}-{label}-{iteration+1}', [lua, ROOT / 'tools/tests/glass_debris_harness.lua',
                           source.resolve(), ROOT / 'tools/qa/glass_debris_jolt_probe.lua', phase])
                for line in rows:
                    if line.startswith('R8-G loadperf '):
                        record(f'load/{label}', fields(line))
                    elif line.startswith('G1-B renderperf '):
                        state = line.split()[2]
                        record(f'{phase}/{state}/{label}', fields(line))
        for label, source in (('before', args.before_lua), ('after', ROOT / 'glass/addon/lua')):
            for line in run(f'capture-{label}-{iteration+1}', [lua, ROOT / 'tools/tests/glass_interaction_harness.lua', source.resolve(), 'sceneperf']):
                if line.startswith('R7-C capture '):
                    record('capture/' + line.split()[2] + '/' + label, fields(line))
        for label, executable in (('before', args.before_native.resolve()), ('after', current_native)):
            for line in run(f'native-guard-{label}-{iteration+1}', [executable, 'glass benchmark 4000']):
                if line.startswith('G1-B benchmark:'):
                    record(f'native-guard/{label}', fields(line))
        for line in run(f'native-load-{iteration+1}', [current_native, 'glass adaptive load benchmark']):
            if line.startswith('R8-G load '):
                row = fields(line)
                record('native-load/' + ('after' if row['grouped'] else 'before'), row)
    medians = {key: {field: statistics.median(row[field] for row in values) for field in values[0]}
               for key, values in samples.items()}
    (destination / 'costs.json').write_text(json.dumps({'runs': args.runs, 'medians': medians, 'samples': samples}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(medians, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
