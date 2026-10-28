"""Exercise M5's RTX-session extras in a generated game root: a patch set applied to a fake engine.dll
before its code runs, a stdshader_dx6.dll override, session console variables with their restore, and
(ADR 0013) a requires_remix package's add-on folder left out of filesystem_stdio's searches of
garrysmod/addons in sessions without RTX. Uses the M4 fake runtime package; never starts a real game."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def check(value, message):
    if not value:
        raise AssertionError(message)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'host', 'proxy', 'runtime', 'fixtures', 'scratch'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    base = args.scratch.resolve()
    check(base.is_relative_to(repo / 'out' / 'tmp'), 'scratch must be below this repo/out/tmp')
    scratch = base / str(os.getpid())
    scratch.mkdir(parents=True)

    runtime_package = scratch / 'runtime.gma'
    subprocess.run([sys.executable, str(repo / 'tools/package_runtime.py'), '--runtime', str(args.runtime), '--gma',
                    str(runtime_package), '--id', 'm5-runtime', '--version', '1.0.0', '--no-system-vulkan', '--json'],
                   cwd=repo, check=True, capture_output=True, text=True)

    # The fixes package as a development folder: a patch set, an override, session variables, and an
    # add-on folder that only makes sense with RTX (requires_remix).
    fixes = scratch / 'fixes'
    shader = (args.fixtures / 'stdshader_dx6.dll').read_bytes()
    (fixes / 'native/payload/shaders').mkdir(parents=True)
    (fixes / 'native/payload/shaders/stdshader_dx6.dll').write_bytes(shader)
    addon_lua = b'print("nl_rtx_addon")' + bytes([10])
    (fixes / 'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun').mkdir(parents=True)
    (fixes / 'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua').write_bytes(addon_lua)
    write_json(fixes / 'native/manifest.json', {
        'schema': 1, 'id': 'm5-fixes', 'version': '1.0.0', 'kinds': ['patch-set', 'module-override', 'lua-addon'],
        'requires_remix': True,
        'files': {'native/payload/shaders/stdshader_dx6.dll': {'size': len(shader), 'sha256': hashlib.sha256(shader).hexdigest()},
                  'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua':
                      {'size': len(addon_lua), 'sha256': hashlib.sha256(addon_lua).hexdigest()}},
        'root_files': [{'path': 'garrysmod/addons/nl_rtx_addon'}],
        'patch_sets': [{'module': 'engine.dll', 'patches': [
            {'name': 'marker', 'find': b'NLM5PATCH:'.hex() + '??' * 6, 'offset': 10, 'replace': b'AFTER!'.hex()}]}],
        'module_overrides': [{'module': 'stdshader_dx6.dll', 'file': 'native/payload/shaders/stdshader_dx6.dll'}],
        'session_cvars': {'r_nl_test': '1', 'r_3dsky': '0'}})

    root = scratch / 'game'
    bin_folder = root / 'bin/win64'
    bin_folder.mkdir(parents=True)
    shutil.copy2(args.host, bin_folder / 'gmod.exe')
    shutil.copy2(args.proxy, bin_folder / 'winmm.dll')
    shutil.copy2(args.fixtures / 'engine.dll', bin_folder / 'engine.dll')
    shutil.copy2(args.fixtures / 'stdshader_dx6.dll', bin_folder / 'stdshader_dx6.dll')
    shutil.copy2(args.fixtures / 'filesystem_stdio.dll', bin_folder / 'filesystem_stdio.dll')
    (root / 'garrysmod/addons/user_addon').mkdir(parents=True)  # the user's own: never hidden
    (root / 'garrysmod/cfg').mkdir(parents=True)
    config_cfg = root / 'garrysmod/cfg/config.cfg'
    config_cfg.write_text('bind "p" "say hi"\nr_nl_test "0"\nr_3dsky "1"\n', encoding='ascii')
    config = {'schema': 1, 'allow': {'local': [str(runtime_package)], 'dev_folders': [str(fixes)]}}
    write_json(root / 'native-loader/config.json', config)
    record = root / 'native-loader/session_cvars.json'
    session_cfg = root / 'garrysmod/cfg/nativeloader_session.cfg'
    restore_cfg = root / 'garrysmod/cfg/nativeloader_restore.cfg'
    evidence = repo / 'out' / 'm5-synthetic' / (args.config.lower() + '-' + str(os.getpid()) + time.strftime('-%Y%m%dT%H%M%S'))
    evidence.mkdir(parents=True, exist_ok=True)  # a reused PID must not fail the run
    runs = []

    def run(name, extra=()):
        probe_file = root / 'probe.json'
        probe_file.unlink(missing_ok=True)
        env = {k: v for k, v in os.environ.items() if k not in ('NATIVE_LOADER_DISABLE', 'DXVK_RTX_CONFIG_FILE', 'DXVK_CONFIG_FILE')}
        argv = [str(bin_folder / 'gmod.exe'), '--m5-probe', str(probe_file), str(bin_folder), *extra]
        done = subprocess.run(argv, cwd=root, env=env, timeout=60, capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        check(done.returncode == 0, f'{name}: host exit {done.returncode:#x}')
        probe = json.loads(probe_file.read_text(encoding='utf-8'))
        status = json.loads((root / 'garrysmod/data/native-loader/status.json').read_text(encoding='utf-8'))
        check(status['process_id'] == probe['process_id'], f'{name}: stale status')
        session_file = root / 'garrysmod/data/native-loader/session.json'
        session = json.loads(session_file.read_text(encoding='utf-8')) if session_file.exists() else None
        if session is not None and session.get('process_id') != probe['process_id']:
            session = None  # from an earlier launch
        for label, value in (('probe', probe), ('status', status), ('session', session)):
            write_json(evidence / f'{len(runs) + 1:02d}-{name}.{label}.json', value)
        runs.append(name)
        return probe, status, session

    def passed(text):
        print('ok  ' + text, flush=True)

    shader_vanilla = bin_folder / 'stdshader_dx6.dll'
    try:
        probe, status, session = run('rtx-insecure', ['-insecure'])
        check(status['activation']['outcome'] == 'active', f'activation: {status["activation"]}')
        check(status['session']['patches_allowed'] and status['session']['hooks'] == 'installed', f'session: {status["session"]}')
        check(probe['engine_at_attach'] == 'NLM5PATCH:AFTER!', f'patch not in place before DllMain: {probe["engine_at_attach"]!r}')
        check(session and session['patches'][0]['result'] == 'applied', f'session.json patches: {session}')
        shader_path = Path(probe['shader_path'])
        check(shader_path.name.lower() == 'stdshader_dx6.dll' and 'native-loader' in shader_path.parts and
              shader_path != shader_vanilla, f'override not used: {shader_path}')
        check(session['overrides'][0]['result'] == 'redirected', 'override not recorded')
        check(probe['command_line_w'].endswith('+exec nativeloader_session.cfg'), 'session cfg not executed')
        check('r_nl_test "1"' in session_cfg.read_text(encoding='ascii'), 'session cfg content')
        recorded = json.loads(record.read_text(encoding='utf-8'))
        check(recorded['values'] == {'r_nl_test': '0', 'r_3dsky': '1'} and not recorded['restore_issued'], f'record: {recorded}')
        both = 'nl_rtx_addon|user_addon'
        check(probe['addons_a'] == both and probe['addons_w'] == both, f'RTX session must see every add-on: {probe}')
        check(status['session']['hidden_addons'] == [], 'add-ons hidden with RTX on')
        passed('RTX with -insecure: patch before DllMain, override, session cfg, user values recorded, every add-on visible')

        record_bytes = record.read_bytes()
        cfg_time = session_cfg.stat().st_mtime_ns
        probe, status, session = run('rtx-secure')
        check(not status['session']['patches_allowed'], 'patches applied without -insecure')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'engine patched without -insecure')
        check(Path(probe['shader_path']) != shader_vanilla, 'override needs no -insecure')
        check(any('-insecure' in note for note in status['session']['notes']), 'missing -insecure note')
        check(record.read_bytes() == record_bytes and session_cfg.stat().st_mtime_ns == cfg_time, 'repeat rewrote record or cfg')
        passed('without -insecure: no patches, override still applies, nothing rewritten')

        config['remix'] = {'enabled': False}
        write_json(root / 'native-loader/config.json', config)
        probe, status, session = run('off-restore')
        check(status['activation']['outcome'] == 'inactive', 'RTX off not inactive')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'patched with RTX off')
        check(Path(probe['shader_path']) == shader_vanilla, f'override with RTX off: {probe["shader_path"]}')
        check(probe['command_line_w'].endswith('+exec nativeloader_restore.cfg'), 'restore not executed')
        restore = restore_cfg.read_text(encoding='ascii')
        check('r_nl_test "0"' in restore and 'r_3dsky "1"' in restore, f'restore cfg: {restore}')
        check(json.loads(record.read_text(encoding='utf-8'))['restore_issued'], 'restore not marked issued')
        check(status['session']['restore_values'] == 2, 'restore not reported')
        check(probe['addons_a'] == 'user_addon' and probe['addons_w'] == 'user_addon',
              f'RTX off must leave out the requires_remix add-on: {probe["addons_a"]!r} {probe["addons_w"]!r}')
        check('config.cfg' in probe['other_a'].split('|'), f'other folders must not be filtered: {probe["other_a"]!r}')
        check(status['session']['hidden_addons'] == ['nl_rtx_addon'], f'hidden not reported: {status["session"]}')
        check(session and session['hidden_addons']['left_out'] == ['nl_rtx_addon'], f'session.json hidden: {session}')
        check((root / 'garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua').read_bytes() == addon_lua, 'add-on changed on disk')
        passed('RTX off: vanilla engine and shader, the restore cfg runs once, the RTX-only add-on hidden (still on disk)')

        probe, status, session = run('off-again')
        check(not record.exists(), 'record kept after its restore ran')
        check('+exec' not in probe['command_line_w'], 'exec added with nothing to restore')
        check(probe['addons_a'] == 'user_addon', 'not hidden again on the next start without RTX')
        passed('the next start without RTX forgets the record and adds nothing; the add-on stays hidden')

        config['remix'] = {'enabled': True}
        write_json(root / 'native-loader/config.json', config)
        probe, status, session = run('rtx-again', ['-insecure'])
        check(json.loads(record.read_text(encoding='utf-8'))['values'] == {'r_nl_test': '0', 'r_3dsky': '1'}, 'record not made again')
        check(probe['engine_at_attach'] == 'NLM5PATCH:AFTER!', 'patch missing on second RTX session')
        check(probe['addons_a'] == 'nl_rtx_addon|user_addon', 'add-on still hidden after RTX came back')
        passed('a later RTX session records the user values again and sees the add-on')
    finally:
        for _ in range(30):
            try:
                shutil.rmtree(scratch)
                break
            except FileNotFoundError:
                break
            except OSError:
                time.sleep(0.1)
    print(f'M5 synthetic evidence: {evidence}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
