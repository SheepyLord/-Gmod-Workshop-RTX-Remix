"""Tests for companion_i18n.py: the companion's text extracted, merged into the .po files, checked
and built into the Lua table the add-on reads; and that table read by the real i18n.lua under
LuaJIT (skipped without LuaJIT)."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import companion_i18n as ci  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'
I18N_LUA = REPO / 'companion' / 'nativeloader' / 'lua' / 'nativeloader' / 'i18n.lua'


def luajit():
    found = shutil.which('luajit')
    if found:
        return found
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs' / 'LuaJIT' / 'bin' / 'luajit.exe'
    return str(local) if local.is_file() else None


LUA = '''-- L("not this") in a comment
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N
panel:Help(L("Start here"))
panel:Button(L"Open the guide", "x")
local PAGES = { { N("Welcome"), { "p", N("Path: bin\\\\win64\\\\winmm.dll, \\"quoted\\"") } } }
notice(string.format(L("Package %s was updated"), name))
panel:Help(L("Start here")) -- again
print("never extracted")
'''


class CompanionI18nTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-companion-i18n-', dir=SCRATCH))
        self.lua = self.root / 'companion' / 'nativeloader' / 'lua'
        (self.lua / 'autorun' / 'client').mkdir(parents=True)
        (self.lua / 'autorun' / 'client' / 'menu.lua').write_text(LUA, encoding='utf-8')
        self.i18n = self.root / 'companion' / 'i18n'

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def po(self, language):
        return self.i18n / (language + '.po')

    def set_translation(self, language, msgid, msgstr):
        entries = ci.read_po(str(self.po(language)))
        table = {e['msgid']: (e['msgstr'], e['fuzzy']) for e in entries if e['msgid']}
        table[msgid] = (msgstr, False)
        ci.write_po(str(self.po(language)), language, ci.extract(str(self.lua)), table)

    def test_marked_text_is_extracted_once_with_every_place(self):
        found = dict(ci.extract(str(self.lua)))
        self.assertEqual(list(found), ['Start here', 'Open the guide', 'Welcome', 'Path: bin\\win64\\winmm.dll, "quoted"',
                                       'Package %s was updated'])
        self.assertEqual(found['Start here'], ['nativeloader/lua/autorun/client/menu.lua:4', 'nativeloader/lua/autorun/client/menu.lua:8'])

    def test_update_keeps_translations_adds_new_text_and_drops_old(self):
        strings, summary = ci.update(str(self.i18n), str(self.lua))
        self.assertEqual(len(strings), 5)
        self.assertTrue((self.i18n / 'nativeloader.pot').is_file())
        self.assertEqual(sorted(p.name for p in self.i18n.glob('*.po')), sorted(l + '.po' for l in ci.LANGUAGES))
        self.set_translation('zh-CN', 'Start here', '从这里开始')
        self.set_translation('zh-CN', 'Path: bin\\win64\\winmm.dll, "quoted"', '路径：bin\\win64\\winmm.dll，「引号」')
        source = self.lua / 'autorun' / 'client' / 'menu.lua'
        source.write_text(LUA.replace('L"Open the guide"', 'L"Open the RTX guide"'), encoding='utf-8')
        strings, summary = ci.update(str(self.i18n), str(self.lua))
        table = {e['msgid']: e['msgstr'] for e in ci.read_po(str(self.po('zh-CN'))) if e['msgid']}
        self.assertEqual(table['Start here'], '从这里开始')
        self.assertEqual(table['Path: bin\\win64\\winmm.dll, "quoted"'], '路径：bin\\win64\\winmm.dll，「引号」')
        self.assertEqual(table['Open the RTX guide'], '')
        self.assertNotIn('Open the guide', table)
        self.assertEqual(summary['zh-CN']['translated'], 2)
        self.assertEqual(summary['zh-CN']['dropped'], [])  # the old text had no translation to lose
        pot = (self.i18n / 'nativeloader.pot').read_text(encoding='utf-8')
        self.assertIn('#, c-format\nmsgid "Package %s was updated"', pot)
        self.assertIn('msgid "Path: bin\\\\win64\\\\winmm.dll, \\"quoted\\""', pot)

    def test_check_reports_file_and_line_for_conversions_and_unknown_text(self):
        ci.update(str(self.i18n), str(self.lua))
        self.set_translation('fr', 'Package %s was updated', 'Le paquet a été mis à jour')
        with self.assertRaisesRegex(ci.I18nError, r'fr\.po:\d+: printf conversions \[\] must match the English \[\'%s\'\]'):
            ci.check(str(self.i18n), str(self.lua))
        self.set_translation('fr', 'Package %s was updated', 'Le paquet %s a été mis à jour')
        tables = ci.check(str(self.i18n), str(self.lua))
        self.assertEqual(tables['fr'], {'Package %s was updated': 'Le paquet %s a été mis à jour'})
        # A percent sign in other text is just a percent sign.
        self.set_translation('fr', 'Welcome', 'Bienvenue à 100 %')
        self.assertIn('Welcome', ci.check(str(self.i18n), str(self.lua))['fr'])
        with open(self.po('ru'), 'a', encoding='utf-8') as fh:
            fh.write('\nmsgid "Not in the companion"\nmsgstr "Нет"\n')
        with self.assertRaisesRegex(ci.I18nError, 'not text the companion has'):
            ci.check(str(self.i18n), str(self.lua))

    def test_fuzzy_and_empty_entries_show_the_english(self):
        ci.update(str(self.i18n), str(self.lua))
        text = self.po('ja').read_text(encoding='utf-8').replace('msgid "Welcome"\nmsgstr ""',
                                                                 '#, fuzzy\nmsgid "Welcome"\nmsgstr "ようこそ"')
        self.po('ja').write_text(text, encoding='utf-8')
        self.assertEqual(ci.check(str(self.i18n), str(self.lua))['ja'], {})

    def test_broken_po_syntax_is_reported(self):
        ci.update(str(self.i18n), str(self.lua))
        self.po('ko').write_text(self.po('ko').read_text(encoding='utf-8') + '\nmsgid "Welcome"\nmsgstr "bad \\q escape"\n',
                                 encoding='utf-8')
        with self.assertRaisesRegex(ci.I18nError, r'ko\.po:\d+: the escape'):
            ci.check(str(self.i18n), str(self.lua))

    def test_po_strings_round_trip(self):
        for text in ('plain', 'a "quote" and \\ backslash', 'two\nlines', 'tab\there', '中文「」', ''):
            quoted = ci.po_quote(text)
            self.assertEqual(ci.po_unquote(quoted.split('\n'), 'test'), text, quoted)

    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_the_add_on_reads_the_built_table_in_the_chosen_language(self):
        ci.update(str(self.i18n), str(self.lua))
        self.set_translation('zh-CN', 'Start here', '从这里开始')
        self.set_translation('zh-CN', 'Path: bin\\win64\\winmm.dll, "quoted"', '路径："bin\\win64"')
        self.set_translation('ru', 'Start here', 'Начните здесь')
        built = self.root / 'i18n_data.lua'
        counts = ci.build(str(built), str(self.i18n), str(self.lua))
        self.assertEqual((counts['zh-CN'], counts['ru'], counts['ja']), (2, 1, 0))
        harness = self.root / 'harness.lua'
        harness.write_text('''
local data_path, module_path = ...
local convars, callbacks = { gmod_language = "zh-CN", nativeloader_language = "" }, {}
local function convar(name) return { GetString = function() return convars[name] end } end
file = { Exists = function(path) return path == "nativeloader/i18n_data.lua" end }
include = function(path)
    if path == "nativeloader/i18n_data.lua" then return dofile(data_path) end
    error("include " .. path)
end
istable = function(v) return type(v) == "table" end
CreateClientConVar = function(name) return convar(name) end
GetConVar = function(name) return convar(name) end
cvars = { AddChangeCallback = function(name, fn) callbacks[name] = fn end }
timer = { Create = function() end }
RunConsoleCommand = function() end
local i18n = dofile(module_path)
local L = i18n.L
print(L("Start here"))
print(L("Path: bin\\\\win64\\\\winmm.dll, \\"quoted\\""))
print(L("Welcome"))
convars.nativeloader_language = "ru"
print(L("Start here"))
convars.nativeloader_language = "ja"
print(L("Start here"))
convars.nativeloader_language = "en"
print(L("Start here"))
print(i18n.N("Welcome"), #i18n.languages, callbacks.nativeloader_language ~= nil)
''', encoding='utf-8')
        done = subprocess.run([luajit(), str(harness), str(built), str(I18N_LUA)], capture_output=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr.decode('utf-8', 'replace'))
        lines = done.stdout.decode('utf-8').splitlines()
        self.assertEqual(lines, ['从这里开始', '路径："bin\\win64"', 'Welcome', 'Начните здесь', 'Start here', 'Start here',
                                 'Welcome\t7\ttrue'])


if __name__ == '__main__':
    unittest.main()
