"""field_snapshot.py on a synthetic install under out/tmp: snapshot, a simulated session (the real
bootstrap installed when a build exists; files changed, created, deleted and written through a hard
link; registry values changed and added), rollback, and checks that everything is back. Plus one
regression test or more for each R1 finding the tool had. Uses a throwaway registry key under
HKCU\\Software, deleted afterwards."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
import winreg
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / 'tools' / 'field_snapshot.py'
sys.path.insert(0, str(REPO / 'tools'))
import field_snapshot as fs  # noqa: E402

BUILD = next((config for config in ('Debug', 'Release')
              if (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'proxy' / 'winmm.dll').is_file()
              and (REPO / 'out' / 'build' / f'win64-{config.lower()}' / 'loader' / 'cli' / 'nlctl.exe').is_file()), None)
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


class FieldSnapshotTests(unittest.TestCase):
    def setUp(self):
        (REPO / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
        self.scratch = Path(tempfile.mkdtemp(prefix='field_snapshot_', dir=REPO / 'out' / 'tmp'))
        self.root = self.scratch / 'game'
        self.snap = self.scratch / 'snapshot'
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

    # ------------------------------------------------------------ the whole round

    def test_rollback_puts_everything_back(self):
        summary = self.snapshot()
        self.assertFalse(summary['depot_check'])  # not a Steam install: every file is kept
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
        self.assertEqual((debris / 'crashes' / 'new.mdmp').read_bytes(), b'new dump')
        self.assertTrue((debris / 'garrysmod' / 'data' / 'existing' / 'newdir' / 'x.txt').is_file())
        self.assertIn('garrysmod/data/existing/newdir', report['moved'])
        self.assertEqual(report['deleted'], [])
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

    def test_listing_differences_fail_the_rollback(self):
        self.snapshot()
        (self.root / 'garrysmod' / 'addons' / 'useraddon' / 'addon.json').unlink()
        (self.root / 'garrysmod' / 'addons' / 'useraddon').rmdir()  # something the snapshot did not keep
        code, report = self.rollback()
        self.assertEqual(code, 1)
        self.assertFalse(report['clean'])
        self.assertEqual(report['listing_differences']['garrysmod/addons'], {'added': [], 'missing': ['useraddon']})

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
