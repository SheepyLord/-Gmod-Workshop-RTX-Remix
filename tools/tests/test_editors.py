"""The editors' Lua fixes of R19-E under LuaJIT, and a check for the GetBool idiom. See test_editors.py.md."""
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
AME = REPO / 'packages/advanced-material-editor/!advanced_material_editor'
ABT = REPO / 'packages/advanced-bodygroup-tool/!advanced_bodygroup_tool'
BBS = REPO / 'packages/procedural-bodygroup-destruction/!gmod_bullet_break_simulator/lua/bullet_break_simulator'
# "convar and convar:GetBool() or fallback" turns a setting of 0 into the fallback; only "or false"
# and "or nil" after GetBool() mean what they say.
GETBOOL_OR = re.compile(r':GetBool\(\s*\)\s+or\s+(?!false\b|nil\b)')


class EditorsStaticTests(unittest.TestCase):
    def test_no_getbool_or_fallback_idiom(self):
        found = []
        for folder in (AME, ABT, BBS.parents[1]):
            for path in sorted(folder.rglob('*.lua')):
                for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                    if GETBOOL_OR.search(line.split('--', 1)[0]):  # code, not a comment quoting the idiom
                        found.append(f'{path.relative_to(REPO)}:{number}: {line.strip()}')
        self.assertEqual(found, [])


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class EditorsLuaTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('editors_harness.lua')), scenario,
                                 str(AME), str(ABT), str(BBS)], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_material_snapshot_encoded_once_and_queue_bounded(self):
        self.run_lua('adv_snapshot')

    def test_rtx_hello_never_resets_the_limit(self):
        self.run_lua('adv_hello')

    def test_crafted_bodygroup_dupe_raises_nothing(self):
        self.run_lua('abt_dupe')

    def test_bodygroup_actions_budget_and_player_targets(self):
        self.run_lua('abt_actions')

    def test_region_analysis_cache_is_bounded(self):
        self.run_lua('abt_cache')

    def test_refused_destruction_settings_are_logged_sparingly(self):
        self.run_lua('bbs_denied')

    def test_getbool_returns_the_setting(self):
        self.run_lua('getbool')


if __name__ == '__main__':
    unittest.main()
