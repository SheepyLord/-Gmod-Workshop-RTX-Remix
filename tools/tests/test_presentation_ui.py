"""Editable splash assets and the real main-menu UI without launching a game."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LANGUAGES = ('en', 'zh-CN', 'zh-TW', 'ja', 'ko', 'fr', 'ru')


class PresentationUITests(unittest.TestCase):
    def test_startup_text_languages_and_placeholders(self):
        for code in LANGUAGES:
            name = 'startup_message.txt' if code == 'en' else f'startup_message.{code}.txt'
            data = (REPO / 'companion/presentation' / name).read_bytes()
            text = data.decode('utf-8-sig')
            with self.subTest(language=code):
                self.assertLessEqual(len(data), 8192)
                self.assertNotIn('\0', text)
                self.assertEqual(set(re.findall(r'\{([a-z]+)\}', text)), {'hotkey', 'seconds'})
                self.assertIn('https://github.com/SheepyLord/-Gmod-Workshop-RTX-Remix', text)
                self.assertNotIn('Xenthio', text)

    def test_mainmenu_labels_complete(self):
        labels = json.loads((REPO / 'loader/proxy/ui/labels.json').read_text(encoding='utf-8'))
        self.assertEqual(set(labels), set(LANGUAGES))
        for code in LANGUAGES:
            self.assertEqual(set(labels[code]), set(labels['en']))
            self.assertTrue(all(value.strip() for value in labels[code].values()))

    @unittest.skipUnless(shutil.which('node'), 'Node.js is not installed')
    def test_mainmenu_behavior(self):
        result = subprocess.run([shutil.which('node'), str(Path(__file__).with_name('menu_diagnostics_harness.js')),
                                 str(REPO / 'loader/proxy/ui/mainmenu.js'), str(REPO / 'loader/proxy/ui/labels.json')],
                                cwd=REPO, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS menu diagnostics', result.stdout)
