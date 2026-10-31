"""Coverage, format safety and real language-selection regressions for bundled add-ons."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_addon_i18n as check

SCRATCH = check.REPO / 'out' / 'tmp'
SCRATCH.mkdir(parents=True, exist_ok=True)


class AddonI18nTests(unittest.TestCase):
    def test_missing_language_key_placeholder_and_english_are_rejected(self):
        languages = {'en': {'hello': 'Hello {{name}}', 'bye': 'Bye'}}
        languages.update({code: {'hello': 'Bonjour {{name}}', 'bye': 'Au revoir'} for code in check.LANGUAGES})
        self.assertEqual(check.validate({'fixture': languages}, {}), [])
        broken = copy.deepcopy(languages)
        del broken['ko']
        del broken['ja']['bye']
        broken['fr']['hello'] = 'Bonjour'
        broken['ru']['bye'] = 'Bye'
        issues = '\n'.join(check.validate({'fixture': broken}, {}))
        for phrase in ('missing language', 'missing or blank', 'changed interpolation', 'unreviewed English'):
            self.assertIn(phrase, issues)

    def test_hotloader_keys_must_resolve_as_the_addon_looks_them_up(self):
        # R4: Model Hotloader renders L('key') from the phrase "mmdhl.<key>"; two catalog keys without the
        # prefix showed as raw names on the External Models tab.
        languages = {code: {'mmdhl.ui.ok': 'OK', 'ui.character.rtx_normals': 'Recalculate'}
                     for code in ('en', 'zh-cn', *check.LANGUAGES[1:])}
        issues = check.validate({'hotloader': languages}, {'hotloader': {code: {'mmdhl.ui.ok': 'OK',
                                'ui.character.rtx_normals': 'Recalculate'} for code in languages}})
        self.assertEqual(len([i for i in issues if 'unreachable' in i]), len(languages))
        with tempfile.TemporaryDirectory(dir=SCRATCH) as folder:
            root = Path(folder)
            lua = root / check.HOTLOADER / 'lua' / 'mmdhl'
            lua.mkdir(parents=True)
            (lua / 'ui.lua').write_text("checkbox(L'ui.ok') checkbox(L('ui.missing'))\n"
                                        "label(L('bonemap.side.'..side)) x.L('ui.method')\n", encoding='utf-8')
            problems = check.hotloader_lookups(root, {'mmdhl.ui.ok': 'OK'})
        self.assertEqual(len(problems), 1)
        self.assertIn("L'ui.missing'", problems[0])
        self.assertEqual(check.missing_parts({'motion': {}}), [f'{part}: catalog not found'
                                                               for part in check.PARTS if part != 'motion'])

    @unittest.skipUnless(check.luajit(), 'LuaJIT is not installed')
    def test_shipped_catalogs_and_actual_language_selectors(self):
        catalogs = check.read_catalogs()
        allowed = json.loads((check.REPO / 'tools/addon_i18n_unchanged.json').read_text(encoding='utf-8'))
        self.assertEqual(check.missing_parts(catalogs) + check.validate(catalogs, allowed), [])
        self.assertEqual(check.hotloader_lookups(check.REPO, catalogs['hotloader']['en']), [])


if __name__ == '__main__':
    unittest.main()
