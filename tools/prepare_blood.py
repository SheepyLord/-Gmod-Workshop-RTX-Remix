"""Select only the user's eighteen generated Blood Overhaul RTX patterns; never deploy anything.

python -I tools/prepare_blood.py --project <blood_overhaul_rtx> --out out/r20c/prepared
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


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_shapes(manifest: dict) -> list[dict]:
    shapes = [s for s in manifest['shapes'] if s['key'] in PATTERNS]
    if len(shapes) != len(PATTERNS) or {s['key'] for s in shapes} != PATTERNS:
        raise ValueError('expected each of the eighteen owned patterns exactly once')
    for shape in shapes:
        if shape['kind'] != 'pool' or shape['units'] <= 0:
            raise ValueError('invalid owned pattern')
        textures = shape['textures']
        expected = {f'decals/bloodoverhaul/tex/{shape["key"]}', f'decals/bloodoverhaul/tex/{shape["key"]}_n'}
        if len(textures) != 2 or {t['tex'] for t in textures} != expected or any(t.get('original') for t in textures):
            raise ValueError('owned pattern references an original or unexpected game texture')
        for texture in textures:
            for algorithm in ('xxh64', 'xxh3'):
                if not re.fullmatch(r'0x[0-9A-Fa-f]{16}', texture['hash'][algorithm]):
                    raise ValueError('invalid texture hash')
    return sorted(shapes, key=lambda s: s['key'])


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
            raise ValueError('material block references an excluded/unknown DDS')
        blocks[key] = block
    if set(blocks) != wanted:
        raise ValueError('missing owned material hash')
    return ('#usda 1.0\n(\n    doc = "Only the eighteen owned AI-generated Blood Overhaul RTX patterns."\n'
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
    shapes = select_shapes(json.loads((project / 'work/manifest.json').read_text(encoding='utf-8')))
    source_addon, source_mod = project / 'dist/addon_companion', project / 'dist/remix_mod/blood_overhaul_rtx'
    layer = selected_layer((source_mod / 'replacements.usda').read_text(encoding='utf-8'), shapes)
    addon, mod = output / 'nlblood', output / 'nl_blood_overhaul_rtx'
    selected = {}

    def copy(source: Path, target: Path):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        selected[source.relative_to(project).as_posix()] = {'sha256': sha(source), 'to': target.relative_to(output).as_posix()}

    def text(target: Path, body: str):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding='utf-8', newline='\n')

    for shape in shapes:
        key = shape['key']
        for suffix in ('', '_n'):
            rel = Path(f'materials/decals/bloodoverhaul/tex/{key}{suffix}.vtf')
            copy(source_addon / rel, addon / rel)
        for suffix in ('.a', '_n.a', '.n', '.r'):
            rel = Path(f'textures/{key}{suffix}.rtex.dds')
            copy(source_mod / rel, mod / rel)
        for family in FAMILIES:
            tex = f'decals/bloodoverhaul/tex/{key}' + ('' if family == 'red' else '_n')
            for model in (False, True):
                path = addon / f'materials/decals/bloodoverhaul/{family}/{key}'
                text(Path(str(path) + ('_model' if model else '') + '.vmt'),
                     vmt(tex, family, shape['units'] / shape['size'][0], model))
    scheme_source = project / 'addon_src/lua/bloodoverhaul/cl_schemes.lua'
    copy(scheme_source, addon / 'lua/nlblood/schemes.lua')
    text(addon / 'lua/nlblood/shapes.lua', 'return {\n' + ''.join(
        f'    {{ key = "{s["key"]}", units = {s["units"]:g} }},\n' for s in shapes) + '}\n')
    text(addon / 'addon.json', json.dumps({'title': 'Blood Overhaul RTX: owned patterns', 'type': 'effects', 'tags': ['realism']}, indent=2))
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
    excluded = {}
    for folder in (source_addon, source_mod):
        for path in sorted(folder.rglob('*')):
            if not path.is_file() or path.relative_to(project).as_posix() in selected:
                continue
            rel = path.relative_to(project).as_posix()
            reason = ('Crunchy original or derivative, including the old blood8 droplet' if path.suffix.lower() in ('.vtf', '.dds')
                      else 'replaced with owned-only generated materials, private Lua or a filtered USD layer')
            excluded[rel] = {'sha256': sha(path), 'reason': reason}
    audit = {'schema': 1, 'project': str(project), 'patterns': sorted(PATTERNS), 'selected': selected, 'excluded': excluded,
             'note': 'New generated shapes used Crunchy textures as style references; no reference pixels/files are distributed. '
                     'Original/derived bo_*, flesh, alienflesh, stains and old droplet excluded. No dependency on Crunchy.'}
    text(output / 'provenance.json', json.dumps(audit, indent=2, ensure_ascii=True) + '\n')
    shutil.copy2(project / 'tools/prompts.json', output / 'prompts.json')
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
