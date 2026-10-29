import calendar
import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import package_fixes

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'gmapack'))
import gmapack  # noqa: E402

COMPANION = REPO / 'companion' / 'nativeloader'
RULE = '// ' + '=' * 60
AUTOEXEC = '\r\n'.join([
    '// header outside any banner',               # 1
    RULE,                                         # 2
    '// RTX stack required settings (test)',      # 3
    '// r_shadows 0 is critical',                 # 4
    RULE,                                         # 5
    'sv_cheats 1',                                # 6
    'r_3dsky "0"',                                # 7
    'mat_softwareskin 1 // trailing comment',     # 8
    '  r_WaterDrawReflection\t0',                 # 9
    'exec rtx_extra',                             # 10
    'bind "x" "+attack"',                         # 11
    'alias foo "bar"',                            # 12
    'echo hello',                                 # 13
    'r_shadows 0; r_novis 1',                     # 14
    'r_lod',                                      # 15
    'r_x 1 2',                                    # 16
    'r_bad! 1',                                   # 17
    'r_long ' + '1' * 33,                         # 18
    'r_space "a b"',                              # 19
    'r_lod 2',                                    # 20
    'R_3DSKY 0',                                  # 21
    'map gm_construct',                           # 22
    '',                                           # 23
    RULE,                                         # 24
    '// Personal settings',                       # 25
    RULE,                                         # 26
    'r_forcehwlight 1',                           # 27
    'jpeg_quality 100',                           # 28
    '',                                           # 29
    'exec astra_importer_compat',                 # 30
]).encode('ascii') + b'\r\n'
EXPECTED_CVARS = {'sv_cheats': '1', 'mat_softwareskin': '1', 'r_WaterDrawReflection': '0', 'r_lod': '2', 'R_3DSKY': '0'}
EXPECTED_SKIPPED = [  # (line, text, part of the reason)
    (7, 'r_3dsky "0"', 'set again on line 21'),
    (10, 'exec rtx_extra', 'a command (exec)'),
    (11, 'bind "x" "+attack"', 'a command (bind)'),
    (12, 'alias foo "bar"', 'a command (alias)'),
    (13, 'echo hello', 'a command (echo)'),
    (14, 'r_shadows 0; r_novis 1', "';'"),
    (15, 'r_lod', 'no value'),
    (16, 'r_x 1 2', 'more than one value'),
    (17, 'r_bad! 1', 'the name'),
    (18, 'r_long ' + '1' * 33, 'the value'),
    (19, 'r_space "a b"', 'the value'),
    (22, 'map gm_construct', 'a command (map)'),
    (27, 'r_forcehwlight 1', 'outside the RTX section'),
    (28, 'jpeg_quality 100', 'outside the RTX section'),
    (30, 'exec astra_importer_compat', 'outside the RTX section'),
]
FAKE = {
    'garrysmod/rtx.conf': b'rtx.a = 1\n',
    'garrysmod/dxvk.conf': b'd3d9.a = 1\n',
    'garrysmod/bin/win64/stdshader_dx6.dll': b'MZ shader',
    'garrysmod/bin/win64/stdshader_dx6.pdb': b'pdb',
    'garrysmod/bin/win64/stdshader_dx6_readme.txt': b'readme',
    'garrysmod/garrysmod/addons/remixbinary/lua/autorun/client/cl_rtx.lua': b'require("RTXFixesBinary")\n',
    'garrysmod/garrysmod/addons/remixbinary/materials/rtx/ignore.vtf': b'VTF',
    'garrysmod/garrysmod/addons/remixbinary/lua/old.lua.bak': b'old',
    'garrysmod/garrysmod/addons/Glass-Rewrite-Remix/.git': b'gitdir: ../../.git/modules/glass\n',
    'garrysmod/garrysmod/addons/Glass-Rewrite-Remix/.gitattributes': b'* text=auto\n',
    'garrysmod/garrysmod/addons/Glass-Rewrite-Remix/README.md': b'# Glass\n',
    'garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/autorun/glass.lua': b'-- glass\n',
    'garrysmod/garrysmod/addons/Glass-Rewrite-Remix/lua/Thumbs.db': b'junk',
    'garrysmod/garrysmod/addons/niknaks/.git/config': b'[core]\n',
    'garrysmod/garrysmod/addons/niknaks/lua/includes/modules/niknaks.lua': b'-- niknaks\n',
    'garrysmod/garrysmod/addons/niknaks/desktop.ini': b'junk',
    'garrysmod/garrysmod/addons/rtx_agent/lua/autorun/client/rtx_agent.lua': b'-- agent\n',
    'garrysmod/garrysmod/addons/loose.txt': b'not an add-on',
    'garrysmod/garrysmod/cfg/autoexec.cfg': AUTOEXEC,
    'garrysmod/garrysmod/cfg/client.vdf': b'"vdf"',
    'garrysmod/garrysmod/lua/menu/problems/problems.lua': b'-- menu',
    'garrysmod/garrysmod/gamemodes/sandbox/entities/weapons/gmod_camera.lua': b'-- camera',
    'garrysmod/garrysmod/html/loading.png': b'PNG',
    'garrysmod/garrysmod/data/remix_map_configs/default.txt': b'map config',
    'garrysmod/rtx-remix/mods/base_mod/mod.usda': b'#usda 1.0\n',
    'garrysmod/rtx-remix/mods/base_mod/textures/a.dds': b'DDS a',
    'garrysmod/rtx-remix/mods/~gmod_topbr/textures/b.dds': b'DDS b',
    'x86_64/Release/gmcl_RTXFixesBinary_win64.dll': b'MZ fixes',
    'x86_64/Release/gmcl_RTXFixesBinary_win64.lib': b'lib',
    'x86_64/Release/gmcl_rtxwater_win64.dll': b'MZ water',
    'x86_64/Release/gmcl_rtxdebug_win64.dll': b'MZ debug',
    'source/debug/addon/lua/autorun/client/rtx_debug.lua': b'require("rtxdebug")\n',
}
DEBUG_ADDON_FILE = 'source/debug/addon/lua/autorun/client/rtx_debug.lua'
FAKE_MOD = 'garrysmod/rtx-remix/mods/base_mod/textures/a.dds'
EXPECTED_ROOTS = [
    'garrysmod/addons/Glass-Rewrite-Remix', 'garrysmod/addons/nativeloader', 'garrysmod/addons/niknaks',
    'garrysmod/addons/remixbinary', 'garrysmod/addons/rtx_agent', 'garrysmod/data/remix_map_configs',
    'garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll',
    'garrysmod/lua/bin/gmcl_rtxwater_win64.dll', 'rtx-remix/mods/base_mod', 'rtx-remix/mods/~gmod_topbr',
]
EXPECTED_LEFT_OUT = [
    'bin/win64/stdshader_dx6.pdb', 'bin/win64/stdshader_dx6_readme.txt', 'dxvk.conf', 'garrysmod/addons/loose.txt',
    'garrysmod/cfg/autoexec.cfg', 'garrysmod/cfg/client.vdf',
    'garrysmod/gamemodes/sandbox/entities/weapons/gmod_camera.lua', 'garrysmod/html/loading.png',
    'garrysmod/lua/menu/problems/problems.lua', 'rtx.conf',
]
EXPECTED_JUNK = [
    'garrysmod/addons/Glass-Rewrite-Remix/.git', 'garrysmod/addons/Glass-Rewrite-Remix/.gitattributes',
    'garrysmod/addons/Glass-Rewrite-Remix/lua/Thumbs.db', 'garrysmod/addons/niknaks/.git',
    'garrysmod/addons/niknaks/desktop.ini', 'garrysmod/addons/remixbinary/lua/old.lua.bak',
]


def companion_files():
    """{package path: source} of the real companion add-on, .md files left out."""
    return {'native/root/garrysmod/addons/nativeloader/' + p.relative_to(COMPANION).as_posix(): p
            for p in sorted(COMPANION.rglob('*')) if p.is_file() and p.suffix.lower() != '.md'}


def built_nlctl():
    """nlctl.exe when it is built and new enough (0.2.0, M5) to read these manifests."""
    for preset in ('win64-debug', 'win64-release'):
        exe = REPO / 'out' / 'build' / preset / 'loader' / 'cli' / 'nlctl.exe'
        if exe.is_file():
            done = subprocess.run([str(exe), 'version'], capture_output=True, text=True, encoding='utf-8')
            version = tuple(int(n) for n in re.findall(r'\d+', done.stdout)[:3])
            if done.returncode == 0 and version >= (0, 2, 0):
                return exe
    return None


class PackageFixesTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch, prefix='package-fixes-')
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'fixes'
        for rel, data in FAKE.items():
            self.write(self.repo / rel, data)
        (self.repo / 'garrysmod' / 'rtx-remix' / 'mods' / 'empty_mod').mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_tool(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = package_fixes.main(['--repo', str(self.repo), *map(str, args)])
        return code, out.getvalue(), err.getvalue()

    def build(self, *args):
        code, out, err = self.run_tool('--json', *args)
        self.assertEqual(code, 0, err)
        return json.loads(out)

    def manifest(self, folder):
        return json.loads((folder / 'native' / 'manifest.json').read_text(encoding='utf-8'))

    def leftovers(self):
        return [p.name for p in self.root.iterdir() if '.partial-' in p.name or '.old-' in p.name]

    def expected_files(self, *, debug=False):
        files = {
            'native/payload/shaders/stdshader_dx6.dll': 'garrysmod/bin/win64/stdshader_dx6.dll',
            'native/root/garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll': 'x86_64/Release/gmcl_RTXFixesBinary_win64.dll',
            'native/root/garrysmod/lua/bin/gmcl_rtxwater_win64.dll': 'x86_64/Release/gmcl_rtxwater_win64.dll',
        }
        if debug:
            files['native/root/garrysmod/lua/bin/gmcl_rtxdebug_win64.dll'] = 'x86_64/Release/gmcl_rtxdebug_win64.dll'
            files['native/root/garrysmod/addons/rtx_debug/lua/autorun/client/rtx_debug.lua'] = DEBUG_ADDON_FILE
        for rel in FAKE:
            for area, target in (('garrysmod/garrysmod/addons/', 'native/root/garrysmod/addons/'),
                                 ('garrysmod/garrysmod/data/', 'native/root/garrysmod/data/'),
                                 ('garrysmod/rtx-remix/mods/', 'native/root/rtx-remix/mods/')):
                if rel.startswith(area) and rel.count('/') > area.count('/') and not any(
                        j in rel for j in ('.git', 'Thumbs.db', 'desktop.ini', '.bak')):
                    files[target + rel[len(area):]] = rel
        out = {key: self.repo / rel for key, rel in files.items()}
        out.update(companion_files())
        return out

    def test_manifest_structure(self):
        out = self.root / 'pkg'
        summary = self.build('--out', out)
        m = self.manifest(out)
        self.assertEqual(list(m), ['schema', 'id', 'name', 'version', 'kinds', 'requires_loader', 'requires_remix', 'files',
                                   'root_files', 'patch_sets', 'module_overrides', 'session_cvars'])
        self.assertEqual((m['schema'], m['id'], m['requires_loader'], m['requires_remix']), (1, 'rtx-fixes', '>=0.2.0', True))
        self.assertEqual(m['name'], 'RTX fixes ' + m['version'])
        self.assertEqual(m['kinds'], ['lua-binary-module', 'lua-addon', 'root-files', 'patch-set', 'module-override'])
        # Seed data and the ToPBR converter's mod are create-only: what the fixes write there at run time
        # stays, and never blocks a reinstall.
        self.assertEqual(m['root_files'], [{'path': p, 'policy': 'create-only' if p.startswith('garrysmod/data/') or
                                            p == 'rtx-remix/mods/~gmod_topbr' else 'replace-owned'} for p in EXPECTED_ROOTS])
        self.assertEqual(m['module_overrides'], [{'module': 'stdshader_dx6.dll', 'file': 'native/payload/shaders/stdshader_dx6.dll'}])
        self.assertEqual(m['session_cvars'], EXPECTED_CVARS)
        self.assertEqual(list(m['session_cvars']), list(EXPECTED_CVARS))  # file order, last assignment wins
        expected = self.expected_files()
        self.assertEqual(list(m['files']), sorted(expected, key=str.lower))
        self.assertEqual((summary['files'], summary['id'], summary['version']), (len(expected), 'rtx-fixes', m['version']))
        self.assertEqual(summary['mods'], ['base_mod', '~gmod_topbr'])
        self.assertEqual(summary['empty_mods'], ['empty_mod'])
        self.assertEqual(summary['addons'], ['Glass-Rewrite-Remix', 'niknaks', 'remixbinary', 'rtx_agent', 'nativeloader'])
        self.assertEqual(summary['left_out'], EXPECTED_LEFT_OUT)
        self.assertEqual(summary['junk'], EXPECTED_JUNK)
        self.assertEqual(summary['patches'], 7)
        self.assertEqual(self.leftovers(), [])

    def test_every_listed_file_matches_its_hash_and_nothing_is_unlisted(self):
        out = self.root / 'pkg'
        self.build('--out', out, '--with-debug-module')
        m = self.manifest(out)
        expected = self.expected_files(debug=True)
        on_disk = sorted(p.relative_to(out).as_posix() for p in (out / 'native').rglob('*') if p.is_file())
        self.assertEqual(on_disk, sorted(list(m['files']) + ['native/manifest.json']))
        self.assertEqual(set(m['files']), set(expected))
        for rel, info in m['files'].items():
            data = (out / rel).read_bytes()
            self.assertEqual(info, {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}, rel)
            self.assertEqual(data, expected[rel].read_bytes(), rel)
        self.assertIn('garrysmod/lua/bin/gmcl_rtxdebug_win64.dll', [r['path'] for r in m['root_files']])
        self.assertIn('garrysmod/addons/rtx_debug', [r['path'] for r in m['root_files']])

    def test_the_debug_module_comes_with_its_add_on_or_not_at_all(self):
        shutil.rmtree(self.repo / 'source' / 'debug')
        code, _, err = self.run_tool('--out', self.root / 'pkg', '--with-debug-module')
        self.assertEqual(code, 1)
        self.assertIn('source', err)
        self.assertIn('debug', err)
        self.assertFalse((self.root / 'pkg').exists())

    def test_steam_files_configs_and_junk_stay_out(self):
        out = self.root / 'pkg'
        self.build('--out', out)
        paths = [p.relative_to(out).as_posix().lower() for p in out.rglob('*') if p.is_file()]
        for banned in ('lua/menu', 'gamemodes', 'html', '/cfg/', 'rtx.conf', 'dxvk.conf', '.pdb', '.lib', '.bak',
                       '/.git', 'thumbs.db', 'desktop.ini', 'loose.txt', 'readme.txt',
                       'nativeloader.lua.md', 'gmcl_rtxdebug'):
            self.assertFalse([p for p in paths if banned in p], banned)
        self.assertIn('native/root/garrysmod/addons/nativeloader/lua/autorun/client/nativeloader.lua', paths)
        self.assertIn('native/root/garrysmod/data/remix_map_configs/default.txt', paths)  # seed data, create-only
        self.assertIn('native/root/garrysmod/addons/glass-rewrite-remix/readme.md', paths)  # the add-ons' own docs stay

    def test_session_cvars_from_the_rtx_section(self):
        summary = self.build('--out', self.root / 'pkg')
        report = summary['session_cvars']
        self.assertEqual(report['source'], str(self.repo / 'garrysmod' / 'garrysmod' / 'cfg' / 'autoexec.cfg'))
        self.assertEqual(report['section'], 'RTX stack required settings (test)')
        self.assertEqual(report['count'], len(EXPECTED_CVARS))
        self.assertEqual([(s['line'], s['text']) for s in report['skipped']], [(n, t) for n, t, _ in EXPECTED_SKIPPED])
        for skip, (_, _, reason) in zip(report['skipped'], EXPECTED_SKIPPED):
            self.assertIn(reason, skip['reason'])

    def test_session_cvars_whole_file_without_an_rtx_section(self):
        cfg = self.write(self.root / 'mine.cfg', '\n'.join([
            RULE, '// Video settings', RULE,
            'r_3dsky 0', '"r_quoted" 1', 'r_unterminated "1', 'exec foo', 'mat_specular "0" // ok', 'mat_x ""',
        ]).encode('ascii'))
        out = self.root / 'pkg'
        report = self.build('--out', out, '--cvars-from', cfg)['session_cvars']
        self.assertEqual(self.manifest(out)['session_cvars'], {'r_3dsky': '0', 'mat_specular': '0', 'mat_x': ''})
        self.assertIsNone(report['section'])
        self.assertEqual([(s['line'], s['text']) for s in report['skipped']],
                         [(5, '"r_quoted" 1'), (6, 'r_unterminated "1'), (7, 'exec foo')])

    def test_patch_sets_match_the_research_table(self):
        out = self.root / 'pkg'
        self.build('--out', out)
        sets = self.manifest(out)['patch_sets']
        self.assertEqual([(s['module'], len(s['patches'])) for s in sets],
                         [('engine.dll', 2), ('shaderapidx9.dll', 3), ('materialsystem.dll', 1), ('datacache.dll', 1)])
        names = [p['name'] for s in sets for p in s['patches']]
        self.assertEqual(len(names), len(set(names)))
        for s in sets:
            self.assertRegex(s['module'], r'^[a-z0-9_]+\.dll$')
            for p in s['patches']:
                self.assertEqual(list(p), ['name', 'find', 'offset', 'replace'])
                self.assertRegex(p['name'], r'^[a-z0-9_]{1,64}$')
                self.assertRegex(p['find'], r'^(?:[0-9a-f]{2}|\?\?){1,256}$')
                self.assertRegex(p['replace'], r'^(?:[0-9a-f]{2}){1,256}$')
                self.assertNotEqual(set(p['find']), {'?'})
                self.assertLessEqual(p['offset'] + len(p['replace']) // 2, len(p['find']) // 2, p['name'])
        # docs/RESEARCH.md section 12 tables the seven patches64 patches; the data must be the same.
        research = (REPO / 'docs' / 'RESEARCH.md').read_text(encoding='utf-8').split('## 12. ', 1)[1]
        table = re.findall(r'^\| (\w+) \| `([0-9a-f?]+)` \((\d+)\) \| `([0-9a-f]+)` \|', research, re.M)
        self.assertEqual(len(table), 7)
        self.assertEqual([(s['module'], p['find'], p['offset'], p['replace']) for s in sets for p in s['patches']],
                         [(d + '.dll', f, int(o), r) for d, f, o, r in table])

    def test_switches_and_exclusions(self):
        out = self.root / 'pkg'
        summary = self.build('--out', out, '--no-patch-sets', '--no-session-cvars', '--exclude-addon', 'rtx_agent',
                             '--exclude-addon', 'NATIVELOADER', '--id', 'my-fixes', '--version', '1.2.3-rc.1+b.5',
                             '--name', 'Test fixes')
        m = self.manifest(out)
        self.assertNotIn('patch_sets', m)
        self.assertNotIn('session_cvars', m)
        self.assertEqual(m['kinds'], ['lua-binary-module', 'lua-addon', 'root-files', 'module-override'])
        self.assertEqual((m['id'], m['version'], m['name']), ('my-fixes', '1.2.3-rc.1+b.5', 'Test fixes'))
        roots = [r['path'] for r in m['root_files']]
        self.assertNotIn('garrysmod/addons/rtx_agent', roots)
        self.assertNotIn('garrysmod/addons/nativeloader', roots)
        self.assertFalse([f for f in m['files'] if '/rtx_agent/' in f or '/nativeloader/' in f])
        self.assertEqual(summary['excluded_addons'], ['nativeloader', 'rtx_agent'])
        self.assertIsNone(summary['session_cvars'])
        self.assertEqual(summary['patches'], 0)
        self.assertEqual(summary['left_out'], EXPECTED_LEFT_OUT)  # an excluded add-on is reported by name only

    def test_default_version_and_reproducible_output(self):
        stamp = calendar.timegm((2026, 1, 1, 0, 0, 0))
        for path in self.repo.rglob('*'):
            os.utime(path, (stamp, stamp))
        newest = calendar.timegm((2030, 1, 2, 3, 4, 5))  # newer than every other input, the companion included
        os.utime(self.repo / FAKE_MOD, (newest, newest))
        a, b = self.root / 'a', self.root / 'b'
        self.build('--out', a, '--gma', self.root / 'a.gma')
        self.build('--out', b, '--gma', self.root / 'b.gma')
        first = (a / 'native' / 'manifest.json').read_bytes()
        self.assertEqual(first, (b / 'native' / 'manifest.json').read_bytes())
        self.assertEqual((self.root / 'a.gma').read_bytes(), (self.root / 'b.gma').read_bytes())
        digest = hashlib.sha256(FAKE['x86_64/Release/gmcl_RTXFixesBinary_win64.dll']).hexdigest()
        self.assertEqual(json.loads(first)['version'], '0.0.0-dev.203001020304+' + digest[:8])
        with gmapack.read_gma(str(self.root / 'a.gma')) as g:
            self.assertEqual(g.timestamp, newest)

    def test_force_replaces_only_a_package_folder(self):
        out = self.root / 'pkg'
        self.build('--out', out)
        self.write(self.repo / FAKE_MOD, b'DDS a v2')
        code, _, _ = self.run_tool('--out', out)
        self.assertEqual(code, 1)
        self.build('--out', out, '--force')
        self.assertEqual((out / 'native' / 'root' / 'rtx-remix' / 'mods' / 'base_mod' / 'textures' / 'a.dds').read_bytes(),
                         b'DDS a v2')
        self.assertEqual(self.leftovers(), [])

    def test_archive_holds_the_same_files_in_their_case(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        self.build('--out', out, '--gma', gma)
        with gmapack.read_gma(str(gma)) as g:
            names = sorted(e['name'] for e in g.files)
        folder = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
        self.assertEqual(names, folder)
        self.assertIn('native/root/garrysmod/addons/Glass-Rewrite-Remix/lua/autorun/glass.lua', names)
        first = gma.read_bytes()
        code, _, _ = self.run_tool('--gma', gma)
        self.assertEqual(code, 1)  # exists, no --force
        self.build('--gma', gma, '--force')
        self.assertEqual(gma.read_bytes(), first)
        self.assertEqual(self.leftovers(), [])

    def test_refusals_leave_nothing_behind(self):
        busy = self.write(self.root / 'busy' / 'file.txt', b'user data')
        cases = [
            [],                                                       # neither --out nor --gma
            ['--out', self.root / 'x', '--exclude-addon', 'nosuch'],
            ['--out', self.root / 'x', '--cvars-from', self.root / 'nowhere.cfg'],
            ['--out', self.root / 'x', '--modules-from', self.root / 'nowhere'],
            ['--out', self.root / 'x', '--id', 'Bad_Id'],
            ['--out', self.root / 'x', '--version', '1.0'],
            ['--out', busy.parent],
            ['--out', busy.parent, '--force'],
            ['--out', self.repo / 'out'],
            ['--out', self.root / 'x', '--gma', self.root / 'x' / 'in.gma'],
        ]
        for args in cases:
            code, _, err = self.run_tool(*args)
            self.assertEqual(code, 1, args)
            self.assertTrue(err.startswith('error: '), err)
        self.assertEqual(busy.read_bytes(), b'user data')
        self.assertFalse((self.root / 'x').exists())
        self.assertFalse((self.repo / 'out').exists())
        self.assertEqual(self.leftovers(), [])

    def test_inputs_the_loader_would_refuse(self):
        addons = self.repo / 'garrysmod' / 'garrysmod' / 'addons'
        for rel, needle in (('rtx_agent/café.lua', 'café.lua'), ('rtx_agent/short~1.lua', 'short~1.lua'),
                            ('My Addon/lua/x.lua', 'My Addon')):
            bad = self.write(addons / rel, b'x')
            code, _, err = self.run_tool('--out', self.root / 'x')
            self.assertEqual(code, 1, rel)
            self.assertIn(needle, err)
            bad.unlink()
            if bad.parent.parent.name == 'My Addon':
                bad.parent.rmdir()
                bad.parent.parent.rmdir()
        (addons / 'emptysub').mkdir()  # an uninitialised submodule
        code, _, err = self.run_tool('--out', self.root / 'x')
        self.assertEqual(code, 1)
        self.assertIn('git submodule', err)
        self.build('--out', self.root / 'x', '--exclude-addon', 'emptysub')
        (addons / 'emptysub').rmdir()
        for rel in ('x86_64/Release/gmcl_rtxwater_win64.dll', 'garrysmod/bin/win64/stdshader_dx6.dll'):
            (self.repo / rel).unlink()
            code, _, err = self.run_tool('--out', self.root / 'y')
            self.assertEqual(code, 1, rel)
            self.assertIn(Path(rel).name, err)
            self.write(self.repo / rel, FAKE[rel])
        self.assertFalse((self.root / 'y').exists())
        self.assertEqual(self.leftovers(), [])

    def test_private_looking_files_are_refused_unless_named(self):
        tree = self.repo / 'garrysmod'
        private = {  # source: package path
            tree / 'garrysmod/addons/remixbinary/lua/debug.log': 'native/root/garrysmod/addons/remixbinary/lua/debug.log',
            tree / 'rtx-remix/mods/base_mod/logs/capture.txt': 'native/root/rtx-remix/mods/base_mod/logs/capture.txt',
            tree / 'garrysmod/data/remix_map_configs/user.conf': 'native/root/garrysmod/data/remix_map_configs/user.conf',
        }
        for source in private:
            self.write(source, b'private')
        code, _, err = self.run_tool('--out', self.root / 'x')
        self.assertEqual(code, 1)
        for rel in private.values():
            self.assertIn(rel, err)
        self.assertFalse((self.root / 'x').exists())
        self.assertEqual(self.leftovers(), [])
        allow = [arg for rel in private.values() for arg in ('--allow-private', rel)]
        summary = self.build('--out', self.root / 'pkg', *allow)
        self.assertEqual(summary['allowed_private'], sorted(private.values(), key=str.lower))
        self.assertLessEqual(set(private.values()), set(self.manifest(self.root / 'pkg')['files']))
        rows = [line.split('\t') for line in (self.root / 'pkg.inventory.txt').read_text(encoding='utf-8').splitlines()[2:]]
        notes = {row[2]: row[4] for row in rows}
        for rel in private.values():
            self.assertTrue(notes[rel].startswith('allowed with --allow-private: '), rel)

    def test_map_compile_logs_stay_out_as_junk(self):
        # The real fixes keep vbsp/vvis/vrad logs beside their maps; they are not a reason to refuse.
        self.write(self.repo / 'garrysmod/garrysmod/addons/remixbinary/maps/gm_construct_rtx.log', b'compile log')
        summary = self.build('--out', self.root / 'pkg')
        self.assertIn('garrysmod/addons/remixbinary/maps/gm_construct_rtx.log', summary['junk'])
        self.assertNotIn('native/root/garrysmod/addons/remixbinary/maps/gm_construct_rtx.log',
                         self.manifest(self.root / 'pkg')['files'])

    def test_an_inventory_beside_each_output_lists_every_file(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        summary = self.build('--out', out, '--gma', gma)
        inventories = [str(self.root / 'pkg.inventory.txt'), str(self.root / 'pkg.gma.inventory.txt')]
        self.assertEqual(summary['inventory'], inventories)
        m, expected = self.manifest(out), self.expected_files()
        manifest = (out / 'native' / 'manifest.json').read_bytes()
        for inventory in inventories:
            lines = Path(inventory).read_text(encoding='utf-8').splitlines()
            self.assertTrue(lines[0].startswith('# rtx-fixes %s: %d files' % (m['version'], len(m['files']))), lines[0])
            rows = [line.split('\t') for line in lines[2:]]
            self.assertEqual([row[2] for row in rows], sorted(m['files'], key=str.lower) + ['native/manifest.json'])
            for size, sha256, path, source, note in rows[:-1]:
                self.assertEqual({'size': int(size), 'sha256': sha256}, m['files'][path])
                self.assertEqual((Path(source), note), (expected[path], ''))
            self.assertEqual(rows[-1][:3], [str(len(manifest)), hashlib.sha256(manifest).hexdigest(), 'native/manifest.json'])

    def test_text_summary(self):
        code, out, err = self.run_tool('--out', self.root / 'pkg')
        self.assertEqual(code, 0, err)
        self.assertRegex(out, r'^Package rtx-fixes 0\.0\.0-dev\.\d{12}\+[0-9a-f]{8}: \d+ files')
        self.assertIn('section "RTX stack required settings (test)"', out)
        self.assertIn('skipped line 27: r_forcehwlight 1 (outside the RTX section)', out)

    @unittest.skipUnless(built_nlctl(), 'nlctl.exe 0.2.0 or newer is not built (tools\\build.ps1)')
    def test_nlctl_accepts_the_folder_and_the_archive(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        self.build('--out', out, '--gma', gma)
        for location in (out, gma):
            done = subprocess.run([str(built_nlctl()), 'manifest', str(location), '--json'], capture_output=True, text=True,
                                  encoding='utf-8')
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(json.loads(done.stdout)['id'], 'rtx-fixes')


if __name__ == '__main__':
    unittest.main()
