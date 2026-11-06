"""Editable splash assets and the real main-menu UI without launching a game."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LANGUAGES = ('en', 'zh-CN', 'zh-TW', 'ja', 'ko', 'fr', 'ru')
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


class PresentationUITests(unittest.TestCase):
    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_r20_lua_reminders_and_menu_choices(self):
        for harness, source, marker in [
            ('loader_update_harness.lua', 'companion/nativeloader/lua/autorun/client/nativeloader.lua', 'PASS companion loader reminders'),
            ('menu_choices_harness.lua', 'loader/proxy/ui/menu_choices.lua', 'PASS menu choices')
        ]:
            with self.subTest(harness=harness):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name(harness)), str(REPO / source)],
                                        cwd=REPO, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(marker, result.stdout)

    def test_released_loader_record_tracks_a_published_version_separately(self):
        record = json.loads((REPO / 'companion/nativeloader/resource/loader-release.json').read_text(encoding='utf-8'))
        self.assertEqual(set(record), {'version', 'url'})
        self.assertRegex(record['version'], r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$')
        self.assertEqual(record['url'], 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/tag/v' + record['version'])
        cmake = re.search(r'\bVERSION (\d+\.\d+\.\d+)', (REPO / 'CMakeLists.txt').read_text()).group(1)
        # CMake releases are stable; any prerelease at the same core has lower precedence.
        self.assertLessEqual(tuple(map(int, record['version'].split('-')[0].split('.'))), tuple(map(int, cmake.split('.'))))

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_mainmenu_local_notice_reader(self):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('menu_notices_harness.lua')),
                                 str(REPO / 'loader/proxy/ui/read_notices.lua')],
                                cwd=REPO, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS menu notices', result.stdout)

    def test_startup_text_languages_and_placeholders(self):
        for code in LANGUAGES:
            name = 'startup_message.txt' if code == 'en' else f'startup_message.{code}.txt'
            data = (REPO / 'companion/presentation' / name).read_bytes()
            text = data.decode('utf-8-sig')
            with self.subTest(language=code):
                self.assertLessEqual(len(data), 8192)
                self.assertNotIn('\0', text)
                self.assertEqual(set(re.findall(r'\{([a-z]+)\}', text)), {'hotkey', 'seconds'})
                self.assertIn('https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix', text)
                self.assertNotIn('Xenthio', text)

    def test_mainmenu_labels_complete(self):
        labels = json.loads((REPO / 'loader/proxy/ui/labels.json').read_text(encoding='utf-8'))
        self.assertEqual(set(labels), set(LANGUAGES))
        for code in LANGUAGES:
            self.assertEqual(set(labels[code]), set(labels['en']))
            self.assertTrue(all(value.strip() for value in labels[code].values()))
            for key, value in labels[code].items():
                self.assertNotIn('?', value, f'{code}/{key}: lossy catalog encoding')
                self.assertNotIn('\ufffd', value, f'{code}/{key}: invalid UTF-8 replacement')

    @unittest.skipUnless(shutil.which('node'), 'Node.js is not installed')
    def test_mainmenu_behavior(self):
        result = subprocess.run([shutil.which('node'), str(Path(__file__).with_name('menu_diagnostics_harness.js')),
                                 str(REPO / 'loader/proxy/ui/mainmenu.js'), str(REPO / 'loader/proxy/ui/labels.json')],
                                cwd=REPO, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS menu diagnostics', result.stdout)
