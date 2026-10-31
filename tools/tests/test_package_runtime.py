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

import package_runtime

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'gmapack'))
import gmapack  # noqa: E402


def built_nlctl():
    for preset in ('win64-debug', 'win64-release'):
        exe = REPO / 'out' / 'build' / preset / 'loader' / 'cli' / 'nlctl.exe'
        if exe.is_file():
            return exe
    return None


class PackageRuntimeTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'  # AGENTS.md rule 9
        scratch.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch, prefix='package-runtime-')
        self.root = Path(self.tmp.name)
        self.runtime = self.root / '_output'
        for rel, data in {
            'd3d9.dll': b'MZ fake runtime',
            'd3d9.pdb': b'fake pdb',
            'd3d9.exp': b'exp',
            'd3d9.lib': b'lib',
            'old.bak': b'bak',
            'NRD.dll': b'nrd',
            'usd_usdGeom.dll': b'usd',
            'crashpad_handler.exe': b'MZ helper',
            'usd/hd/resources/plugInfo.json': b'{}',
            'usd/hdx/resources/shaders/renderPass.glslfx': b'shader',
        }.items():
            self.write(self.runtime / rel, data)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_tool(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = package_runtime.main(['--runtime', str(self.runtime), *map(str, args)])
        return code, out.getvalue(), err.getvalue()

    def build(self, *args):
        code, out, err = self.run_tool(*args)
        self.assertEqual(code, 0, err)
        return out

    def manifest(self, folder):
        return json.loads((folder / 'native' / 'manifest.json').read_text(encoding='utf-8'))

    def leftovers(self):
        return [p.name for p in self.root.iterdir() if '.partial-' in p.name or '.old-' in p.name]

    def test_default_package_lists_every_runtime_file_with_its_hash(self):
        out = self.root / 'pkg'
        self.build('--out', out)
        m = self.manifest(out)
        self.assertEqual(m['schema'], 1)
        self.assertEqual(m['id'], 'rtx-remix-runtime')
        self.assertEqual(m['kinds'], ['remix-runtime'])
        self.assertEqual(m['requires_loader'], '>=0.1.0')
        expected = ['NRD.dll', 'crashpad_handler.exe', 'd3d9.dll', 'usd/hd/resources/plugInfo.json',
                    'usd/hdx/resources/shaders/renderPass.glslfx', 'usd_usdGeom.dll']
        self.assertEqual(sorted(m['files'], key=str.lower), ['native/payload/runtime/' + p for p in sorted(expected, key=str.lower)])
        for rel in expected:
            data = (self.runtime / rel).read_bytes()
            info = m['files']['native/payload/runtime/' + rel]
            self.assertEqual(info, {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
            self.assertEqual((out / 'native' / 'payload' / 'runtime' / rel).read_bytes(), data)
        self.assertEqual(m['remix'], {
            'entry': 'runtime/d3d9.dll', 'rtx_conf_layers': [], 'dxvk_conf_layers': [], 'env': {},
            'launch_args': ['-dxlevel', '90', '-nod3d9ex'],
            'prefer_system_vulkan_loader': True})
        self.assertFalse((out / 'native' / 'payload' / 'runtime' / 'd3d9.pdb').exists())
        self.assertEqual(self.leftovers(), [])

    def test_default_version_comes_from_d3d9_and_output_is_reproducible(self):
        self.build('--out', self.root / 'a')
        self.build('--out', self.root / 'b')
        first = (self.root / 'a' / 'native' / 'manifest.json').read_bytes()
        self.assertEqual(first, (self.root / 'b' / 'native' / 'manifest.json').read_bytes())
        version = json.loads(first)['version']
        digest = hashlib.sha256((self.runtime / 'd3d9.dll').read_bytes()).hexdigest()
        self.assertRegex(version, r'^0\.0\.0-dev\.\d{12}\+[0-9a-f]{8}$')
        self.assertTrue(version.endswith('+' + digest[:8]))

    def test_pdbs_on_request_and_d3d9_from_another_build(self):
        newer = self.root / 'built-new'
        self.write(newer / 'd3d9.dll', b'MZ newer runtime')
        self.write(newer / 'd3d9.pdb', b'newer pdb')
        out = self.root / 'pkg'
        self.build('--out', out, '--d3d9-from', newer, '--with-pdbs')
        runtime = out / 'native' / 'payload' / 'runtime'
        self.assertEqual((runtime / 'd3d9.dll').read_bytes(), b'MZ newer runtime')
        self.assertEqual((runtime / 'd3d9.pdb').read_bytes(), b'newer pdb')
        self.assertFalse((runtime / 'd3d9.exp').exists())
        m = self.manifest(out)
        self.assertIn('native/payload/runtime/d3d9.pdb', m['files'])
        self.assertTrue(m['version'].endswith('+' + hashlib.sha256(b'MZ newer runtime').hexdigest()[:8]))

    def test_layers_env_and_switches(self):
        a = self.write(self.root / 'confs' / 'base.conf', b'rtx.a = 1\n')
        b = self.write(self.root / 'confs' / 'rtx.conf', b'rtx.b = 2\n')
        d = self.write(self.root / 'confs' / 'dxvk.conf', b'd3d9.x = 1\n')
        out = self.root / 'pkg'
        self.build('--out', out, '--rtx-conf', a, '--rtx-conf', b, '--dxvk-conf', d, '--env', 'DXVK_LOG_LEVEL=info',
                   '--env', 'RTX_TEST=a b', '--no-launch-args', '--no-system-vulkan', '--id', 'my-runtime',
                   '--version', '1.2.3-rc.1+build.5', '--name', 'Test runtime')
        m = self.manifest(out)
        self.assertEqual((m['id'], m['version'], m['name']), ('my-runtime', '1.2.3-rc.1+build.5', 'Test runtime'))
        self.assertEqual(m['remix']['rtx_conf_layers'], ['config/rtx/01_base.conf', 'config/rtx/02_rtx.conf'])
        self.assertEqual(m['remix']['dxvk_conf_layers'], ['config/dxvk/01_dxvk.conf'])
        self.assertEqual(m['remix']['env'], {'DXVK_LOG_LEVEL': 'info', 'RTX_TEST': 'a b'})
        self.assertEqual(m['remix']['launch_args'], [])
        self.assertFalse(m['remix']['prefer_system_vulkan_loader'])
        self.assertEqual((out / 'native' / 'payload' / 'config' / 'rtx' / '02_rtx.conf').read_bytes(), b'rtx.b = 2\n')
        self.assertEqual(m['files']['native/payload/config/dxvk/01_dxvk.conf']['size'], len(b'd3d9.x = 1\n'))

    def test_refusals_leave_nothing_behind(self):
        not_conf = self.write(self.root / 'layer.txt', b'x')
        busy = self.write(self.root / 'busy' / 'file.txt', b'user data')
        cases = [
            ['--out', self.root / 'x', '--rtx-conf', not_conf],
            ['--out', self.root / 'x', '--env', 'PATH=C:\\'],
            ['--out', self.root / 'x', '--env', 'DXVK_RTX_CONFIG_FILE=a.conf'],
            ['--out', self.root / 'x', '--env', 'DXVK_LOG_LEVEL=caf\u00e9'],
            ['--out', self.root / 'x', '--version', '1.0'],
            ['--out', self.root / 'x', '--id', 'Bad_Id'],
            ['--out', busy.parent],
            ['--out', busy.parent, '--force'],
            ['--out', self.runtime / 'inside'],
            ['--out', self.root / 'x', '--d3d9-from', self.root / 'nowhere'],
        ]
        for args in cases:
            code, _, err = self.run_tool(*args)
            self.assertEqual(code, 1, args)
            self.assertTrue(err.startswith('error: '), err)
        self.assertEqual(busy.read_bytes(), b'user data')
        self.assertFalse((self.root / 'x').exists())
        self.assertEqual(self.leftovers(), [])
        code, _, _ = self.run_tool()
        self.assertEqual(code, 1)  # neither --out nor --gma

    def test_tiers_are_hashed_payloads_but_not_unconditional_layers(self):
        classic = self.write(self.root / 'classic.conf', b'rtx.pathMaxBounces = 12\n')
        medium = self.write(self.root / 'medium.conf', b'# compute\nrtx.pathMaxBounces = 8\n')
        low = self.write(self.root / 'low.conf', b'rtx.lowMemoryGpu = True\n')
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        self.build('--out', out, '--gma', gma, '--dxvk-conf', classic,
                   '--tier-conf', 'medium', medium, '--tier-conf', 'low', low)
        manifest = self.manifest(out)
        self.assertEqual(manifest['remix']['dxvk_conf_layers'], ['config/dxvk/01_classic.conf'])
        self.assertEqual(manifest['remix']['rtx_conf_layers'], [])
        self.assertEqual(manifest['requires_loader'], '>=0.1.0')
        with gmapack.read_gma(str(gma)) as archive:
            entries = {entry['name']: entry for entry in archive.files}
            for tier, source in [('medium', medium), ('low', low)]:
                path = 'native/payload/config/dxvk-tiers/%s.conf' % tier
                data = source.read_bytes()
                self.assertEqual(manifest['files'][path],
                                 {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
                self.assertEqual((out / path).read_bytes(), data)
                archive.fh.seek(entries[path]['offset'])
                self.assertEqual(archive.fh.read(entries[path]['size']), data)
                self.assertIn(path, Path(str(out) + '.inventory.txt').read_text())

    def test_invalid_tiers_are_refused_before_writing(self):
        valid = self.write(self.root / 'valid.conf', b'rtx.lowMemoryGpu = True\n')
        cases = [
            ['high', valid],
            ['medium', valid, '--tier-conf', 'medium', valid],
            ['low', self.write(self.root / 'bad.txt', valid.read_bytes())],
            ['low', self.root / 'missing.conf'],
        ]
        for content in (b'dxvk.enableAftermath = True\n', b'rtx.a\n', b'rtx.a =\n', b'# empty\n',
                        b'rtx.a = 1\nrtx.a = 2\n', b'\xff\n'):
            cases.append(['low', self.write(self.root / ('bad%d.conf' % len(cases)), content)])
        for args in cases:
            code, _, err = self.run_tool('--out', self.root / 'bad', '--tier-conf', *args)
            self.assertEqual(code, 1, err)
            self.assertIn('--tier-conf', err)
            self.assertFalse((self.root / 'bad').exists())
        self.assertEqual(self.leftovers(), [])

    def test_runtime_paths_the_loader_refuses(self):
        # Names Windows itself would alter or treat as devices (trailing dots, con.txt) cannot be
        # created here; path_problem's unit cases below cover them.
        for name in ('caf\u00e9.dll', 'short~1.dll'):
            bad = self.write(self.runtime / name, b'x')
            code, _, err = self.run_tool('--out', self.root / 'x')
            self.assertEqual(code, 1, name)
            self.assertIn(name, err)
            bad.unlink()
        (self.runtime / 'd3d9.dll').unlink()
        code, _, err = self.run_tool('--out', self.root / 'x')
        self.assertEqual(code, 1)
        self.assertIn('no d3d9.dll', err)
        self.assertEqual(self.leftovers(), [])

    def test_private_looking_files_are_refused_unless_named(self):
        private = ['user.conf', 'remix-dxvk.log', '.env', 'local.ENV', 'crash.dmp', 'mini.mdmp', 'logs/readme.txt',
                   'usd/Logs/plugInfo.json']
        for rel in private:
            self.write(self.runtime / rel, b'private')
        layer = self.write(self.root / 'mine' / 'user.conf', b'rtx.mine = 1\n')  # a layer named like Remix's own
        listed = ['native/payload/runtime/' + rel for rel in private] + ['native/payload/config/rtx/01_user.conf']
        code, _, err = self.run_tool('--out', self.root / 'x', '--rtx-conf', layer)
        self.assertEqual(code, 1)
        for rel in listed:
            self.assertIn(rel, err)
        self.assertNotIn('d3d9.dll', err)
        self.assertFalse((self.root / 'x').exists())
        allow = [arg for rel in listed for arg in ('--allow-private', rel)]
        code, _, err = self.run_tool('--out', self.root / 'x', '--rtx-conf', layer, *allow[:-2])
        self.assertEqual(code, 1)  # one not named: still refused, and only that one listed
        self.assertEqual([line.strip() for line in err.splitlines()[1:]],
                         ['native/payload/config/rtx/01_user.conf (Remix\'s user.conf, a user\'s own settings)'])
        code, _, err = self.run_tool('--out', self.root / 'x', '--rtx-conf', layer, *allow,
                                     '--allow-private', 'native/payload/runtime/d3d9.dll')
        self.assertEqual(code, 1)  # an exception for a file that is not private is a mistake
        self.assertIn('--allow-private native/payload/runtime/d3d9.dll', err)
        self.assertEqual(self.leftovers(), [])
        out = self.root / 'pkg'
        summary = json.loads(self.build('--out', out, '--rtx-conf', layer, '--json', *allow))
        self.assertEqual(summary['allowed_private'], sorted(listed, key=str.lower))
        self.assertLessEqual(set(listed), set(self.manifest(out)['files']))

    def test_an_inventory_beside_each_output_lists_every_file(self):
        self.write(self.runtime / 'logs' / 'kept.txt', b'reviewed')
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        text = self.build('--out', out, '--gma', gma, '--allow-private', 'native/payload/runtime/logs/kept.txt')
        m = self.manifest(out)
        manifest = (out / 'native' / 'manifest.json').read_bytes()
        for inventory in (self.root / 'pkg.inventory.txt', self.root / 'pkg.gma.inventory.txt'):
            self.assertIn('inventory  %s' % inventory, text)
            lines = inventory.read_text(encoding='utf-8').splitlines()
            self.assertRegex(lines[0], r'^# rtx-remix-runtime \S+: %d files and native/manifest.json' % len(m['files']))
            self.assertEqual(lines[1], 'size\tsha256\tpath\tsource\tnote')
            rows = [line.split('\t') for line in lines[2:]]
            self.assertEqual([row[2] for row in rows], sorted(m['files'], key=str.lower) + ['native/manifest.json'])
            for size, sha256, path, source, note in rows[:-1]:
                self.assertEqual({'size': int(size), 'sha256': sha256}, m['files'][path])
                self.assertEqual(Path(source).read_bytes(), (out / path).read_bytes())
                self.assertEqual(note, 'allowed with --allow-private: inside a logs folder' if path.endswith('kept.txt') else '')
            self.assertEqual(rows[-1][:3], [str(len(manifest)), hashlib.sha256(manifest).hexdigest(), 'native/manifest.json'])
        with gmapack.read_gma(str(gma)) as g:
            self.assertEqual(sorted(e['name'] for e in g.files), sorted(row[2] for row in rows))

    def test_path_rules_match_the_loader(self):
        ok = ['native/payload/runtime/d3d9.dll', 'native/payload/runtime/usd/hd/resources/plugInfo.json']
        bad = ['', 'a//b', 'a/./b', 'a/../b', 'a\\b', 'a:b', 'a/b*', 'con', 'CON.txt', 'lpt9.dll', 'com¹',
               'conin$', 'a/trailing.', 'a/trailing ', 'a/ leading', 'short~1.dll', 'café', 'tab\there',
               'x' * 256, '/'.join(['abc'] * 300)]
        for path in ok:
            self.assertEqual(package_runtime.path_problem(path), '', path)
        for path in bad:
            self.assertNotEqual(package_runtime.path_problem(path), '', path)

    def test_force_replaces_only_a_package_folder(self):
        out = self.root / 'pkg'
        self.build('--out', out)
        (self.runtime / 'NRD.dll').write_bytes(b'nrd v2')
        code, _, _ = self.run_tool('--out', out)
        self.assertEqual(code, 1)
        self.build('--out', out, '--force')
        self.assertEqual((out / 'native' / 'payload' / 'runtime' / 'NRD.dll').read_bytes(), b'nrd v2')
        self.assertEqual(self.leftovers(), [])

    def test_archive_holds_the_same_files_in_their_case(self):
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        self.build('--out', out, '--gma', gma)
        with gmapack.read_gma(str(gma)) as g:
            names = sorted(e['name'] for e in g.files)
            self.assertEqual(g.timestamp, int((self.runtime / 'd3d9.dll').stat().st_mtime))
        folder = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
        self.assertEqual(names, folder)
        self.assertIn('native/payload/runtime/usd_usdGeom.dll', names)
        first = gma.read_bytes()
        code, _, _ = self.run_tool('--gma', gma)
        self.assertEqual(code, 1)  # exists, no --force
        self.build('--gma', gma, '--force')
        self.assertEqual(gma.read_bytes(), first)
        self.assertEqual(self.leftovers(), [])

    @unittest.skipUnless(built_nlctl(), 'nlctl.exe is not built (tools\\build.ps1)')
    def test_nlctl_accepts_the_folder_and_the_archive(self):
        conf = self.write(self.root / 'rtx.conf', b'rtx.x = 1\n')
        out, gma = self.root / 'pkg', self.root / 'pkg.gma'
        self.build('--out', out, '--gma', gma, '--rtx-conf', conf, '--env', 'DXVK_LOG_LEVEL=info')
        for location in (out, gma):
            done = subprocess.run([str(built_nlctl()), 'manifest', str(location), '--json'], capture_output=True, text=True,
                                  encoding='utf-8')
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(json.loads(done.stdout)['id'], 'rtx-remix-runtime')


if __name__ == '__main__':
    unittest.main()
