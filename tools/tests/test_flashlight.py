"""Run the RTX fixes' packaged flashlight Lua under flashlight_harness.lua (R19, ADR 0112): toggle and
colour cooldowns, the gamemode's flashlight rule, and one Remix light per player. No game."""
import os
import shutil
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
HARNESS = REPO / 'tools/tests/flashlight_harness.lua'
REMIXLUA = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/remixlua'


class FlashlightTests(unittest.TestCase):
    def run_harness(self, mode: str, path: Path) -> None:
        result = subprocess.run([LUA, str(HARNESS), mode, str(path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'PASS flashlight {mode}', result.stdout)

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
    def test_server_cooldowns_and_gamemode_rule(self):
        self.run_harness('server', REMIXLUA / 'sv/sv_remix_flashlight.lua')

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
    def test_client_one_light_per_player(self):
        self.run_harness('client', REMIXLUA / 'cl/remixapi/cl_remix_flashlight.lua')


if __name__ == '__main__':
    unittest.main()
