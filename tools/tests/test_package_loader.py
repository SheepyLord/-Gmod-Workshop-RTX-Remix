"""Tests for package_loader.py: the end-user bundle, and the shipped default config.json."""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import package_loader as pl  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'
NLCTL = next((p for p in (REPO / 'out/build/win64-release/loader/cli/nlctl.exe', REPO / 'out/build/win64-debug/loader/cli/nlctl.exe')
              if p.is_file()), None)


class BundleTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-package-loader-', dir=SCRATCH))
        self.build = self.root / 'build'
        self.build.mkdir()
        (self.build / 'winmm.dll').write_bytes(b'MZ' + b'\0' * 62 + b'fake loader')
        (self.build / 'winmm.pdb').write_bytes(b'Microsoft C/C++ MSF 7.00 fake')

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_the_bundle_holds_the_loader_the_default_config_and_the_readme(self):
        summary = pl.bundle(self.build, self.root / 'out', '1.2.3', 'abcdef12')
        self.assertTrue(summary['bundle'].endswith('gmod-native-loader-1.2.3+abcdef12.zip'))
        with zipfile.ZipFile(summary['bundle']) as archive:
            self.assertEqual(sorted(archive.namelist()),
                             ['README-native-loader.txt', 'bin/win64/winmm.dll', 'native-loader/config.json'])
            self.assertEqual(archive.read('bin/win64/winmm.dll'), (self.build / 'winmm.dll').read_bytes())
            config = json.loads(archive.read('native-loader/config.json'))
        self.assertEqual(config, json.loads((REPO / 'dist/native-loader/config.json').read_text(encoding='utf-8')))
        self.assertEqual(config['allow']['workshop'], ['3829070317'])
        with zipfile.ZipFile(summary['symbols']) as archive:
            self.assertEqual(archive.namelist(), ['winmm.pdb'])

    def test_two_bundles_of_the_same_files_are_the_same_bytes(self):
        first = pl.bundle(self.build, self.root / 'a', '1.2.3', 'abcdef12')
        second = pl.bundle(self.build, self.root / 'b', '1.2.3', 'abcdef12')
        self.assertEqual(first['bundle_sha256'], second['bundle_sha256'])

    def test_no_loader_or_no_image_is_refused(self):
        (self.build / 'winmm.dll').write_bytes(b'not a dll')
        with self.assertRaisesRegex(pl.BundleError, 'not a Windows image'):
            pl.bundle(self.build, self.root / 'out', '1.2.3', 'abcdef12')
        (self.build / 'winmm.dll').unlink()
        with self.assertRaisesRegex(pl.BundleError, 'build first'):
            pl.bundle(self.build, self.root / 'out', '1.2.3', 'abcdef12')

    def test_a_config_the_loader_would_refuse_is_refused(self):
        for text, message in (('{"schema": 2, "allow": {}}', 'schema 1'), ('{"schema": 1, "allow": {}, "extra": 1}', 'extra'),
                              ('{oops', 'not JSON')):
            with self.assertRaisesRegex(pl.BundleError, message):
                pl.check_config(text)

    def test_the_version_comes_from_cmake(self):
        self.assertRegex(pl.project_version(), r'^\d+\.\d+\.\d+$')

    @unittest.skipUnless(NLCTL, 'nlctl.exe is not built')
    def test_the_shipped_config_is_accepted_by_the_loader(self):
        game = self.root / 'game'
        (game / 'bin/win64').mkdir(parents=True)
        (game / 'native-loader').mkdir()
        shutil.copy2(REPO / 'dist/native-loader/config.json', game / 'native-loader/config.json')
        (self.root / 'no-steam').mkdir()
        done = subprocess.run([str(NLCTL), 'plan', str(game), '--steam-dir', str(self.root / 'no-steam'), '--json'],
                              capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('3829070317', done.stdout)


if __name__ == '__main__':
    unittest.main()
