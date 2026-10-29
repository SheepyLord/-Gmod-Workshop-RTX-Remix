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
        summary = self.build('--gma', gma, '--version', '1.0.0', '--title', 'House', '--type', 'effects',
                             '--tag', 'realism', '--tag', 'scenic')
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
        code, _, err = self.run_tool('--id', 'x', '--addon', self.addon, '--out', self.root / 'x')
        self.assertEqual(code, 1)
        self.assertIn('native/root/garrysmod/addons/house_rtx/lua/debug.log', err)
        summary = self.build('--out', self.root / 'pkg', '--allow-private', 'native/root/garrysmod/addons/house_rtx/lua/debug.log')
        self.assertEqual(summary['allowed_private'], ['native/root/garrysmod/addons/house_rtx/lua/debug.log'])
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
