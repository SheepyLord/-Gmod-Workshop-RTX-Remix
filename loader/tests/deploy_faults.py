"""CTest for M3: kills nl_fault_host (the deployer, built for tests) just before each file-system
change of a deployment, runs recovery, and checks that the game folder is then exactly as it was
before the deployment or exactly as after it.

Scenarios on gmapack-built packages: a first deployment, an upgrade (new runtime version; root files
replaced, added and removed), a rollback and an uninstall. These runs are real process kills on the
real, durable file system. test_deploy.cpp covers the same scenarios in process, adding interrupted
recoveries and a failure at every change (nl_fault_host --fail-at does the same from outside, for
manual runs). All files go to --scratch.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

KILLED = 99


def check(condition, message):
    if not condition:
        sys.exit('deploy_faults failed: ' + message)


def write_package(folder, manifest_fields, files):
    """Writes a package folder; native/ files are listed in native/manifest.json with real hashes."""
    shutil.rmtree(folder, ignore_errors=True)
    for rel, data in files.items():
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    listed = {rel: {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()} for rel, data in files.items()}
    manifest = {'schema': 1, **manifest_fields, 'files': listed}
    (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest, indent=1), encoding='utf-8')
    (folder / 'addon.json').write_text(json.dumps({'title': folder.name, 'type': 'servercontent', 'tags': []}),
                                       encoding='utf-8')
    return folder


def pack(gmapack, folder, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run([sys.executable, '-I', '-B', gmapack, 'create', '--folder', str(folder), '--out', str(out),
                           '--timestamp', '1700000000', '--quiet', '--force'], capture_output=True, text=True)
    check(proc.returncode == 0, f'gmapack: {proc.stderr}')


MOD = 'native/root/rtx-remix/mods/fault_mod/'


def version(game, src, gmapack, n):
    """Puts version n (1 or 2) of a runtime and a root-files package into the game's addons folder."""
    runtime = {'native/payload/runtime/d3d9.dll': f'MZ-runtime-{n}'.encode(),
               'native/payload/config/rtx.conf': f'rtx.version = {n}\n'.encode()}
    mods = ({MOD + 'mod.usda': b'#usda v1\n', MOD + 'a.dds': b'A'} if n == 1 else
            {MOD + 'mod.usda': b'#usda v2\n', MOD + 'textures/b.dds': b'B'})
    pack(gmapack, write_package(src / f'runtime{n}', {'id': 'fault-runtime', 'version': f'{n}.0.0', 'kinds': ['remix-runtime'],
                                                      'remix': {'entry': 'runtime/d3d9.dll'}}, runtime),
         game / 'garrysmod' / 'addons' / 'runtime.gma')
    pack(gmapack, write_package(src / f'mods{n}', {'id': 'fault-mods', 'version': f'{n}.0.0', 'kinds': ['root-files'],
                                                   'root_files': [{'path': 'rtx-remix/mods/fault_mod'}]}, mods),
         game / 'garrysmod' / 'addons' / 'mods.gma')


def snapshot(root):
    """Every file (path -> SHA-256) and folder below the game folder, except the journal and lock."""
    out = {}
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root).as_posix()
        if rel in ('native-loader/state.json', 'native-loader/lock'):
            continue
        out[rel] = '<folder>' if path.is_dir() else hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def copy(src, dst):
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)


class Host:
    def __init__(self, exe):
        self.exe = exe

    def run(self, command, root, kill=None, fail=None):
        cmd = [self.exe, command, str(root)]
        if kill:
            cmd += ['--kill-at', str(kill)]
        if fail:
            cmd += ['--fail-at', str(fail)]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')  # the host writes UTF-8
        report = json.loads(proc.stdout) if proc.returncode in (0, 1) and proc.stdout.strip() else None
        return proc.returncode, report, proc.stderr

    def settle(self, root):
        """Recovery: undo an interrupted transaction, finish clean-up. Must succeed."""
        code, report, err = self.run('recover', root)
        check(code == 0, f'recovery failed ({code}): {report} {err}')
        journal = json.loads((root / 'native-loader' / 'state.json').read_text(encoding='utf-8')) \
            if (root / 'native-loader' / 'state.json').exists() else None
        check(journal is None or (journal['pending'] is None and not journal['retired']), f'recovery left work: {journal}')
        check(not (root / 'native-loader' / 'staging').exists(), 'recovery left the staging folder')


def kill_everywhere(host, scratch, before, command):
    """Kills `command` before each of its changes in turn; returns the number of changes."""
    done = scratch / 'after'
    copy(before, done)
    code, report, err = host.run(command, done)
    check(code == 0, f'{command} without faults: {code} {report} {err}')
    old_state, new_state = snapshot(before), snapshot(done)
    check(old_state != new_state, f'{command} changed nothing')
    work = scratch / 'work'
    n = 1
    while True:
        copy(before, work)
        code, report, err = host.run(command, work, kill=n)
        if code == 0:
            break  # finished before change n
        check(code == KILLED, f'{command} killed before change {n}: exit {code} {report} {err}')
        host.settle(work)
        state = snapshot(work)
        check(state in (old_state, new_state),
              f'{command} killed before change {n}: neither the old nor the new state; differs from the old one in '
              f'{sorted(set(state.items()) ^ set(old_state.items()))[:6]}')
        n += 1
    return n - 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--host', required=True)
    ap.add_argument('--gmapack', required=True)
    ap.add_argument('--scratch', required=True)
    a = ap.parse_args()

    scratch = Path(a.scratch)
    shutil.rmtree(scratch, ignore_errors=True)
    host = Host(a.host)
    game = scratch / 'game'
    (game / 'bin' / 'win64').mkdir(parents=True)
    (game / 'bin' / 'win64' / 'gmod.exe').write_bytes(b'')
    (game / 'garrysmod' / 'cfg').mkdir(parents=True)
    (game / 'native-loader').mkdir()
    (game / 'native-loader' / 'config.json').write_text(json.dumps(
        {'schema': 1, 'allow': {'local': ['garrysmod/addons/runtime.gma', 'garrysmod/addons/mods.gma']}}), encoding='utf-8')
    version(game, scratch / 'src', a.gmapack, 1)

    counts = {}
    fresh = scratch / 'states' / 'fresh'
    copy(game, fresh)
    counts['first deployment'] = kill_everywhere(host, scratch / 'first', fresh, 'apply')

    check(host.run('apply', game)[0] == 0, 'deploying version 1')
    version(game, scratch / 'src', a.gmapack, 2)
    upgrade = scratch / 'states' / 'upgrade'
    copy(game, upgrade)
    counts['upgrade'] = kill_everywhere(host, scratch / 'upgrade', upgrade, 'apply')

    check(host.run('apply', game)[0] == 0, 'deploying version 2')
    upgraded = scratch / 'states' / 'upgraded'
    copy(game, upgraded)
    counts['rollback'] = kill_everywhere(host, scratch / 'rollback', upgraded, 'rollback')
    counts['uninstall'] = kill_everywhere(host, scratch / 'uninstall', upgraded, 'uninstall')

    for name, n in counts.items():
        check(n >= 5, f'{name}: only {n} changes; the scenario is not doing what it should')
    shutil.rmtree(scratch, ignore_errors=True)
    print('deploy_faults OK: ' + ', '.join(f'{name} {n} changes' for name, n in counts.items()))


if __name__ == '__main__':
    main()
