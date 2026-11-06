"""Prepare Blood Overhaul's permitted resources and the user's PBR; never deploy anything.

python -I tools/prepare_blood.py --project <blood_overhaul_rtx> --out out/r21a/prepared
The output is an import-ready part tree plus a provenance/exclusion audit. See prepare_blood.py.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct

PATTERNS = frozenset('arterial_trail castoff_sweep dark_core_halo directional_spray double_impact '
                     'drip_runs drops_scatter heavy_splash impact_dense long_swipe mist_cloud pooled_smear '
                     'ring_spatter shotgun_clusters sparse_mist spray_fan streak_web torn_blotches'.split())
FAMILIES = {'red': (1, 1, 1), 'alien': (.78, .70, .24), 'green': (.43, .55, .12), 'worker': (.67, .82, .14)}
ORIGINALS = {f'bo_blood{i}': units for i, units in enumerate((41, 51.2, 61.4, 41, 51.2, 41, 45.1, 24.6), 1)}
MAPS = PATTERNS | ORIGINALS.keys() | {f'{family}{i}' for family in ('flesh', 'alienflesh') for i in range(1, 6)} | {
    f'bo_yblood{i}' for i in range(1, 7)} | {f'bloodstain_{i}' for i in ('001', '002', '003', '003b', '101')}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_shapes(manifest: dict) -> list[dict]:
    keys = PATTERNS | ORIGINALS.keys()
    shapes = [s for s in manifest['shapes'] if s['key'] in keys]
    if len(shapes) != len(keys) or {s['key'] for s in shapes} != keys:
        raise ValueError('expected each of the twenty-six patterns exactly once')
    for shape in shapes:
        if shape['kind'] != 'pool' or shape['units'] <= 0 or len(shape['size']) != 2 or min(shape['size']) <= 0:
            raise ValueError('invalid pattern')
        if shape['key'] in ORIGINALS and shape['units'] != ORIGINALS[shape['key']]:
            raise ValueError('original shape world size differs from the published shape list')
        textures = shape['textures']
        expected = {f'decals/bloodoverhaul/tex/{shape["key"]}', f'decals/bloodoverhaul/tex/{shape["key"]}_n'}
        if shape['key'] in ORIGINALS:
            expected.add('decals/blood' + shape['key'].removeprefix('bo_blood'))
        if len(textures) != len(expected) or {t['tex'] for t in textures} != expected:
            raise ValueError('pattern references an unexpected game texture')
        for texture in textures:
            for algorithm in ('xxh64', 'xxh3'):
                if not re.fullmatch(r'0x[0-9A-Fa-f]{16}', texture['hash'][algorithm]):
                    raise ValueError('invalid texture hash')
    # The original eight lead the list: variety off preserves bloodN's requested shape.
    return sorted(shapes, key=lambda s: (s['key'] not in ORIGINALS, s['key']))


def selected_layer(layer: str, shapes: list[dict]) -> str:
    wanted = {t['hash'][alg][2:].upper() for s in shapes for t in s['textures'] for alg in ('xxh64', 'xxh3')}
    blocks = {}
    for match in re.finditer(r'        over "mat_([0-9A-Fa-f]{16})"\s*\{', layer):
        start, end, depth = match.start(), match.end(), 1
        while depth and end < len(layer):
            depth += (layer[end] == '{') - (layer[end] == '}')
            end += 1
        key = match[1].upper()
        if key not in wanted:
            continue
        if depth or key in blocks:
            raise ValueError('unbalanced/duplicate material block')
        block = layer[start:end].replace('bool inputs:preload_textures = 1', 'bool inputs:preload_textures = 0')
        allowed = {s['key'] + suffix for s in shapes for suffix in ('.a', '_n.a', '.n', '.r')}
        paths = re.findall(r'@\./textures/([^@]+)\.rtex\.dds@', block)
        if len(paths) != 3 or any(p not in allowed for p in paths):
            raise ValueError('material block references an unknown DDS')
        blocks[key] = block
    if set(blocks) != wanted:
        raise ValueError('missing material hash')
    return ('#usda 1.0\n(\n    doc = "Blood Overhaul resources by permission, with SheepyLord PBR and analytic impacts."\n'
            '    upAxis = "Z"\n)\nover "RootNode"\n{\n    over "Looks"\n    {\n' +
            '\n'.join(blocks[key] for key in sorted(blocks)) + '\n    }\n}\n')


def vmt(texture: str, family: str, scale: float, model: bool) -> str:
    shader = 'VertexLitGeneric' if model else 'LightmappedGeneric'
    colour = ' '.join(f'{v:.3f}' for v in FAMILIES[family])
    fields = {'$basetexture': texture, '$decal': '1', '$translucent': '1', '$decalscale': f'{scale:.6f}',
              '$color2' if model else '$color': f'[{colour}]'}
    if not model:
        key = texture.rsplit('/', 1)[1].removesuffix('_n')
        fields['$modelmaterial'] = f'decals/bloodoverhaul/{family}/{key}_model'
    return '"' + shader + '"\n{\n' + ''.join(f'    "{k}" "{v}"\n' for k, v in fields.items()) + '}\n'


def procedural_vtf(size: int, mist: bool) -> bytes:
    """Original analytic shapes, RGBA8888 VTF 7.2. No existing image is read or transformed."""
    rgba = bytearray()
    for y in range(size):
        for x in range(size):
            u, v = (x + .5) / size * 2 - 1, (y + .5) / size * 2 - 1
            if mist:
                radius = math.hypot(u, v)
                noise = .78 + .22 * math.sin(x * 1.7 + math.cos(y * 2.3))
                alpha = max(0, 1 - radius) ** 2 * noise
            else:
                # Surface-tension bead with a short taper. Thin bright rim is coverage, not glow.
                radius = math.hypot(u / (.50 - .17 * v), (v + .12) / .76)
                alpha = max(0, min(1, (1 - radius) * 14))
            rgba.extend((210, 210, 210, round(alpha * 255)))
    header = bytearray(80)
    struct.pack_into('<4sIIIHHIHH', header, 0, b'VTF\0', 7, 2, 80, size, size, 0x220C, 1, 0)
    struct.pack_into('<3f', header, 32, .5, .5, .5)
    struct.pack_into('<f', header, 48, 1)
    struct.pack_into('<iB', header, 52, 0, 1)  # RGBA8888, one mip
    struct.pack_into('<i', header, 57, -1)
    struct.pack_into('<H', header, 63, 1)
    return bytes(header + rgba)


def prepare(project: Path, output: Path) -> dict:
    project, output = project.resolve(), output.resolve()
    repo = Path(__file__).resolve().parents[1]
    scratch = repo / 'out'
    if not output.is_relative_to(scratch) or output == scratch or output.is_relative_to(project):
        raise ValueError('output must be a new folder under this worktree/out, outside the source')
    if output.exists():
        raise ValueError('output already exists; choose a new folder')
    manifest = json.loads((project / 'work/manifest.json').read_text(encoding='utf-8'))
    shapes = select_shapes(manifest)
    maps = manifest['shapes']
    if len(maps) != len(MAPS) or {s['key'] for s in maps} != MAPS:
        raise ValueError('unexpected or missing PBR shape')
    source_addon, source_mod = project / 'dist/addon', project / 'dist/remix_mod/blood_overhaul_rtx'
    layer = selected_layer((source_mod / 'replacements.usda').read_text(encoding='utf-8'), maps)
    referenced = set(re.findall(r'@\./textures/([^@]+)@', layer))
    available = {p.name for p in (source_mod / 'textures').glob('*.dds')}
    if referenced != available:
        raise ValueError('PBR DDS inventory and material references differ')
    md5s = {}
    for line in (project / 'backup/blood_overhaul_md5.txt').read_text(encoding='utf-8-sig').splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{32})\s+\*?\./(.+)', line)
        if not match:
            raise ValueError('invalid original MD5 inventory line')
        md5s[match[2].lower()] = match[1].lower()
    addon, mod = output / 'nlblood', output / 'nl_blood_overhaul_rtx'
    selected, generated = {}, {}

    def authorship(source: Path):
        rel = source.relative_to(source_addon).as_posix() if source.is_relative_to(source_addon) else ''
        if rel.lower() in md5s:
            original = md5s[rel.lower()]
            same = hashlib.md5(source.read_bytes()).hexdigest() == original
            return {'authorship': 'Crunchy unchanged' if same else 'Crunchy file modified by SheepyLord',
                    'original_md5': original, 'matches_original_md5': same}
        if any(key in source.name for key in PATTERNS):
            return {'authorship': 'SheepyLord AI-generated pattern or its PBR/material'}
        if source.suffix.lower() in ('.vtf', '.dds'):
            return {'authorship': 'SheepyLord conversion/PBR derived from Crunchy resources'}
        return {'authorship': 'SheepyLord material, Lua data or layer'}

    def copy(source: Path, target: Path):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        selected[source.relative_to(project).as_posix()] = {
            'sha256': sha(source), 'to': target.relative_to(output).as_posix(),
            'reason': 'source bytes included with the resource author\'s permission' if source.suffix.lower() in ('.dds', '.vtf')
                      else 'published source bytes retained', **authorship(source)}

    def text(target: Path, body: str):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding='utf-8', newline='\n')
        generated[target.relative_to(output).as_posix()] = {'sha256': sha(target), 'reason': 'private package material, data or layer'}

    for source in sorted((source_addon / 'materials').rglob('*')):
        if source.is_file() and 'particle/bo_droplets/' not in source.as_posix():
            if source.suffix.lower() not in ('.vmt', '.vtf'):
                raise ValueError('unexpected add-on asset')
            copy(source, addon / source.relative_to(source_addon))
    for name in sorted(referenced):
        copy(source_mod / 'textures' / name, mod / 'textures' / name)
    for shape in shapes:
        key = shape['key']
        # Published red/alien VMTs stay byte-identical. R20-C adds the other species.
        for family in ('green', 'worker'):
            tex = f'decals/bloodoverhaul/tex/{key}' + ('' if family == 'red' else '_n')
            for model in (False, True):
                path = addon / f'materials/decals/bloodoverhaul/{family}/{key}'
                text(Path(str(path) + ('_model' if model else '') + '.vmt'),
                     vmt(tex, family, shape['units'] / shape['size'][0], model))
    scheme_source = project / 'addon_src/lua/bloodoverhaul/cl_schemes.lua'
    copy(scheme_source, addon / 'lua/nlblood/schemes.lua')
    text(addon / 'lua/nlblood/shapes.lua', 'return {\n' + ''.join(
        f'    {{ key = "{s["key"]}", units = {s["units"]:g} }},\n' for s in shapes) + '}\n')
    text(addon / 'addon.json', json.dumps({'title': 'Blood Overhaul RTX', 'type': 'effects', 'tags': ['realism']}, indent=2))
    text(mod / 'replacements.usda', layer)
    text(mod / 'mod.usda', '#usda 1.0\n(\n    customLayerData = {\n'
         '        string lightspeed_game_name = "Garry\'s Mod (x64)"\n'
         '        string lightspeed_layer_type = "replacement"\n'
         '        string lightspeed_mod_name = "nl_blood_overhaul_rtx"\n    }\n'
         '    subLayers = [@./replacements.usda@]\n    metersPerUnit = 0.01\n    upAxis = "Z"\n)\n')
    for name, size in (('drop', 128), ('mist', 64)):
        path = addon / f'materials/particle/nlfluid/{name}.vtf'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(procedural_vtf(size, name == 'mist'))
        generated[path.relative_to(output).as_posix()] = {'sha256': sha(path), 'reason': 'unchanged R20-C analytic sprite; no source image'}
    excluded = {}
    copy(project / 'tools/prompts.json', output / 'prompts.json')
    transformed = {
        'dist/addon/lua/bloodoverhaul/sh_shapes.lua': 'world sizes retained in private shapes.lua; legacy global code replaced',
        'dist/remix_mod/blood_overhaul_rtx/replacements.usda': 'all hash overrides retained with lazy loading, plus R20-C sprites',
        'dist/remix_mod/blood_overhaul_rtx/mod.usda': 'private Remix mod identity prevents a collision with the legacy folder',
    }
    for path in sorted(project.rglob('*')):
        if not path.is_file() or path.relative_to(project).as_posix() in selected:
            continue
        rel = path.relative_to(project).as_posix()
        if rel in transformed:
            reason = transformed[rel]
        elif 'particle/bo_droplets/' in rel:
            reason = 'unused old blood8-derived droplet replaced by R20-C analytic sprites'
        elif path.is_relative_to(source_addon) and path.suffix == '.lua':
            reason = 'legacy mixer/menu replaced by the companion private implementation'
        elif path.is_relative_to(source_addon) and path.name == 'addon.json':
            reason = 'package identity replaces standalone add-on metadata'
        else:
            reason = 'development/source/reference/backup or duplicate distribution output; not a runtime input'
        excluded[rel] = {'sha256': sha(path), 'reason': reason}
    audit = {'schema': 2, 'project': str(project), 'patterns': [s['key'] for s in shapes],
             'permission': {'author': 'Crunchy', 'workshop': '2683396098', 'obtained_by': 'SheepyLord',
                            'date': '2026-11-06', 'terms': 'Included by permission; Crunchy resources and derivatives are not MIT.'},
             'selected': selected, 'excluded': excluded, 'generated': generated,
             'note': 'Audit covers every source-project file. Eighteen AI-generated patterns used Crunchy style references; '
                     'reference images do not ship. All selected source bytes are unchanged. Stock blood materials now ship. '
                     'Original MD5 comparisons distinguish unchanged Crunchy files from the user\'s edits.'}
    text(output / 'provenance.json', json.dumps(audit, indent=2, ensure_ascii=True) + '\n')
    return audit


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        audit = prepare(args.project, args.out)
        print(f'{len(audit["patterns"])} patterns; {len(audit["selected"])} copied files; {len(audit["excluded"])} excluded; {args.out}')
    except (OSError, ValueError, KeyError) as error:
        print(f'prepare_blood: {error}')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
