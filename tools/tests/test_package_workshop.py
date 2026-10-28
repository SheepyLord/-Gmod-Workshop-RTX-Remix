"""Tests for package_workshop.py: merging native packages into one, from folders and archives."""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import package_workshop as pw  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'


def write_package(folder: Path, manifest: dict, files: dict) -> Path:
    """A package folder: the files (path: bytes) and a manifest listing them with size and SHA-256."""
    manifest = dict(manifest)
    manifest['files'] = {}
    for rel, data in files.items():
        (folder / rel).parent.mkdir(parents=True, exist_ok=True)
        (folder / rel).write_bytes(data)
        manifest['files'][rel] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    (folder / 'native').mkdir(parents=True, exist_ok=True)
    (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    return folder


RUNTIME = ({'schema': 1, 'id': 'rt', 'version': '1.0.0', 'kinds': ['remix-runtime'], 'requires_loader': '>=0.1.0',
            'remix': {'entry': 'runtime/d3d9.dll', 'rtx_conf_layers': [], 'dxvk_conf_layers': [], 'env': {}, 'launch_args': []}},
           {'native/payload/runtime/d3d9.dll': b'MZ runtime', 'native/payload/config/rtx/01_rtx.conf': b'rtx.a = 1\n'})
FIXES = ({'schema': 1, 'id': 'fx', 'version': '2.0.0', 'kinds': ['root-files', 'patch-set'], 'requires_loader': '>=0.2.0',
          'requires_remix': True, 'root_files': [{'path': 'rtx-remix/mods/fx'}],
          'patch_sets': [{'module': 'engine.dll', 'patches': [{'name': 'p', 'find': 'aa', 'replace': 'bb'}]}],
          'session_cvars': {'r_3dsky': '0'}},
         {'native/root/rtx-remix/mods/fx/mod.usda': b'#usda 1.0\n'})
ADDON = {'title': 'Test item', 'type': 'tool', 'tags': ['build'], 'description': 'test'}


class CombineTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-package-workshop-', dir=SCRATCH))
        self.runtime = write_package(self.root / 'runtime', *RUNTIME)
        self.fixes = write_package(self.root / 'fixes', *FIXES)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def combine(self, parts, version='3.0.0', **kw):
        return pw.combine(parts, 'combined', version, 'Combined', ADDON, kw.pop('out', self.root / 'out'),
                          kw.pop('gma', self.root / 'out.gma'), force=True, validate=False, **kw)

    def manifest(self, folder: Path) -> dict:
        return json.loads((folder / 'native' / 'manifest.json').read_text(encoding='utf-8'))

    def test_two_folders_become_one_package_and_archive(self):
        summary = self.combine([self.runtime, self.fixes])
        m = self.manifest(self.root / 'out')
        self.assertEqual((m['id'], m['version'], m['name']), ('combined', '3.0.0', 'Combined'))
        self.assertEqual(m['kinds'], ['remix-runtime', 'root-files', 'patch-set'])
        self.assertEqual(m['requires_loader'], '>=0.2.0')
        self.assertTrue(m['requires_remix'])
        self.assertEqual(m['remix'], RUNTIME[0]['remix'])
        self.assertEqual(m['root_files'], FIXES[0]['root_files'])
        self.assertEqual(m['patch_sets'], FIXES[0]['patch_sets'])
        self.assertEqual(m['session_cvars'], {'r_3dsky': '0'})
        self.assertEqual(set(m['files']), set(RUNTIME[1]) | set(FIXES[1]))
        for rel, data in {**RUNTIME[1], **FIXES[1]}.items():
            self.assertEqual((self.root / 'out' / rel).read_bytes(), data)
        self.assertEqual(json.loads((self.root / 'out' / 'addon.json').read_text(encoding='utf-8')), ADDON)
        self.assertEqual(summary['files'], 3)
        with pw.gmapack.read_gma(str(self.root / 'out.gma')) as g:
            names = {e['name'].replace('\\', '/').lower() for e in g.files}
        self.assertEqual(names, {n.lower() for n in m['files']} | {'native/manifest.json'})
        self.assertEqual(summary['gma_sha256'], pw.sha256_file(self.root / 'out.gma'))

    def test_an_archive_part_is_read_in_place(self):
        archive = self.root / 'runtime.gma'
        (self.runtime / 'addon.json').write_text(json.dumps({'title': 'rt', 'type': 'tool', 'tags': []}), encoding='utf-8')
        subprocess.run([sys.executable, '-I', '-B', str(TOOLS / 'gmapack' / 'gmapack.py'), 'create', '--folder', str(self.runtime),
                        '--out', str(archive), '--quiet'], check=True)
        from_archive = self.combine([archive, self.fixes], out=self.root / 'a', gma=None)
        from_folder = self.combine([self.runtime, self.fixes], out=self.root / 'b', gma=None)
        self.assertEqual(from_archive['digest'], from_folder['digest'])
        self.assertEqual((self.root / 'a' / 'native/payload/runtime/d3d9.dll').read_bytes(), b'MZ runtime')

    def test_the_digest_ignores_version_and_name_but_not_content(self):
        first = self.combine([self.runtime, self.fixes], version='3.0.0', out=None)
        second = self.combine([self.runtime, self.fixes], version='3.0.1', out=None)
        self.assertEqual(first['digest'], second['digest'])
        write_package(self.fixes, FIXES[0], {'native/root/rtx-remix/mods/fx/mod.usda': b'#usda 1.0\n# changed\n'})
        third = self.combine([self.runtime, self.fixes], version='3.0.2', out=None)
        self.assertNotEqual(first['digest'], third['digest'])

    def test_a_file_in_two_parts_is_refused(self):
        other = write_package(self.root / 'other', {'schema': 1, 'id': 'o', 'version': '1.0.0', 'kinds': ['root-files']},
                              {'native/root/rtx-remix/mods/fx/MOD.usda': b'x'})
        with self.assertRaisesRegex(pw.CombineError, 'more than one part'):
            self.combine([self.fixes, other])

    def test_two_runtimes_are_refused(self):
        second = write_package(self.root / 'rt2', {**RUNTIME[0], 'id': 'rt2'}, {'native/payload/runtime2/d3d9.dll': b'MZ'})
        with self.assertRaisesRegex(pw.CombineError, 'runtime'):
            self.combine([self.runtime, second])

    def test_a_file_that_does_not_match_its_manifest_is_refused(self):
        (self.fixes / 'native/root/rtx-remix/mods/fx/mod.usda').write_bytes(b'tampered!!')
        with self.assertRaisesRegex(pw.CombineError, 'does not match'):
            self.combine([self.runtime, self.fixes])
        self.assertFalse((self.root / 'out').exists())

    def test_conflicting_session_values_and_unknown_keys_are_refused(self):
        other = write_package(self.root / 'other', {'schema': 1, 'id': 'o', 'version': '1.0.0', 'kinds': [],
                                                    'session_cvars': {'R_3DSKY': '1'}}, {})
        with self.assertRaisesRegex(pw.CombineError, 'different values'):
            self.combine([self.fixes, other])
        odd = write_package(self.root / 'odd', {'schema': 1, 'id': 'x', 'version': '1.0.0', 'kinds': [], 'surprise': 1}, {})
        with self.assertRaisesRegex(pw.CombineError, 'surprise'):
            self.combine([self.fixes, odd])

    @unittest.skipUnless(pw.find_nlctl(), 'nlctl.exe is not built')
    def test_nlctl_validates_a_real_combination(self):
        mods = write_package(self.root / 'mods', {'schema': 1, 'id': 'm', 'version': '1.0.0', 'kinds': ['root-files'],
                                                  'root_files': [{'path': 'rtx-remix/mods/m'}]},
                             {'native/root/rtx-remix/mods/m/mod.usda': b'#usda 1.0\n'})
        module = write_package(self.root / 'module', {'schema': 1, 'id': 'b', 'version': '1.0.0', 'kinds': ['lua-binary-module'],
                                                      'root_files': [{'path': 'garrysmod/lua/bin/gmcl_b_win64.dll'}]},
                               {'native/root/garrysmod/lua/bin/gmcl_b_win64.dll': b'MZ module'})
        code = pw.main(['--part', str(mods), '--part', str(module), '--id', 'mb', '--version', '1.0.0', '--title', 't',
                        '--out', str(self.root / 'valid'), '--force'])
        self.assertEqual(code, 0)
        code = subprocess.run([str(pw.find_nlctl()), 'manifest', str(self.root / 'valid')], capture_output=True).returncode
        self.assertEqual(code, 0)


if __name__ == '__main__':
    unittest.main()
