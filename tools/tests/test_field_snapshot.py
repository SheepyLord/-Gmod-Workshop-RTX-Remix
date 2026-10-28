"""field_snapshot.py on a synthetic install under out/tmp: snapshot, a simulated session (the real
bootstrap installed when a build exists; files changed, created, deleted and written through a hard
link; registry values changed and added), rollback, and checks that everything is back. Plus one
regression test or more for each R1 finding the tool had (R1-009 to R1-013, R1-026, R1-029). Uses a
throwaway registry key under HKCU\\Software, deleted afterwards."""
import _winapi
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
import winreg
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'tools' / 'field_snapshot.py'
sys.path.insert(0, str(REPO / 'tools'))
sys.path.insert(0, str(REPO / 'tools' / 'steam' / 'tests'))
import field_snapshot as fs  # noqa: E402  (puts tools/steam on the path too)
import steam_manifest  # noqa: E402
from _fixtures import build_manifest, entry  # noqa: E402
from steam_manifest import FLAG_USERCONFIG  # noqa: E402

BUILD = next((config for config in ('Debug', 'Release')
              if (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'proxy' / 'winmm.dll').is_file()
              and (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'cli' / 'nlctl.exe').is_file()), None)
MANIFEST_ID = 1234567890
APP_MANIFEST = ('"AppState"\n{\n\t"appid"\t\t"4000"\n\t"installdir"\t\t"GarrysMod"\n\t"InstalledDepots"\n\t{\n'
                f'\t\t"4002"\n\t\t{{\n\t\t\t"manifest"\t\t"{MANIFEST_ID}"\n\t\t}}\n\t}}\n}}\n')
# What PowerShell 7's Microsoft.PowerShell.Utility manifest declares, which Windows PowerShell 5.1 finds
# first on an inherited module path and cannot load: a Core-only module exporting the Utility cmdlets.
UTILITY_CMDLETS = (
    'Export-Alias Get-Alias Import-Alias New-Alias Set-Alias Export-Clixml Import-Clixml Measure-Command Trace-Command '
    'ConvertFrom-Csv ConvertTo-Csv Export-Csv Import-Csv Get-Culture Format-Custom Get-Date Set-Date Write-Debug '
    'Wait-Debugger Register-EngineEvent Write-Error Get-Event New-Event Remove-Event Unregister-Event Wait-Event '
    'Get-EventSubscriber Invoke-Expression Out-File Unblock-File Get-FileHash Export-FormatData Get-FormatData '
    'Update-FormatData New-Guid Format-Hex Get-Host Read-Host Write-Host ConvertTo-Html Write-Information '
    'ConvertFrom-Json ConvertTo-Json Format-List Import-LocalizedData Send-MailMessage Add-Member Get-Member '
    'Compare-Object Group-Object Measure-Object New-Object Select-Object Sort-Object Tee-Object Register-ObjectEvent '
    'Write-Output Import-PowerShellDataFile Write-Progress Get-Random Invoke-RestMethod Get-Runspace Start-Sleep '
    'Out-String Select-String ConvertFrom-StringData Format-Table New-TemporaryFile New-TimeSpan Add-Type Get-TypeData '
    'Get-UICulture Get-Unique Clear-Variable Get-Variable New-Variable Remove-Variable Set-Variable Get-Verb '
    'Write-Verbose Write-Warning Invoke-WebRequest Format-Wide ConvertTo-Xml Select-Xml Out-GridView Show-Command').split()
CORE_ONLY_UTILITY = ('@{\nGUID = "1DA87E53-152B-403E-98DC-74D7B4D63D59"\nModuleVersion = "7.0.0.0"\n'
                     'CompatiblePSEditions = @("Core")\nPowerShellVersion = "3.0"\n'
                     f'CmdletsToExport = @({", ".join(repr(name) for name in UTILITY_CMDLETS)})\n'
                     'FunctionsToExport = @()\n}\n')


def powershell_env():
    """This environment without PSModulePath, for a Windows PowerShell child (R1-029)."""
    return {name: value for name, value in os.environ.items() if name.upper() != 'PSMODULEPATH'}


def run(*args, env=None):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, encoding='utf-8',
                          errors='replace', timeout=600, env=env)


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


def junction(link, target):
    _winapi.CreateJunction(str(target), str(link))


class OtherVolume:
    """Stands in for the os module inside field_snapshot: os.stat of anything at or below `far`
    reports another volume."""

    def __init__(self, far):
        self.far = os.path.normcase(str(far))

    def __getattr__(self, name):
        return getattr(os, name)

    def stat(self, path, *args, **kwargs):
        info = os.stat(path, *args, **kwargs)
        if not os.path.normcase(os.path.abspath(path)).startswith(self.far):
            return info
        fields = {name: getattr(info, name) for name in dir(info) if name.startswith('st_')}
        fields['st_dev'] = info.st_dev + 1
        return SimpleNamespace(**fields)


class FieldSnapshotTests(unittest.TestCase):
    def setUp(self):
        (REPO / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
        self.scratch = Path(tempfile.mkdtemp(prefix='field_snapshot_', dir=REPO / 'out' / 'tmp'))
        # A Steam library's layout; Steam manages the install only once a test adds its app manifest.
        self.root = self.scratch / 'library' / 'steamapps' / 'common' / 'GarrysMod'
        self.snap = self.scratch / 'snapshot'
        self.steam = self.scratch / 'steam'
        self.key = 'HKCU\\Software\\NativeLoaderTest_' + uuid.uuid4().hex[:12]
        self.full_key = self.key.replace('HKCU', 'HKEY_CURRENT_USER', 1)
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
        # Every other form `reg export` writes: hex over several lines, escaped quotes, the default value.
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, self.key[5:], 0, winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, '', 0, winreg.REG_SZ, 'default')
            winreg.SetValueEx(key, 'Quote"And\\Slash', 0, winreg.REG_SZ, 'say "hi" \\ there')
            winreg.SetValueEx(key, 'Binary', 0, winreg.REG_BINARY, bytes(range(60)))
            winreg.SetValueEx(key, 'Multi', 0, winreg.REG_MULTI_SZ, ['a', 'b c'])
            winreg.SetValueEx(key, 'Expand', 0, winreg.REG_EXPAND_SZ, '%TEMP%\\x')
            winreg.SetValueEx(key, 'Empty', 0, winreg.REG_SZ, '')

    def cleanup(self):
        reg('delete', self.key, '/f')
        subprocess.run(['cmd', '/c', 'rmdir', '/s', '/q', str(self.scratch)], capture_output=True)

    def write(self, rel, data):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    # The command line.
    def snapshot(self, *extra):
        done = run('--snapshot', str(self.snap), 'snapshot', '--root', str(self.root), '--registry-key', self.key, *extra)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return json.loads(done.stdout)

    def rollback(self, env=None):
        done = run('--snapshot', str(self.snap), 'rollback', '--config', BUILD or 'Release', env=env)
        return done.returncode, json.loads(done.stdout) if done.stdout.strip().startswith('{') else done.stderr

    # In this process, where a test can stand in for parts of the system; the game check is skipped.
    def snapshot_args(self, **options):
        values = dict(root=str(self.root), snapshot=str(self.snap), registry_key=self.key, manifests_from=None,
                      no_depot_check=False)
        values.update(options)
        return argparse.Namespace(**values)

    def rollback_args(self):
        return argparse.Namespace(snapshot=str(self.snap), config=BUILD or 'Release')

    def snapshot_here(self, **options):
        with patch.object(fs, 'game_running', return_value=False):
            return fs.snapshot(self.snapshot_args(**options))

    def rollback_here(self):
        with patch.object(fs, 'game_running', return_value=False):
            return fs.rollback(self.rollback_args())

    def install_bootstrap(self):
        installed = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                    str(REPO / 'tools' / 'install-loader.ps1'), '-GameRoot', str(self.root), '-Config', BUILD],
                                   capture_output=True, text=True, env=powershell_env())
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
        self.assertTrue((self.root / 'bin' / 'win64' / 'winmm.dll').is_file())

    def make_steam_managed(self, depot):
        """Adds the app manifest that makes Steam manage the install. depot, {path: (bytes, flags)},
        becomes its depot manifest cached in a synthetic Steam folder; None leaves it uncached."""
        (self.root.parent.parent / 'appmanifest_4000.acf').write_text(APP_MANIFEST, encoding='utf-8')
        (self.steam / 'depotcache').mkdir(parents=True, exist_ok=True)
        if depot is not None:
            (self.steam / 'depotcache' / f'4002_{MANIFEST_ID}.manifest').write_bytes(
                build_manifest([entry(path, data, flags) for path, (data, flags) in depot.items()], manifest_id=MANIFEST_ID))

    def steam_folder(self):
        return patch.object(steam_manifest, 'steam_root', return_value=self.steam)

    # ------------------------------------------------------------ the whole round

    def test_rollback_puts_everything_back(self):
        summary = self.snapshot()
        self.assertFalse(summary['depot_check'])  # not a Steam install: every file is kept
        self.assertIsNone(summary['steam_managed'])
        self.assertTrue(summary['registry_exported'])
        self.assertEqual(summary['loader_paths_present'], [])
        if BUILD:
            self.install_bootstrap()
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
        reg('add', self.key, '/v', 'Binary', '/t', 'REG_BINARY', '/d', 'ff', '/f')
        reg('add', self.key, '/v', 'Multi', '/t', 'REG_MULTI_SZ', '/d', 'z', '/f')
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
        self.assertEqual(Path(report['debris']), debris)
        self.assertEqual((debris / 'crashes' / 'new.mdmp').read_bytes(), b'new dump')
        self.assertTrue((debris / 'garrysmod' / 'data' / 'existing' / 'newdir' / 'x.txt').is_file())
        self.assertIn('garrysmod/data/existing/newdir', report['moved'])
        self.assertNotIn('deleted', report)
        self.assertEqual((report['left_in_place'], report['moved_as'], report['errors']), ({}, {}, []))
        self.assertFalse(report['depot_check'])
        # A changed file below a watched folder cannot be put back; it is reported.
        self.assertEqual(report['watched']['garrysmod/data']['changed_files'], ['existing/a.txt'])
        self.assertEqual(report['watched']['garrysmod/settings']['changed'], 0)
        # The registry key as it was: the changed values back, the added value and keys gone.
        self.assertEqual(reg_value(self.key, 'DXLevel_V1'), '0x5a')
        self.assertEqual(reg_value(self.key, 'Binary'), bytes(range(60)).hex().upper())
        self.assertEqual(reg_value(self.key, 'Multi'), 'a\\0b c')
        self.assertIsNone(reg_value(self.key, 'NewValue'))
        self.assertNotEqual(reg('query', self.key + '\\Sub').returncode, 0)
        self.assertEqual(reg_value(self.key + '\\Settings', 'Name'), 'keep me')
        self.assertEqual((report['registry']['error'], report['registry']['differences']), (None, []))
        self.assertIn(self.full_key + '\\Sub', report['registry']['pruned'])
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
        # R1-010: schema 2 lacks the entry kinds a rollback needs to tell a link from the folder it replaced.
        (old / 'snapshot.json').write_text(json.dumps({'schema': 2, 'root': str(self.root)}), encoding='utf-8')
        older = run('--snapshot', str(old), 'rollback')
        self.assertEqual(older.returncode, 1)
        self.assertIn('older field_snapshot.py (schema 2)', older.stderr)

    def test_listing_differences_fail_the_rollback(self):
        self.snapshot()
        (self.root / 'garrysmod' / 'addons' / 'useraddon' / 'addon.json').unlink()
        (self.root / 'garrysmod' / 'addons' / 'useraddon').rmdir()  # something the snapshot did not keep
        code, report = self.rollback()
        self.assertEqual(code, 1)
        self.assertFalse(report['clean'])
        self.assertEqual(report['listing_differences']['garrysmod/addons'], {'added': [], 'missing': ['useraddon'], 'changed': []})

    # ------------------------------------------------------------ R1-009: never delete

    def test_a_failed_move_leaves_the_entry_where_it_is(self):
        """R1-009: a new entry rollback cannot rename into the debris folder stays, and is reported."""
        self.snapshot_here()
        self.write('crashes/new.mdmp', b'new dump')
        self.write('garrysmod/data/existing/newdir/x.txt', b'x')
        with patch.object(fs.os, 'rename', side_effect=OSError(18, 'The system cannot move the file to a different disk drive')):
            report = self.rollback_here()
        self.assertTrue((self.root / 'crashes' / 'new.mdmp').is_file())
        self.assertTrue((self.root / 'garrysmod' / 'data' / 'existing' / 'newdir' / 'x.txt').is_file())
        self.assertEqual(sorted(report['left_in_place']), ['crashes/new.mdmp', 'garrysmod/data/existing/newdir'])
        self.assertIn('different disk drive', report['left_in_place']['crashes/new.mdmp'])
        self.assertNotIn('deleted', report)
        self.assertFalse(report['clean'])

    def test_a_taken_debris_name_gets_a_number(self):
        """R1-009: an entry whose name the debris folder already holds goes in under name.1."""
        source = self.scratch / 'new.txt'
        source.write_bytes(b'from this session')
        target = self.scratch / 'debris' / 'new.txt'
        target.parent.mkdir()
        target.write_bytes(b'from an earlier rollback')
        fs.move_out(source, target)
        self.assertFalse(source.exists())
        self.assertEqual(target.read_bytes(), b'from an earlier rollback')
        self.assertEqual((self.scratch / 'debris' / 'new.txt.1').read_bytes(), b'from this session')
        # Through rollback: an earlier rollback in the same second left its own new.mdmp.
        self.snapshot_here()
        self.write('crashes/new.mdmp', b'new dump')
        earlier = self.snap / 'debris' / '20260101-000000' / 'crashes' / 'new.mdmp'
        earlier.parent.mkdir(parents=True)
        earlier.write_bytes(b'earlier dump')
        with patch.object(fs, 'stamp', return_value='20260101-000000'):
            report = self.rollback_here()
        self.assertFalse((self.root / 'crashes' / 'new.mdmp').exists())
        self.assertEqual(earlier.read_bytes(), b'earlier dump')
        moved = [path.read_bytes() for path in (self.snap / 'debris').rglob('new.mdmp*') if path != earlier]
        self.assertEqual(moved, [b'new dump'])
        self.assertTrue(report['clean'], report)

    def test_the_snapshot_folder_must_be_on_the_install_volume(self):
        """R1-009: snapshot and rollback refuse a snapshot folder on another volume, where a rename
        cannot reach."""
        far = self.scratch / 'far'
        far.mkdir()
        with patch.object(fs, 'os', OtherVolume(far)), self.assertRaises(fs.Failure) as refused:
            self.snapshot_here(snapshot=str(far / 'snapshot'))
        self.assertIn('volume', str(refused.exception))
        self.assertFalse((far / 'snapshot').exists())
        self.snapshot_here()
        self.write('crashes/new.mdmp', b'new dump')
        with patch.object(fs, 'os', OtherVolume(self.snap)), self.assertRaises(fs.Failure) as refused:
            self.rollback_here()
        self.assertIn('volume', str(refused.exception))
        self.assertTrue((self.root / 'crashes' / 'new.mdmp').is_file())
        self.assertFalse((self.snap / 'debris').exists())

    # ------------------------------------------------------------ R1-010: never through a link

    def test_a_folder_replaced_by_a_link_moves_out_as_a_link(self):
        """R1-010: a listed folder that is now a link moves to the debris folder as a link (its target
        untouched), and the kept files go back into a new ordinary folder."""
        self.snapshot()
        victim = self.scratch / 'victim'
        victim.mkdir()
        (victim / 'config.cfg').write_bytes(b'USER DATA')
        cfg = self.root / 'garrysmod' / 'cfg'
        shutil.rmtree(cfg)
        junction(cfg, victim)
        code, report = self.rollback()
        self.assertEqual([path.name for path in victim.iterdir()], ['config.cfg'])
        self.assertEqual((victim / 'config.cfg').read_bytes(), b'USER DATA')
        self.assertEqual(code, 0, report)
        self.assertFalse(fs.is_link(cfg))
        self.assertEqual((cfg / 'config.cfg').read_bytes(), b'r_x 1\n')
        self.assertIn('garrysmod/cfg', report['moved'])
        self.assertTrue(os.path.isjunction(Path(report['debris']) / 'garrysmod' / 'cfg'))

    def test_a_link_above_a_kept_file_is_never_written_through(self):
        """R1-010: bin/win64 sits in bin, which no listing covers; replaced by a link, it stops the
        restore of every file below it, and the rollback is not clean."""
        self.snapshot()
        victim = self.scratch / 'victim'
        victim.mkdir()
        (victim / 'd3d9.dll').write_bytes(b'VICTIM')
        win64 = self.root / 'bin' / 'win64'
        shutil.rmtree(win64)
        junction(win64, victim)
        code, report = self.rollback()
        self.assertEqual([path.name for path in victim.iterdir()], ['d3d9.dll'])
        self.assertEqual((victim / 'd3d9.dll').read_bytes(), b'VICTIM')
        self.assertEqual(code, 1)
        self.assertFalse(report['clean'])
        self.assertIn('bin/win64/d3d9.dll: not restored, because bin/win64 is a link (never written through)', report['errors'])

    def test_a_link_the_checks_miss_is_caught_at_the_write(self):
        """R1-010: should a link escape every check before the write (here they are made blind to it),
        the write itself refuses a file that opens outside the install."""
        self.snapshot_here()
        victim = self.scratch / 'victim'
        victim.mkdir()
        (victim / 'config.cfg').write_bytes(b'USER DATA')
        cfg = self.root / 'garrysmod' / 'cfg'
        shutil.rmtree(cfg)
        junction(cfg, victim)
        with patch.object(fs, 'is_link', return_value=False):
            report = self.rollback_here()
        self.assertEqual((victim / 'config.cfg').read_bytes(), b'USER DATA')
        self.assertFalse(report['clean'])
        refused = [error for error in report['errors'] if error.startswith('garrysmod/cfg/config.cfg: not restored')]
        self.assertEqual(len(refused), 1, report['errors'])
        self.assertIn('through a link; nothing was written', refused[0])

    # ------------------------------------------------------------ R1-011: prune only after a verified import

    def test_a_damaged_registry_export_prunes_nothing(self):
        """R1-011: a registry.reg without its recorded SHA-256 (here cut short by a whole subkey, which
        still parses) is neither imported nor pruned against."""
        self.snapshot()
        reg('add', self.key, '/v', 'NewValue', '/t', 'REG_SZ', '/d', 'x', '/f')
        export = self.snap / 'registry.reg'
        text = export.read_bytes().decode('utf-16')
        export.write_bytes(text[:text.index('[' + self.full_key + '\\Settings]')].encode('utf-16'))
        code, report = self.rollback()
        self.assertEqual(reg_value(self.key + '\\Settings', 'Name'), 'keep me')
        self.assertEqual(reg_value(self.key, 'NewValue'), 'x')
        self.assertEqual(code, 1)
        self.assertIn('SHA-256', report['registry']['error'])
        self.assertEqual(report['registry']['pruned'], [])
        self.assertFalse(report['clean'])

    def test_a_failed_import_prunes_nothing(self):
        """R1-011: when reg import fails, nothing is pruned."""
        self.snapshot_here()
        reg('add', self.key, '/v', 'NewValue', '/t', 'REG_SZ', '/d', 'x', '/f')
        real_run = subprocess.run

        def failing_import(command, *args, **kwargs):
            if list(command[:2]) == ['reg', 'import']:
                return subprocess.CompletedProcess(command, 1, '', 'ERROR: simulated')
            return real_run(command, *args, **kwargs)
        with patch.object(fs.subprocess, 'run', side_effect=failing_import):
            report = self.rollback_here()
        self.assertEqual(reg_value(self.key, 'NewValue'), 'x')
        self.assertEqual(report['registry']['import_exit'], 1)
        self.assertEqual(report['registry']['pruned'], [])
        self.assertIn('nothing was pruned', report['registry']['error'])
        self.assertFalse(report['clean'])

    def test_an_export_without_the_key_prunes_nothing(self):
        """R1-011: an export that parses but does not hold the key (its SHA-256 recorded as if the
        snapshot had written it) counts as unreadable: the key is left alone instead of emptied."""
        self.snapshot()
        export = self.snap / 'registry.reg'
        export.write_bytes('Windows Registry Editor Version 5.00\r\n\r\n'.encode('utf-16'))
        state = json.loads((self.snap / 'snapshot.json').read_text(encoding='utf-8'))
        state['registry'].update(sha256=hashlib.sha256(export.read_bytes()).hexdigest(), size=export.stat().st_size)
        (self.snap / 'snapshot.json').write_text(json.dumps(state), encoding='utf-8')
        code, report = self.rollback()
        self.assertEqual(reg_value(self.key, 'DXLevel_V1'), '0x5a')
        self.assertEqual(reg_value(self.key + '\\Settings', 'Name'), 'keep me')
        self.assertEqual(code, 1)
        self.assertIn('does not hold the key', report['registry']['error'])

    # ------------------------------------------------------------ R1-012: never over Steam's files

    def test_a_steam_install_needs_its_depot_manifests(self):
        """R1-012: snapshot refuses a Steam-managed install whose depot manifests it cannot read, unless
        --no-depot-check, which the snapshot records."""
        self.make_steam_managed(None)
        with self.steam_folder(), self.assertRaises(fs.Failure) as refused:
            self.snapshot_here()
        self.assertIn('appmanifest_4000.acf', str(refused.exception))
        self.assertIn('--no-depot-check', str(refused.exception))
        self.assertFalse(self.snap.exists())
        with self.steam_folder():
            summary = self.snapshot_here(no_depot_check=True)
        self.assertEqual((summary['steam_managed'], summary['depot_check'], summary['no_depot_check']),
                         ('appmanifest_4000.acf', False, True))
        self.assertTrue(json.loads((self.snap / 'snapshot.json').read_text(encoding='utf-8'))['no_depot_check'])
        cli = run('--snapshot', str(self.scratch / 'snapshot2'), 'snapshot', '--root', str(self.root), '--registry-key',
                  self.key, '--no-depot-check')
        self.assertEqual(cli.returncode, 0, cli.stderr)
        self.assertTrue(json.loads(cli.stdout)['no_depot_check'])

    def test_rollback_never_writes_a_steam_file_back(self):
        """R1-012: a file a depot lists is never written back, even when the snapshot holds a copy (taken
        with --no-depot-check). Without manifests only the user-config names go back and the rollback is
        not clean; once Steam has cached them, a second rollback puts back the rest and is clean."""
        self.write('garrysmod/cfg/autoexec.cfg', b'bind f5 jpeg')  # a depot user-config file the user edited
        self.make_steam_managed(None)
        with self.steam_folder():
            self.snapshot_here(no_depot_check=True)
        self.assertTrue((self.snap / 'files' / 'bin' / 'win64' / 'gmod.exe').is_file())
        self.write('bin/win64/gmod.exe', b'steam update')  # Steam updates its file
        self.write('garrysmod/cfg/autoexec.cfg', b'session')  # a session changes the user's
        self.write('bin/win64/d3d9.dll', b'overwritten')
        with self.steam_folder():
            report = self.rollback_here()
        self.assertEqual((self.root / 'bin' / 'win64' / 'gmod.exe').read_bytes(), b'steam update')
        self.assertEqual((self.root / 'garrysmod' / 'cfg' / 'autoexec.cfg').read_bytes(), b'bind f5 jpeg')
        self.assertEqual((self.root / 'bin' / 'win64' / 'd3d9.dll').read_bytes(), b'overwritten')  # could be Steam's
        self.assertFalse(report['depot_check'])
        self.assertFalse(report['clean'])
        self.make_steam_managed({'bin/win64/gmod.exe': (b'steam update', 0), 'garrysmod/cfg/autoexec.cfg': (b'', FLAG_USERCONFIG)})
        with self.steam_folder():
            report = self.rollback_here()
        self.assertEqual((self.root / 'bin' / 'win64' / 'gmod.exe').read_bytes(), b'steam update')
        self.assertEqual((self.root / 'bin' / 'win64' / 'd3d9.dll').read_bytes(), b'the user DXVK')
        self.assertEqual((report['depot_check'], report['steam_files_not_restored']), (True, ['bin/win64/gmod.exe']))
        self.assertEqual((report['verify']['ok'], report['verify']['hash_mismatch']), (1, []))
        self.assertTrue(report['clean'], report)

    def test_a_steam_file_the_snapshot_kept_is_never_written_back(self):
        """R1-012: when the snapshot read the manifests, a kept file they list as Steam's (config.cfg
        here, hypothetically) is never written back, even when the rollback cannot read them."""
        self.make_steam_managed({'bin/win64/gmod.exe': (b'not a real game', 0), 'garrysmod/cfg/config.cfg': (b'r_x 1\n', 0)})
        with self.steam_folder():
            summary = self.snapshot_here()
        self.assertTrue(summary['depot_check'])
        self.assertFalse((self.snap / 'files' / 'bin' / 'win64' / 'gmod.exe').exists())  # Steam's: not even copied
        self.write('garrysmod/cfg/config.cfg', b'changed')
        self.write('bin/win64/d3d9.dll', b'overwritten')
        (self.steam / 'depotcache' / f'4002_{MANIFEST_ID}.manifest').unlink()
        with self.steam_folder():
            report = self.rollback_here()
        self.assertEqual((self.root / 'garrysmod' / 'cfg' / 'config.cfg').read_bytes(), b'changed')
        self.assertEqual((self.root / 'bin' / 'win64' / 'd3d9.dll').read_bytes(), b'the user DXVK')
        self.assertEqual(report['steam_files_not_restored'], ['garrysmod/cfg/config.cfg'])
        self.assertFalse(report['depot_check'])
        self.assertFalse(report['clean'])

    # ------------------------------------------------------------ R1-013: copies checked first

    def test_a_damaged_copy_stops_the_rollback_before_any_change(self):
        """R1-013: every saved copy is checked first; a damaged or missing one stops the rollback before
        it uninstalls, moves, writes or prunes anything."""
        self.snapshot()
        if BUILD:
            self.install_bootstrap()
        self.write('garrysmod/cfg/config.cfg', b'session')
        self.write('crashes/new.mdmp', b'new dump')
        reg('add', self.key, '/v', 'NewValue', '/t', 'REG_SZ', '/d', 'x', '/f')
        (self.snap / 'files' / 'garrysmod' / 'cfg' / 'config.cfg').write_bytes(b'DAMAGED COPY')
        (self.snap / 'files' / 'bin' / 'win64' / 'd3d9.dll').unlink()
        code, message = self.rollback()
        self.assertEqual((self.root / 'garrysmod' / 'cfg' / 'config.cfg').read_bytes(), b'session')
        self.assertTrue((self.root / 'crashes' / 'new.mdmp').is_file())
        self.assertEqual(reg_value(self.key, 'NewValue'), 'x')
        self.assertEqual((self.root / 'bin' / 'win64' / 'winmm.dll').is_file(), bool(BUILD))
        self.assertFalse((self.snap / 'debris').exists())
        self.assertFalse((self.snap / 'rollback.json').exists())
        self.assertEqual(code, 1)
        self.assertIn('nothing was changed', message)
        self.assertIn("garrysmod/cfg/config.cfg: the copy has 12 bytes, not 6", message)
        self.assertIn('bin/win64/d3d9.dll: the copy is missing', message)

    # ------------------------------------------------------------ R1-026: the user's allowlist

    def test_the_users_loader_config_comes_back(self):
        """R1-026: native-loader/config.json, the user's allowlist, is kept; rollback puts it back after
        the uninstaller removed native-loader with it."""
        allowlist = b'{"schema": 1, "allow": {"local": ["my-reviewed-package.gma"]}}\n'
        self.write('native-loader/config.json', allowlist)
        self.snapshot()
        if BUILD:
            self.install_bootstrap()
        self.write('native-loader/config.json', b'{"schema": 1, "allow": {}}\n')  # a session's install rewrites it
        code, report = self.rollback()
        self.assertEqual((self.root / 'native-loader' / 'config.json').read_bytes(), allowlist)
        self.assertEqual(code, 0, report)
        self.assertIn('native-loader/config.json', report['restored'])
        self.assertEqual(report['uninstall'], 0 if BUILD else None)
        self.assertFalse((self.root / 'bin' / 'win64' / 'winmm.dll').exists())

    def test_a_new_loader_config_goes_to_the_debris(self):
        """R1-026: a config.json that was not there is new: it goes to the debris folder, and the rest of
        the native-loader folder that was there stays."""
        self.write('native-loader/logs/old.log', b'an earlier install')
        self.snapshot()
        self.write('native-loader/config.json', b'{"schema": 1}')
        code, report = self.rollback()
        self.assertFalse((self.root / 'native-loader' / 'config.json').exists())
        self.assertEqual((self.root / 'native-loader' / 'logs' / 'old.log').read_bytes(), b'an earlier install')
        self.assertEqual((Path(report['debris']) / 'native-loader' / 'config.json').read_bytes(), b'{"schema": 1}')
        self.assertEqual(code, 0, report)

    # ------------------------------------------------------------ R1-029: PowerShell's module path

    def test_powershell_children_get_no_module_path(self):
        """R1-029: every powershell child starts without PSModulePath, and a game check that cannot run
        refuses instead of reporting no game."""
        calls = []
        real_run = subprocess.run

        def recording_run(command, *args, **kwargs):
            if command[0] == 'powershell':
                calls.append((command, kwargs.get('env')))
                return subprocess.CompletedProcess(command, 0, '', '')
            return real_run(command, *args, **kwargs)
        with patch.dict(os.environ, {'PSModulePath': str(self.scratch / 'Modules')}), \
                patch.object(fs.subprocess, 'run', side_effect=recording_run):
            fs.snapshot(self.snapshot_args())
            self.write('bin/win64/winmm.dll', b'a bootstrap')  # makes rollback run the uninstaller
            fs.rollback(self.rollback_args())
        self.assertEqual(len(calls), 3, calls)  # the game check twice, the uninstaller once
        self.assertIn('uninstall-loader.ps1', ' '.join(calls[2][0]))
        for command, env in calls:
            self.assertIsNotNone(env, command)
            self.assertNotIn('PSMODULEPATH', {name.upper() for name in env}, command)
        failed = subprocess.CompletedProcess(['powershell'], 1, '', "The term 'Get-Process' is not recognized")
        with patch.object(fs.subprocess, 'run', return_value=failed), self.assertRaises(fs.Failure):
            fs.game_running(self.root)

    @unittest.skipUnless(BUILD, 'needs a built bootstrap (tools\\build.ps1)')
    def test_rollback_under_powershell_7s_module_path(self):
        """R1-029: started from PowerShell 7, rollback inherits a PSModulePath whose modules Windows
        PowerShell 5.1 cannot load; its uninstaller must still find Get-FileHash."""
        utility = self.scratch / 'pwsh7-modules' / 'Microsoft.PowerShell.Utility'
        utility.mkdir(parents=True)
        (utility / 'Microsoft.PowerShell.Utility.psd1').write_text(CORE_ONLY_UTILITY, encoding='utf-8')
        inherited = powershell_env()
        inherited['PSModulePath'] = f"{utility.parent};{os.environ.get('PSModulePath', '')}"
        probe = subprocess.run(['powershell', '-NoProfile', '-Command', 'Get-FileHash -LiteralPath $env:ComSpec | Out-Null'],
                               capture_output=True, text=True, env=inherited)
        if probe.returncode == 0:
            self.skipTest('this Windows PowerShell finds Get-FileHash despite the inherited module path')
        self.snapshot()
        self.install_bootstrap()
        self.write('crashes/new.mdmp', b'new dump')
        code, report = self.rollback(env=inherited)
        self.assertEqual(code, 0, report)
        self.assertEqual(report['uninstall'], 0)
        self.assertFalse((self.root / 'bin' / 'win64' / 'winmm.dll').exists())


if __name__ == '__main__':
    unittest.main()
