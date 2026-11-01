"""Exercise the real rundll32 observer against copied synthetic hosts; never run GMod."""
import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel.OpenProcess.restype = wintypes.HANDLE
kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
kernel.TerminateProcess.restype = wintypes.BOOL
kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel.WaitForSingleObject.restype = wintypes.DWORD
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
kernel.CloseHandle.restype = wintypes.BOOL


def wait_for(predicate, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = predicate()
            if result:
                return result
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(0.02)
    raise AssertionError('timed out waiting for observer fixture')


def write(root, path, text):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--proxy', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    scratch = args.scratch.resolve()
    assert scratch.is_relative_to(repo / 'out') and scratch != repo / 'out', scratch
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, NATIVE_LOADER_EXIT_REPORT='quiet')
    env.pop('NATIVE_LOADER_DISABLE', None)
    # No Remix automation/consent variable is set; this host has no runtime at all.
    rundll = Path(os.environ['SystemRoot']) / 'System32/rundll32.exe'
    cases = [
        ('clean', 0, '', 'clean'),
        ('clean-noise', 0, 'VK_ERROR_DEVICE_LOST (nonfatal)', 'clean'),
        ('oom', 0xC0000017, '', 'out_of_memory'),
        ('commit-limit', 0xC000012D, '', 'out_of_memory'),
        ('access', 0xC0000005, '', 'crash'),
        ('failfast', 0xC0000409, '', 'crash'),
        ('stack', 0xC00000FD, '', 'crash'),
        ('cpp', 0xE06D7363, '', 'crash'),
        ('device', 1, 'Exiting after GPU device loss', 'device_lost'),
        ('device-zero', 0, 'Exiting after GPU device loss', 'device_lost'),
        ('allocation', 1, 'Memory allocation failed', 'allocation_failed'),
        ('cs', 1, 'Exception on CS thread', 'cs_exception'),
        ('gpu-marker', 1, '', 'device_lost'),
        ('dump', 0, '', 'crash'),
        ('oom-dump', 1, '', 'out_of_memory'),
        ('commit-sample', 1, '', 'likely_out_of_memory'),
    ]
    for name, code, log, expected in cases:
        root = scratch / (name + '-测试-' + str(time.time_ns()))
        (root / 'bin/win64').mkdir(parents=True)
        host = root / 'bin/win64/gmod.exe'
        dll = root / 'bin/win64/winmm.dll'
        shutil.copy2(args.host, host)
        shutil.copy2(args.proxy, dll)
        write(root, 'native-loader/config.json', '{"schema":1,"diagnostics":{"memory_telemetry":"off"}}')
        # An export invoked manually has no inherited, identity-checked game handle. DllMain's
        # rundll32 guard must leave the root unchanged, even with loader configuration present.
        subprocess.run([str(rundll), str(dll) + ',NativeLoaderObserve', '123', '124',
                        str(os.getpid()), '123', '124', '-'], env=env, check=True, timeout=10)
        assert not (root / 'native-loader/logs').exists()
        process = subprocess.Popen([str(host), '--m4-hold', str(root / 'ready')], cwd=root, env=env)
        observer = None
        try:
            wait_for(lambda: (root / 'ready').exists())
            notes = (root / 'native-loader/logs/loader.log').read_text(encoding='utf-8')
            pid = int(re.search(r'exit observer ready: pid=(\d+)', notes).group(1))
            observer = kernel.OpenProcess(0x100000, False, pid)  # SYNCHRONIZE, pins the exact observer
            assert observer, ctypes.get_last_error()
            assert kernel.WaitForSingleObject(observer, 0) == 258  # alive while game is alive
            assert not list((root / 'native-loader/logs').glob('sessions/**/exit-report.json'))
            if log:
                write(root, 'rtx-remix/logs/remix-dxvk.log', log + '\n')
            if name == 'gpu-marker':
                write(root, 'rtx-remix/logs/last_gpu_crash.json', '{"event":"device_lost"}')
            if name == 'dump':
                write(root, 'rtx-remix/logs/.sentry-native/reports/fresh.dmp', 'synthetic dump')
            if name == 'oom-dump':
                write(root, 'crashes/fresh.dmp', 'OUT OF MEMORY!')
            if name == 'commit-sample':
                status = json.loads((root / 'garrysmod/data/native-loader/status.json').read_text(encoding='utf-8'))
                write(root, 'garrysmod/data/native-loader/memory.json', json.dumps({
                    'schema': 1, 'session_token': status['session_token'],
                    'time_utc': datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
                    'commit_total': 90 << 30, 'commit_limit': 90 << 30}))
            assert kernel.TerminateProcess(wintypes.HANDLE(int(process._handle)), code)
            process.wait(timeout=10)
            assert kernel.WaitForSingleObject(observer, 12000) == 0, 'quiet observer did not exit'
            marker = json.loads((root / 'native-loader/logs/session-start.json').read_text(encoding='utf-8'))
            end = marker['end']
            assert end['exit_code'] == code and end['previous_session']['reason'] == expected, end
            assert end['process_id'] == process.pid and end['dialog_suppressed'] is True
            assert end['exit_filetime'] >= end['start_filetime']
            reports = list((root / 'native-loader/logs').glob('sessions/**/exit-report.json'))
            if expected == 'clean':
                assert not reports and end['abnormal'] is False
            else:
                assert len(reports) == 1 and end['abnormal'] is True
                assert json.loads(reports[0].read_text(encoding='utf-8')) == end
            print('PASS', name, hex(code), expected, flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            if observer:
                kernel.WaitForSingleObject(observer, 12000)
                kernel.CloseHandle(observer)
        # Keep failed cases for diagnosis; remove only this verified in-workspace generated root.
        assert root.resolve().is_relative_to(scratch) and root.resolve() != scratch
        shutil.rmtree(root)

    for policy in ('config', 'environment', 'disable-file', 'command', 'off', 'non-game', 'chromium'):
        root = scratch / (policy + '-' + str(time.time_ns()))
        (root / 'bin/win64').mkdir(parents=True)
        host = root / ('bin/win64/other.exe' if policy == 'non-game' else 'bin/win64/gmod.exe')
        shutil.copy2(args.host, host)
        shutil.copy2(args.proxy, host.with_name('winmm.dll'))
        write(root, 'native-loader/config.json', json.dumps({'schema': 1, 'enabled': policy != 'config'}))
        child_env = dict(env)
        if policy == 'environment':
            child_env['NATIVE_LOADER_DISABLE'] = '1'
        if policy == 'off':
            child_env['NATIVE_LOADER_EXIT_REPORT'] = 'off'
        if policy == 'disable-file':
            write(root, 'native-loader/disable', '')
        arguments = ['--m4-hold', str(root / 'ready')]
        if policy == 'command':
            arguments.append('-nonativeloader')
        if policy == 'chromium':
            arguments.append('--type=renderer')
        process = subprocess.Popen([str(host), *arguments], cwd=root, env=child_env)
        try:
            wait_for(lambda: (root / 'ready').exists())
        finally:
            process.terminate()
            process.wait(timeout=10)
        notes = root / 'native-loader/logs/loader.log'
        assert not notes.exists() or 'exit observer ready' not in notes.read_text(encoding='utf-8')
        assert not list((root / 'native-loader/logs').glob('sessions/**/exit-report.json'))
        assert root.resolve().is_relative_to(scratch) and root.resolve() != scratch
        shutil.rmtree(root)
        print('PASS observer disabled:', policy, flush=True)
    print(f'PASS observer integration: {len(cases) + 7} synthetic cases')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
