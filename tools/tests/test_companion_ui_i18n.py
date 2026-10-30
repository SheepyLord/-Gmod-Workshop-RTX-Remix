"""Exercise shipping catalogs and in-game localization helpers under LuaJIT."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import companion_i18n
from check_addon_i18n import REPO, luajit


class CompanionUiI18nTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_real_catalogs_and_language_changes(self):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as temp:
            built = Path(temp) / 'i18n.lua'
            companion_i18n.build(built, Path(companion_i18n.I18N), Path(companion_i18n.LUA_ROOT))
            result = subprocess.run([luajit(), str(REPO / 'tools/tests/companion_ui_i18n_harness.lua'),
                                     str(built),
                                     str(REPO / 'companion/nativeloader/lua/nativeloader/i18n.lua'),
                                     str(REPO / 'companion/nativeloader/lua/autorun/nativeloader_i18n.lua')],
                                    capture_output=True, encoding='utf-8', timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
