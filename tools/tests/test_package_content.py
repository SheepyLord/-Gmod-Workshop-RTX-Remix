import contextlib
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import package_content

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'gmapack'))
import gmapack  # noqa: E402

FAKE = {
    'house_rtx/addon.json': b'{"title": "house"}',
    'house_rtx/lua/autorun/house_rtx.lua': b'-- house\n',
    'house_rtx/materials/house_rtx/tag.vtf': b'VTF',
    'house_rtx/lua/Thumbs.db': b'junk',
    'mods/house_rtx/mod.usda': b'#usda 1.0\n',
    'mods/house_rtx/materials.usda': b'#usda 1.0\nover "RootNode" {}\n',
    'mods/house_rtx/textures/A.dds': b'DDS a',
    'mods/house_rtx/textures/b.dds': b'DDS b',
    'mods/Emissives/mod.usda': b'#usda 1.0\n',
    'mods/Emissives/SubUSDs/textures/B19B22D6FDE30598.dds': b'DDS emissive',
}


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


class PackageContentTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch, prefix='package-content-')
        self.root = Path(self.tmp.name)
        self.src = self.root / 'src'
        for rel, data in FAKE.items():
            self.write(self.src / rel, data)
        self.addon, self.mod, self.emissives = self.src / 'house_rtx', self.src / 'mods' / 'house_rtx', self.src / 'mods' / 'Emissives'

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_tool(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = package_content.main([*map(str, args)])
        return code, out.getvalue(), err.getvalue()

    def build(self, *args):
        code, out, err = self.run_tool('--json', '--id', 'house-rtx', '--addon', self.addon, '--mod', self.mod, *args)
        self.assertEqual(code, 0, err)
        return json.loads(out)

    def manifest(self, folder):
        return json.loads((folder / 'native' / 'manifest.json').read_text(encoding='utf-8'))

    def leftovers(self):
        return [p.name for p in self.root.iterdir() if any(s in p.name for s in ('.partial-', '.old-', '.unchecked-'))]

    def test_manifest_structure(self):
        out = self.root / 'pkg'
        summary = self.build('--out', out, '--requires-remix', '--name', 'House RTX')
        m = self.manifest(out)
        self.assertEqual(m['schema'], 1)
        self.assertEqual((m['id'], m['name'], m['version']), ('house-rtx', 'House RTX', summary['version']))
        self.assertEqual(m['kinds'], ['lua-addon', 'root-files'])
        self.assertEqual(m['requires_loader'], '>=0.2.0')
        self.assertIs(m['requires_remix'], True)
        self.assertEqual(m['root_files'], [{'path': 'garrysmod/addons/house_rtx', 'policy': 'replace-owned'},
                                           {'path': 'rtx-remix/mods/house_rtx', 'policy': 'replace-owned'}])
        self.assertEqual(sorted(m['files']), sorted([
            'native/root/garrysmod/addons/house_rtx/addon.json',
            'native/root/garrysmod/addons/house_rtx/lua/autorun/house_rtx.lua',
            'native/root/garrysmod/addons/house_rtx/materials/house_rtx/tag.vtf',
            'native/root/rtx-remix/mods/house_rtx/mod.usda',
            'native/root/rtx-remix/mods/house_rtx/materials.usda',
            'native/root/rtx-remix/mods/house_rtx/textures/A.dds',
            'native/root/rtx-remix/mods/house_rtx/textures/b.dds',
        ]))
        for rel, info in m['files'].items():
            data = (out / rel).read_bytes()
            self.assertEqual(info, {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        self.assertEqual(summary['addons'], ['house_rtx'])
        self.assertEqual(summary['mods'], ['house_rtx'])
        self.assertEqual(summary['junk'], [str(self.addon / 'lua' / 'Thumbs.db')])
        self.assertFalse(summary['linked'])
        self.assertEqual(json.loads((out / 'addon.json').read_text(encoding='utf-8'))['title'], 'House RTX')

    def test_a_mod_alone_and_no_remix_requirement(self):
        code, out, err = self.run_tool('--json', '--id', 'emissives', '--mod', self.emissives, '--out', self.root / 'pkg')
        self.assertEqual(code, 0, err)
        m = self.manifest(self.root / 'pkg')
        self.assertEqual(m['kinds'], ['root-files'])
        self.assertIs(m['requires_remix'], False)
        self.assertEqual(m['root_files'], [{'path': 'rtx-remix/mods/Emissives', 'policy': 'replace-owned'}])

    def test_default_version_and_reproducible_archive(self):
        stamp = 1_700_000_000
        for path in self.src.rglob('*'):
            if path.is_file():
                os.utime(path, (stamp, stamp))
        first = self.build('--gma', self.root / 'a.gma')
        self.assertRegex(first['version'], r'^0\.0\.0-dev\.202311142213\+[0-9a-f]{8}$')
        again = self.build('--gma', self.root / 'b.gma')
        self.assertEqual(again['version'], first['version'])
        self.assertEqual((self.root / 'a.gma').read_bytes(), (self.root / 'b.gma').read_bytes())
        self.write(self.mod / 'textures' / 'b.dds', b'DDS b changed')
        os.utime(self.mod / 'textures' / 'b.dds', (stamp, stamp))
        self.assertNotEqual(self.build('--gma', self.root / 'c.gma')['version'], first['version'])

    def test_archive_only_build_links_and_matches_a_folder_build(self):
        out, gma = self.root / 'pkg', self.root / 'only.gma'
        self.build('--out', out, '--version', '1.0.0')
        self.assertFalse(self.build('--gma', self.root / 'copied.gma', '--version', '1.0.0')['linked'])  # links are opt-in
        summary = self.build('--gma', gma, '--version', '1.0.0', '--title', 'House', '--type', 'effects',
                             '--tag', 'realism', '--tag', 'scenic', '--link')
        self.assertTrue(summary['linked'])
        # nlctl refuses hard-linked files in a folder, so a linked build is checked as the archive.
        self.assertEqual(bool(summary['validated_by']), bool(built_nlctl()))
        self.assertTrue(self.mod.joinpath('textures', 'A.dds').read_bytes() == b'DDS a')  # sources untouched
        with gmapack.read_gma(str(gma)) as g:
            names = sorted(e['name'] for e in g.files)
            meta = json.loads(g.description)  # gmad's shape: description, type, tags
            self.assertEqual((g.title, meta['type'], meta['tags']), ('House', 'effects', ['realism', 'scenic']))
        # The archive root's addon.json is the header, not a file; the add-on's own addon.json is a file.
        folder = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()
                        and p.relative_to(out).as_posix() != 'addon.json')
        self.assertIn('native/root/garrysmod/addons/house_rtx/addon.json', names)
        self.assertEqual(names, folder)
        self.assertEqual(summary['gma_sha256'], hashlib.sha256(gma.read_bytes()).hexdigest())
        self.assertEqual(self.leftovers(), [])

    def test_refusals_leave_nothing_behind(self):
        busy = self.write(self.root / 'busy' / 'file.txt', b'user data')
        empty = self.root / 'src' / 'empty_mod'
        empty.mkdir()
        cases = [
            ['--id', 'x', '--addon', self.addon],                                       # neither --out nor --gma
            ['--id', 'x', '--out', self.root / 'x'],                                    # nothing to package
            ['--id', 'Bad_Id', '--addon', self.addon, '--out', self.root / 'x'],
            ['--id', 'x', '--version', '1.0', '--addon', self.addon, '--out', self.root / 'x'],
            ['--id', 'x', '--addon', self.root / 'nowhere', '--out', self.root / 'x'],
            ['--id', 'x', '--mod', empty, '--out', self.root / 'x'],
            ['--id', 'x', '--mod', self.mod, '--mod', self.addon, '--out', self.root / 'x'],  # same folder name twice
            ['--id', 'x', '--addon', self.addon, '--out', busy.parent],
            ['--id', 'x', '--addon', self.addon, '--out', self.addon / 'pkg'],
            ['--id', 'x', '--addon', self.addon, '--out', self.root / 'x', '--gma', self.root / 'x' / 'in.gma'],
        ]
        for args in cases:
            code, _, err = self.run_tool(*args)
            self.assertEqual(code, 1, args)
            self.assertTrue(err.startswith('error: '), err)
        self.assertEqual(busy.read_bytes(), b'user data')
        self.assertFalse((self.root / 'x').exists())
        self.assertFalse((self.addon / 'pkg').exists())
        self.assertEqual(self.leftovers(), [])

    def test_inputs_the_loader_would_refuse_and_private_files(self):
        bad = self.write(self.mod / 'textures' / 'café.dds', b'x')
        code, _, err = self.run_tool('--id', 'x', '--mod', self.mod, '--out', self.root / 'x')
        self.assertEqual((code, 'café.dds' in err), (1, True))
        bad.unlink()
        self.write(self.addon / 'lua' / 'debug.log', b'private')
        log = 'native/root/garrysmod/addons/house_rtx/lua/debug.log'
        # gmad would not publish a log, so the add-on filter leaves it out before it could be refused...
        self.assertIn(log, self.build('--out', self.root / 'filtered')['filtered'])
        # ...and without the filter, or in a mod, a private-looking file is refused unless named.
        code, _, err = self.run_tool('--id', 'x', '--addon', self.addon, '--no-addon-filter', '--out', self.root / 'x')
        self.assertEqual(code, 1)
        self.assertIn(log, err)
        summary = self.build('--out', self.root / 'pkg', '--no-addon-filter', '--allow-private', log)
        self.assertEqual(summary['allowed_private'], [log])
        self.write(self.mod / 'logs' / 'capture.txt', b'private')
        code, _, err = self.run_tool('--id', 'x', '--mod', self.mod, '--out', self.root / 'x')
        self.assertEqual((code, 'native/root/rtx-remix/mods/house_rtx/logs/capture.txt' in err), (1, True))
        self.assertFalse((self.root / 'x').exists())
        self.assertEqual(self.leftovers(), [])

    def test_an_inventory_beside_each_output(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        summary = self.build('--out', out, '--gma', gma)
        self.assertEqual(summary['inventory'], [str(self.root / 'pkg.inventory.txt'), str(self.root / 'pkg.gma.inventory.txt')])
        m = self.manifest(out)
        for inventory in summary['inventory']:
            rows = [line.split('\t') for line in Path(inventory).read_text(encoding='utf-8').splitlines()[2:]]
            self.assertEqual([row[2] for row in rows], sorted(m['files'], key=str.lower) + ['native/manifest.json'])

    def test_text_summary(self):
        code, out, err = self.run_tool('--id', 'house-rtx', '--addon', self.addon, '--mod', self.mod, '--out', self.root / 'pkg')
        self.assertEqual(code, 0, err)
        self.assertRegex(out, r'^Package house-rtx 0\.0\.0-dev\.\d{12}\+[0-9a-f]{8}: 7 files')
        self.assertIn('mods       house_rtx', out)

    def test_addons_keep_only_what_gmad_would_publish(self):
        dev = self.src / 'dev_addon'
        for rel, data in {'addon.json': b'{"title": "dev", "ignore": ["lua/dev/*", "*.psd"]}',
                          'lua/autorun/dev.lua': b'-- kept', 'lua/dev/scratch.lua': b'-- ignored by addon.json',
                          'materials/dev/icon.png': b'PNG', 'icon.psd': b'PSD', 'README.md': b'# notes',
                          '.codex_stage/lua/autorun/old.lua': b'-- a staging copy', 'native/bridge.cpp': b'int x;',
                          'shaders/fxc/dev_ps20b.vcs': b'VCS', 'data_static/dev.json': b'{}'}.items():
            self.write(dev / rel, data)
        summary = self.build('--addon', dev, '--out', self.root / 'pkg')
        prefix = 'native/root/garrysmod/addons/dev_addon/'
        kept = sorted(p[len(prefix):] for p in self.manifest(self.root / 'pkg')['files'] if p.startswith(prefix))
        self.assertEqual(kept, ['addon.json', 'data_static/dev.json', 'lua/autorun/dev.lua', 'materials/dev/icon.png',
                                'shaders/fxc/dev_ps20b.vcs'])
        self.assertEqual(sorted((p[len(prefix):] for p in summary['filtered'] if p.startswith(prefix)), key=str.lower),
                         ['.codex_stage/lua/autorun/old.lua', 'icon.psd', 'lua/dev/scratch.lua', 'native/bridge.cpp', 'README.md'])
        narrower = self.build('--addon', dev, '--out', self.root / 'narrower', '--ignore', 'materials/*')
        self.assertIn(prefix + 'materials/dev/icon.png', narrower['filtered'])
        everything = self.build('--addon', dev, '--out', self.root / 'all', '--no-addon-filter')
        self.assertEqual(everything['filtered'], [])
        self.assertIn(prefix + 'README.md', self.manifest(self.root / 'all')['files'])

    def test_an_addon_under_another_name_and_a_leading_bang(self):
        code, out, err = self.run_tool('--json', '--id', 'x', '--addon-as', '!house_first', self.addon, '--out', self.root / 'pkg')
        self.assertEqual(code, 0, err)
        roots = [r['path'] for r in self.manifest(self.root / 'pkg')['root_files']]
        self.assertEqual(roots, ['garrysmod/addons/!house_first'])
        self.assertEqual(json.loads(out)['addons'], ['!house_first'])
        code, _, err = self.run_tool('--id', 'x', '--addon-as', 'bad name', self.addon, '--out', self.root / 'x')
        self.assertEqual((code, 'bad name' in err), (1, True))

    def test_binary_modules_and_the_runtime_they_load_first(self):
        natives = {name: self.write(self.src / 'bin' / name, name.encode())
                   for name in ('gmcl_mmdhl_win64.dll', 'gmsv_mmdhl_win64.dll', 'mmdhl_runtime_win64.dll', 'mmdhl_worker.exe')}
        args = [arg for path in natives.values() for arg in ('--lua-bin', path)]
        summary = self.build(*args, '--load-first', 'gmcl_mmdhl_win64.dll=mmdhl_runtime_win64.dll',
                             '--load-first', 'GMSV_mmdhl_win64.dll=mmdhl_runtime_win64.dll', '--out', self.root / 'pkg')
        m = self.manifest(self.root / 'pkg')
        self.assertEqual(m['kinds'], ['lua-binary-module', 'lua-addon', 'root-files'])
        self.assertEqual(m['requires_loader'], '>=0.3.0')
        self.assertEqual(m['module_dependencies'], [
            {'module': 'garrysmod/lua/bin/gmcl_mmdhl_win64.dll', 'load_first': ['garrysmod/lua/bin/mmdhl_runtime_win64.dll']},
            {'module': 'garrysmod/lua/bin/gmsv_mmdhl_win64.dll', 'load_first': ['garrysmod/lua/bin/mmdhl_runtime_win64.dll']}])
        for name in natives:
            self.assertIn({'path': 'garrysmod/lua/bin/' + name, 'policy': 'replace-owned'}, m['root_files'])
            self.assertIn('native/root/garrysmod/lua/bin/' + name, m['files'])
        self.assertEqual(sorted(summary['lua_bin']), sorted(natives))
        # Without a dependency the package needs only the M5 loader.
        plain = self.build('--lua-bin', natives['mmdhl_worker.exe'], '--out', self.root / 'plain')
        self.assertEqual(self.manifest(self.root / 'plain')['requires_loader'], '>=0.2.0')
        self.assertEqual(plain['module_dependencies'], [])
        dll, runtime = natives['gmcl_mmdhl_win64.dll'], natives['mmdhl_runtime_win64.dll']
        for bad in (['--load-first', 'gmcl_mmdhl_win64.dll'],                                   # no =
                    ['--load-first', 'gmcl_mmdhl_win64.dll=nowhere.dll'],                       # not a --lua-bin file
                    ['--load-first', 'gmcl_mmdhl_win64.dll=mmdhl_worker.exe'],                  # not a .dll
                    ['--load-first', 'gmcl_mmdhl_win64.dll=gmcl_mmdhl_win64.dll'],              # itself
                    ['--load-first', 'gmcl_mmdhl_win64.dll=mmdhl_runtime_win64.dll'] * 2,       # twice
                    ['--lua-bin', dll],                                                         # same name twice
                    ['--lua-bin', self.src / 'bin' / 'missing.dll']):
            code, _, err = self.run_tool('--id', 'x', *args, *bad, '--out', self.root / 'x')
            self.assertEqual(code, 1, bad)
            self.assertTrue(err.startswith('error: '), err)
        self.assertFalse((self.root / 'x').exists())
        self.assertTrue(runtime.is_file())

    @unittest.skipUnless(built_nlctl(), 'nlctl.exe 0.2.0 or newer is not built (tools\\build.ps1)')
    def test_nlctl_accepts_the_folder_and_the_archive(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        summary = self.build('--out', out, '--gma', gma, '--requires-remix')
        self.assertTrue(summary['validated_by'])
        for location in (out, gma):
            done = subprocess.run([str(built_nlctl()), 'manifest', str(location), '--json'], capture_output=True, text=True,
                                  encoding='utf-8')
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(json.loads(done.stdout)['id'], 'house-rtx')


if __name__ == '__main__':
    unittest.main()
