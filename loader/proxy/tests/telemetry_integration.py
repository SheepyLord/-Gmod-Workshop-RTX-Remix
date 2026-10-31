"""Real bootstrap worker in generated roots; the EXE is the synthetic proxy test host."""
import argparse
import csv
from datetime import datetime
import io
import json
from pathlib import Path
import shutil
import subprocess
import time


def wait_for(predicate, timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = predicate()
            if result:
                return result
        except (OSError, ValueError, KeyError):
            pass  # atomic replacement may briefly share-lock a diagnostic file
        time.sleep(0.05)
    raise AssertionError('timed out waiting for bootstrap diagnostics')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--proxy', type=Path, required=True)
    parser.add_argument('--nlctl', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    args = parser.parse_args()
    args.host, args.proxy, args.nlctl, args.scratch = (path.resolve() for path in (args.host, args.proxy, args.nlctl, args.scratch))
    args.scratch.mkdir(parents=True, exist_ok=True)

    def fixture(name, policy):
        root = args.scratch / name
        if root.exists():
            shutil.rmtree(root)
        (root / 'bin/win64').mkdir(parents=True)
        (root / 'native-loader/logs').mkdir(parents=True)
        shutil.copy2(args.host, root / 'bin/win64/gmod.exe')
        shutil.copy2(args.proxy, root / 'bin/win64/winmm.dll')
        (root / 'native-loader/config.json').write_text(json.dumps(policy), encoding='utf-8')
        return root

    def start(root):
        # This is nl_proxy_host.exe renamed to match the bootstrap's activation gate. No GMod code.
        return subprocess.Popen([str(root / 'bin/win64/gmod.exe'), '--m4-hold', str(root / 'ready')], cwd=root)

    def stop(process):
        process.terminate()
        process.wait(timeout=10)

    root = fixture('on', {'schema': 1})
    memory = root / 'native-loader/logs/memory.csv'
    snapshot = root / 'garrysmod/data/native-loader/memory.json'
    process = start(root)
    try:
        wait_for(lambda: (root / 'ready').exists())
        wait_for(lambda: memory.read_text(encoding='utf-8') if memory.exists() else '')
        def two_rows():
            rows = list(csv.DictReader(io.StringIO(memory.read_text(encoding='utf-8'))))
            return rows if len(rows) >= 2 else None
        rows = wait_for(two_rows)
        assert all(len(row) == 10 and None not in row for row in rows), rows
        assert int(rows[-1]['private_bytes']) > 0 and int(rows[-1]['system_commit_limit_bytes']) > 0
        assert rows[0]['time_utc'].endswith('Z') and rows[0]['time_utc'] != rows[1]['time_utc']
        interval = (datetime.fromisoformat(rows[1]['time_utc'].replace('Z', '+00:00')) -
                    datetime.fromisoformat(rows[0]['time_utc'].replace('Z', '+00:00'))).total_seconds()
        assert 9.5 <= interval <= 25, interval
        state = wait_for(lambda: json.loads(snapshot.read_text(encoding='utf-8')))
        assert state['session_token'].startswith(str(process.pid) + '-')
        assert not (root / 'native-loader/logs/memory.1.csv').exists()
    finally:
        stop(process)
    print('PASS default-on worker: flushed UTC/byte samples ten seconds apart, latest commit snapshot')

    # The next bootstrap must save the old rows before a new sampler is allowed to append.
    before = memory.read_bytes()
    (root / 'rtx-remix/logs').mkdir(parents=True)
    (root / 'rtx-remix/logs/remix-dxvk.log').write_text('VK_ERROR_DEVICE_LOST\n', encoding='utf-8')
    (root / 'ready').unlink()
    process = start(root)
    try:
        def current_status():
            state = json.loads((root / 'garrysmod/data/native-loader/status.json').read_text(encoding='utf-8'))
            return state if state.get('process_id') == process.pid else None
        status = wait_for(current_status)
        previous = status['previous_session']
        assert previous['reason'] == 'device_lost', previous
        assert (root / previous['folder'] / 'native-loader/logs/memory.csv').read_bytes() == before
        text = subprocess.run([str(args.nlctl), 'status', str(root)], capture_output=True, text=True, check=True).stdout
        result = json.loads(subprocess.run([str(args.nlctl), 'status', str(root), '--json'],
                                           capture_output=True, text=True, check=True).stdout)
        assert 'device_lost' in text and previous['folder'] in text
        assert result['previous_session'] == previous
    finally:
        stop(process)
    print('PASS next-start evidence precedes sampling; nlctl text/JSON show the same previous session')

    root = fixture('off', {'schema': 1, 'diagnostics': {'memory_telemetry': 'off'}})
    memory = root / 'native-loader/logs/memory.csv'
    memory.write_bytes(b'user-owned history\n')
    process = start(root)
    try:
        wait_for(lambda: (root / 'garrysmod/data/native-loader/memory.json').exists())
        assert memory.read_bytes() == b'user-owned history\n'
        assert not (root / 'native-loader/logs/memory-index.json').exists()
    finally:
        stop(process)
    print('PASS off: CSV history untouched, latest-only system commit remains available for the warning')

    root = fixture('disabled', {'schema': 1, 'enabled': False})
    process = start(root)
    try:
        wait_for(lambda: (root / 'ready').exists())
        assert not (root / 'garrysmod/data/native-loader/memory.json').exists()
        assert not (root / 'native-loader/logs/memory.csv').exists()
    finally:
        stop(process)
    print('PASS loader disabled: no diagnostics worker output')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
