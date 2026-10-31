"""Render isolation and failure recovery for the late toolgun screen pass."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class ToolgunScreenTests(unittest.TestCase):
    def test_render_contract(self):
        source = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_toolgun.lua'
        harness = Path(__file__).with_name('toolgun_screen_harness.lua')
        for scenario in ('normal', 'no_api', 'third_person', 'other_weapon', 'unsupported',
                         'subview', 'target_failure', 'depth_failure', 'mesh_failure'):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(harness), str(source), scenario], capture_output=True,
                                        text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


if __name__ == '__main__':
    unittest.main()
