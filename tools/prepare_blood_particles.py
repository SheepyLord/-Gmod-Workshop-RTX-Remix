"""Author opacity materials for the two original procedural blood sprites; output stays under out/."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import subprocess
import zlib

REPO = Path(__file__).resolve().parents[1]
BEGIN = '        # BEGIN R20-C PARTICLE MATERIALS\n'
END = '        # END R20-C PARTICLE MATERIALS\n'


def png_rgba(width: int, height: int, rgba: bytes) -> bytes:
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def block(hash_hex: str, name: str, adaptive: float) -> str:
    return f'''        over "mat_{hash_hex.upper()}"
        {{
            over "Shader"
            {{
                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@
                uniform token info:mdl:sourceAsset:subIdentifier = "AperturePBR_Opacity"
                bool inputs:preload_textures = 0
                asset inputs:diffuse_texture = @./textures/nlfluid_{name}.a.rtex.dds@
                float inputs:reflection_roughness_constant = 0.18
                float inputs:metallic_constant = 0
                float inputs:opacity_constant = 1
                bool inputs:use_legacy_alpha_state = 0
                bool inputs:blend_enabled = 1
                int inputs:blend_type = 0
                bool inputs:inverted_blend = 0
                int inputs:alpha_test_type = 7
                bool inputs:enable_emission = 1
                asset inputs:emissive_mask_texture = @./textures/nlfluid_{name}.a.rtex.dds@
                color3f inputs:emissive_color_constant = (1, 1, 1)
                float inputs:emissive_intensity = 0.01
                float inputs:emissive_adaptive_intensity = {adaptive:g}
            }}
        }}
'''


def build(addon: Path, mod: Path, nvtt: Path, adaptive: float = .05) -> dict:
    addon, mod = addon.resolve(), mod.resolve()
    for folder in (addon, mod):
        if not folder.is_relative_to(REPO / 'out'):
            raise ValueError('asset preparation writes only under this worktree/out')
    work = mod.parent / 'particle-pbr-work'
    for target in (mod/'replacements.usda', mod/'textures', work):
        if not target.resolve().is_relative_to(REPO/'out'):
            raise ValueError('linked output escapes this worktree/out')
        for parent in (target, *target.parents):
            if parent == REPO/'out':
                break
            if parent.is_symlink() or getattr(parent, 'is_junction', lambda: False)():
                raise ValueError('linked output is refused')
    import xxhash  # asset preparation only; normal package builds use the indexed DDSs
    if not 0 <= adaptive <= 1:
        raise ValueError('adaptive emission must be between zero and one')
    layer = mod / 'replacements.usda'
    text = layer.read_text(encoding='utf-8')
    if BEGIN in text:
        start = text.index(BEGIN)
        end = text.index(END, start) + len(END)
        text = text[:start] + text[end:]
    if not text.endswith('    }\n}\n'):
        raise ValueError('unexpected replacement layer ending')
    work.mkdir(exist_ok=True)
    records, blocks = {}, []
    for name in ('drop', 'mist'):
        source = addon / f'materials/particle/nlfluid/{name}.vtf'
        data = source.read_bytes()
        width, height = struct.unpack_from('<HH', data, 16)
        if data[:4] != b'VTF\0' or struct.unpack_from('<i', data, 52)[0] != 0 or data[56] != 1:
            raise ValueError('expected the original one-mip RGBA8888 analytic sprite')
        rgba = data[80:]
        if len(rgba) != width * height * 4:
            raise ValueError('unexpected sprite size')
        png = work / f'{name}.png'
        png.write_bytes(png_rgba(width, height, rgba))
        dds = mod / f'textures/nlfluid_{name}.a.rtex.dds'
        run = subprocess.run([str(nvtt), str(png), '--output', str(dds), '--format', 'bc7',
                              '--mip-filter', 'kaiser', '--mip-gamma-correct'], capture_output=True, text=True)
        if run.returncode or not dds.exists():
            raise ValueError('NVTT failed: ' + run.stdout[-1000:] + run.stderr[-1000:])
        hashes = {'xxh64': xxhash.xxh64(rgba).hexdigest(), 'xxh3': xxhash.xxh3_64(rgba).hexdigest()}
        for value in hashes.values():
            blocks.append(block(value, name, adaptive))
        records[name] = {'hashes': hashes, 'dds_bytes': dds.stat().st_size, 'adaptive_emission': adaptive,
                         'source': f'analytic {width}x{height} sprite from prepare_blood.py; unchanged VTF'}
    text = text[:-len('    }\n}\n')] + BEGIN + ''.join(blocks) + END + '    }\n}\n'
    layer.write_text(text, encoding='utf-8', newline='\n')
    (work / 'provenance.json').write_text(json.dumps(records, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--addon', type=Path, required=True)
    parser.add_argument('--mod', type=Path, required=True)
    parser.add_argument('--nvtt', type=Path, required=True)
    parser.add_argument('--adaptive', type=float, default=.05)
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.addon, args.mod, args.nvtt, args.adaptive), indent=2))
    except (OSError, ValueError, ImportError) as error:
        print(f'prepare_blood_particles: {error}')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
