"""Run the packaged ToPBR Lua driver regressions without a game."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest
REPO = Path(__file__).resolve().parents[2]
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
DRIVER = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_topbr_conversion.lua'
class ToPBRTests(unittest.TestCase):
    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT unavailable')
    def test_packaged_game_panel(self):
        panel = DRIVER
        result = subprocess.run([LUA, str(REPO/'tools/tests/game_pbr_panel_harness.lua'), str(panel)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT unavailable')
    def test_packaged_client_driver(self):
        result = subprocess.run([LUA, str(REPO/'tools/tests/topbr_harness.lua'), str(DRIVER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
