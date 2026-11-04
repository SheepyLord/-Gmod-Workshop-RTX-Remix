"""Run the painted-shadow and solid-hair rules, their controller and the hotloader hook through LuaJIT fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('shadows', 'hair_names', 'vtf', 'hidden', 'remix_off', 'big_manifest', 'solid', 'late_soft',
             'reimport', 'despawn', 'hook')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class ImportedPartsTests(unittest.TestCase):
    pass


def scenario_test(scenario):
    def test(self):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('imported_parts_harness.lua')),
                                 str(ROOT), scenario], capture_output=True, text=True,
                                encoding='utf-8', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)
    return test


for _scenario in SCENARIOS:
    setattr(ImportedPartsTests, 'test_' + _scenario, scenario_test(_scenario))

if __name__ == '__main__':
    unittest.main()
