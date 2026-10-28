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
            'launch_args': ['-dxlevel', '90', '-nod3d9ex', '+mat_disable_d3d9ex', '1'],
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
            done = subprocess.run([str(built_nlctl()), 'manifest', str(location), '--json'], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(json.loads(done.stdout)['id'], 'rtx-remix-runtime')


if __name__ == '__main__':
    unittest.main()
