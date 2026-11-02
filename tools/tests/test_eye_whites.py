"""Run the production eye-white Lua code through lifecycle, coverage and identity fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('names', 'vtf', 'normal', 'no_api', 'late_api', 'old_runtime', 'late_material',
             'late_hash', 'invalid_hash', 'retry', 'foreign', 'edited_cache', 'disabled',
             'brightness', 'toggle', 'prune', 'user_edit', 'shutdown', 'bounded', 'wrappers',
             'soft_normal', 'soft_late', 'soft_inherited', 'soft_foreign', 'soft_user_edit', 'soft_prune',
             'cache_cap')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class EyeWhiteTests(unittest.TestCase):
    pass


def scenario_test(scenario):
    def test(self):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('eye_whites_harness.lua')),
                                 str(ROOT), scenario], capture_output=True, text=True,
                                encoding='utf-8', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)
    return test


for _scenario in SCENARIOS:
    setattr(EyeWhiteTests, 'test_' + _scenario, scenario_test(_scenario))

if __name__ == '__main__':
    unittest.main()
