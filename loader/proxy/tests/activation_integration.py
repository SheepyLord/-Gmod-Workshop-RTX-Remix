"""Exercise M4 in generated game roots using a packaged fake runtime. Never starts a real game."""
import argparse
import ctypes
from ctypes import wintypes
import hashlib
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
    evidence = repo / 'out' / 'm4-synthetic' / (args.config.lower() + '-' + str(os.getpid()) + time.strftime('-%Y%m%dT%H%M%S'))
    evidence.mkdir(parents=True, exist_ok=True)  # a reused PID must not fail the run
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
    # Synthetic R6 payloads only: the production tier files belong to task T6.
    tier_folder = scratch / 'tier-package'
    tier_package = scratch / 'tiers.gma'
    gmapack = repo / 'tools/gmapack/gmapack.py'
    subprocess.run([sys.executable, str(gmapack), 'extract', '--file', str(package_a), '--out', str(tier_folder), '--quiet'],
                   check=True, capture_output=True)
    tier_manifest = tier_folder / 'native/manifest.json'
    manifest = json.loads(tier_manifest.read_text(encoding='utf-8'))
    for tier, value in (('medium', 768), ('low', 512)):
        path = tier_folder / f'native/payload/config/dxvk-tiers/{tier}.conf'
        path.parent.mkdir(parents=True, exist_ok=True)
        data = f'rtx.skyProbeSide = {value}\n'.encode('ascii')
        path.write_bytes(data)
        manifest['files'][path.relative_to(tier_folder).as_posix()] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    write_json(tier_manifest, manifest)
    subprocess.run([sys.executable, str(gmapack), 'create', '--folder', str(tier_folder), '--out', str(tier_package),
                    '--preserve-case', '--quiet'], check=True, capture_output=True)
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
                         'NL_M4_BAD_CMDLINE', 'NL_M4_FAIL_ATTACH', 'NL_M4_SEH_ATTACH', 'DXVK_AFTERMATH_DUMP_PATH'):
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
            # nlctl writes UTF-8 whatever the code page; the locale default (cp1252 on CI) garbles non-ASCII.
            run = subprocess.run([str(args.nlctl), command, str(self.root), '--json'], env=env, capture_output=True,
                                 text=True, encoding='utf-8')
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
        check(probe['dll_directory'] == '', f'{game.name}: the DLL directory must stay the default (the runtime folder goes on PATH)')
        added = activation['launch_arguments']['added']
        check(probe['command_line_w'] == original + (' ' + ' '.join(added) if added else ''), f'{game.name}: appended arguments differ')
        for variable in activation['environment']['set']:
            check(probe['environment'][variable['name']] == variable['value'], f'{game.name}: environment differs')
        for layer in activation['layer_copies']:  # ADR 0036: the runtime reads copies, byte for byte the package's files
            check((game.root / layer['copy']).read_bytes() == (game.root / layer['source']).read_bytes(),
                  f'{game.name}: {layer["copy"]} is not a copy of {layer["source"]}')
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

        # ADR 0018: after the package's arguments, a borderless window the size of the primary display
        # (no size when the display cannot be read); nlctl reads the same display.
        added = first['activation']['launch_arguments']['added']
        check(added[:5] == ['-dxlevel', '90', '-nod3d9ex', '-windowed', '-noborder'], f'RTX session is not a borderless window: {added}')
        check(added[5:] == [] or (len(added) == 9 and added[5] == '-w' and added[7] == '-h' and added[6].isdigit() and added[8].isdigit()),
              f'window size malformed: {added}')
        check(game.cli('activation')['launch_args'] == added, 'CLI and startup window differ')
        passed('an RTX session is a borderless window the size of the display; CLI agrees')

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

        # R19 (proxy F-02): that stale "active" is why an RTX start also holds
        # garrysmod/data/native-loader/rtx-session.txt for its whole life. Windows deletes it when the
        # game ends, however it ends, and no off-switch start makes one: the companion's guard needs it.
        marker = game.status.with_name('rtx-session.txt')
        check(not marker.exists(), f'a session marker outlived its game: {marker}')
        ready = game.root / 'marker.ready'
        holder = subprocess.Popen([str(game.exe), '--m4-hold', str(ready)], cwd=game.root,
                                  env={k: v for k, v in os.environ.items() if k != 'NATIVE_LOADER_DISABLE'},
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 15
            while not ready.exists() and time.monotonic() < deadline and holder.poll() is None:
                time.sleep(0.02)
            check(ready.exists(), 'the RTX holder did not start')
            held = json.loads(game.status.read_text(encoding='utf-8'))
            check(held['process_id'] == holder.pid and held['activation']['outcome'] == 'active', f'holder status: {held["activation"]}')
            check(any(note.startswith('RTX session marker held') for note in held['session']['notes']),
                  f'the marker is not reported: {held["session"]["notes"]}')
            check(marker.exists() and marker.name in os.listdir(marker.parent), 'a running RTX start holds no session marker')
            try:
                marker.unlink()
            except OSError:
                pass
            else:
                check(False, 'another process deleted the session marker of a running game')
            check(marker.exists(), 'the session marker of a running game went')
        finally:
            holder.kill()  # ended as a crash ends it: Windows still closes the handle
            holder.wait(timeout=10)
        deadline = time.monotonic() + 5
        while marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        check(not marker.exists(), 'the session marker outlived a killed game')
        vanilla(game.run(extra=['-nonativeloader'], report_expected=False))
        check('\n"activation":{"outcome":"active"' in game.status.read_text(encoding='utf-8'), 'the stale report changed')
        check(not marker.exists(), 'an off-switch start made a session marker')
        marker.write_text('session_token=1-1\n', encoding='ascii')  # what a power loss would leave
        game.config['remix'] = {'enabled': False}
        game.save()
        vanilla(game.run())
        check(not marker.exists(), 'a start without RTX kept a leftover session marker')
        game.config['remix']['enabled'] = True
        game.save()
        passed('an RTX start holds its session marker until the game ends; off-switch and RTX-off starts have none')

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

        # ADR 0036 (R3-017): the runtime gets short copies of the package's layers, whatever the payload
        # folder's name; a copy changed by hand is written again, and one that cannot be written leaves
        # its source in the list, with a note.
        copies = Game('layer-copies')
        status = active(copies, copies.run())
        layer_copies = status['activation']['layer_copies']
        check([layer['copy'] for layer in layer_copies] == ['native-loader/remix/rtx-1.conf', 'native-loader/remix/dxvk-1.conf'],
              f'layer copies: {layer_copies}')
        # A computer without an NVIDIA GPU (CI's runner) also gets the loader's non-NVIDIA layer (ADR 0030).
        tier = status['activation']['performance_tier']
        loader_layers = [tier['layer']] if tier['layer'] else []
        if status['activation']['non_nvidia']:
            loader_layers.append('native-loader/remix/non-nvidia.conf')
        memory_layer = 'native-loader/remix/memory.conf'
        check(status['activation']['layers']['dxvk'] == [*loader_layers, 'native-loader/remix/dxvk-1.conf', memory_layer, 'dxvk.conf'],
              f'the runtime is not given the copy: {status["activation"]["layers"]}')
        # R13 (ADR 0101): the memory profile's D3D9 layer follows the package's layers.
        memory = status['activation']['memory']
        check(memory['layer'] == memory_layer and memory['profile'] in ('below_minimum', 'minimum', 'recommended', 'high'),
              f'memory profile: {memory}')
        memory_text = (copies.root / memory_layer).read_bytes().decode('ascii')
        check(f"\r\nd3d9.managedTextureBudgetMiB = {memory['managed_texture_budget_mib']}\r\n" in memory_text and 'rtx.' not in memory_text,
              f'memory layer: {memory_text!r}')
        rtx_copy = copies.root / layer_copies[0]['copy']
        rtx_copy.write_text('rtx.test = False\n', encoding='ascii')
        active(copies, copies.run())
        dxvk_copy = copies.root / layer_copies[1]['copy']
        dxvk_copy.unlink()
        dxvk_copy.mkdir()  # a folder in its place: the copy cannot be written
        result = copies.run()
        fallback = active(copies, result)
        check(result[0]['environment']['DXVK_CONFIG_FILE'] == ','.join([*loader_layers, layer_copies[1]['source'], memory_layer, 'dxvk.conf']),
              f'an unwritten copy did not fall back to its source: {result[0]["environment"]}')
        check([layer['copy'] for layer in fallback['activation']['layer_copies']] == ['native-loader/remix/rtx-1.conf'],
              'an unwritten copy is still reported as used')
        check(any('was not written' in note for note in fallback['session']['notes']), 'no note for the unwritten copy')
        # A memory layer that cannot be written is not listed: the runtime then sizes its own budgets.
        (copies.root / memory_layer).unlink()
        (copies.root / memory_layer).mkdir()
        result = copies.run()
        unwritten = active(copies, result)
        check(memory_layer not in unwritten['activation']['layers']['dxvk'] and
              memory_layer not in result[0]['environment']['DXVK_CONFIG_FILE'], 'an unwritten memory layer is still listed')
        check(unwritten['activation']['memory']['layer'] == '' and
              any('memory layer was not written' in note for note in unwritten['activation']['notes']),
              'no note for the unwritten memory layer')
        (copies.root / memory_layer).rmdir()
        passed('the runtime reads short copies of the package\'s layers and the memory layer; a changed copy is rewritten, an unwritable one falls back')

        dumps = Game('gpu-crash-diagnostics')
        dumps.config['diagnostics'] = {'gpu_crash_dumps': 'next_start'}
        dumps.save()
        preview = dumps.cli('activation')  # no journal yet; preview must not create the marker
        marker = dumps.root / 'native-loader/remix/gpu-crash-dumps.used'
        check(not marker.exists(), 'CLI consumed next_start')
        dumps.config['remix'] = {'enabled': False}
        dumps.save()
        vanilla(dumps.run())
        check(not marker.exists(), 'RTX-off start consumed next_start')
        dumps.config['remix']['enabled'] = True
        dumps.save()
        config_bytes = (dumps.root / 'native-loader/config.json').read_bytes()
        on = active(dumps, dumps.run())
        diagnostic_layer = 'native-loader/remix/diagnostics.conf'
        layers = on['activation']['layers']['dxvk']
        check(layers[-2:] == [diagnostic_layer, 'dxvk.conf'], f'diagnostics layer order: {layers}')
        text = (dumps.root / diagnostic_layer).read_text(encoding='utf-8')
        for option in ('dxvk.enableAftermath = True', 'dxvk.enableAftermathResourceTracking = True', 'rtx.enableGpuCrashState = True'):
            check(option in text, f'missing diagnostic option {option}')
        destination = dumps.root / 'native-loader/logs/gpu'
        requested = {entry['name']: entry['value'] for entry in on['activation']['environment']['requested']}
        check(Path(requested['DXVK_AFTERMATH_DUMP_PATH']) == destination and destination.is_dir(), 'dump destination not prepared')
        check(marker.is_file(), 'one-start marker absent')
        off = active(dumps, dumps.run())
        check(diagnostic_layer not in off['activation']['layers']['dxvk'], 'next_start repeated')
        check(not any(entry['name'] == 'DXVK_AFTERMATH_DUMP_PATH' for entry in off['activation']['environment']['set']), 'dump env repeated')
        marker.unlink()  # documented re-arm
        ready = dumps.cli('activation')
        check(not marker.exists(), 'activation preview consumed a rearmed request')
        check(any(entry['name'] == 'DXVK_AFTERMATH_DUMP_PATH' for entry in ready['env']), 'preview missed rearmed request')
        rearmed = active(dumps, dumps.run(env_extra={'DXVK_AFTERMATH_DUMP_PATH': 'player-choice'}))
        check(diagnostic_layer in rearmed['activation']['layers']['dxvk'], 'rearmed diagnostics missing')
        check((dumps.root / 'native-loader/config.json').read_bytes() == config_bytes, 'next_start rewrote config')
        dumps.config['diagnostics']['gpu_crash_dumps'] = 'always'
        dumps.save()
        for _ in range(2):
            check(diagnostic_layer in active(dumps, dumps.run())['activation']['layers']['dxvk'], 'always not retained')
        dumps.config['diagnostics']['gpu_crash_dumps'] = 'off'
        dumps.save()
        check(diagnostic_layer not in active(dumps, dumps.run())['activation']['layers']['dxvk'], 'off still lists diagnostics')
        check(not marker.exists(), 'off did not rearm next_start')
        dumps.config['diagnostics']['gpu_crash_dumps'] = 'next_start'
        dumps.save()
        config_bytes = (dumps.root / 'native-loader/config.json').read_bytes()
        check(diagnostic_layer in active(dumps, dumps.run())['activation']['layers']['dxvk'], 'next_start -> off -> next_start did not capture again')
        check(marker.is_file(), 'rearmed request did not consume its marker')
        check(diagnostic_layer not in active(dumps, dumps.run())['activation']['layers']['dxvk'], 'rearmed request repeated')
        check((dumps.root / 'native-loader/config.json').read_bytes() == config_bytes, 'off/rearm rewrote config')
        passed('GPU dumps: correct layer/path, next_start once, read-only preview, manual and off-mode rearm, always/off; config preserved')

        blocked = Game('gpu-diagnostics-blocked')
        blocked.config['diagnostics'] = {'gpu_crash_dumps': 'next_start'}
        blocked.save()
        blocker = blocked.root / 'native-loader/logs/gpu'
        blocker.parent.mkdir(parents=True, exist_ok=True)
        blocker.write_text('player file in the way', encoding='ascii')
        status = active(blocked, blocked.run())
        check(diagnostic_layer not in status['activation']['layers']['dxvk'], 'blocked diagnostics layer still listed')
        check(not (blocked.root / 'native-loader/remix/gpu-crash-dumps.used').exists(), 'failed preparation consumed next_start')
        check(blocker.read_text(encoding='ascii') == 'player file in the way', 'blocked dump path was overwritten')
        check(any('GPU diagnostics were not enabled' in note for note in status['activation']['notes']), 'no diagnostic preparation note')
        rollback_dumps = Game('gpu-diagnostics-rollback')
        rollback_dumps.config['diagnostics'] = {'gpu_crash_dumps': 'always'}
        rollback_dumps.save()
        rolled_back = rollback_dumps.run(env_extra={'NL_M4_FAIL_ATTACH': '1', 'DXVK_AFTERMATH_DUMP_PATH': 'player-folder'})
        vanilla(rolled_back, {'DXVK_AFTERMATH_DUMP_PATH': 'player-folder'})
        check(rolled_back[1]['activation']['rolled_back'], 'diagnostic session failure did not roll back')
        passed('diagnostics preparation failure preserves RTX and request; activation rollback restores the player dump destination')

        policy = Game('performance-policy')
        policy.config['remix'] = {'performance_tier': 'low'}
        policy.save()
        low_status = active(policy, policy.run())
        low = low_status['activation']['performance_tier']
        if not low_status['activation']['non_nvidia']:  # unknown GPU queries also honor an override
            check(low['tier'] == 'low' and low['source'] == 'config', f'old package explicit low fallback: {low}')
            text = (policy.root / low['layer']).read_text(encoding='utf-8')
            check('rtx.opacityMicromap.cache.maxBudgetSizeMB = 512' in text, 'built-in fallback not written')
        else:
            check(not low['layer'], 'non-NVIDIA adapter received a tier layer')
        check(policy.cli('activation')['performance_tier'] == low, 'CLI and bootstrap tiers differ')
        policy.config['remix']['performance_tier'] = 'invalid-tier'
        policy.save()
        invalid = active(policy, policy.run())
        check(any('remix.performance_tier' in note for note in invalid['activation']['notes']), 'invalid tier was not reported')
        log = (policy.root / 'native-loader/logs/loader.log').read_text(encoding='utf-8')
        check('activation.performance_tier=' in log and 'using auto' in log, 'tier or config note missing from bootstrap log')
        policy.config['diagnostics'] = {'gpu_crash_dumps': True}
        policy.save()
        invalid_dumps = active(policy, policy.run())
        check(diagnostic_layer not in invalid_dumps['activation']['layers']['dxvk'], 'invalid dump mode enabled diagnostics')
        check(any('diagnostics.gpu_crash_dumps' in note and 'using off' in note for note in invalid_dumps['activation']['notes']),
              'invalid dump mode did not recover with a note')
        passed('performance tier: fallback/non-NVIDIA behavior, CLI equality, invalid value note and bootstrap log')

        packaged = Game('performance-package', tier_package)
        for choice in ('low', 'medium', 'high'):
            packaged.config['remix'] = {'performance_tier': choice}
            packaged.save()
            status = active(packaged, packaged.run())
            tier = status['activation']['performance_tier']
            if choice == 'high':
                check('native-loader/remix/tier.conf' not in status['activation']['layers']['dxvk'], 'high run listed a stale low/medium tier.conf')
                effective_env = {entry['name']: entry['value'] for entry in status['activation']['environment']['set']}
                check('native-loader/remix/tier.conf' not in effective_env.get('DXVK_CONFIG_FILE', ''), 'high run passed stale tier.conf in the environment')
                if not status['activation']['non_nvidia']:
                    check((packaged.root / 'native-loader/remix/tier.conf').is_file(), 'high-run regression did not retain a leftover tier file')
            if not status['activation']['non_nvidia']:
                check(tier['tier'] == choice and tier['source'] == 'config', f'package tier override: {tier}')
                check(bool(tier['layer']) == (choice != 'high'), f'package tier layer: {tier}')
                if choice != 'high':
                    check(status['activation']['layers']['dxvk'][0] == 'native-loader/remix/tier.conf', 'tier copy not first')
                    check(any(entry['copy'] == tier['layer'] and f'dxvk-tiers/{choice}.conf' in entry['source']
                              for entry in status['activation']['layer_copies']), 'wrong tier source')
            else:
                check(not tier['layer'], 'non-NVIDIA got packaged tier layer')
        passed('package tier files: low and medium copied from verified runtime payload, high lists none')

        chosen = Game('user-window')
        arguments = active(chosen, chosen.run(extra=['-fullscreen', '-w', '1280', '-h', '720']))['activation']['launch_arguments']
        check(arguments['added'] == ['-dxlevel', '90', '-nod3d9ex'], f'user window mode overridden: {arguments}')
        check(arguments['already_present'] == ['-fullscreen'], f'user window mode not reported: {arguments}')
        passed('a window mode the user chose stays as it is')

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
        check(not json.loads(missing.journal.read_text(encoding='utf-8'))['current']['packages'], 'explicit removal kept package')
        passed('missing allowlisted source is kept; explicit allowlist removal removes it')

        workshop = Game('workshop-disabled', workshop=True)
        workshop_status = active(workshop, workshop.run())
        # M6: the report names the deployed package's source for the companion's restart notice.
        sources = workshop_status['packages']
        check(len(sources) == 1 and sources[0]['source'] == 'workshop' and sources[0]['label'] == '123' and
              sources[0]['id'] == package_id, f'status.json packages: {sources}')
        addon_list = workshop.root / 'garrysmod/cfg/addonnomount.txt'
        addon_list.parent.mkdir(parents=True, exist_ok=True)
        addon_list.write_text('"addonnomount" { "1" "123" }', encoding='ascii')
        vanilla(workshop.run())
        check(not json.loads(workshop.journal.read_text(encoding='utf-8'))['current']['packages'], 'disabled Workshop source retained')
        passed('explicit Workshop disable removes the package')

        # ADR 0025: Steam's record of the item through a subscription's life. While an update downloads,
        # Steam keeps the item in appworkshop_4000.acf; after the user unsubscribed it drops it and its
        # files (at the next launch from Steam), which removes the package.
        steam = Game('workshop-unsubscribed', workshop=True)
        acf = steam.case / 'steamapps/workshop/appworkshop_4000.acf'
        listed = ('"AppWorkshop" { "appid" "4000" "WorkshopItemsInstalled" { "123" { "size" "1" } } '
                  '"WorkshopItemDetails" { "123" { "subscribedby" "1" } } }')
        acf.write_text(listed, encoding='ascii')
        active(steam, steam.run())
        payload = steam.root / json.loads(steam.journal.read_text(encoding='utf-8'))['current']['packages'][0]['payload']
        check(payload.is_dir(), f'payload not deployed: {payload}')
        shutil.move(str(steam.source.parent), str(steam.case / 'item-aside'))  # an update replacing the folder
        updating = active(steam, steam.run())
        check(updating['deployment']['outcome'] == 'kept', f'an update in progress must keep the package: {updating["deployment"]}')
        acf.write_text('"AppWorkshop" { "appid" "4000" "WorkshopItemsInstalled" { } "WorkshopItemDetails" { } }', encoding='ascii')
        gone = steam.run()
        vanilla(gone)
        check(not json.loads(steam.journal.read_text(encoding='utf-8'))['current']['packages'], 'unsubscribed Workshop item retained')
        check(not payload.exists(), f'the payload of an unsubscribed item stayed: {payload}')
        gone_status = gone[1]
        check(any('not subscribed' in skip['reason'] for skip in gone_status['deployment']['skipped']), f'reason: {gone_status["deployment"]}')
        shutil.move(str(steam.case / 'item-aside'), str(steam.source.parent))  # subscribed again
        acf.write_text(listed, encoding='ascii')
        active(steam, steam.run())
        passed('an update in progress keeps the package; an unsubscribed Workshop item is removed, and comes back when subscribed again')

        # ADR 0111 (R19 H2): a content package without the allowlist deploys only from an item an
        # account here subscribed to. One a server or the game downloaded (steamworks.DownloadUGC)
        # is installed and recorded too, but its details name no subscriber.
        subscriptions = Game('content-subscriptions', workshop=True)
        source = scratch / 'content-src'
        mod_bytes = b'#usda 1.0' + bytes([10])
        mod_rel = 'native/root/rtx-remix/mods/nl_h2_mod/mod.usda'
        (source / mod_rel).parent.mkdir(parents=True)
        (source / mod_rel).write_bytes(mod_bytes)
        write_json(source / 'native/manifest.json', {
            'schema': 1, 'id': 'h2-content', 'version': '1.0.0', 'kinds': ['root-files'],
            'root_files': [{'path': 'rtx-remix/mods/nl_h2_mod'}],
            'files': {mod_rel: {'size': len(mod_bytes), 'sha256': hashlib.sha256(mod_bytes).hexdigest()}}})
        (source / 'addon.json').write_text(json.dumps({'title': 'h2', 'type': 'servercontent', 'tags': []}), encoding='utf-8')
        item = subscriptions.case / 'steamapps/workshop/content/4000/456/content.gma'
        item.parent.mkdir(parents=True)
        subprocess.run([sys.executable, str(gmapack), 'create', '--folder', str(source), '--out', str(item), '--quiet'],
                       check=True, capture_output=True)
        record = subscriptions.case / 'steamapps/workshop/appworkshop_4000.acf'

        def steam_record(subscribed):
            by = ' "subscribedby" "12345678"' if subscribed else ''
            record.write_text('"AppWorkshop" { "appid" "4000" "WorkshopItemsInstalled" { "123" { "size" "1" } "456" { "size" "1" } } '
                              '"WorkshopItemDetails" { "123" { "subscribedby" "12345678" } '
                              '"456" { "manifest" "9" "timetouched" "1"' + by + ' } } }', encoding='ascii')
        deployed_mod = subscriptions.root / 'rtx-remix/mods/nl_h2_mod/mod.usda'
        steam_record(False)
        downloaded = active(subscriptions, subscriptions.run())
        check(not deployed_mod.exists(), 'content from a downloaded item nobody subscribed to was deployed')
        check(not any('456' in skip['package'] for skip in downloaded['deployment']['skipped']), 'an unsubscribed download was listed')
        steam_record(True)
        active(subscriptions, subscriptions.run())
        check(deployed_mod.read_bytes() == mod_bytes, 'a subscribed content package was not deployed')
        steam_record(False)
        dropped = active(subscriptions, subscriptions.run())
        check(not deployed_mod.exists(), 'content from an item no longer subscribed stayed')
        check(any('456' in skip['package'] and 'only because the game or a server downloaded it' in skip['reason']
                  for skip in dropped['deployment']['skipped']), f'reason: {dropped["deployment"]["skipped"]}')
        check(item.exists(), 'a Workshop file was touched')
        steam_record(True)
        active(subscriptions, subscriptions.run())
        check(deployed_mod.exists(), 'a subscribed content package did not come back')
        record.unlink()
        blind = active(subscriptions, subscriptions.run())
        check(deployed_mod.exists() and blind['deployment']['outcome'] == 'unchanged', 'a missing Steam record removed deployed content')
        passed('content packages come only from subscriptions; a deployed one goes when no account here subscribes, '
               'and stays when Steam\'s record cannot be read')

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
        check(result[1]['deployment']['outcome'] == 'failed' and invalid.journal.read_text(encoding='utf-8') == 'not a journal', 'invalid journal changed')
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
        check(fallback.startswith('-dxlevel 90 -nod3d9ex -windowed -noborder') and
              fallback == ' '.join(refused.cli('activation')['launch_args']), f'fallback options incorrect: {fallback}')
        active(refused, refused.run(extra=fallback.split(), env_extra={'NL_M4_BAD_CMDLINE': '1'}))
        passed('refused swap rolls back; supplying the reported arguments permits activation')

        wrong_cwd = Game('wrong-cwd')
        result = wrong_cwd.run(cwd=wrong_cwd.case)
        vanilla(result)
        check('working directory' in result[1]['activation']['reason'], 'working-directory precondition missing')
        bad_size = Game('missing-layer')
        status = active(bad_size, bad_size.run())
        bad_size.source.unlink()
        layer_path = bad_size.root / status['activation']['layer_copies'][0]['source']  # the package's file, not its copy
        layer_path.write_bytes(b'')
        result = bad_size.run()
        vanilla(result)
        check('changed since it was deployed' in result[1]['activation']['reason'], 'layer-size precondition missing')
        # The runtime DLL changed in place (same size, new time) while deployment is held back (its
        # source is gone, so the last good version stays): not loaded (R1-008).
        changed = Game('changed-runtime')
        status = active(changed, changed.run())
        changed.source.unlink()
        runtime_dll = Path(status['activation']['runtime']['folder']) / 'd3d9.dll'
        image = bytearray(runtime_dll.read_bytes())
        image[-1] ^= 0xFF
        runtime_dll.write_bytes(bytes(image))
        result = changed.run()
        vanilla(result)
        check('changed since it was deployed' in result[1]['activation']['reason'], 'changed runtime DLL was activated')
        passed('working-directory, layer and runtime size-and-time preconditions prevent activation')

        too_long = Game('long-runtime-path')
        active(too_long, too_long.run())
        too_long.source.unlink()
        long_state = json.loads(too_long.journal.read_text(encoding='utf-8'))
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

        memory_before = {name: user.status.with_name(name).read_bytes()
                         for name in ('memory.json', 'memory.json.tmp') if user.status.with_name(name).exists()}
        user.cli('uninstall')
        check(not user.status.exists(), 'uninstall left generated status')
        if memory_before:
            for name, before in memory_before.items():
                check(user.status.with_name(name).read_bytes() == before, 'uninstall changed retained memory diagnostics')
        else:
            check(not user.status.parent.exists(), 'uninstall left an empty status folder')
        passed('nlctl uninstall removes status and retains local memory diagnostics when present')

        # ADR 0056: the catalog-verified RTX package whose early guard view cannot be prepared (here,
        # an initializer a game update changed) still starts RTX, and status says why; the companion's
        # guard autorun installs later instead. Loader 0.10.0 refused RTX for this.
        guarded_package = scratch / 'guarded-package'
        subprocess.run([sys.executable, str(repo / 'tools/package_runtime.py'), '--runtime', str(args.runtime), '--out',
                        str(guarded_package), '--id', 'gmod-rtx-remix', '--version', '1.0.0', '--no-system-vulkan', '--json'],
                       cwd=repo, check=True, capture_output=True, text=True)
        manifest_path = guarded_package / 'native/manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        for rel, data in {'native/root/garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll': b'synthetic verified client helper',
                          'native/root/garrysmod/addons/nativeloader/lua/autorun/_nativeloader_guard.lua':
                              b'-- NATIVELOADER_RENDER_GUARD_V2' + bytes([10])}.items():
            (guarded_package / rel).parent.mkdir(parents=True, exist_ok=True)
            (guarded_package / rel).write_bytes(data)
            manifest['files'][rel] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        manifest['requires_remix'] = True
        manifest['kinds'] += ['lua-binary-module', 'lua-addon']
        manifest['root_files'] = manifest.get('root_files', []) + [
            {'path': 'garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll'}, {'path': 'garrysmod/addons/nativeloader'}]
        write_json(manifest_path, manifest)
        guarded = Game('guard-unavailable')
        guarded.config = {'schema': 1, 'allow': {'dev_folders': [str(guarded_package)]}}
        guarded.save()
        initializer = guarded.root / 'garrysmod/lua/includes/init.lua'
        initializer.parent.mkdir(parents=True)
        initializer.write_bytes(b'-- a generated initializer that no stock hash matches' + bytes([10]))
        status = active(guarded, guarded.run())
        notes = status['session']['notes']
        check(any(note.startswith('early render guard unavailable (Unsupported stock Lua initializer') and
                  note.endswith('the companion guard installs at autorun time instead') for note in notes),
              f'guard-unavailable: the reason is not reported: {notes}')
        check(not status['errors'], f'guard-unavailable: reported as an error: {status["errors"]}')
        check(not (guarded.root / 'native-loader/presentation').exists() or
              not any(guarded.root.glob('native-loader/presentation/render-guard-*.lua')), 'a guard view was written')
        passed('an RTX package whose early guard view cannot be prepared still starts RTX and says why')

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
