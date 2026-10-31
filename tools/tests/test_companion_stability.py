"""Exercise the actual tier panel and stability-guide navigation with shipping gettext catalogs."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import companion_i18n
from test_companion import LUAJIT, REPO


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionStabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=scratch)
        cls.addClassCleanup(cls.temp.cleanup)
        cls.catalog = Path(cls.temp.name) / 'i18n_data.lua'
        companion_i18n.build(cls.catalog)

    def run_scenario(self, scenario, language):
        lua = REPO / 'companion/nativeloader/lua'
        result = subprocess.run([
            LUAJIT, str(Path(__file__).with_name('companion_stability_harness.lua')),
            str(lua / 'autorun/client/nativeloader_menu.lua'),
            str(lua / 'autorun/client/nativeloader_guide.lua'),
            str(lua / 'nativeloader/i18n.lua'), str(self.catalog), scenario, language,
        ], capture_output=True, encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario + ' ' + language, result.stdout)

    def test_tier_selection_sources_and_refresh_in_every_language(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            for scenario in ('low_auto', 'medium_fallback', 'high_config', 'unknown_hardware', 'refresh'):
                with self.subTest(language=language, scenario=scenario):
                    self.run_scenario(scenario, language)

    def test_absent_or_invalid_reports_show_no_tier_line(self):
        for scenario in ('absent', 'no_activation', 'bad_field', 'missing', 'malformed',
                         'unreadable', 'bad_schema', 'invalid_tier'):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario, 'en')

    def test_stability_link_selects_the_translated_guide_page(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            with self.subTest(language=language):
                self.run_scenario('guide', language)


if __name__ == '__main__':
    unittest.main()
