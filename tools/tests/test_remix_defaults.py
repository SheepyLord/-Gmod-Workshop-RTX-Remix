"""Tests for tools/remix_defaults.py: ordinary options take the stronger file's value, texture-hash
sets combine as Remix layers do (adds, removes, removals kept as -tokens)."""
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools'))
import remix_defaults as rd  # noqa: E402


class RemixDefaultsTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(dir=REPO / 'out' / 'tmp' if (REPO / 'out' / 'tmp').is_dir() else None))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def write(self, name, text):
        path = self.root / name
        path.write_text(text, encoding='utf-8')
        return path

    def test_later_files_win_for_ordinary_options(self):
        weak = self.write('rtx.conf', '# comment\nrtx.a = 1\nrtx.b = 0.5, 0.5, 0.5\n')
        strong = self.write('user.conf', 'rtx.a = 2\nrtx.c = True\n')
        merged, origin = rd.merge([weak, strong])
        self.assertEqual(merged, {'rtx.a': '2', 'rtx.b': '0.5, 0.5, 0.5', 'rtx.c': 'True'})
        self.assertEqual(origin['rtx.a'], 'user.conf')
        self.assertEqual(list(merged), ['rtx.a', 'rtx.b', 'rtx.c'])  # first-seen order

    def test_hash_sets_combine_like_remix_layers(self):
        weak = self.write('rtx.conf', 'rtx.decalTextures = 0xAA, 0xBB, -0xCC, -0xDD\n')
        strong = self.write('user.conf', 'rtx.decalTextures = 0xCC, -0xBB, 0xEE\n')
        merged, _ = rd.merge([weak, strong])
        tokens = [t.strip() for t in merged['rtx.decalTextures'].split(',')]
        # 0xBB removed by the stronger file, 0xCC added back, 0xDD stays removed (from the built-in list).
        self.assertEqual(sorted(t for t in tokens if not t.startswith('-')), ['0xAA', '0xCC', '0xEE'])
        self.assertEqual(sorted(t for t in tokens if t.startswith('-')), ['-0xBB', '-0xDD'])

    def test_a_non_hash_value_replaces_a_set(self):
        weak = self.write('rtx.conf', 'rtx.x = 0xAA, 0xBB\n')
        strong = self.write('user.conf', 'rtx.x = \n')
        merged, _ = rd.merge([weak, strong])
        self.assertEqual(merged['rtx.x'], '')

    def test_main_writes_the_layer_and_refuses_missing_inputs(self):
        weak = self.write('dxvk.conf', 'd3d9.shaderModel = 0\n')
        out = self.root / 'out' / 'defaults.conf'
        self.assertEqual(rd.main([str(weak), '--out', str(out)]), 0)
        text = out.read_text(encoding='utf-8')
        self.assertIn('d3d9.shaderModel = 0', text)
        self.assertTrue(text.startswith('# Remix defaults'))
        self.assertEqual(rd.main([str(self.root / 'missing.conf'), '--out', str(out)]), 1)

    def test_frame_generation_is_left_off_whatever_the_classic_install_had(self):
        # The classic install's DLSS-G at 3x crashed RTX 30, RTX 40 and AMD GPUs (ADR 0037).
        classic = self.write('user.conf', 'rtx.frameGenerationType = 1\nrtx.dlfg.enable = True\n'
                                          'rtx.dlfg.maxInterpolatedFrames = 2\nrtx.qualityDLSS = 1\n')
        out = self.root / 'out' / 'defaults.conf'
        self.assertEqual(rd.main([str(classic), '--out', str(out)]), 0)
        lines = out.read_text(encoding='utf-8').splitlines()
        for line in ('rtx.frameGenerationType = 0', 'rtx.dlfg.enable = False', 'rtx.dlfg.maxInterpolatedFrames = 1',
                     'rtx.qualityDLSS = 1'):
            self.assertIn(line, lines)
        self.assertNotIn('rtx.frameGenerationType = 1', lines)


if __name__ == '__main__':
    unittest.main()
