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
        for scenario in ('budget', 'coexist', 'absent', 'menu', 'impacts', 'saturation', 'blood_menu'):
            with self.subTest(scenario=scenario):
                run = subprocess.run([LUA, str(REPO / 'tools/tests/r20_blood_harness.lua'), str(REPO), scenario],
                                     cwd=REPO, capture_output=True, text=True, encoding='utf-8', timeout=20)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn('PASS ' + scenario, run.stdout)


if __name__ == '__main__':
    unittest.main()
