"""Tests for the RTX package workflow's helpers in tools/ci (R16, ADR 0106): fetched files checked against
their pins (also out of an archive, and the files a packager takes out of them), the runtime's install
folder laid out as the runtime part, this repository's modules collected with their source, the cache
keys, and the RTX fixes' recorded native trees (R19). No network: fetch_prebuilt reads a local folder, as
its --from option does; the trees are replayed from a local fixes clone when this machine has one."""
import hashlib
import io
import json
import os
import shutil
import subprocess
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
PINS = json.loads((REPO / 'tools' / 'ci' / 'pins.json').read_text(encoding='utf-8'))


def fixes_clone() -> Path | None:
    """A local clone of the RTX fixes holding the pinned commits: NL_FIXES_CLONE, or
    garrys-mod-rtx-remixed beside this checkout or beside the main checkout of a worktree."""
    candidates = [os.environ.get('NL_FIXES_CLONE', '')]
    candidates.append(str(REPO.parent / 'garrys-mod-rtx-remixed'))
    common = subprocess.run(['git', '-C', str(REPO), 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                            capture_output=True, text=True)
    if common.returncode == 0 and common.stdout.strip():
        candidates.append(str(Path(common.stdout.strip()).parent.parent / 'garrys-mod-rtx-remixed'))
    for candidate in filter(None, candidates):
        path = Path(candidate)
        if (path / '.git').exists() and all(
                subprocess.run(['git', '-C', str(path), 'cat-file', '-e', f'{commit}^{{commit}}'],
                               capture_output=True).returncode == 0
                for commit in (PINS['fixes']['base'], PINS['fixes']['rtxwater_commit'])):
            return path
    return None


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
        for name in ('runtime', 'modules', 'hotloader'):
            key = getattr(cache_key, name)()
            self.assertRegex(key, '^[0-9a-f]{64}$')
            self.assertEqual(key, getattr(cache_key, name)())
        self.assertEqual(len({cache_key.runtime(), cache_key.modules(), cache_key.hotloader()}), 3)
        one, two = self.root / 'one.txt', self.root / 'two.txt'
        one.write_bytes(b'a\r\nb')
        two.write_bytes(b'a\nb')
        # A checkout's line endings do not change a key; the content does.
        self.assertEqual(cache_key.digest([one]), cache_key.digest([one]))
        self.assertNotEqual(cache_key.digest([one]), cache_key.digest([one], extra=['x']))
        self.assertEqual(cache_key.main(['nothing']), 2)

    def test_the_fixes_pins_record_their_native_trees(self):
        """R19: build_modules.ps1 checks the patched fixes, and RTX Water after its own patches, against
        object ids pins.json records, so the check holds with no pushed commit."""
        fixes = PINS['fixes']
        self.assertNotIn('patched_commit', fixes)
        self.assertEqual(sorted(fixes['patched_tree']), ['premake5.lua', 'public', 'source'])
        self.assertEqual(list(fixes['rtxwater_tree']), ['source/rtx_water'])
        for oid in list(fixes['patched_tree'].values()) + list(fixes['rtxwater_tree'].values()):
            self.assertRegex(oid, '^[0-9a-f]{40}$')
        for patch in fixes['patches'] + fixes['rtxwater_patches']:
            self.assertTrue(patch.startswith('packages/fixes/licenses/') and (REPO / patch).is_file(), patch)
        # The water patches touch only source/rtx_water, the one folder the script applies them to.
        for patch in fixes['rtxwater_patches']:
            for line in (REPO / patch).read_text(encoding='utf-8').splitlines():
                if line.startswith('diff --git '):
                    self.assertTrue(line.startswith('diff --git a/source/rtx_water/'), line)
        script = (REPO / 'tools' / 'ci' / 'build_modules.ps1').read_text(encoding='utf-8')
        for word in ('write-tree', 'patched_tree', 'rtxwater_patches', 'rtxwater_tree'):
            self.assertIn(word, script)
        self.assertNotIn('patched_commit', script)

    @unittest.skipUnless(shutil.which('git') and fixes_clone(), 'no local clone of the RTX fixes with the pinned commits')
    def test_the_patches_give_the_recorded_trees(self):
        """Replays build_modules.ps1's index steps in a shared scratch clone (the fixes clone is only
        read): the base and the patches give patched_tree; RTX Water's commit and its patches give
        rtxwater_tree."""
        fixes = PINS['fixes']
        clone = self.root / 'fixes'

        def git(*args: str) -> str:
            done = subprocess.run(['git', '-C', str(clone), *args], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, ' '.join(args) + '\n' + done.stderr)
            return done.stdout.strip()

        done = subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout', str(fixes_clone()), str(clone)],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        git('read-tree', fixes['base'])
        include = [f'--include={path}' for path in fixes['patch_paths']]
        for patch in fixes['patches']:
            git('apply', '--cached', *include, str(REPO / patch))
        tree = git('write-tree')
        self.assertEqual({path: git('rev-parse', f'{tree}:{path}') for path in fixes['patched_tree']}, fixes['patched_tree'])
        git('restore', f'--source={fixes["rtxwater_commit"]}', '--staged', '--', 'source/rtx_water')
        for patch in fixes['rtxwater_patches']:
            git('apply', '--cached', '--include=source/rtx_water/*', str(REPO / patch))
        tree = git('write-tree')
        self.assertEqual({path: git('rev-parse', f'{tree}:{path}') for path in fixes['rtxwater_tree']}, fixes['rtxwater_tree'])


if __name__ == '__main__':
    unittest.main()
