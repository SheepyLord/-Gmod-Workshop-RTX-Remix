import hashlib
import tempfile
import unittest
from pathlib import Path

import steam_manifest as sm
from _fixtures import build_manifest, entry


class ParseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data):
        path = self.dir / name
        path.write_bytes(data)
        return path

    def test_round_trip(self):
        path = self.write('m.manifest', build_manifest([
            entry('bin'),
            entry('bin\\win64\\engine.dll', b'engine'),
            entry('garrysmod\\cfg\\autoexec.cfg', b'', flags=sm.FLAG_USERCONFIG),
        ], depot_id=4002, manifest_id=99))
        m = sm.parse_manifest(path)
        self.assertEqual((m.depot_id, m.manifest_id, m.filenames_encrypted), (4002, 99, False))
        self.assertEqual([f.path for f in m.files], ['bin', 'bin/win64/engine.dll', 'garrysmod/cfg/autoexec.cfg'])
        self.assertTrue(m.files[0].is_dir)
        self.assertIsNone(m.files[0].sha1)
        engine = m.files[1]
        self.assertEqual((engine.size, engine.sha1), (6, hashlib.sha1(b'engine').hexdigest()))
        self.assertTrue(m.files[2].is_userconfig)

    def test_zero_hash_means_no_hash(self):
        path = self.write('m.manifest', build_manifest([entry('empty.txt', b'', sha=bytes(20))]))
        self.assertIsNone(sm.parse_manifest(path).files[0].sha1)

    def test_encrypted_flag_is_reported(self):
        path = self.write('m.manifest', build_manifest([entry('x', b'1')], encrypted=True))
        self.assertTrue(sm.parse_manifest(path).filenames_encrypted)

    def test_rejects_other_files(self):
        with self.assertRaises(ValueError):
            sm.parse_manifest(self.write('bad.manifest', b'PK\x03\x04' + bytes(16)))


class SafeRelpathTests(unittest.TestCase):
    def test_accepts_relative_paths(self):
        self.assertEqual(str(sm.safe_relpath('bin\\win64\\gmod.exe')), 'bin/win64/gmod.exe')

    def test_rejects_escaping_and_absolute_paths(self):
        for bad in ('..\\evil.dll', 'bin/../../evil.dll', 'C:\\Windows\\x.dll', '/etc/passwd', ''):
            with self.subTest(path=bad), self.assertRaises(ValueError):
                sm.safe_relpath(bad)


class LocateInstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.library = root / 'lib' / 'steamapps'
        self.install = self.library / 'common' / 'GarrysMod'
        self.install.mkdir(parents=True)
        self.steam = root / 'steam'
        (self.steam / 'depotcache').mkdir(parents=True)
        (self.library / 'appmanifest_4000.acf').write_text(
            '"AppState" { "appid" "4000" "installdir" "GarrysMod" '
            '"InstalledDepots" { "4001" { "manifest" "11" } "4002" { "manifest" "22" } } }', encoding='utf-8')
        (self.library / 'appmanifest_220.acf').write_text(
            '"AppState" { "appid" "220" "installdir" "Half-Life 2" }', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_finds_cached_manifests(self):
        for name in ('4001_11.manifest', '4002_22.manifest'):
            (self.steam / 'depotcache' / name).write_bytes(b'')
        info = sm.locate_install(self.install, self.steam)
        self.assertEqual(info.appid, '4000')
        self.assertEqual(sorted(p.name for p in info.manifests), ['4001_11.manifest', '4002_22.manifest'])

    def test_reports_uncached_manifests(self):
        (self.steam / 'depotcache' / '4001_11.manifest').write_bytes(b'')
        with self.assertRaisesRegex(FileNotFoundError, '4002_22'):
            sm.locate_install(self.install, self.steam)

    def test_requires_steam_library_layout(self):
        with self.assertRaises(FileNotFoundError):
            sm.locate_install(Path(self.tmp.name), self.steam)


if __name__ == '__main__':
    unittest.main()
