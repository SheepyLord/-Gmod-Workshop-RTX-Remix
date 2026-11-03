"""The in-game RTX Remix guide: its pages and window code under LuaJIT with GMod's panels mocked, in
every language and for every loader generation, and its pictures (the badges of each match its legend,
the size budget, nothing enlarged past the window). See test_companion_guide.py.md."""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import companion_i18n  # noqa: E402
from test_companion import LUAJIT, REPO, lua_value  # noqa: E402

LUA = REPO / 'companion' / 'nativeloader' / 'lua'
GUIDE = LUA / 'autorun' / 'client' / 'nativeloader_guide.lua'
PAGES = LUA / 'nativeloader' / 'guide_pages.lua'
MATERIALS = REPO / 'companion' / 'nativeloader' / 'materials'
PICTURES = MATERIALS / 'nativeloader' / 'guide'
SPEC = REPO / 'tools' / 'guide_pictures.json'
HARNESS = Path(__file__).with_name('companion_guide_harness.lua')
# The repository's README shows these two; the guide shows the first.
README_PICTURES = {'rtx_on.jpg', 'remix_menu.jpg'}
MAX_BYTES = 256_000          # each picture: about 250 KB
MAX_TOTAL = 4 * 1024 * 1024  # all of them: about 4 MB (they ship in the Workshop package)
MAX_WIDTH = 900              # the page's width in a 1280x720 game: wider pictures would be shrunk
KINDS = {'h', 'p', 'steps', 'list', 'image', 'term', 'q', 'tip', 'warn', 'code', 'button', 'link'}
WHEN = {'', 'r6', 'legacy', 'r13', 'pre13'}


def jpeg_size(path: Path):
    """(width, height) from a JPEG's frame header, without Pillow."""
    data = path.read_bytes()
    assert data[:2] == b'\xff\xd8', f'{path.name} is not a JPEG'
    i = 2
    while i < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        length = int.from_bytes(data[i + 2:i + 4], 'big')
        if marker in (0xC0, 0xC1, 0xC2):
            return int.from_bytes(data[i + 7:i + 9], 'big'), int.from_bytes(data[i + 5:i + 7], 'big')
        i += 2 + length
    raise AssertionError(f'{path.name}: no frame header')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionGuideTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=scratch)
        cls.addClassCleanup(cls.temp.cleanup)
        root = Path(cls.temp.name)
        # The structure does not wait for translations: new text shows in English until it has one.
        cls.catalog = root / 'i18n_data.lua'
        companion_i18n.build(str(cls.catalog), complete=False)
        pot = {entry['msgid'] for entry in companion_i18n.read_po(str(REPO / 'companion' / 'i18n' / companion_i18n.POT))
               if entry['msgid']}
        images = {path.relative_to(MATERIALS).as_posix(): True for path in PICTURES.glob('*.jpg')}
        cls.inputs = root / 'inputs.lua'
        cls.inputs.write_text('return ' + lua_value({'pot': {m: True for m in pot}, 'images': images}) + '\n', encoding='utf-8')
        cls.structure = cls.run_harness('structure', 'en', 'r13')

    @classmethod
    def run_harness(cls, mode, language, caps):
        done = subprocess.run([LUAJIT, str(HARNESS), str(GUIDE), str(PAGES), str(LUA / 'nativeloader' / 'i18n.lua'),
                               str(cls.catalog), str(cls.inputs), mode, language, caps],
                              capture_output=True, encoding='utf-8', timeout=60)
        if done.returncode != 0:
            raise AssertionError(f'{mode} {language} {caps}: {done.stdout[-2000:]}{done.stderr}')
        return [line.split('\t') for line in done.stdout.splitlines()]

    def rows(self, kind):
        return [row[1:] for row in self.structure if row[0] == kind]

    def test_pages_sections_links_and_items_are_well_formed(self):
        pages = self.rows('PAGE')
        ids = [page[0] for page in pages]
        self.assertEqual(ids, ['welcome', 'tab', 'remix_menu', 'characters', 'memory', 'troubleshooting'])
        self.assertTrue(all(page[2].startswith('icon16/') for page in pages), pages)
        sections = {}
        for page, section in self.rows('SECTION'):
            self.assertNotIn(section, sections.setdefault(page, set()), f'{page}: section {section} twice')
            sections[page].add(section)
        for page, kind, when in self.rows('ITEM'):
            self.assertIn(kind, KINDS, f'{page}: unknown item {kind}')
            self.assertIn(when, WHEN, f'{page}: unknown condition {when}')
        for page, target, section in self.rows('LINK'):
            self.assertIn(target, ids, f'{page}: a link to a missing page')
            self.assertTrue(not section or section in sections.get(target, set()), f'{page}: a link to {target}.{section}')
        for page, command in self.rows('BUTTON'):
            self.assertTrue(re.fullmatch(r'[a-z_]+( [a-z_]+)*', command), f'{page}: button command {command!r}')
        self.assertIn('crash', sections['memory'])

    def test_every_picture_matches_its_spec_and_is_shipped(self):
        spec = json.loads(SPEC.read_text(encoding='utf-8'))['pictures']
        shown = set()
        for page, path, legends in self.rows('IMAGE'):
            name = Path(path).stem
            shown.add(Path(path).name)
            self.assertTrue((MATERIALS / path).is_file(), f'{page}: {path} is not in the guide folder')
            if int(legends) == 0:
                continue  # a picture without badges (the Welcome page's view of the game)
            self.assertIn(name, spec, f'{page}: {name} has a legend but no spec in tools/guide_pictures.json')
            self.assertEqual(len(spec[name]['badges']), int(legends),
                             f'{page}: {name} has {legends} legend entries and {len(spec[name]["badges"])} badges')
        unused = {path.name for path in PICTURES.glob('*.jpg')} - shown - README_PICTURES
        self.assertFalse(unused, f'pictures nothing shows: {sorted(unused)}')
        self.assertFalse(set(spec) - {Path(name).stem for name in shown}, 'specs for pictures no page shows')

    def test_pictures_stay_within_the_budget_and_the_window(self):
        total = 0
        for path in sorted(PICTURES.glob('*.jpg')):
            size = path.stat().st_size
            total += size
            self.assertLessEqual(size, MAX_BYTES, f'{path.name}: {size:,} bytes')
            width, height = jpeg_size(path)
            if path.name not in README_PICTURES:  # views of the game, not captures of controls to read
                self.assertLessEqual(width, MAX_WIDTH, f'{path.name} is {width} wide: shrunk in a 1280x720 game')
            self.assertLessEqual(height, 1000, f'{path.name} is {height} high')
        self.assertLessEqual(total, MAX_TOTAL, f'the pictures take {total:,} bytes')
        self.assertFalse(list(PICTURES.glob('*.png')), 'pictures ship as JPEG')

    def test_every_page_opens_in_every_language_for_every_loader(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            for caps in ('legacy', 'r6', 'r13'):
                with self.subTest(language=language, caps=caps):
                    rows = self.run_harness('render', language, caps)
                    self.assertIn(['PASS render ' + language + ' ' + caps + ' 6'], rows)

    def test_the_guide_follows_the_games_interface_scale(self):
        # A GUI scaler makes the game's text larger: the guide follows, its pictures by whole steps.
        self.assertIn(['PASS scale'], self.run_harness('scale', 'en', 'r13'))

    def test_loader_conditions_choose_the_advice(self):
        # The same page text for each loader: older loaders never get keys they would reject.
        def memory_page(caps):
            return [row for row in self.run_harness('render', 'en', caps) if row[0] == 'SHOWN' and row[1] == 'memory']
        self.assertTrue(memory_page('legacy') and memory_page('r6') and memory_page('r13'))
        legacy, r6, r13 = (int(memory_page(c)[0][2]) for c in ('legacy', 'r6', 'r13'))
        self.assertLess(legacy, r6)
        self.assertLessEqual(r6, r13)


if __name__ == '__main__':
    unittest.main()
