"""Behavior regressions for native brush glass and its persistent networked debris."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix'


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


class GlassMapTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_actual_geometry_native_break_lifecycle_and_packet_writer(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='glass-map-', dir=scratch) as folder:
            # This legacy file uses GLua line comments; executable server code is ordinary Lua.
            source = (ADDON / 'lua/autorun/networking.lua').read_text(encoding='utf-8')
            normalized = re.sub(r'(?m)(^|\s)//', r'\1--', source)
            network = Path(folder) / 'networking.lua'
            network.write_text(normalized, encoding='utf-8')
            result = subprocess.run([luajit(), str(REPO / 'tools/tests/glass_map_harness.lua'),
                                     str(ADDON), str(network)], cwd=REPO, capture_output=True,
                                    encoding='utf-8', errors='replace', timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('all glass map assertions passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
