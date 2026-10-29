"""Tests for package_reshade.py: the ReShade part of the RTX package, from a setup that is checked
against pinned hashes. A small stand-in setup (bytes, then a ZIP holding a ReShade64.dll) is pinned
for the tests, so no ReShade download is needed."""
import hashlib
import io
import json
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / 'gmapack'))
import gmapack  # noqa: E402
import package_reshade as pr  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class PackageReshadeTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-package-reshade-', dir=SCRATCH))
        self.dll = b'MZ' + b'\x90' * 4096 + b'stand-in ReShade64.dll'
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('ReShade64.dll', self.dll)
            z.writestr('ReShade64.json', b'{"upstream": true}')
        self.setup = self.root / 'ReShade_Setup_test.exe'
        self.setup.write_bytes(b'MZ setup stub ' * 100 + archive.getvalue())
        self.license = self.root / 'LICENSE.md'
        self.license.write_bytes(b'Copyright 2014 Patrick Mours. All rights reserved.\r\n')
        pinned = {'setup': sha(self.setup.read_bytes()), 'dll': sha(self.dll), 'dll_size': len(self.dll),
                  'license': sha(self.license.read_bytes())}
        patches = [mock.patch.dict(pr.PINNED, {'9.9.9': pinned}), mock.patch.object(pr, 'LICENSE', str(self.license))]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def run_tool(self, *extra):
        out = io.StringIO()
        with mock.patch('sys.stdout', out), mock.patch('sys.stderr', io.StringIO()) as err:
            code = pr.main(['--setup', str(self.setup), '--version', '9.9.9', '--no-validate', *extra])
        return code, out.getvalue(), err.getvalue()

    def test_the_part_holds_the_unchanged_dll_its_layer_and_the_licence(self):
        code, out, _ = self.run_tool('--out', str(self.root / 'part'), '--gma', str(self.root / 'part.gma'), '--json')
        self.assertEqual(code, 0)
        summary = json.loads(out)
        part = self.root / 'part'
        manifest = json.loads((part / 'native' / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual((manifest['id'], manifest['version'], manifest['kinds']), ('reshade', '9.9.9', ['reshade']))
        self.assertEqual(manifest['requires_loader'], '>=0.5.0')
        self.assertEqual(manifest['reshade'], {'layer': 'reshade/VkLayer_nativeloader_reshade.json'})
        self.assertEqual((part / 'native/payload/reshade/ReShade64.dll').read_bytes(), self.dll)
        self.assertEqual((part / 'native/payload/reshade/LICENSE.md').read_bytes(), self.license.read_bytes())
        notice = (part / 'native/payload/reshade/README.md').read_text(encoding='utf-8')
        self.assertIn('ReShade 9.9.9 by crosire', notice)
        self.assertIn('VK_LAYER_nativeloader_reshade', notice)
        layer = json.loads((part / 'native/payload/reshade/VkLayer_nativeloader_reshade.json').read_text(encoding='utf-8'))
        self.assertEqual(layer['layer']['name'], 'VK_LAYER_nativeloader_reshade')
        self.assertEqual(layer['layer']['library_path'], '.\\ReShade64.dll')
        self.assertNotIn('disable_environment', layer['layer'])  # not an implicit layer: enabled by name only
        for rel, info in manifest['files'].items():
            data = (part / rel).read_bytes()
            self.assertEqual((info['size'], info['sha256']), (len(data), sha(data)), rel)
        self.assertEqual(set(manifest['files']), {'native/payload/reshade/' + n for n in
                                                  ('ReShade64.dll', 'VkLayer_nativeloader_reshade.json', 'LICENSE.md', 'README.md')})
        self.assertEqual(summary['dll_sha256'], sha(self.dll))
        with gmapack.read_gma(str(self.root / 'part.gma')) as g:
            names = {e['name'].replace('\\', '/').lower() for e in g.files}
        self.assertIn('native/payload/reshade/reshade64.dll', names)
        self.assertFalse([p for p in self.root.iterdir() if '.partial-' in p.name or '.unchecked-' in p.name])

    def test_another_setup_dll_or_licence_is_refused(self):
        self.setup.write_bytes(self.setup.read_bytes() + b'x')  # not the pinned setup
        code, _, err = self.run_tool('--out', str(self.root / 'a'))
        self.assertEqual(code, 1)
        self.assertFalse((self.root / 'a').exists())
        with mock.patch('sys.stderr', io.StringIO()):
            code = pr.main(['--setup', str(self.setup), '--version', '0.0.1', '--out', str(self.root / 'b'), '--no-validate'])
        self.assertEqual(code, 1)  # a version that is not pinned
        self.license.write_bytes(b'something else')
        with self.assertRaisesRegex(pr.PackageError, 'LICENSE'):
            pr.build(pr_args(self.setup, self.root / 'c'))

    def test_a_setup_without_the_dll_is_refused(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('ReShade32.dll', b'MZ 32-bit')
        self.setup.write_bytes(b'MZ' + archive.getvalue())
        pr.PINNED['9.9.9'] = {**pr.PINNED['9.9.9'], 'setup': sha(self.setup.read_bytes())}
        with self.assertRaisesRegex(pr.PackageError, 'no ReShade64.dll'):
            pr.build(pr_args(self.setup, self.root / 'd'))

    def test_an_existing_target_needs_force(self):
        (self.root / 'part').mkdir()
        code, _, _ = self.run_tool('--out', str(self.root / 'part'))
        self.assertEqual(code, 1)
        code, _, _ = self.run_tool('--out', str(self.root / 'part'), '--force')
        self.assertEqual(code, 0)
        self.assertTrue((self.root / 'part' / 'native' / 'manifest.json').is_file())


def pr_args(setup, out):
    return pr.argparse.Namespace(setup=str(setup), version='9.9.9', out=str(out), gma=None, no_validate=True, force=False,
                                 json=False)


if __name__ == '__main__':
    unittest.main()
