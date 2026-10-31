"""The Motion importer tab and the motion importer's builders under LuaJIT. See test_motion_tab.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
TAB = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_motion_tab.lua'
ADDON = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc'


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MotionTabTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('motion_tab_harness.lua')), scenario,
                                 str(TAB), str(ADDON)], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_tab_fills_in_when_the_addon_arrives(self):
        # The importer's sections in the desktop importer's order, the library, both windows.
        self.run_lua('late')

    def test_without_file_access_the_importer_explains(self):
        self.run_lua('unavailable')

    def test_floating_windows_and_console_commands(self):
        self.run_lua('windows')

    def test_tab_and_window_share_the_inputs(self):
        self.run_lua('shared')

    def test_addon_without_builders_gets_window_buttons(self):
        self.run_lua('fallback')

    def test_a_failing_builder_is_reported_once_and_offers_the_windows(self):
        self.run_lua('broken')

    def test_the_importer_scales_with_the_screen_like_external_models(self):
        self.run_lua('scale')

    def test_with_gui_scaler_the_tab_opts_out_of_its_second_scaling(self):
        self.run_lua('guiscaler')

    def test_title_and_tooltip_follow_the_language(self):
        self.run_lua('translations')


if __name__ == '__main__':
    unittest.main()
