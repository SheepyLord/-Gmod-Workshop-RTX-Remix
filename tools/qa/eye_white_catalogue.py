"""Audit the production Lua name matcher against a PMX corpus and read-only installed manifests."""
from __future__ import annotations
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
MATCHER = REPO / 'companion/nativeloader/lua/nativeloader/eye_white_names.lua'


def luajit_path():
    return shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) /
                                         'Programs/LuaJIT/bin/luajit.exe')


def lua_string(value):
    return '"' + ''.join('\\' + c if c in '\\"' else f'\\{ord(c):03d}' if ord(c) < 32 else c
                         for c in str(value or '')) + '"'


def classify(pairs, *, interpreter=None):
    """Run the exact shipped matcher once for a batch, keeping every temporary inside this repo."""
    scratch = REPO / 'out/tmp'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='eye-catalogue-', dir=scratch) as temp:
        data = Path(temp) / 'names.lua'
        data.write_text('return {\n' + ',\n'.join('{' + lua_string(a) + ',' + lua_string(b) + '}'
                                                for a, b in pairs) + '\n}\n', encoding='utf-8')
        runner = Path(temp) / 'match.lua'
        runner.write_text('local m=dofile(arg[1]) for _,p in ipairs(dofile(arg[2])) do '
                          'io.write(m.matches(p[1],p[2]) and "1\\n" or "0\\n") end\n', encoding='utf-8')
        result = subprocess.run([interpreter or luajit_path(), str(runner), str(MATCHER), str(data)],
                                capture_output=True, text=True, encoding='utf-8', timeout=60, check=True)
    values = result.stdout.splitlines()
    if len(values) != len(pairs) or any(v not in ('0', '1') for v in values):
        raise ValueError('matcher returned an incomplete or invalid result')
    return [v == '1' for v in values]


def audit(models, *, interpreter=None):
    items = [(model, material) for model in models for material in model.get('materials', [])]
    decisions = classify([(m.get('name', ''), m.get('en') or m.get('englishName') or m.get('nameEnglish', ''))
                          for _, m in items], interpreter=interpreter)
    hits, near = [], []
    for (model, material), eligible in zip(items, decisions):
        entry = {'model': model.get('id') or model.get('path') or model.get('name'),
                 'model_name': model.get('name'), **material}
        if eligible:
            hits.append(entry)
        elif any(token in (str(material.get('name', '')) + ' ' + str(material.get('en', ''))).lower()
                 for token in ('白', 'eye', 'sclera', '角膜', 'cornea', 'shirome')):
            near.append(entry)
    hit_models = {e['model'] for e in hits}
    shared = {e['model'] for e in hits if e.get('shared')}
    return {'models': len(models), 'materials': len(items), 'hit_models': len(hit_models),
            'hit_materials': len(hits), 'shared_texture_hit_models': len(shared),
            'models_without_named_eye_white': len(models) - len(hit_models),
            'hit_names': dict(Counter(e.get('name', '') + ' | ' + str(e.get('en', '')) for e in hits)),
            'hits': hits, 'near_misses_for_review': near,
            'ground_truth': 'Name/English-name audit only; unnamed or combined eye/face meshes cannot be inferred.'}


def library_models(path):
    models = []
    for manifest in sorted(Path(path).glob('*/manifest.json')):
        model = json.loads(manifest.read_text(encoding='utf-8-sig'))
        model['id'] = manifest.parent.name
        for material in model.get('materials', []):
            material['tex'] = material.get('base', '')
            material['shared'] = [m.get('name', '') for m in model['materials']
                                  if m is not material and material['tex'] and m.get('base') == material['tex']]
        models.append(model)
    return models


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path)
    parser.add_argument('--library', action='append', default=[], metavar='LABEL=ASSETS_DIRECTORY')
    parser.add_argument('--luajit')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args(argv)
    sources = {}
    if args.corpus:
        sources['corpus'] = [json.loads(line) for line in args.corpus.read_text(encoding='utf-8').splitlines() if line.strip()]
    for value in args.library:
        label, path = value.split('=', 1)
        sources[label] = library_models(path)
    if not sources:
        parser.error('supply --corpus and/or --library')
    report = {label: audit(models, interpreter=args.luajit) for label, models in sources.items()}
    output = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(output, encoding='utf-8')
    else:
        print(output, end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
