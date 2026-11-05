"""Tests for the RTX package workflow's helpers in tools/ci (R16, ADR 0106): fetched files checked against
their pins (also out of an archive, and the files a packager takes out of them), the runtime's install
folder laid out as the runtime part, this repository's modules collected with their source, and the cache
keys. No network: fetch_prebuilt reads a local folder, as its --from option does."""
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
sys.path.insert(0, str(TOOLS / 'ci'))
import cache_key  # noqa: E402
import collect_repo_build  # noqa: E402
import collect_runtime  # noqa: E402
import fetch_prebuilt  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'


class CiToolTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-ci-tools-', dir=SCRATCH))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_fetched_files_are_checked_against_their_pins(self):
        local = self.root / 'local'
        (local / 'reshade').mkdir(parents=True)
        setup = b'MZ setup with a zip inside'
        (local / 'reshade' / 'Setup.exe').write_bytes(setup)
        inner = 'b' * 64
        entry = {'name': 'setup', 'part': 'reshade', 'path': 'Setup.exe', 'url': 'https://example.invalid/s.exe',
                 'size': len(setup), 'sha256': hashlib.sha256(setup).hexdigest(), 'contains': {'R.dll': inner},
                 'repository': 'https://github.com/x/y', 'commit': 'v1', 'why': 'the signed setup'}
        out = self.root / 'out'
        record = fetch_prebuilt.fetch([entry], out, 'run-url', local)
        self.assertEqual(record['problems'], [])
        self.assertEqual((out / 'reshade' / 'Setup.exe').read_bytes(), setup)
        source = record['binaries'][entry['sha256']]
        self.assertEqual((source['part'], source['path'], source['run']), ('reshade', 'Setup.exe', 'run-url'))
        self.assertTrue(source['how'].startswith('fetched'))
        self.assertEqual(record['binaries'][inner]['path'], 'Setup.exe!R.dll')
        self.assertEqual(json.loads((out / 'provenance-fetched.json').read_text(encoding='utf-8'))['problems'], [])
        # Other bytes are refused, and nothing is written for them.
        bad = dict(entry, sha256='0' * 64, path='Setup.exe')
        shutil.rmtree(out)
        record = fetch_prebuilt.fetch([bad], out, None, local)
        self.assertEqual(len(record['problems']), 1)
        self.assertFalse((out / 'reshade' / 'Setup.exe').exists())

    def test_a_file_out_of_a_pinned_archive(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as z:
            z.writestr('coacd/lib_coacd.dll', b'MZ coacd')
            z.writestr('coacd/__init__.py', b'')
        self.assertEqual(fetch_prebuilt.member(buffer.getvalue(), 'lib_coacd.dll'), b'MZ coacd')
        with self.assertRaisesRegex(ValueError, '0 files called x.dll'):
            fetch_prebuilt.member(buffer.getvalue(), 'x.dll')
        archive = buffer.getvalue()
        entry = {'name': 'coacd', 'part': 'model-hotloader', 'path': 'bin/lib_coacd.dll', 'url': 'u',
                 'archive_sha256': hashlib.sha256(archive).hexdigest(), 'member': 'lib_coacd.dll',
                 'sha256': hashlib.sha256(b'MZ coacd').hexdigest(), 'why': 'its wheel'}
        with mock.patch.object(fetch_prebuilt, 'download', return_value=archive):
            record = fetch_prebuilt.fetch([entry], self.root / 'out', None)
        self.assertEqual(record['problems'], [])
        self.assertEqual((self.root / 'out' / 'model-hotloader' / 'bin' / 'lib_coacd.dll').read_bytes(), b'MZ coacd')
        with mock.patch.object(fetch_prebuilt, 'download', return_value=archive + b'x'):
            record = fetch_prebuilt.fetch([entry], self.root / 'out2', None)
        self.assertIn("the archive's SHA-256", record['problems'][0])

    def test_the_runtime_build_is_laid_out_as_the_runtime_part(self):
        index = json.loads((REPO / 'packages' / 'runtime' / 'files.json').read_text(encoding='utf-8'))['files']
        shipped = [rel for rel in index if rel.startswith('files/') and not rel.startswith('files/atmosphere/')]
        output = self.root / '_output'
        for rel in shipped:
            path = output / rel[len('files/'):]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(rel.encode())
        (output / 'd3d9.pdb').write_bytes(b'symbols, not shipped')
        record = collect_runtime.collect(output, self.root / 'built', 'run-url')
        self.assertEqual((record['copied'], record['missing'], record['built_not_shipped']), (len(shipped), [], []))
        binaries = [rel for rel in shipped if rel.lower().endswith(('.dll', '.exe'))]
        self.assertEqual(len(record['binaries']), len(binaries))
        d3d9 = record['binaries'][hashlib.sha256(b'files/d3d9.dll').hexdigest()]
        self.assertTrue(d3d9['how'].startswith('compiled'))
        base = json.loads((REPO / 'runtime' / 'base.json').read_text(encoding='utf-8'))
        self.assertEqual((d3d9['repository'], d3d9['commit']), (base['repository'], base['commit']))
        self.assertEqual((self.root / 'built' / 'runtime' / 'files' / 'd3d9.dll').read_bytes(), b'files/d3d9.dll')
        # A binary the part ships that the build lacks stops it; a folder without d3d9.dll is no build.
        vendor = next(rel for rel in binaries if rel != 'files/d3d9.dll')
        (output / vendor[len('files/'):]).unlink()
        with self.assertRaisesRegex(SystemExit, f'did not produce {vendor}'):
            collect_runtime.collect(output, self.root / 'built2')
        (output / 'd3d9.dll').unlink()
        with self.assertRaisesRegex(SystemExit, 'not a runtime build output'):
            collect_runtime.collect(output, self.root / 'built3')

    def test_this_repositorys_modules_are_collected_with_their_source(self):
        build = self.root / 'build'
        build.mkdir()
        (build / 'a.dll').write_bytes(b'MZ a')
        pins = self.root / 'pins.json'
        rel = (build / 'a.dll').relative_to(REPO).as_posix()
        pins.write_text(json.dumps({'repository_builds': [
            {'part': 'glass', 'path': 'bin/a.dll', 'from': rel, 'target': 'a'},
            {'part': 'fixes', 'path': 'modules/b.dll', 'from': rel + '.missing', 'target': 'b'}]}), encoding='utf-8')
        with mock.patch.object(collect_repo_build, 'PINS', pins):
            record = collect_repo_build.collect(self.root / 'out', 'run-url')
        self.assertEqual(record['missing'], [rel + '.missing'])
        source = record['binaries'][hashlib.sha256(b'MZ a').hexdigest()]
        self.assertEqual((source['part'], source['path'], source['run']), ('glass', 'bin/a.dll', 'run-url'))
        self.assertIn('CMake target a', source['how'])
        self.assertTrue(source['commit'])
        self.assertEqual((self.root / 'out' / 'glass' / 'bin' / 'a.dll').read_bytes(), b'MZ a')

    def test_the_cache_keys(self):
        for name in ('runtime', 'modules'):
            key = getattr(cache_key, name)()
            self.assertRegex(key, '^[0-9a-f]{64}$')
            self.assertEqual(key, getattr(cache_key, name)())
        self.assertNotEqual(cache_key.runtime(), cache_key.modules())
        one, two = self.root / 'one.txt', self.root / 'two.txt'
        one.write_bytes(b'a\r\nb')
        two.write_bytes(b'a\nb')
        # A checkout's line endings do not change a key; the content does.
        self.assertEqual(cache_key.digest([one]), cache_key.digest([one]))
        self.assertNotEqual(cache_key.digest([one]), cache_key.digest([one], extra=['x']))
        self.assertEqual(cache_key.main(['nothing']), 2)


if __name__ == '__main__':
    unittest.main()
