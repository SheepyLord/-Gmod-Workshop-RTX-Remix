"""Persistence and widget initialization regressions for the companion Remix settings panel."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
# The RTX fixes create rtx_pseudoplayer before the companion's menu loads; the menu runs with their default.
FIXES_MISC = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_misc.lua'


def body_default() -> str:
    found = re.search(r'''CreateClientConVar\(\s*["']rtx_pseudoplayer["']\s*,\s*["']?([^,"'\s)]+)''',
                      FIXES_MISC.read_text(encoding='utf-8-sig'))
    if not found:
        raise AssertionError(f'{FIXES_MISC} no longer creates rtx_pseudoplayer')
    return found.group(1)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class RemixSettingsTests(unittest.TestCase):
    def test_settings_lifecycle(self):
        menu = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_menu.lua'
        default = body_default()
        self.assertEqual(default, '1')  # the case that overwrote saved shadows at every map start
        for scenario in ('fresh', 'legacy', 'replay', 'edit', 'restart', 'invalid', 'reset', 'bounce_defaults',
                         'player_shadow'):
            with self.subTest(scenario=scenario):
                done = subprocess.run([LUAJIT, str(Path(__file__).with_name('remix_settings_harness.lua')),
                                       str(menu), scenario, default], capture_output=True, text=True, timeout=20)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertIn('PASS ' + scenario, done.stdout)

    def test_the_menu_does_not_define_the_body_switch(self):
        # A second CreateClientConVar with another default is dead (the fixes' runs first) and misleads.
        text = (REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_menu.lua').read_text(encoding='utf-8')
        self.assertNotRegex(text, r'CreateClientConVar\(\s*"rtx_pseudoplayer"\s*,')


if __name__ == '__main__':
    unittest.main()
