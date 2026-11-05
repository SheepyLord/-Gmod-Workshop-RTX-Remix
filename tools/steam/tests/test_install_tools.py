import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import make_vanilla_copy
import verify_install
from _fixtures import REPO, SCRATCH, build_manifest, entry, scratch_folder, write_tree
from steam_manifest import FLAG_USERCONFIG

try:
    from _winapi import CreateJunction  # CPython on Windows; a junction needs no privilege
except ImportError:
    CreateJunction = None

VANILLA = {
    'bin/win64/engine.dll': b'engine-vanilla',
    'bin/win64/client.dll': b'client-vanilla',
    'bin/win64/server.dll': b'server-vanilla',
    'gmod.exe': b'launcher',
    'garrysmod/cfg/autoexec.cfg': b'',
}


class InstallToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = scratch_folder('install-tools-')
        self.root = Path(self.tmp.name)
        self.manifest = self.root / 'depot.manifest'
        self.manifest.write_bytes(build_manifest([
            entry('bin'), entry('bin\\win64'), entry('garrysmod\\empty_dir'),
            *(entry(p.replace('/', '\\'), d, FLAG_USERCONFIG if p.endswith('.cfg') else 0) for p, d in VANILLA.items()),
        ]))
        # The "field install": client.dll edited in place (same size), server.dll resized,
        # gmod.exe missing, autoexec.cfg customised, plus a non-depot DLL.
        self.src = self.root / 'src'
        write_tree(self.src, {
            'bin/win64/engine.dll': VANILLA['bin/win64/engine.dll'],
            'bin/win64/client.dll': b'client-PATCHED',
            'bin/win64/server.dll': b'server-vanilla-but-longer',
            'garrysmod/cfg/autoexec.cfg': b'bind f5 jpeg',
            'bin/win64/d3d9.dll': b'dxvk',
        })
        os.utime(self.src / 'bin/win64/engine.dll', (1_700_000_000, 1_700_000_000))

    def tearDown(self):
        self.tmp.cleanup()

    def test_scratch_is_in_the_repo_whatever_the_temp_folder(self):
        # A temp folder that does not exist: a fixture that used it would fail to start.
        with mock.patch.object(tempfile, 'tempdir', str(REPO / 'out' / 'no-such-temp-folder')):
            self.tearDown()
            self.setUp()
        self.assertEqual(self.root.resolve().parent, SCRATCH.resolve())

    def verify_quietly(self, install, manifest):
        with contextlib.redirect_stdout(io.StringIO()):
            return verify_install.main([str(install), '--manifest', str(manifest), '--quiet'])

    @unittest.skipUnless(CreateJunction, 'directory junctions need Windows')
    def test_a_depot_path_through_a_junction_is_not_vanilla(self):
        # garrysmod/cfg is a junction to a folder elsewhere that holds byte-identical depot files.
        files = {'garrysmod/cfg/config_default.cfg': b'DEPOT BYTES', 'bin/win64/engine.dll': b'engine'}
        manifest = self.root / 'linked.manifest'
        manifest.write_bytes(build_manifest([entry(p.replace('/', '\\'), d) for p, d in files.items()]))
        install, victim = self.root / 'linked', self.root / 'victim'
        write_tree(install, {'bin/win64/engine.dll': b'engine'})
        write_tree(victim, {'config_default.cfg': b'DEPOT BYTES'})
        (install / 'garrysmod').mkdir()
        junction = install / 'garrysmod' / 'cfg'
        CreateJunction(str(victim), str(junction))
        try:
            report = verify_install.verify(install, [manifest])
            self.assertEqual(report['reparse_point'], ['garrysmod/cfg/config_default.cfg'])
            self.assertEqual((report['ok'], report['missing'], report['hash_mismatch']), (1, [], []))
            self.assertEqual(self.verify_quietly(install, manifest), 1)
        finally:
            os.rmdir(junction)  # the junction only, never what it points to

    def test_a_depot_file_that_is_a_symbolic_link_is_not_vanilla(self):
        manifest = self.root / 'symlink.manifest'
        manifest.write_bytes(build_manifest([entry('gmod.exe', b'launcher')]))
        install = self.root / 'symlinked'
        write_tree(self.root / 'elsewhere', {'gmod.exe': b'launcher'})
        install.mkdir()
        try:
            os.symlink(self.root / 'elsewhere' / 'gmod.exe', install / 'gmod.exe')
        except OSError:
            self.skipTest('creating a symbolic link needs Developer Mode or the symlink privilege')
        report = verify_install.verify(install, [manifest])
        self.assertEqual((report['reparse_point'], report['ok']), (['gmod.exe'], 0))
        self.assertEqual(self.verify_quietly(install, manifest), 1)

    def test_a_depot_file_without_a_hash_is_unverified_unless_empty(self):
        zero = bytes(20)  # Steam's "no hash"
        manifest = self.root / 'nohash.manifest'
        manifest.write_bytes(build_manifest([
            entry('bin\\win64\\nohash.dll', b'0123456789', sha=zero),
            entry('garrysmod\\empty.txt', b'', sha=zero),
            entry('garrysmod\\cfg\\autoexec.cfg', b'bind x', FLAG_USERCONFIG, sha=zero),
        ]))
        install = self.root / 'nohash'
        write_tree(install, {'bin/win64/nohash.dll': b'abcdefghij', 'garrysmod/empty.txt': b'',
                             'garrysmod/cfg/autoexec.cfg': b'bind y'})
        report = verify_install.verify(install, [manifest])
        self.assertEqual(report['unverified'], ['bin/win64/nohash.dll'])  # same size, content unknown
        self.assertEqual(report['ok'], 2)  # the empty file, and the user's config (it may differ anyway)
        self.assertEqual(self.verify_quietly(install, manifest), 1)
        (install / 'bin/win64/nohash.dll').unlink()
        manifest.write_bytes(build_manifest([entry('garrysmod\\empty.txt', b'', sha=zero)]))
        self.assertEqual(self.verify_quietly(install, manifest), 0)

    def test_verify_classifies_every_difference(self):
        report = verify_install.verify(self.src, [self.manifest])
        self.assertEqual(report['ok'], 1)
        self.assertEqual(report['hash_mismatch'], ['bin/win64/client.dll'])
        self.assertEqual(report['size_mismatch'], ['bin/win64/server.dll'])
        self.assertEqual(report['missing'], ['gmod.exe'])
        self.assertEqual(report['userconfig_differs'], ['garrysmod/cfg/autoexec.cfg'])

    def test_extras_lists_non_depot_files(self):
        self.assertEqual(verify_install.extras(self.src, [self.manifest], ['bin/win64']), ['bin/win64/d3d9.dll'])

    def test_verify_cli_exit_codes(self):
        clean = self.root / 'clean'
        write_tree(clean, VANILLA)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(verify_install.main([str(self.src), '--manifest', str(self.manifest), '--quiet']), 1)
            self.assertEqual(verify_install.main([str(clean), '--manifest', str(self.manifest), '--quiet']), 0)

    def test_clone_copies_only_verified_files(self):
        dst = self.root / 'dst'
        report = make_vanilla_copy.clone(self.src, dst, [self.manifest])
        self.assertEqual(report['copied'], 1)
        self.assertEqual(sorted(report['unverified']), ['bin/win64/client.dll', 'bin/win64/server.dll', 'gmod.exe'])
        self.assertEqual(report['skipped_userconfig'], ['garrysmod/cfg/autoexec.cfg'])
        self.assertEqual((dst / 'bin/win64/engine.dll').read_bytes(), VANILLA['bin/win64/engine.dll'])
        self.assertEqual(int((dst / 'bin/win64/engine.dll').stat().st_mtime), 1_700_000_000)
        self.assertTrue((dst / 'garrysmod/empty_dir').is_dir())
        self.assertFalse((dst / 'bin/win64/d3d9.dll').exists())
        self.assertFalse(list(dst.rglob('*.partial')))

    def test_clone_leaves_out_a_depot_file_without_a_hash(self):
        # Review R19, F-05: a non-empty depot file without a SHA-1 was copied whenever its size matched,
        # so the copy could hold changed bytes while the run reported success.
        zero = bytes(20)  # Steam's "no hash"
        manifest = self.root / 'nohash.manifest'
        manifest.write_bytes(build_manifest([
            entry('bin\\win64\\nohash.dll', b'0123456789', sha=zero),
            entry('garrysmod\\empty.txt', b'', sha=zero),
            entry('garrysmod\\cfg\\autoexec.cfg', b'bind x', FLAG_USERCONFIG, sha=zero),
            entry('bin\\win64\\engine.dll', b'engine'),
        ]))
        src, fallback = self.root / 'nohash-src', self.root / 'nohash-fallback'
        write_tree(src, {'bin/win64/nohash.dll': b'abcdefghij', 'garrysmod/empty.txt': b'',
                         'garrysmod/cfg/autoexec.cfg': b'bind y', 'bin/win64/engine.dll': b'engine'})
        write_tree(fallback, {'bin/win64/nohash.dll': b'0123456789'})  # no fallback can prove it either
        dst = self.root / 'nohash-dst'
        report = make_vanilla_copy.clone(src, dst, [manifest], [fallback])
        self.assertEqual(report['unverified'], ['bin/win64/nohash.dll'])
        self.assertFalse((dst / 'bin/win64/nohash.dll').exists())
        self.assertEqual(report['copied'], 3)  # the verified file, the empty file and the user's config
        self.assertEqual((dst / 'garrysmod/empty.txt').read_bytes(), b'')
        self.assertEqual(report['from_fallback'], [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(make_vanilla_copy.main([str(src), str(self.root / 'nohash-cli'), '--manifest', str(manifest),
                                                     '--quiet']), 1)

    def test_clone_uses_fallback_for_unverified_files(self):
        fallback = self.root / 'fallback'
        write_tree(fallback, {k: v for k, v in VANILLA.items() if k != 'bin/win64/engine.dll'})
        report = make_vanilla_copy.clone(self.src, self.root / 'dst', [self.manifest], [fallback])
        self.assertEqual(report['unverified'], [])
        self.assertEqual(len(report['from_fallback']), 4)  # client, server, gmod.exe, autoexec.cfg

    def test_clone_refuses_unsafe_destinations(self):
        busy = self.root / 'busy'
        write_tree(busy, {'x.txt': b'x'})
        with self.assertRaises(FileExistsError):
            make_vanilla_copy.clone(self.src, busy, [self.manifest])
        with self.assertRaises(ValueError):
            make_vanilla_copy.clone(self.src, self.src / 'nested', [self.manifest])
        self.assertFalse((self.src / 'nested').exists())


if __name__ == '__main__':
    unittest.main()
