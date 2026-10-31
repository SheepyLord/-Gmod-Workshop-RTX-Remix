"""Lifecycle, bounded per-frame work and shared-texture protection for stylized model overlays."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('normal', 'no_api', 'late_hash', 'toggle', 'shells', 'collision', 'ordinary_hei', 'submaterial',
             'proxy', 'world', 'client_entity', 'skin_change', 'retry', 'bounded', 'nil_revision', 'revision',
             'prune')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class ModelLayersTests(unittest.TestCase):
    def test_lifecycle(self):
        source = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_model_layers.lua'
        harness = Path(__file__).with_name('model_layers_harness.lua')
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(harness), str(source), scenario],
                                        capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


if __name__ == '__main__':
    unittest.main()
