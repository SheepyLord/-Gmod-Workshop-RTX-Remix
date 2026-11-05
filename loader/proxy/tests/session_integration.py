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
import struct
import subprocess
import sys
import time


def check(value, message):
    if not value:
        raise AssertionError(message)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')


def junction(link, target):
    subprocess.run(['cmd', '/c', 'mklink', '/J', str(link), str(target)], check=True, capture_output=True)


def without_import_names(dll, target):
    """Copies `dll` with its KERNEL32 import descriptor's OriginalFirstThunk set to 0: a valid layout
    (Windows then resolves the imports from FirstThunk and overwrites it with addresses) that left
    the import hooks without names to match (R1-006). Returns how many descriptors changed."""
    data = bytearray(dll.read_bytes())
    file_header = struct.unpack_from('<I', data, 0x3C)[0] + 4
    sections, optional_size = struct.unpack_from('<H', data, file_header + 2)[0], struct.unpack_from('<H', data, file_header + 16)[0]
    optional = file_header + 20
    table = optional + optional_size

    def offset(rva):
        for i in range(sections):
            virtual_size, address, raw_size, raw = struct.unpack_from('<IIII', data, table + i * 40 + 8)
            if address <= rva < address + max(virtual_size, raw_size):
                return rva - address + raw
        raise ValueError(f'RVA {rva:#x} is in no section')

    at = offset(struct.unpack_from('<I', data, optional + 112 + 8)[0])  # PE32+ import directory
    changed = 0
    while struct.unpack_from('<I', data, at + 12)[0]:
        name = bytes(data[offset(struct.unpack_from('<I', data, at + 12)[0]):]).split(b'\0', 1)[0]
        if name.lower() == b'kernel32.dll':
            struct.pack_into('<I', data, at, 0)
            changed += 1
        at += 20
    target.write_bytes(bytes(data))
    return changed


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

    # The fixes package as a development folder: a patch set, an override, session variables, an
    # add-on folder that only makes sense with RTX (requires_remix), and (ADR 0024) a binary module
    # whose runtime, a static import, is deployed only beside it in garrysmod/lua/bin.
    fixes = scratch / 'fixes'
    shader = (args.fixtures / 'stdshader_dx6.dll').read_bytes()
    (fixes / 'native/payload/shaders').mkdir(parents=True)
    (fixes / 'native/payload/shaders/stdshader_dx6.dll').write_bytes(shader)
    addon_lua = b'print("nl_rtx_addon")' + bytes([10])
    (fixes / 'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun').mkdir(parents=True)
    (fixes / 'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua').write_bytes(addon_lua)
    lua_bin = {name: (args.fixtures / name).read_bytes() for name in ('gmcl_nl_dep_win64.dll', 'nl_dep_runtime_win64.dll')}
    (fixes / 'native/root/garrysmod/lua/bin').mkdir(parents=True)
    for name, data in lua_bin.items():
        (fixes / 'native/root/garrysmod/lua/bin' / name).write_bytes(data)
    write_json(fixes / 'native/manifest.json', {
        'schema': 1, 'id': 'm5-fixes', 'version': '1.0.0', 'kinds': ['patch-set', 'module-override', 'lua-addon', 'lua-binary-module'],
        'requires_remix': True,
        'files': {'native/payload/shaders/stdshader_dx6.dll': {'size': len(shader), 'sha256': hashlib.sha256(shader).hexdigest()},
                  'native/root/garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua':
                      {'size': len(addon_lua), 'sha256': hashlib.sha256(addon_lua).hexdigest()},
                  **{'native/root/garrysmod/lua/bin/' + name: {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                     for name, data in lua_bin.items()}},
        'root_files': [{'path': 'garrysmod/addons/nl_rtx_addon'}] + [{'path': 'garrysmod/lua/bin/' + name} for name in lua_bin],
        'module_dependencies': [{'module': 'garrysmod/lua/bin/gmcl_nl_dep_win64.dll',
                                 'load_first': ['garrysmod/lua/bin/nl_dep_runtime_win64.dll']}],
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
    shutil.copy2(args.fixtures / 'lua_shared.dll', bin_folder / 'lua_shared.dll')
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

    def run(name, extra=(), env_extra=None):
        probe_file = root / 'probe.json'
        probe_file.unlink(missing_ok=True)
        env = {k: v for k, v in os.environ.items() if k not in ('NATIVE_LOADER_DISABLE', 'DXVK_RTX_CONFIG_FILE', 'DXVK_CONFIG_FILE')}
        env.update(env_extra or {})
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

    def dependency_loaded(name, probe, status, session):
        """ADR 0024: the module loaded with its runtime from garrysmod/lua/bin, and both reports say so."""
        dep = probe['dep_module']
        check(not dep.startswith('!') and dep.endswith('|nl-dep-runtime') and
              Path(dep.split('|')[0]).parent == root / 'garrysmod/lua/bin', f'{name}: module with its runtime in lua/bin: {dep}')
        check(status['session']['module_dependencies'] == ['garrysmod/lua/bin/gmcl_nl_dep_win64.dll'],
              f'{name}: dependencies not reported: {status["session"]}')
        loaded = session and session['module_dependencies']['loaded']
        check(loaded and loaded[0]['result'] == 'loaded' and loaded[0]['loaded_first'].lower().endswith('nl_dep_runtime_win64.dll'),
              f'{name}: session.json dependencies: {session and session.get("module_dependencies")}')

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
        # R19 (proxy F-05): a caller's LOAD_LIBRARY_SEARCH_* flag, which Windows refuses next to the
        # altered search path, still gets the override.
        check(probe['shader_search_error'] == 0 and Path(probe['shader_search_path']) == shader_path,
              f'override with a LOAD_LIBRARY_SEARCH flag: {probe["shader_search_path"]!r}, error {probe["shader_search_error"]}')
        check(probe['command_line_w'].endswith('+exec nativeloader_session.cfg'), 'session cfg not executed')
        check('r_nl_test "1"' in session_cfg.read_text(encoding='ascii'), 'session cfg content')
        recorded = json.loads(record.read_text(encoding='utf-8'))
        check(recorded['values'] == {'r_nl_test': '0', 'r_3dsky': '1'} and not recorded['restore_issued'], f'record: {recorded}')
        check(recorded['session_values'] == {'r_nl_test': '1', 'r_3dsky': '0'}, f'session values not recorded: {recorded}')
        both = 'nl_rtx_addon|user_addon'
        check(probe['addons_a'] == both and probe['addons_w'] == both, f'RTX session must see every add-on: {probe}')
        check(status['session']['hidden_addons'] == [], 'add-ons hidden with RTX on')
        dependency_loaded('rtx-insecure', probe, status, session)
        passed('RTX with -insecure: patch before DllMain, override, session cfg, user values recorded, every add-on visible, '
               'a module\'s runtime loaded first from lua/bin')

        record_bytes = record.read_bytes()
        cfg_time = session_cfg.stat().st_mtime_ns
        probe, status, session = run('rtx-secure')
        check(not status['session']['patches_allowed'], 'patches applied without -insecure')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'engine patched without -insecure')
        check(Path(probe['shader_path']) != shader_vanilla, 'override needs no -insecure')
        check(any('-insecure' in note for note in status['session']['notes']), 'missing -insecure note')
        check(record.read_bytes() == record_bytes and session_cfg.stat().st_mtime_ns == cfg_time, 'repeat rewrote record or cfg')
        passed('without -insecure: no patches, override still applies, nothing rewritten')

        # R19 (proxy F-04): the module's runtime is away for the first require (as when a scanner holds
        # it), so that load fails; the next require tries the runtime again, and the module loads.
        probe, status, session = run('rtx-dep-retry', ['-insecure'], {'NL_M5_DEP_RETRY': '1'})
        check(probe['dep_retry'] == '!126', f'the first require found its runtime anyway: {probe["dep_retry"]!r}')
        dep = probe['dep_module']
        check(not dep.startswith('!') and dep.endswith('|nl-dep-runtime'), f'the second require did not load: {dep!r}')
        loaded = session and session['module_dependencies']['loaded']
        check(loaded and [entry['result'] for entry in loaded] == ['failed', 'loaded'],
              f'session.json dependencies: {session and session.get("module_dependencies")}')
        check((root / 'garrysmod/lua/bin/nl_dep_runtime_win64.dll').read_bytes() == lua_bin['nl_dep_runtime_win64.dll'],
              'the runtime did not come back')
        passed('a module dependency that failed to load is tried again at the next require, and reported once each way')

        # What the game does when an RTX session quits: it archives the session's values. During the
        # session the user also set r_3dsky to 2 themselves.
        config_cfg.write_text('bind "p" "say hi"\nr_nl_test "1"\nr_3dsky "2"\n', encoding='ascii')
        config['remix'] = {'enabled': False}
        write_json(root / 'native-loader/config.json', config)

        # A journal that cannot be read: a pure pass-through, the record waits (R1-004).
        journal_file = root / 'native-loader/state.json'
        journal_bytes = journal_file.read_bytes()
        record_bytes = record.read_bytes()
        journal_file.write_text('{"schema": 1, "broken', encoding='utf-8')
        probe, status, session = run('off-invalid-journal')
        check(status['activation']['outcome'] != 'active', 'activated with an invalid journal')
        check('+exec' not in probe['command_line_w'], f'command line changed with an invalid journal: {probe["command_line_w"]}')
        check(record.read_bytes() == record_bytes and not restore_cfg.exists(), 'restore prepared with an invalid journal')
        journal_file.write_bytes(journal_bytes)
        passed('an invalid journal: no restore, no command-line change; the record waits')

        probe, status, session = run('off-restore')
        check(status['activation']['outcome'] == 'inactive', 'RTX off not inactive')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'patched with RTX off')
        check(Path(probe['shader_path']) == shader_vanilla, f'override with RTX off: {probe["shader_path"]}')
        check(Path(probe['shader_search_path']) == shader_vanilla, f'override with RTX off: {probe["shader_search_path"]}')
        check(probe['command_line_w'].endswith('+exec nativeloader_restore.cfg'), 'restore not executed')
        restore = restore_cfg.read_text(encoding='ascii')
        check('r_nl_test "0"' in restore and 'r_3dsky' not in restore, f'restore cfg (the user\'s r_3dsky must stay): {restore}')
        check(json.loads(record.read_text(encoding='utf-8'))['restore_issued'], 'restore not marked issued')
        check(status['session']['restore_values'] == 1, 'restore not reported')
        check(probe['addons_a'] == 'user_addon' and probe['addons_w'] == 'user_addon',
              f'RTX off must leave out the requires_remix add-on: {probe["addons_a"]!r} {probe["addons_w"]!r}')
        check('config.cfg' in probe['other_a'].split('|'), f'other folders must not be filtered: {probe["other_a"]!r}')
        check(status['session']['hidden_addons'] == ['nl_rtx_addon'], f'hidden not reported: {status["session"]}')
        check(session and session['hidden_addons']['left_out'] == ['nl_rtx_addon'], f'session.json hidden: {session}')
        check((root / 'garrysmod/addons/nl_rtx_addon/lua/autorun/nl.lua').read_bytes() == addon_lua, 'add-on changed on disk')
        check(session and session.get('utc'), f'session.json has no time: {session}')
        dependency_loaded('off-restore', probe, status, session)
        passed('RTX off: vanilla engine and shader, the restore cfg runs once and keeps the user\'s own change, '
               'the RTX-only add-on hidden (still on disk), the module\'s runtime still loaded first')

        # The loader off: Windows looks for the module's runtime next to gmod.exe and finds none.
        done = subprocess.run([str(bin_folder / 'gmod.exe'), '--m5-probe', str(root / 'probe.json'), str(bin_folder)], cwd=root,
                              env={**os.environ, 'NATIVE_LOADER_DISABLE': '1'}, timeout=60, capture_output=True,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        check(done.returncode == 0, f'loader off: host exit {done.returncode:#x}')
        check(json.loads((root / 'probe.json').read_text(encoding='utf-8'))['dep_module'] == '!126',
              'the module found its runtime without the loader: the test proves nothing')
        passed('with the loader off the same module does not load (ERROR_MOD_NOT_FOUND): the runtime in lua/bin needs the hook')

        probe, status, session = run('off-again')
        check(not record.exists(), 'record kept after its restore ran')
        check('+exec' not in probe['command_line_w'], 'exec added with nothing to restore')
        check(probe['addons_a'] == 'user_addon', 'not hidden again on the next start without RTX')
        passed('the next start without RTX forgets the record and adds nothing; the add-on stays hidden')

        # A start without RTX whose filesystem_stdio.dll has no import name table (R1-006): still hidden.
        filesystem = bin_folder / 'filesystem_stdio.dll'
        filesystem_bytes = filesystem.read_bytes()
        check(without_import_names(args.fixtures / 'filesystem_stdio.dll', filesystem) == 1, 'fixture has no KERNEL32 imports')
        probe, status, session = run('off-no-import-names')
        check(probe['addons_a'] == 'user_addon' and probe['addons_w'] == 'user_addon',
              f'add-on visible when the module has no import name table: {probe["addons_a"]!r} {probe["addons_w"]!r}')
        filesystem.write_bytes(filesystem_bytes)
        passed('a module without an import name table is hooked by address: the add-on stays hidden')

        # Links where the loader writes (R1-001, R1-005): a junction is never written through.
        logs = root / 'native-loader/logs'
        logs.rename(root / 'native-loader/logs.real')
        victim_logs = scratch / 'victim-logs'
        victim_logs.mkdir()
        (victim_logs / 'loader.log').write_bytes(b'USER DATA')
        junction(logs, victim_logs)
        run('linked-log')
        check((victim_logs / 'loader.log').read_bytes() == b'USER DATA', 'loader.log written through a junction')
        os.rmdir(logs)
        (root / 'native-loader/logs.real').rename(logs)
        data_folder = root / 'garrysmod/data/native-loader'
        data_folder.rename(root / 'garrysmod/data/native-loader.real')
        victim_data = scratch / 'victim-data'
        victim_data.mkdir()
        (victim_data / 'session.json').write_bytes(b'USER DATA')
        junction(data_folder, victim_data)
        done = subprocess.run([str(bin_folder / 'gmod.exe'), '--m5-probe', str(root / 'probe.json'), str(bin_folder)], cwd=root,
                              env={k: v for k, v in os.environ.items() if k != 'NATIVE_LOADER_DISABLE'}, timeout=60,
                              capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        check(done.returncode == 0, f'linked data folder: host exit {done.returncode:#x}')
        check((victim_data / 'session.json').read_bytes() == b'USER DATA', 'session.json written through a junction')
        check(not (victim_data / 'status.json').exists(), 'status.json written through a junction')
        os.rmdir(data_folder)
        (root / 'garrysmod/data/native-loader.real').rename(data_folder)
        passed('loader.log and session.json are never written through a junction')

        # What the game does with the restore cfg: it sets and archives r_nl_test 0 again.
        config_cfg.write_text('bind "p" "say hi"\nr_nl_test "0"\nr_3dsky "2"\n', encoding='ascii')
        config['remix'] = {'enabled': True}
        write_json(root / 'native-loader/config.json', config)
        probe, status, session = run('rtx-again', ['-insecure'])
        check(json.loads(record.read_text(encoding='utf-8'))['values'] == {'r_nl_test': '0', 'r_3dsky': '2'}, 'record not made again')
        check(probe['engine_at_attach'] == 'NLM5PATCH:AFTER!', 'patch missing on second RTX session')
        check(probe['addons_a'] == 'nl_rtx_addon|user_addon', 'add-on still hidden after RTX came back')
        passed('a later RTX session records the user values again and sees the add-on')

        # The runtime fails to load after the module hooks went in (its DllMain fails): activation is
        # undone, and the start continues as one without a runtime, so the RTX-only add-on is hidden
        # by a second hook installation (the first one's state stays allocated, inactive).
        probe, status, session = run('rtx-attach-fails', ['-insecure'], {'NL_M4_FAIL_ATTACH': '1'})
        check(status['activation']['outcome'] == 'failed', f'activation: {status["activation"]}')
        check(Path(probe['shader_path']) == shader_vanilla, f'override left after a failed activation: {probe["shader_path"]}')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'patched after a failed activation')
        check(probe['addons_a'] == 'user_addon' and probe['addons_w'] == 'user_addon',
              f'RTX-only add-on visible after a failed activation: {probe["addons_a"]!r} {probe["addons_w"]!r}')
        check(status['session']['hidden_addons'] == ['nl_rtx_addon'], f'hidden not reported: {status["session"]}')
        dependency_loaded('rtx-attach-fails', probe, status, session)
        passed('a runtime that fails to load: hooks undone, no patch or override, the RTX-only add-on hidden, '
               'the module\'s runtime loaded first by the second installation')

        # ADR 0056: opting out of the reviewed rendering recipes without -insecure would start RTX
        # without them, the configuration ADR 0052 found crashing. The start stays vanilla and says why.
        sys.path.insert(0, str(repo / 'tools'))
        import package_fixes  # the seven recipes exactly as the RTX package ships them
        recipes = scratch / 'recipes'
        recipe_mod = b'#usda 1.0' + bytes([10])
        (recipes / 'native/root/rtx-remix/mods/nl_recipes').mkdir(parents=True)
        (recipes / 'native/root/rtx-remix/mods/nl_recipes/mod.usda').write_bytes(recipe_mod)
        write_json(recipes / 'native/manifest.json', {
            'schema': 1, 'id': 'gmod-rtx-remix', 'version': '1.0.0', 'kinds': ['root-files', 'patch-set'],
            'files': {'native/root/rtx-remix/mods/nl_recipes/mod.usda':
                      {'size': len(recipe_mod), 'sha256': hashlib.sha256(recipe_mod).hexdigest()}},
            'root_files': [{'path': 'rtx-remix/mods/nl_recipes'}], 'patch_sets': package_fixes.patch_sets()})
        config['allow']['dev_folders'].append(str(recipes))
        config['patch_sets'] = {'allow_rtx_render_patches': False}
        write_json(root / 'native-loader/config.json', config)
        probe, status, session = run('rtx-recipes-opted-out')
        activation = status['activation']
        check(activation['outcome'] == 'failed' and 'allow_rtx_render_patches' in activation['reason'] and
              '-insecure' in activation['reason'], f'the crashing opt-out was not refused: {activation}')
        check(activation['reason'] in status['errors'], f'refusal not reported: {status["errors"]}')
        check(probe['engine_at_attach'] == 'NLM5PATCH:BEFORE', 'patched in a refused start')
        check(Path(probe['shader_path']) == shader_vanilla, f'override in a refused start: {probe["shader_path"]}')
        check(status['session']['hidden_addons'] == ['nl_rtx_addon'], f'vanilla fallback incomplete: {status["session"]}')
        probe, status, session = run('rtx-recipes-opted-out-insecure', ['-insecure'])
        check(status['activation']['outcome'] == 'active', f'refused with -insecure: {status["activation"]}')
        check(probe['engine_at_attach'] == 'NLM5PATCH:AFTER!', 'patch missing with -insecure')
        check(status['session']['patches'] == 8, f'applied patch count (1 marker + 7 recipes): {status["session"]}')
        passed('the rendering-recipe opt-out without -insecure stays vanilla with its reason; with -insecure RTX starts')
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
