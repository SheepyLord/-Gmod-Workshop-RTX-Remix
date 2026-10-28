"""Exercise M4 in generated game roots using a packaged fake runtime. Never starts a real game."""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def check(value, message):
    if not value:
        raise AssertionError(message)


def remove_tree(path):
    for attempt in range(30):
        try:
            shutil.rmtree(path)
            return
        except FileNotFoundError:
            return
        except OSError:
            if attempt == 29:
                raise
            time.sleep(0.1)  # Windows may retain an exited process's image briefly.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'host', 'proxy', 'runtime', 'nlctl', 'scratch'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    base = args.scratch.resolve()
    check(base.is_relative_to(repo / 'out' / 'tmp'), 'scratch must be below this repo/out/tmp')
    scratch = base / str(os.getpid())
    check(not scratch.exists(), 'scratch PID directory already exists')
    scratch.mkdir(parents=True)
    evidence = repo / 'out' / 'm4-synthetic' / (args.config.lower() + '-' + str(os.getpid()))
    evidence.mkdir(parents=True)
    results = []
    package_a, package_b, broken = (scratch / name for name in ('a.gma', 'b.gma', 'missing-dependency.gma'))
    layer = scratch / 'defaults.conf'
    layer.write_text('rtx.test = True\n', encoding='ascii')
    package_id = 'm4-runtime'

    def build_package(output, version, runtime, system_vulkan=False):
        command = [sys.executable, str(repo / 'tools/package_runtime.py'), '--runtime', str(runtime), '--gma', str(output),
                   '--id', package_id, '--version', version, '--rtx-conf', str(layer), '--dxvk-conf', str(layer),
                   '--env', 'RTX_TEST=package', '--env', 'DXVK_LOG_LEVEL=info', '--json']
        if not system_vulkan:
            command.append('--no-system-vulkan')
        subprocess.run(command, cwd=repo, check=True, capture_output=True, text=True)

    build_package(package_a, '1.0.0', args.runtime)
    build_package(package_b, '2.0.0', args.runtime)
    incomplete = scratch / 'incomplete-runtime'
    incomplete.mkdir()
    shutil.copy2(args.runtime / 'd3d9.dll', incomplete / 'd3d9.dll')
    has_system_vulkan = (Path(os.environ['SystemRoot']) / 'System32/vulkan-1.dll').exists()
    build_package(broken, '3.0.0', incomplete, system_vulkan=has_system_vulkan)

    class Game:
        def __init__(self, name, package=package_a, workshop=False):
            self.name = name
            self.case = scratch / name
            self.root = self.case / 'steamapps/common/game' if workshop else self.case / 'game'
            self.exe = self.root / 'bin/win64/gmod.exe'
            self.exe.parent.mkdir(parents=True)
            shutil.copy2(args.host, self.exe)
            shutil.copy2(args.proxy, self.exe.parent / 'winmm.dll')
            self.source = self.case / 'steamapps/workshop/content/4000/123/runtime.gma' if workshop else self.case / 'runtime.gma'
            self.source.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(package, self.source)
            self.config = {'schema': 1, 'allow': {'workshop': ['123']} if workshop else {'local': [str(self.source)]}}
            self.save()
            self.journal = self.root / 'native-loader/state.json'
            self.status = self.root / 'garrysmod/data/native-loader/status.json'
            self.probe = self.root / 'probe.json'
            self.run_number = 0

        def save(self):
            write_json(self.root / 'native-loader/config.json', self.config)

        def run(self, extra=(), env_extra=None, cwd=None, report_expected=True):
            self.run_number += 1
            env = dict(os.environ)
            for name in ('NATIVE_LOADER_DISABLE', 'DXVK_RTX_CONFIG_FILE', 'DXVK_CONFIG_FILE', 'RTX_TEST', 'DXVK_LOG_LEVEL',
                         'NL_M4_BAD_CMDLINE', 'NL_M4_FAIL_ATTACH', 'NL_M4_SEH_ATTACH'):
                env.pop(name, None)
            env.update(env_extra or {})
            argv = [str(self.exe), '--m4-probe', str(self.probe), *extra]
            original_command = subprocess.list2cmdline(argv)
            self.probe.unlink(missing_ok=True)
            completed = subprocess.run(argv, cwd=cwd or self.root, env=env, timeout=30, capture_output=True,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            check(completed.returncode == 0, f'{self.name}: host exit {completed.returncode:#x}, {completed.stderr!r}')
            probe = json.loads(self.probe.read_text(encoding='utf-8'))
            status = json.loads(self.status.read_text(encoding='utf-8')) if self.status.exists() else None
            if report_expected:
                check(status and status['schema'] == 1, f'{self.name}: missing status')
                check(status['process_id'] == probe['process_id'], f'{self.name}: stale process id')
                check(probe['status_at_main'], f'{self.name}: status was not written before main')
            check(probe['command_line_w'] == probe['command_line_peb'], f'{self.name}: PEB differs')
            check(probe['ansi_matches_wide'], f'{self.name}: ANSI differs from wide command line')
            write_json(evidence / f'{self.name}-{self.run_number}.probe.json', probe)
            if status:
                write_json(evidence / f'{self.name}-{self.run_number}.status.json', status)
            log = self.root / 'native-loader/logs/loader.log'
            if log.exists():
                shutil.copy2(log, evidence / f'{self.name}-{self.run_number}.loader.log')
            return probe, status, original_command

        def cli(self, command, env=None):
            run = subprocess.run([str(args.nlctl), command, str(self.root), '--json'], env=env, capture_output=True, text=True)
            check(run.returncode == 0, f'{command}: {run.stdout}\n{run.stderr}')
            return json.loads(run.stdout)

    def active(game, result, version='1.0.0'):
        probe, status, original = result
        activation = status['activation']
        check(activation['outcome'] == 'active', f'{game.name}: activation {activation}')
        check(activation['runtime']['version'] == version, f'{game.name}: wrong runtime version')
        folder = Path(activation['runtime']['folder'])
        check(Path(probe['runtime_path']) == folder / 'd3d9.dll', f'{game.name}: bare-name import missed preload')
        check(probe['preloaded'] and probe['fake_probe'] == 42 and probe['delay_error'] == 0, f'{game.name}: static/delay dependency failed')
        check(Path(probe['static_dependency']) == folder / 'nl_m4_static.dll', f'{game.name}: static dependency outside package')
        check(Path(probe['delay_dependency']) == folder / 'nl_m4_delay.dll', f'{game.name}: delay dependency outside package')
        check(Path(probe['dll_directory']) == folder, f'{game.name}: runtime DLL directory missing')
        added = activation['launch_arguments']['added']
        check(probe['command_line_w'] == original + (' ' + ' '.join(added) if added else ''), f'{game.name}: appended arguments differ')
        for variable in activation['environment']['set']:
            check(probe['environment'][variable['name']] == variable['value'], f'{game.name}: environment differs')
        return status

    def vanilla(result, expected_env=None):
        probe, _, original = result
        check(not probe['preloaded'], 'vanilla process has preloaded d3d9')
        check(Path(probe['runtime_path']) == Path(os.environ['SystemRoot']) / 'System32/d3d9.dll', 'vanilla d3d9 is not System32')
        check(probe['command_line_w'] == original, 'vanilla command line changed')
        check(probe['dll_directory'] == '', 'DLL directory was not restored')
        for name, value in probe['environment'].items():
            check(value == (expected_env or {}).get(name), f'vanilla environment changed: {name}={value!r}')

    def passed(name):
        results.append(name)
        print('ok  ' + name, flush=True)

    try:
        game = Game('on-off-switch-rollback')
        first = active(game, game.run())
        check(first['deployment']['outcome'] == 'deployed', 'first launch did not deploy')
        journal_bytes = game.journal.read_bytes()
        journal_time = game.journal.stat().st_mtime_ns
        second = active(game, game.run())
        check(second['deployment']['operations'] == 0 and second['deployment']['change_count'] == 0, 'repeat changed deployment')
        check(game.journal.read_bytes() == journal_bytes and game.journal.stat().st_mtime_ns == journal_time, 'repeat rewrote journal')
        passed('first startup deploys and preloads; repeat makes zero deployment writes')

        if has_system_vulkan:
            vk_package = scratch / 'vulkan.gma'
            build_package(vk_package, '1.0.0', args.runtime, system_vulkan=True)
            vk_game = Game('system-vulkan', vk_package)
            vk_result = vk_game.run()
            active(vk_game, vk_result)
            check(Path(vk_result[0]['vulkan_path']) == Path(os.environ['SystemRoot']) / 'System32/vulkan-1.dll', 'Vulkan preload was not System32')
            passed('optional Vulkan preload uses System32')

        game.config['remix'] = {'enabled': False}
        game.save()
        off = game.run()
        vanilla(off)
        check(off[1]['activation']['outcome'] == 'inactive', 'RTX off not inactive')
        check(game.journal.read_bytes() == journal_bytes, 'RTX off removed deployment')
        passed('RTX off leaves process vanilla and packages deployed')
        game.config['remix']['enabled'] = True
        game.save()
        shutil.copy2(package_b, game.source)
        active(game, game.run(), '2.0.0')
        game.cli('rollback')
        rollback = active(game, game.run(), '1.0.0')
        check(rollback['deployment']['outcome'] == 'held' and rollback['deployment']['operations'] == 0, 'rollback hold was bypassed')
        passed('switch to B then rollback to A remains held at startup')

        for kind in ('command', 'environment', 'file'):
            disabled = Game('disabled-' + kind)
            if kind == 'file':
                (disabled.root / 'native-loader/disable').write_text('', encoding='ascii')
            result = disabled.run(extra=['-nonativeloader'] if kind == 'command' else [],
                                  env_extra={'NATIVE_LOADER_DISABLE': '1'} if kind == 'environment' else {}, report_expected=False)
            vanilla(result)
            check(result[1] is None and not disabled.journal.exists(), kind + ' off switch wrote state')
            check(not (disabled.root / 'native-loader/logs').exists(), kind + ' off switch wrote log')
        stale_before = game.status.read_bytes()
        vanilla(game.run(extra=['-nonativeloader'], report_expected=False))
        check(game.status.read_bytes() == stale_before, 'pure pass-through rewrote stale status')
        passed('all off switches stay pure pass-through, including stale status preservation')

        user = Game('user-layers')
        user_values = {'DXVK_RTX_CONFIG_FILE': '用户.conf,user-top.conf', 'DXVK_CONFIG_FILE': 'dxvk-user.conf,dxvk-top.conf',
                       'DXVK_LOG_LEVEL': 'debug', 'RTX_TEST': ''}
        user_result = user.run(extra=['-dxlevel', '95'], env_extra=user_values)
        status = active(user, user_result)
        for name in ('DXVK_RTX_CONFIG_FILE', 'DXVK_CONFIG_FILE'):
            check(user_result[0]['environment'][name].endswith(',' + user_values[name]), 'user layers lost')
        check(user_result[0]['environment']['RTX_TEST'] == '', 'empty user environment was replaced')
        check(status['activation']['launch_arguments']['already_present'] == ['-dxlevel', '95'], 'user dxlevel lost')
        preview = user.cli('activation', env={**os.environ, **user_values})
        check(preview['env'] == status['activation']['environment']['requested'], 'CLI and startup layer plans differ')
        passed('user lists remain on top, empty values and dxlevel 95 stay intact; CLI agrees')

        missing = Game('missing-source')
        active(missing, missing.run())
        before = missing.journal.read_bytes()
        missing.source.unlink()
        kept = active(missing, missing.run())
        check(kept['deployment']['outcome'] == 'kept' and missing.journal.read_bytes() == before, 'missing source discarded current')
        missing.config['allow']['local'] = []
        missing.save()
        removed = missing.run()
        vanilla(removed)
        check(not json.loads(missing.journal.read_text())['current']['packages'], 'explicit removal kept package')
        passed('missing allowlisted source is kept; explicit allowlist removal removes it')

        workshop = Game('workshop-disabled', workshop=True)
        active(workshop, workshop.run())
        addon_list = workshop.root / 'garrysmod/cfg/addonnomount.txt'
        addon_list.parent.mkdir(parents=True, exist_ok=True)
        addon_list.write_text('"addonnomount" { "1" "123" }', encoding='ascii')
        vanilla(workshop.run())
        check(not json.loads(workshop.journal.read_text())['current']['packages'], 'disabled Workshop source retained')
        passed('explicit Workshop disable removes the package')

        locked = Game('locked')
        active(locked, locked.run())
        original_journal = locked.journal.read_bytes()
        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                        wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel32.CreateFileW.restype = wintypes.HANDLE
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel32.CreateFileW(str(locked.root / 'native-loader/lock'), 0xC0000000, 0, None, 4, 0x80, None)
        check(handle != ctypes.c_void_p(-1).value, 'could not hold test deployer lock')
        try:
            result = active(locked, locked.run())
            check(result['deployment']['blocked_by'] == 'deployer_lock', 'lock contention not reported')
            pending = json.loads(original_journal)
            tx = pending['next']
            pending['pending'] = {'transaction': tx, 'action': 'apply', 'steps': [
                {'op': 'make_dir', 'path': f'native-loader/backup/{tx}'}]}
            write_json(locked.journal, pending)
            pending_result = locked.run()
            vanilla(pending_result)
            check('pending' in pending_result[1]['activation']['reason'], 'pending journal activated')
        finally:
            kernel32.CloseHandle(handle)
        recovered = active(locked, locked.run())
        check(recovered['deployment']['recovered'], 'pending transaction not recovered')
        passed('lock contention activates only committed state; pending blocks until recovery')

        second_game = Game('second-instance')
        active(second_game, second_game.run())
        shutil.copy2(package_b, second_game.source)
        ready = second_game.root / 'holder.ready'
        holder = subprocess.Popen([str(second_game.exe), '--m4-hold', str(ready), '-nonativeloader'],
                                  cwd=second_game.root, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and time.monotonic() < deadline and holder.poll() is None:
                time.sleep(0.02)
            check(ready.exists(), 'synthetic second instance did not start')
            result = active(second_game, second_game.run())
            check(result['deployment']['blocked_by'] == 'running_game', 'second instance was ignored')
        finally:
            if holder.poll() is None:
                holder.terminate()
            holder.wait(timeout=10)
        passed('only the current PID is excluded; another same-root instance defers deployment')

        invalid = Game('invalid-journal')
        invalid.journal.write_text('not a journal', encoding='ascii')
        result = invalid.run()
        vanilla(result)
        check(result[1]['deployment']['outcome'] == 'failed' and invalid.journal.read_text() == 'not a journal', 'invalid journal changed')
        passed('invalid journal stays untouched and prevents activation')

        configuration = Game('configuration-off')
        active(configuration, configuration.run())
        preserved_journal = configuration.journal.read_bytes()
        configuration.config['enabled'] = False
        configuration.save()
        vanilla(configuration.run())
        (configuration.root / 'native-loader/config.json').write_text('invalid config', encoding='ascii')
        vanilla(configuration.run())
        (configuration.root / 'native-loader/config.json').unlink()
        vanilla(configuration.run())
        check(configuration.journal.read_bytes() == preserved_journal, 'missing/disabled/invalid config removed deployed files')
        passed('missing, disabled and invalid config preserve deployment and stay vanilla')

        for name, package, environment in [('missing-dependency', broken, {}), ('attach-failure', package_a, {'NL_M4_FAIL_ATTACH': '1'}),
                                           ('attach-seh', package_a, {'NL_M4_SEH_ATTACH': '1'})]:
            failure = Game(name, package)
            kept_env = {'DXVK_RTX_CONFIG_FILE': 'original.conf', 'DXVK_LOG_LEVEL': 'debug'}
            result = failure.run(env_extra={**kept_env, **environment})
            vanilla(result, kept_env)
            check(result[1]['activation']['outcome'] == 'failed', name + ' not reported')
            check(result[1]['activation']['rolled_back'], name + ' did not report rollback')
            check(result[0]['vulkan_path'] == '', name + ' retained its Vulkan reference')
        passed('missing dependency, failed DllMain and native exception restore all process settings')

        refused = Game('swap-refused')
        result = refused.run(env_extra={'NL_M4_BAD_CMDLINE': '1'})
        vanilla(result)
        fallback = result[1]['activation']['launch_arguments']['fallback_launch_options']
        check(fallback == '-dxlevel 90 -nod3d9ex', 'fallback options incorrect')
        active(refused, refused.run(extra=fallback.split(), env_extra={'NL_M4_BAD_CMDLINE': '1'}))
        passed('refused swap rolls back; supplying the reported arguments permits activation')

        wrong_cwd = Game('wrong-cwd')
        result = wrong_cwd.run(cwd=wrong_cwd.case)
        vanilla(result)
        check('working directory' in result[1]['activation']['reason'], 'working-directory precondition missing')
        bad_size = Game('missing-layer')
        status = active(bad_size, bad_size.run())
        bad_size.source.unlink()
        layer_path = bad_size.root / status['activation']['layers']['rtx'][0]
        layer_path.write_bytes(b'')
        result = bad_size.run()
        vanilla(result)
        check('recorded size' in result[1]['activation']['reason'], 'layer-size precondition missing')
        passed('working-directory and journaled layer-size preconditions prevent activation')

        too_long = Game('long-runtime-path')
        active(too_long, too_long.run())
        too_long.source.unlink()
        long_state = json.loads(too_long.journal.read_text())
        previous_folder = long_state['current']['packages'][0]['payload']
        long_folder = 'native-loader/packages/m4-runtime/' + 'v' * 220
        long_state['current']['packages'][0]['payload'] = long_folder
        for file in long_state['current']['files']:
            file['path'] = file['path'].replace(previous_folder, long_folder, 1)
        write_json(too_long.journal, long_state)
        result = too_long.run()
        vanilla(result)
        check('MAX_PATH' in result[1]['activation']['reason'], 'runtime path bound was not enforced')
        passed('runtime paths exceeding MAX_PATH are refused before preload')

        user.cli('uninstall')
        check(not user.status.exists() and not user.status.parent.exists(), 'uninstall left generated status')
        passed('nlctl uninstall removes status and the empty data folder')

        timing = Game('timing')
        active(timing, timing.run())
        samples = []
        for _ in range(10):
            status = active(timing, timing.run())
            check(status['deployment']['operations'] == 0, 'timing run unexpectedly changed deployment')
            samples.append(status['startup_elapsed_ms'])
        summary = {'passed': len(results), 'cases': results, 'config': args.config, 'evidence': str(evidence),
                   'unchanged_startup_ms': {'samples': samples, 'median': statistics.median(samples), 'min': min(samples), 'max': max(samples)}}
        write_json(evidence / 'summary.json', summary)
        print(json.dumps(summary), flush=True)
        remove_tree(scratch)
        return 0
    except Exception:
        print(f'M4 synthetic evidence: {evidence}; retained scratch: {scratch}', file=sys.stderr)
        raise


if __name__ == '__main__':
    sys.exit(main())
