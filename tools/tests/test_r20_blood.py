"""R20-C/R21-A resource selection, permission audit, Lua controllers and toolgun settings."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

import prepare_blood as prep

REPO = Path(__file__).resolve().parents[2]
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')


class BloodInputsTests(unittest.TestCase):
    def manifest(self):
        shapes = [{'key': key, 'kind': 'pool', 'units': prep.ORIGINALS.get(key, 50), 'size': [1024, 1024], 'textures': [
            {'tex': 'decals/bloodoverhaul/tex/' + key + suffix,
             'hash': {'xxh64': '0x0123456789ABCDEF', 'xxh3': '0xFEDCBA9876543210'}}
            for suffix in ('', '_n')]} for key in sorted(prep.PATTERNS | prep.ORIGINALS.keys())]
        for shape in shapes:
            if shape['key'] in prep.ORIGINALS:
                shape['textures'].append({'tex': 'decals/blood' + shape['key'][-1], 'original': True,
                    'hash': {'xxh64': '0x1123456789ABCDEF', 'xxh3': '0xEEDCBA9876543210'}})
        return {'shapes': shapes}

    def test_complete_permitted_shapes_world_sizes_and_expected_textures(self):
        manifest = self.manifest()
        shapes = prep.select_shapes(manifest)
        self.assertEqual({s['key'] for s in shapes}, prep.PATTERNS | prep.ORIGINALS.keys())
        self.assertEqual([s['key'] for s in shapes[:8]], list(prep.ORIGINALS))
        manifest['shapes'].append(manifest['shapes'][0])
        with self.assertRaises(ValueError): prep.select_shapes(manifest)
        manifest = self.manifest()
        manifest['shapes'][0]['textures'][0]['tex'] = 'decals/blood1'
        with self.assertRaises(ValueError):
            prep.select_shapes(manifest)
        manifest = self.manifest()
        manifest['shapes'].pop()
        with self.assertRaises(ValueError):
            prep.select_shapes(manifest)

    def test_layer_cannot_pull_in_unlisted_maps(self):
        shape = self.manifest()['shapes'][:1]
        layer = '''        over "mat_0123456789ABCDEF" {
            asset inputs:diffuse_texture = @./textures/bo_blood1.a.rtex.dds@
            asset inputs:normalmap_texture = @./textures/bo_blood1.n.rtex.dds@
            asset inputs:reflectionroughness_texture = @./textures/bo_blood1.r.rtex.dds@
        }'''
        with self.assertRaisesRegex(ValueError, 'unknown'):
            prep.selected_layer(layer, shape)

    def test_small_original_particle_textures_have_coverage_and_transparent_edges(self):
        import struct
        for size, mist in [(128, False), (64, True)]:
            raw = prep.procedural_vtf(size, mist)
            self.assertEqual(raw[:4], b'VTF\0')
            self.assertEqual(struct.unpack_from('<i', raw, 52)[0], 0)
            self.assertEqual(len(raw), 80 + size * size * 4)
            alpha = raw[83::4]
            self.assertEqual(max(alpha[:size]), 0)
            self.assertGreater(max(alpha), 180)
            self.assertEqual(raw, prep.procedural_vtf(size, mist))

    def test_imported_part_covers_source_pbr_stock_materials_and_analytic_sprites(self):
        import re
        part = REPO / 'packages/blood-overhaul-rtx'
        index = json.loads((part / 'files.json').read_text())['files']
        vtfs = {p for p in index if p.endswith('.vtf')}
        self.assertEqual(len(vtfs), 93)
        for key in prep.PATTERNS | prep.ORIGINALS.keys():
            for suffix in ('', '_n'):
                self.assertIn(f'nlblood/materials/decals/bloodoverhaul/tex/{key}{suffix}.vtf', vtfs)
        for prefix,count in [('blood',8),('yblood',6)]:
            for i in range(1,count+1):
                self.assertIn(f'nlblood/materials/decals/{prefix}{i}.vtf', vtfs)
                self.assertIn(f'nlblood/materials/decals/{prefix}{i}_subrect.vmt', index)
        dds = {Path(p).name for p in index if p.endswith('.dds')}
        self.assertEqual(len(dds), 179)
        layer = (part / 'nl_blood_overhaul_rtx/replacements.usda').read_text()
        self.assertEqual(len(re.findall(r'over "mat_[0-9A-F]{16}"', layer)), 186)
        self.assertEqual(set(re.findall(r'@\./textures/([^@]+)@', layer)), dds)
        self.assertNotIn('preload_textures = 1', layer)
        audit = json.loads((part / 'licenses/provenance.json').read_text())
        self.assertEqual(audit['permission']['date'], '2026-11-06')
        self.assertIn('dist/addon/materials/particle/bo_droplets/drop.vtf', audit['excluded'])
        self.assertEqual(len(audit['selected']), 437)
        self.assertTrue(audit['selected']['dist/addon/materials/decals/blood1.vtf']['matches_original_md5'])
        self.assertFalse(audit['selected']['dist/addon/materials/decals/blood1_subrect.vmt']['matches_original_md5'])
        for source,entry in audit['selected'].items():
            if entry['to'].startswith(('nlblood/', 'nl_blood_overhaul_rtx/')):
                self.assertEqual(index[entry['to']]['sha256'],entry['sha256'],source)
        for target,entry in audit['generated'].items():
            self.assertEqual(index[target]['sha256'], entry['sha256'], target)
        self.assertTrue(all(len(entry['sha256']) == 64 and entry['reason'] for entry in audit['excluded'].values()))
        self.assertNotIn('nlblood/materials/particle/bo_droplets/drop.vtf', index)
        patterns, sprites = layer.split('        # BEGIN R20-C PARTICLE MATERIALS', 1)
        self.assertEqual(patterns.count('bool inputs:enable_emission = 0'), 182)
        self.assertEqual(sprites.count('inputs:emissive_adaptive_intensity = 0.05'), 4)

    def test_procedural_sprite_png_is_lossless_rgba(self):
        import struct
        import zlib
        import prepare_blood_particles as sprites
        pixels = bytes((210, 210, 210, 0, 210, 210, 210, 255))
        png = sprites.png_rgba(2, 1, pixels)
        self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
        at, raw = 8, b''
        while at < len(png):
            length = struct.unpack_from('>I', png, at)[0]
            kind, payload = png[at+4:at+8], png[at+8:at+8+length]
            self.assertEqual(struct.unpack_from('>I', png, at+8+length)[0], zlib.crc32(kind + payload))
            if kind == b'IDAT':
                raw += payload
            at += length + 12
        self.assertEqual(zlib.decompress(raw), b'\0' + pixels)

    def test_sprite_asset_generator_refuses_game_outputs(self):
        import prepare_blood_particles as sprites
        with self.assertRaisesRegex(ValueError, 'only under'):
            sprites.build(Path('H:/SteamLibrary/steamapps/common/GarrysMod_PoC'), REPO/'out/unused', Path('nvtt.exe'))

    def test_new_parts_are_local_package_content_without_new_trust(self):
        config = json.loads((REPO / 'tools/workshop.json').read_text())
        parts = {p['name']: p for p in config['parts']}
        for name in ('toolgun-screen', 'blood-overhaul-rtx'):
            self.assertEqual(parts[name]['build'], 'package_content')
            self.assertNotIn('--lua-bin', parts[name]['args'])
            self.assertNotIn('--requires-remix', parts[name]['args'])
        self.assertIn('--mod', parts['blood-overhaul-rtx']['args'])

    def test_packager_can_start_with_isolated_python(self):
        import sys
        run = subprocess.run([sys.executable, '-I', str(REPO / 'tools/package_content.py'), '--help'],
                             cwd=REPO, capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn('--addon-as', run.stdout)


@unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
class BloodLuaTests(unittest.TestCase):
    def test_controllers(self):
        for scenario in ('budget', 'server_delivery', 'dts_bootstrap', 'coexist', 'preloaded', 'absent', 'menu', 'menu_fallback', 'impacts', 'saturation',
                         'blood_menu', 'ragdolls', 'previous_impact', 'world_landing', 'stock_materials'):
            with self.subTest(scenario=scenario):
                run = subprocess.run([LUA, str(REPO / 'tools/tests/r20_blood_harness.lua'), str(REPO), scenario],
                                     cwd=REPO, capture_output=True, text=True, encoding='utf-8', timeout=20)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn('PASS ' + scenario, run.stdout)


if __name__ == '__main__':
    unittest.main()
