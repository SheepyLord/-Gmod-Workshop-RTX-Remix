"""End-to-end CTest for M3: `nlctl apply | status | rollback | uninstall` on gmapack-built packages.

A fake game folder in a fake Steam library allowlists a runtime as a development folder (shadowing a
local archive of the same id), a root-files package in a Workshop item wrapped like a legacy upload
(LZMA with GMod's footer), and a binary Lua module. The test deploys and checks every placed byte
and the journal, re-runs (nothing may be written), dry-runs and applies an upgrade, finds a changed
file with `status`, rolls back twice, is refused while another deployer holds the lock and while
the folder's gmod.exe runs, refuses a broken journal, and uninstalls: the game folder must then be
exactly as before the first deployment. All files go to --scratch.
"""

import argparse
import ctypes
import hashlib
import json
import lzma
import os
import shutil
import struct
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path


def check(condition, message):
    if not condition:
        sys.exit('e2e_deploy failed: ' + message)


def run(cmd, expect=None):
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if expect is not None and proc.returncode != expect:
        sys.exit(f'{cmd!r} exited {proc.returncode}, expected {expect}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}')
    return proc


def write_package(folder, manifest_fields, files):
    """Writes a package folder; native/ files are listed in native/manifest.json with real hashes."""
    shutil.rmtree(folder, ignore_errors=True)
    for rel, data in files.items():
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    listed = {rel: {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
              for rel, data in files.items() if rel.startswith('native/')}
    manifest = {'schema': 1, **manifest_fields, 'files': listed}
    (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest, indent=1), encoding='utf-8')
    (folder / 'addon.json').write_text(json.dumps({'title': folder.name, 'type': 'servercontent', 'tags': []}),
                                       encoding='utf-8')
    return folder


def pack(gmapack, folder, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    run([sys.executable, '-I', '-B', gmapack, 'create', '--folder', str(folder), '--out', str(out),
         '--timestamp', '1700000000', '--quiet', '--force'], expect=0)
    return out


def legacy_wrap(gma, out):
    """The Workshop's *_legacy.bin form: LZMA-alone with a declared size, then GMod's 8-byte footer."""
    data = gma.read_bytes()
    stream = bytearray(lzma.compress(data, format=lzma.FORMAT_ALONE))
    stream[5:13] = struct.pack('<Q', len(data))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(bytes(stream) + struct.pack('<II', len(data) & 0xFFFFFFFF, 0xBEEFCACE))
    return out


def snapshot(root):
    """Every file (path -> SHA-256) and folder below the game folder, except the journal and lock."""
    out = {}
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root).as_posix()
        if rel in ('native-loader/state.json', 'native-loader/lock'):
            continue
        out[rel] = '<folder>' if path.is_dir() else hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def runtime_files(version, dll):
    return {'native/payload/runtime/d3d9.dll': dll,
            'native/payload/config/rtx.conf': f'rtx.version = {version}\n'.encode()}


def runtime_manifest(version):
    return {'id': 'e2e-runtime', 'version': version, 'kinds': ['remix-runtime'],
            'remix': {'entry': 'runtime/d3d9.dll', 'rtx_conf_layers': ['config/rtx.conf']}}


MOD = 'native/root/rtx-remix/mods/e2e_mod/'
MOD_DIR = 'rtx-remix/mods/e2e_mod/'


def mods_manifest(version):
    return {'id': 'e2e-mods', 'version': version, 'kinds': ['root-files'],
            'root_files': [{'path': 'rtx-remix/mods/e2e_mod'}]}


def hold_lock(path):
    """Opens the file without sharing, as a running deployer does; returns the handle."""
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.CreateFileW.restype = wintypes.HANDLE
    kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
                                     wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    handle = kernel32.CreateFileW(str(path), 0xC0000000, 0, None, 4, 0x80, None)  # read|write, no sharing, OPEN_ALWAYS
    check(handle not in (None, wintypes.HANDLE(-1).value), f'cannot open {path} exclusively')
    return kernel32, handle


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--nlctl', required=True)
    ap.add_argument('--gmapack', required=True)
    ap.add_argument('--scratch', required=True)
    a = ap.parse_args()

    scratch = Path(a.scratch)
    shutil.rmtree(scratch, ignore_errors=True)
    steamapps = scratch / 'lib' / 'steamapps'
    game = steamapps / 'common' / 'GarrysMod'
    content = steamapps / 'workshop' / 'content' / '4000'
    src = scratch / 'src'
    (game / 'bin' / 'win64').mkdir(parents=True)
    (game / 'bin' / 'win64' / 'gmod.exe').write_bytes(b'')
    (game / 'garrysmod' / 'cfg').mkdir(parents=True)

    dev = write_package(scratch / 'dev' / 'runtime', runtime_manifest('1.0.0-dev'), runtime_files('1.0.0-dev', b'MZ-dev-1'))
    pack(a.gmapack, write_package(src / 'runtime_local', runtime_manifest('0.9.0'), runtime_files('0.9.0', b'MZ-local')),
         game / 'garrysmod' / 'addons' / 'runtime.gma')
    mods_v1 = {MOD + 'mod.usda': b'#usda 1.0 v1\n', MOD + 'textures/a.dds': b'DDS-a'}
    legacy_wrap(pack(a.gmapack, write_package(src / 'mods', mods_manifest('1.0.0'), mods_v1), src / 'mods.gma'),
                content / '2001' / '987654321_legacy.bin')
    pack(a.gmapack, write_package(src / 'lua', {'id': 'e2e-lua', 'version': '1.0.0', 'kinds': ['lua-binary-module'],
                                                'root_files': [{'path': 'garrysmod/lua/bin/gmcl_e2e_win64.dll'}]},
                                  {'native/root/garrysmod/lua/bin/gmcl_e2e_win64.dll': b'MZ-module'}),
         game / 'garrysmod' / 'addons' / 'lua.gma')
    config = {'schema': 1, 'allow': {'workshop': ['2001'], 'local': ['garrysmod/addons/runtime.gma',
                                                                      'garrysmod/addons/lua.gma'],
                                     'dev_folders': [str(dev)]}}
    (game / 'native-loader').mkdir()
    (game / 'native-loader' / 'config.json').write_text(json.dumps(config, indent=1), encoding='utf-8')
    steam = ['--steam-dir', str(scratch / 'no-steam')]
    nlctl = a.nlctl
    original = snapshot(game)

    def apply(*extra, expect=0):
        return json.loads(run([nlctl, 'apply', str(game), '--json', *steam, *extra], expect=expect).stdout)

    def journal():
        return json.loads((game / 'native-loader' / 'state.json').read_text(encoding='utf-8'))

    # First deployment: three packages, one of them from an LZMA-wrapped Workshop item.
    r = apply()
    check(r['outcome'] == 'deployed' and r['generation'] == 1, f'first apply: {r}')
    check(len(r['packages']) == 3, f'packages {r["packages"]}')
    check(any('shadowed by dev_folder' in s['reason'] for s in r['skipped']), f'skipped {r["skipped"]}')
    j = journal()
    runtime = next(p for p in j['current']['packages'] if p['id'] == 'e2e-runtime')
    check(runtime['source'] == 'dev_folder' and runtime['remix']['entry'] == 'runtime/d3d9.dll', f'runtime {runtime}')
    check((game / runtime['payload'] / 'runtime' / 'd3d9.dll').read_bytes() == b'MZ-dev-1', 'payload d3d9.dll')
    check((game / MOD_DIR / 'mod.usda').read_bytes() == mods_v1[MOD + 'mod.usda'], 'mod.usda v1')
    check((game / 'garrysmod' / 'lua' / 'bin' / 'gmcl_e2e_win64.dll').read_bytes() == b'MZ-module', 'lua module')
    for f in j['current']['files']:
        data = (game / f['path']).read_bytes()
        check(f['sha256'] == hashlib.sha256(data).hexdigest() and f['size'] == len(data), f'journal record {f}')
    check(not (game / 'native-loader' / 'staging').exists(), 'staging left behind')
    status = json.loads(run([nlctl, 'status', str(game), '--json', '--verify'], expect=0).stdout)
    check(status['ok'] and not status['drift'], f'status {status}')

    # Running again changes nothing at all.
    state = game / 'native-loader' / 'state.json'
    before = (state.read_bytes(), state.stat().st_mtime_ns)
    r = apply()
    check(r['outcome'] == 'unchanged' and r['operations'] == 0, f'second apply: {r}')
    check((state.read_bytes(), state.stat().st_mtime_ns) == before, 'the journal was rewritten by a no-op run')

    # An upgrade: the Workshop item is updated in place, the development runtime changes.
    mods_v2 = {MOD + 'mod.usda': b'#usda 1.0 v2\n', MOD + 'textures/b.dds': b'DDS-b'}
    legacy_wrap(pack(a.gmapack, write_package(src / 'mods', mods_manifest('1.1.0'), mods_v2), src / 'mods.gma'),
                content / '2001' / '987654321_legacy.bin')
    write_package(dev, runtime_manifest('1.1.0-dev'), runtime_files('1.1.0-dev', b'MZ-dev-2'))
    untouched = snapshot(game)
    r = apply('--dry-run')
    check(r['outcome'] == 'planned' and r['operations'] == 0, f'dry run: {r}')
    check({'action': 'replace', 'path': MOD_DIR + 'mod.usda'} in r['changes'], f'dry-run changes {r["changes"]}')
    check(snapshot(game) == untouched, 'the dry run changed the folder')
    r = apply()
    check(r['outcome'] == 'deployed' and r['generation'] == 2, f'upgrade: {r}')
    for change in ({'action': 'replace', 'path': MOD_DIR + 'mod.usda'}, {'action': 'remove', 'path': MOD_DIR + 'textures/a.dds'},
                   {'action': 'add', 'path': MOD_DIR + 'textures/b.dds'}):
        check(change in r['changes'], f'upgrade changes lack {change}: {r["changes"]}')
    j = journal()
    check(j['previous']['generation'] == 1 and j['previous_backup'] == 'native-loader/backup/2', f'previous {j["previous_backup"]}')
    check((game / 'native-loader' / 'backup' / '2' / MOD_DIR / 'textures' / 'a.dds').read_bytes() == b'DDS-a', 'backup a.dds')

    # status finds a changed file; putting the bytes back makes it clean again.
    b_dds = game / MOD_DIR / 'textures' / 'b.dds'
    b_dds.write_bytes(b'DDS-changed')
    status = json.loads(run([nlctl, 'status', str(game), '--json'], expect=1).stdout)
    check({'path': MOD_DIR + 'textures/b.dds', 'problem': 'changed'} in status['drift'], f'drift {status["drift"]}')
    b_dds.write_bytes(b'DDS-b')
    run([nlctl, 'status', str(game)], expect=0)

    # Rollback restores version 1 and holds it; rolling back again returns to version 2.
    r = json.loads(run([nlctl, 'rollback', str(game), '--json'], expect=0).stdout)
    check(r['outcome'] == 'rolled-back' and r['generation'] == 3, f'rollback: {r}')
    check((game / MOD_DIR / 'mod.usda').read_bytes() == mods_v1[MOD + 'mod.usda'], 'rolled-back mod.usda')
    check((game / MOD_DIR / 'textures' / 'a.dds').exists() and not b_dds.exists(), 'rolled-back textures')
    r = apply()
    check(r['outcome'] == 'held' and r['operations'] == 0, f'apply after rollback: {r}')
    r = json.loads(run([nlctl, 'rollback', str(game), '--json'], expect=0).stdout)
    check(r['outcome'] == 'rolled-back' and b_dds.read_bytes() == b'DDS-b', f'second rollback: {r}')
    check(apply()['outcome'] == 'unchanged', 'apply after the second rollback')

    # Refused while another deployer holds the lock.
    kernel32, handle = hold_lock(game / 'native-loader' / 'lock')
    try:
        r = apply(expect=1)
        check(r['outcome'] == 'refused' and 'another deployment' in r['error'], f'apply while locked: {r}')
    finally:
        kernel32.CloseHandle(handle)

    # Refused while this folder's gmod.exe runs (a copy of ping.exe stands in for the game).
    gmod = game / 'bin' / 'win64' / 'gmod.exe'
    stand_in = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32' / 'PING.EXE'
    try:
        shutil.copyfile(stand_in, gmod)
        game_process = subprocess.Popen([str(gmod), '-n', '60', '127.0.0.1'], stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
    except OSError as exc:
        print(f'  (skipped the running-game check: {exc})')
        game_process = None
    if game_process:
        try:
            time.sleep(0.5)
            r = apply(expect=1)
            check(r['outcome'] == 'refused' and 'running' in r['error'], f'apply while the game runs: {r}')
        finally:
            game_process.kill()
            game_process.wait()
    gmod.write_bytes(b'')

    # A journal that does not parse stops every command with exit code 2 and changes nothing.
    saved = state.read_bytes()
    state.write_text('{"schema": 1}', encoding='utf-8')
    run([nlctl, 'apply', str(game), *steam], expect=2)
    run([nlctl, 'status', str(game)], expect=2)
    run([nlctl, 'uninstall', str(game)], expect=2)
    state.write_bytes(saved)

    # Uninstall: a dry run first, then for real. The game folder is as it was before the first apply.
    untouched = snapshot(game)
    r = json.loads(run([nlctl, 'uninstall', str(game), '--json', '--dry-run'], expect=0).stdout)
    check(r['outcome'] == 'planned' and r['changes'] and snapshot(game) == untouched, f'uninstall dry run: {r}')
    r = json.loads(run([nlctl, 'uninstall', str(game), '--json'], expect=0).stdout)
    check(r['outcome'] == 'removed', f'uninstall: {r}')
    after = snapshot(game)
    check(after == original, 'uninstall left differences: ' +
          repr(sorted(set(after.items()) ^ set(original.items()))[:10]))
    check(not state.exists() and not (game / 'native-loader' / 'lock').exists(), 'journal or lock left behind')
    r = json.loads(run([nlctl, 'uninstall', str(game), '--json'], expect=0).stdout)
    check(r['outcome'] == 'unchanged', f'second uninstall: {r}')
    run([nlctl, 'rollback', str(game)], expect=1)

    shutil.rmtree(scratch, ignore_errors=True)
    print('e2e_deploy OK: deploy, no-op, dry run, upgrade, drift, rollback x2, lock, running game, '
          'broken journal, uninstall')


if __name__ == '__main__':
    main()
