"""Paired R9 fracture/handler/split costs and native sound/buoyancy CPU costs; no game access."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def fields(text):
    return {k: float(v) for k, v in re.findall(r'(\w+)=(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)', text)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--before-lua', type=Path, required=True)
    p.add_argument('--before-native', type=Path, required=True)
    p.add_argument('--out', type=Path, default=ROOT / 'out/qa-r9/feature-costs')
    p.add_argument('--runs', type=int, default=3)
    a = p.parse_args()
    dest = a.out.resolve()
    if not dest.is_relative_to(ROOT / 'out') or not 1 <= a.runs <= 10:
        p.error('output must stay in this worktree/out; runs 1-10')
    dest.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TEMP=str(scratch), TMP=str(scratch))
    lua = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
    native = ROOT / 'out/build/win64-release/glass/native/nl_glass_tests.exe'
    samples = {}

    def run(label, argv):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT, env=env, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=180)
        (dest / (label + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise RuntimeError(f'{label} failed: see its log')
        return result.stdout.splitlines()

    def record(key, line):
        samples.setdefault(key, []).append(fields(line))

    for i in range(a.runs):
        for name, source, executable in [('before', a.before_lua.resolve(), a.before_native.resolve()),
                                         ('after', ROOT / 'glass/addon/lua', native)]:
            for harness, mode in [('nlglass_fracture_harness.lua', 'timings'),
                                  ('nlglass_engine_harness.lua', 'client_timings')]:
                for line in run(f'{name}-{mode}-{i+1}', [lua, ROOT / 'tools/tests' / harness, source, mode]):
                    if re.match(r'\w+ n=\d+ mean_ms=', line):
                        record(f'{mode}/{line.split()[0]}/{name}', line)
            for line in run(f'{name}-split-{i+1}', [executable, 'glass interaction benchmark bounds']):
                if line.startswith('R7-C split '):
                    record('native/binary-split/' + name, line)
        for line in run(f'environment-{i+1}', [native, 'glass R9 environment benchmark']):
            if line.startswith('R9 environment '):
                v = fields(line)
                record(f'native/environment/water-{int(v["water"])}/sound-{int(v["sound"])}', line)
            elif line.startswith('R9 split '):
                record('native/multi-split/after', line)
    medians = {k: {field: statistics.median(row[field] for row in rows) for field in rows[0]}
               for k, rows in samples.items()}
    result = {'runs': a.runs, 'medians': medians, 'samples': samples}
    (dest / 'costs.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(medians, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
