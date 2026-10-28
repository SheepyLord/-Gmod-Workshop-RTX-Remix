"""field_snapshot.py on a synthetic install under out/tmp: snapshot, a simulated session (the real
bootstrap installed when a build exists; files changed, created, deleted and written through a hard
link; registry values changed and added), rollback, and checks that everything is back. Uses a
throwaway registry key under HKCU\\Software, deleted afterwards."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'tools' / 'field_snapshot.py'
BUILD = next((config for config in ('Debug', 'Release')
              if (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'proxy' / 'winmm.dll').is_file()
              and (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'cli' / 'nlctl.exe').is_file()), None)


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, encoding='utf-8',
                          errors='replace', timeout=600)


def reg(*args):
    return subprocess.run(['reg', *args], capture_output=True, text=True)


def reg_value(key, name):
    done = reg('query', key, '/v', name)
    if done.returncode != 0:
        return None
    for line in done.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[0] == name:
            return parts[2].strip()
    return None


class FieldSnapshotTests(unittest.TestCase):
    def setUp(self):
        (REPO / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
        self.scratch = Path(tempfile.mkdtemp(prefix='field_snapshot_', dir=REPO / 'out' / 'tmp'))
        self.root = self.scratch / 'game'
        self.snap = self.scratch / 'snapshot'
        self.key = 'HKCU\\Software\\NativeLoaderTest_' + uuid.uuid4().hex[:12]
        self.addCleanup(self.cleanup)
        for rel, data in {
            'bin/win64/gmod.exe': b'not a real game',
            'bin/win64/d3d9.dll': b'the user DXVK',
            'bin/win64/vulkan-1.dll': b'a patch tool loader',
            'garrysmod/cfg/config.cfg': b'r_x 1\n',
            'garrysmod/console.log': b'old log\n',
            'garrysmod/cl.db': b'db',
            'garrysmod/data/existing/a.txt': b'a',
            'garrysmod/settings/users.txt': b'users',
            'garrysmod/addons/useraddon/addon.json': b'{}',
            'garrysmod/lua/bin/gmcl_user_win64.dll': b'user module',
            'crashes/old.mdmp': b'old dump',
            'gmod_d3d9.log': b'dxvk log',
        }.items():
            self.write(rel, data)
        # A file hard-linked from elsewhere, as some of the user's tools leave them.
        self.outside = self.scratch / 'elsewhere' / 'shared.dll'
        self.outside.parent.mkdir()
        self.outside.write_bytes(b'shared original')
        os.link(self.outside, self.root / 'bin' / 'win64' / 'shared.dll')
        self.assertEqual(reg('add', self.key, '/v', 'DXLevel_V1', '/t', 'REG_DWORD', '/d', '90', '/f').returncode, 0)
        self.assertEqual(reg('add', self.key + '\\Settings', '/v', 'Name', '/t', 'REG_SZ', '/d', 'keep me', '/f').returncode, 0)

    def cleanup(self):
        reg('delete', self.key, '/f')
        subprocess.run(['cmd', '/c', 'rmdir', '/s', '/q', str(self.scratch)], capture_output=True)

    def write(self, rel, data):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def snapshot(self, *extra):
        done = run('--snapshot', str(self.snap), 'snapshot', '--root', str(self.root), '--registry-key', self.key, *extra)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return json.loads(done.stdout)

    def rollback(self):
        done = run('--snapshot', str(self.snap), 'rollback', '--config', BUILD or 'Release')
        return done.returncode, json.loads(done.stdout) if done.stdout.strip().startswith('{') else done.stderr

    def test_rollback_puts_everything_back(self):
        summary = self.snapshot()
        self.assertFalse(summary['depot_check'])  # not a Steam install: every file is kept
        self.assertTrue(summary['registry_exported'])
        self.assertEqual(summary['loader_paths_present'], [])
        if BUILD:
            installed = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                        str(REPO / 'tools' / 'install-loader.ps1'), '-GameRoot', str(self.root), '-Config', BUILD],
                                       capture_output=True, text=True)
            self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
            self.assertTrue((self.root / 'bin' / 'win64' / 'winmm.dll').is_file())
        # The session.
        self.write('garrysmod/cfg/config.cfg', b'r_x 2\nrtx 1\n')
        with open(self.root / 'garrysmod' / 'console.log', 'ab') as log:
            log.write(b'session output\n')
        self.write('garrysmod/data/existing/a.txt', b'changed')
        self.write('garrysmod/data/existing/new.txt', b'new')
        self.write('garrysmod/data/existing/newdir/x.txt', b'x')
        self.write('garrysmod/data/native-loader/status.json', b'{}')
        self.write('garrysmod/data/remix_map_configs/default.txt', b'{}')
        self.write('native-loader/logs/loader.log', b'log')
        self.write('rtx-remix/mods/m/mod.usda', b'#usda')
        self.write('garrysmod/addons/pkgaddon/lua/autorun/x.lua', b'print(1)')
        self.write('garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll', b'module')
        self.write('garrysmod/cfg/nativeloader_session.cfg', b'// Generated by the GMod native loader\n')
        self.write('garrysmod/settings/presets/new.txt', b'preset')
        self.write('imgui.ini', b'[Window]')
        self.write('crashes/new.mdmp', b'new dump')
        self.write('bin/win64/d3d9.dll', b'overwritten')
        (self.root / 'bin' / 'win64' / 'vulkan-1.dll').unlink()
        with open(self.root / 'bin' / 'win64' / 'shared.dll', 'r+b') as shared:
            shared.write(b'SHARED')  # in place: the linked copy elsewhere changes too
        self.assertEqual(self.outside.read_bytes(), b'SHARED original')
        reg('add', self.key, '/v', 'DXLevel_V1', '/t', 'REG_DWORD', '/d', '95', '/f')
        reg('add', self.key, '/v', 'NewValue', '/t', 'REG_SZ', '/d', 'x', '/f')
        reg('add', self.key + '\\Sub\\Deep', '/v', 'V', '/t', 'REG_SZ', '/d', 'y', '/f')

        code, report = self.rollback()
        self.assertEqual(code, 0, report)
        self.assertTrue(report['clean'])
        self.assertEqual(report['uninstall'], 0 if BUILD else None)
        files = {'garrysmod/cfg/config.cfg': b'r_x 1\n', 'garrysmod/console.log': b'old log\n', 'bin/win64/d3d9.dll': b'the user DXVK',
                 'bin/win64/vulkan-1.dll': b'a patch tool loader', 'bin/win64/shared.dll': b'shared original'}
        for rel, data in files.items():
            self.assertEqual((self.root / rel).read_bytes(), data, rel)
        self.assertTrue(set(files) <= set(report['restored']), report['restored'])
        # Written back in place: the hard link holds, and the copy elsewhere is back too.
        self.assertTrue(os.path.samefile(self.outside, self.root / 'bin' / 'win64' / 'shared.dll'))
        self.assertEqual(self.outside.read_bytes(), b'shared original')
        for rel in ('native-loader', 'rtx-remix', 'garrysmod/data/native-loader', 'garrysmod/data/remix_map_configs',
                    'garrysmod/addons/pkgaddon', 'garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll',
                    'garrysmod/cfg/nativeloader_session.cfg', 'imgui.ini', 'crashes/new.mdmp', 'garrysmod/data/existing/new.txt',
                    'garrysmod/data/existing/newdir', 'garrysmod/settings/presets', 'bin/win64/winmm.dll'):
            self.assertFalse((self.root / rel).exists(), rel)
        for rel in ('crashes/old.mdmp', 'garrysmod/addons/useraddon/addon.json', 'garrysmod/lua/bin/gmcl_user_win64.dll',
                    'gmod_d3d9.log', 'garrysmod/settings/users.txt'):
            self.assertTrue((self.root / rel).is_file(), rel)
        # Moved, not deleted: the debris folder holds what the session left.
        debris = next((self.snap / 'debris').iterdir())
        self.assertEqual((debris / 'crashes' / 'new.mdmp').read_bytes(), b'new dump')
        self.assertTrue((debris / 'garrysmod' / 'data' / 'existing' / 'newdir' / 'x.txt').is_file())
        self.assertIn('garrysmod/data/existing/newdir', report['moved'])
        self.assertEqual(report['deleted'], [])
        # A changed file below a watched folder cannot be put back; it is reported.
        self.assertEqual(report['watched']['garrysmod/data']['changed_files'], ['existing/a.txt'])
        self.assertEqual(report['watched']['garrysmod/settings']['changed'], 0)
        # The registry key as it was: the changed value back, the added value and keys gone.
        self.assertEqual(reg_value(self.key, 'DXLevel_V1'), '0x5a')
        self.assertIsNone(reg_value(self.key, 'NewValue'))
        self.assertNotEqual(reg('query', self.key + '\\Sub').returncode, 0)
        self.assertEqual(reg_value(self.key + '\\Settings', 'Name'), 'keep me')
        self.assertEqual(report['registry']['differences'], [])
        self.assertIn(self.key.replace('HKCU', 'HKEY_CURRENT_USER', 1) + '\\Sub', report['registry']['pruned'])
        # A second rollback finds nothing left to do.
        code, again = self.rollback()
        self.assertEqual(code, 0, again)
        self.assertEqual((again['moved'], again['restored'], again['registry']['pruned']), ([], [], []))

    def test_a_key_that_was_absent_is_deleted_again(self):
        reg('delete', self.key, '/f')
        summary = self.snapshot()
        self.assertFalse(summary['registry_exported'])
        reg('add', self.key, '/v', 'DXLevel_V1', '/t', 'REG_DWORD', '/d', '90', '/f')
        code, report = self.rollback()
        self.assertEqual(code, 0, report)
        self.assertTrue(report['registry']['deleted_key'])
        self.assertNotEqual(reg('query', self.key).returncode, 0)

    def test_refusals(self):
        self.snapshot()
        again = run('--snapshot', str(self.snap), 'snapshot', '--root', str(self.root), '--registry-key', self.key)
        self.assertEqual(again.returncode, 1)
        self.assertIn('already holds a snapshot', again.stderr)
        inside = run('--snapshot', str(self.root / 'snap'), 'snapshot', '--root', str(self.root), '--registry-key', self.key)
        self.assertEqual(inside.returncode, 1)
        self.assertIn('outside the install', inside.stderr)
        self.assertFalse((self.root / 'snap').exists())
        old = self.scratch / 'old'
        old.mkdir()
        (old / 'snapshot.json').write_text(json.dumps({'root': str(self.root)}), encoding='utf-8')
        older = run('--snapshot', str(old), 'rollback')
        self.assertEqual(older.returncode, 1)
        self.assertIn('older field_snapshot.py', older.stderr)

    def test_listing_differences_fail_the_rollback(self):
        self.snapshot()
        (self.root / 'garrysmod' / 'addons' / 'useraddon' / 'addon.json').unlink()
        (self.root / 'garrysmod' / 'addons' / 'useraddon').rmdir()  # something the snapshot did not keep
        code, report = self.rollback()
        self.assertEqual(code, 1)
        self.assertFalse(report['clean'])
        self.assertEqual(report['listing_differences']['garrysmod/addons'], {'added': [], 'missing': ['useraddon']})


if __name__ == '__main__':
    unittest.main()
