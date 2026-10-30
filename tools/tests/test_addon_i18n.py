"""Coverage, format safety and real language-selection regressions for bundled add-ons."""
import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_addon_i18n as check


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

    @unittest.skipUnless(check.luajit(), 'LuaJIT is not installed')
    def test_shipped_catalogs_and_actual_language_selectors(self):
        catalogs = check.read_catalogs()
        allowed = json.loads((check.REPO / 'tools/addon_i18n_unchanged.json').read_text(encoding='utf-8'))
        self.assertEqual(check.validate(catalogs, allowed), [])


if __name__ == '__main__':
    unittest.main()
