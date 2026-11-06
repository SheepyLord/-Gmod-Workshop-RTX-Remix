"""Owned-asset selection and execution regressions for R20-C blood and the toolgun settings move."""
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
        return {'shapes': [{'key': key, 'kind': 'pool', 'units': 50, 'textures': [
            {'tex': 'decals/bloodoverhaul/tex/' + key + suffix,
             'hash': {'xxh64': '0x0123456789ABCDEF', 'xxh3': '0xFEDCBA9876543210'}}
            for suffix in ('', '_n')]} for key in sorted(prep.PATTERNS)]}

    def test_only_complete_owned_shapes_and_expected_textures(self):
        manifest = self.manifest()
        manifest['shapes'].append({'key': 'bo_blood1', 'kind': 'pool'})
        self.assertEqual({s['key'] for s in prep.select_shapes(manifest)}, prep.PATTERNS)
        manifest['shapes'][0]['textures'][0]['original'] = True
        with self.assertRaises(ValueError):
            prep.select_shapes(manifest)
        manifest = self.manifest()
        manifest['shapes'][0]['textures'][0]['tex'] = 'decals/blood1'
        with self.assertRaises(ValueError):
            prep.select_shapes(manifest)
        manifest = self.manifest()
        manifest['shapes'].pop()
        with self.assertRaises(ValueError):
            prep.select_shapes(manifest)

    def test_layer_cannot_pull_in_original_derived_maps(self):
        shape = self.manifest()['shapes'][:1]
        layer = '''        over "mat_0123456789ABCDEF" {
            asset inputs:diffuse_texture = @./textures/bo_blood1.a.rtex.dds@
            asset inputs:normalmap_texture = @./textures/bo_blood1.n.rtex.dds@
            asset inputs:reflectionroughness_texture = @./textures/bo_blood1.r.rtex.dds@
        }'''
        with self.assertRaisesRegex(ValueError, 'excluded/unknown'):
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

    def test_imported_part_has_only_owned_texture_names_and_filtered_hashes(self):
        import re
        part = REPO / 'packages/blood-overhaul-rtx'
        index = json.loads((part / 'files.json').read_text())['files']
        vtfs = {p for p in index if p.endswith('.vtf')}
        expected_vtfs = {f'nlblood/materials/decals/bloodoverhaul/tex/{key}{suffix}.vtf'
                         for key in prep.PATTERNS for suffix in ('', '_n')}
        expected_vtfs |= {f'nlblood/materials/particle/nlfluid/{name}.vtf' for name in ('drop', 'mist')}
        self.assertEqual(vtfs, expected_vtfs)
        dds = {Path(p).name for p in index if p.endswith('.dds')}
        self.assertEqual(dds, {f'{key}{suffix}.rtex.dds' for key in prep.PATTERNS
                              for suffix in ('.a', '_n.a', '.n', '.r')} |
                         {f'nlfluid_{name}.a.rtex.dds' for name in ('drop', 'mist')})
        layer = (part / 'nl_blood_overhaul_rtx/replacements.usda').read_text()
        self.assertEqual(len(re.findall(r'over "mat_[0-9A-F]{16}"', layer)), 76)
        self.assertEqual(set(re.findall(r'@\./textures/([^@]+)@', layer)), dds)
        self.assertNotIn('preload_textures = 1', layer)
        audit = json.loads((part / 'licenses/provenance.json').read_text())
        self.assertEqual(len(audit['selected']), 109)
        self.assertIn('dist/addon_companion/materials/particle/bo_droplets/drop.vtf', audit['excluded'])
        patterns, sprites = layer.split('        # BEGIN R20-C PARTICLE MATERIALS', 1)
        self.assertEqual(patterns.count('bool inputs:enable_emission = 0'), 72)
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
                         'blood_menu', 'ragdolls', 'previous_impact', 'world_landing'):
            with self.subTest(scenario=scenario):
                run = subprocess.run([LUA, str(REPO / 'tools/tests/r20_blood_harness.lua'), str(REPO), scenario],
                                     cwd=REPO, capture_output=True, text=True, encoding='utf-8', timeout=20)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn('PASS ' + scenario, run.stdout)


if __name__ == '__main__':
    unittest.main()
