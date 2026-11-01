"""Run the G1-B debris manager in LuaJIT with engine/physics doubles; no game or installs."""
from pathlib import Path
import subprocess
import unittest

from test_glass_map import luajit

REPO = Path(__file__).resolve().parents[2]


class GlassDebrisTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_real_manager_geometry_world_import_lifecycle_batching_and_fallback(self):
        result = subprocess.run([luajit(), str(REPO / 'tools/tests/glass_debris_harness.lua'),
                                 str(REPO / 'glass/addon/lua'),
                                 str(REPO / 'tools/qa/glass_debris_jolt_probe.lua')], cwd=REPO, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('all glass debris assertions passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
