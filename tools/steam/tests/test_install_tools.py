import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path

import make_vanilla_copy
import verify_install
from _fixtures import build_manifest, entry, write_tree
from steam_manifest import FLAG_USERCONFIG

VANILLA = {
    'bin/win64/engine.dll': b'engine-vanilla',
    'bin/win64/client.dll': b'client-vanilla',
    'bin/win64/server.dll': b'server-vanilla',
    'gmod.exe': b'launcher',
    'garrysmod/cfg/autoexec.cfg': b'',
}


class InstallToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
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
