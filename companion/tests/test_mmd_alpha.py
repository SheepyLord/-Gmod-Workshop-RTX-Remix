"""Exercise the real companion's transient MMD hash registration without launching GMod."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('normal', 'no_api', 'late_hash', 'late_material', 'fallback', 'invalid_hash',
             'nil_revision', 'no_tracking', 'retry', 'new_asset', 'prune', 'revision', 'bounded', 'namespace',
             'late_api', 'track_retry', 'soft_only', 'soft_late', 'soft_budget', 'soft_namespace', 'cold_library')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MmdAlphaTests(unittest.TestCase):
    def run_scenario(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('mmd_alpha_harness.lua')),
                                 str(ROOT / 'companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua'),
                                 scenario], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)


for _scenario in SCENARIOS:
    setattr(MmdAlphaTests, 'test_' + _scenario, lambda self, scenario=_scenario: self.run_scenario(scenario))

if __name__ == '__main__':
    unittest.main()
