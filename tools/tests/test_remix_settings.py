"""Persistence and widget initialization regressions for the companion Remix settings panel."""
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
class RemixSettingsTests(unittest.TestCase):
    def test_settings_lifecycle(self):
        menu = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_menu.lua'
        for scenario in ('fresh', 'legacy', 'replay', 'edit', 'restart', 'invalid', 'reset'):
            with self.subTest(scenario=scenario):
                done = subprocess.run([LUAJIT, str(Path(__file__).with_name('remix_settings_harness.lua')),
                                       str(menu), scenario], capture_output=True, text=True, timeout=20)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertIn('PASS ' + scenario, done.stdout)


if __name__ == '__main__':
    unittest.main()
