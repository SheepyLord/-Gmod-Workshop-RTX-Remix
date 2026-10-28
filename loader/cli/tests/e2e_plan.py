"""End-to-end CTest for M2: packages built with gmapack.py, a fake Steam library, a config.json
allowlist, and `nlctl plan --json`, which must reach the expected decision for every source.

Covers plain and LZMA-wrapped (GMod footer included) Workshop packages, a local archive, a
development folder that shadows a Workshop copy of the same id, a second runtime, a broken
manifest, an ordinary addon without a manifest, an item GMod's addon list disables, and one that is
not installed. All files go to --scratch.
"""

import argparse
import hashlib
import json
import lzma
import shutil
import struct
import subprocess
import sys
from pathlib import Path


def check(condition, message):
    if not condition:
        sys.exit('e2e_plan failed: ' + message)


def run(cmd, expect=None):
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if expect is not None and proc.returncode != expect:
        sys.exit(f'{cmd!r} exited {proc.returncode}, expected {expect}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}')
    return proc


def write_package(folder, manifest_fields, files):
    """Writes an addon folder; native/ files are listed in native/manifest.json with real hashes."""
    for rel, data in files.items():
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    listed = {rel: {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
              for rel, data in files.items() if rel.startswith('native/')}
    if manifest_fields is not None:
        manifest = {'schema': 1, **manifest_fields, 'files': listed}
        (folder / 'native').mkdir(parents=True, exist_ok=True)
        (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest, indent=1), encoding='utf-8')
    (folder / 'addon.json').write_text(json.dumps({'title': folder.name, 'type': 'servercontent', 'tags': []}),
                                       encoding='utf-8')
    return folder


def pack(gmapack, folder, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    run([sys.executable, '-I', '-B', gmapack, 'create', '--folder', str(folder), '--out', str(out),
         '--timestamp', '1700000000', '--quiet'], expect=0)
    return out


def legacy_wrap(gma, out):
    """The Workshop's *_legacy.bin form: LZMA-alone with a declared size, then GMod's 8-byte footer."""
    data = gma.read_bytes()
    stream = bytearray(lzma.compress(data, format=lzma.FORMAT_ALONE))
    stream[5:13] = struct.pack('<Q', len(data))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(bytes(stream) + struct.pack('<II', len(data) & 0xFFFFFFFF, 0xBEEFCACE))
    return out


RUNTIME_FILES = {
    'native/payload/runtime/d3d9.dll': b'MZ' + b'\0' * 64,
    'native/payload/config/rtx.conf': b'rtx.enableRaytracing = True\n',
    'lua/autorun/client/remix_status.lua': b'print("status")\n',
}


def runtime_manifest(package_id, version):
    return {'id': package_id, 'version': version, 'kinds': ['remix-runtime'],
            'remix': {'entry': 'runtime/d3d9.dll', 'rtx_conf_layers': ['config/rtx.conf'],
                      'launch_args': ['-dxlevel', '90', '-nod3d9ex']}}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--nlctl', required=True)
    ap.add_argument('--gmapack', required=True)
    ap.add_argument('--scratch', required=True)
    a = ap.parse_args()

    scratch = Path(a.scratch)
    shutil.rmtree(scratch, ignore_errors=True)
    src = scratch / 'src'
    steamapps = scratch / 'lib' / 'steamapps'
    game = steamapps / 'common' / 'GarrysMod'
    content = steamapps / 'workshop' / 'content' / '4000'
    (game / 'bin' / 'win64').mkdir(parents=True)
    (game / 'bin' / 'win64' / 'gmod.exe').write_bytes(b'')
    (game / 'garrysmod' / 'cfg').mkdir(parents=True)
    (game / 'garrysmod' / 'cfg' / 'addonnomount.txt').write_text('"addonnomount"\n{\n\t"1"\t\t"2002"\n}\n')

    # Workshop 1001: runtime-a 1.0.0, plain .gma (to be shadowed by the dev folder below).
    pack(a.gmapack, write_package(src / 'runtime_a', runtime_manifest('runtime-a', '1.0.0'), RUNTIME_FILES),
         content / '1001' / 'runtime_a.gma')
    # Dev folder: runtime-a 1.1.0-dev, unpacked.
    dev = write_package(scratch / 'dev' / 'runtime_a', runtime_manifest('runtime-a', '1.1.0-dev'), RUNTIME_FILES)
    # Local: runtime-b, a second runtime.
    pack(a.gmapack, write_package(src / 'runtime_b', runtime_manifest('runtime-b', '2.0.0'), RUNTIME_FILES),
         game / 'garrysmod' / 'addons' / 'runtime-b.gma')
    # Workshop 1003: root-files package, LZMA-wrapped like a legacy upload.
    mods = write_package(src / 'mods', {'id': 'mods-pack', 'version': '0.3.0', 'kinds': ['root-files'],
                                        'root_files': [{'path': 'rtx-remix/mods/base_mod'}]},
                         {'native/root/rtx-remix/mods/base_mod/mod.usda': b'#usda 1.0\n'})
    legacy_wrap(pack(a.gmapack, mods, src / 'mods.gma'), content / '1003' / '123456789_legacy.bin')
    # Workshop 1004: binary Lua module.
    pack(a.gmapack, write_package(src / 'lua_mod', {'id': 'lua-mod', 'version': '1.0.0', 'kinds': ['lua-binary-module'],
                                                    'root_files': [{'path': 'garrysmod/lua/bin/gmcl_test_win64.dll'}]},
                                  {'native/root/garrysmod/lua/bin/gmcl_test_win64.dll': b'MZ-module'}),
         content / '1004' / 'lua_mod.gma')
    # Workshop 1005: manifest without a version.
    pack(a.gmapack, write_package(src / 'broken', {'id': 'broken', 'kinds': ['root-files'],
                                                   'root_files': [{'path': 'rtx-remix/mods/broken'}]},
                                  {'native/root/rtx-remix/mods/broken/mod.usda': b'x'}),
         content / '1005' / 'broken.gma')
    # Workshop 1006: an ordinary addon, no manifest.
    pack(a.gmapack, write_package(src / 'ordinary', None, {'lua/autorun/hello.lua': b'print(1)\n'}),
         content / '1006' / 'ordinary.gma')
    # Workshop 2002: a valid package GMod's addon list disables.
    pack(a.gmapack, write_package(src / 'disabled', {'id': 'disabled-pack', 'version': '1.0.0', 'kinds': ['root-files'],
                                                     'root_files': [{'path': 'rtx-remix/mods/d'}]},
                                  {'native/root/rtx-remix/mods/d/mod.usda': b'x'}),
         content / '2002' / 'disabled.gma')

    config = {'schema': 1, 'allow': {
        'workshop': ['1001', '1003', '1004', '1005', '1006', '2002', '3003'],
        'local': ['garrysmod/addons/runtime-b.gma'],
        'dev_folders': [str(dev)]}}
    (game / 'native-loader').mkdir()
    (game / 'native-loader' / 'config.json').write_text(json.dumps(config, indent=1), encoding='utf-8')

    # Every package archive validates on its own; the broken and ordinary ones do not.
    for gma in [content / '1001' / 'runtime_a.gma', content / '1003' / '123456789_legacy.bin',
                content / '1004' / 'lua_mod.gma', game / 'garrysmod' / 'addons' / 'runtime-b.gma']:
        run([a.nlctl, 'manifest', str(gma)], expect=0)
    run([a.nlctl, 'manifest', str(dev)], expect=0)
    run([a.nlctl, 'manifest', str(content / '1005' / 'broken.gma')], expect=1)
    run([a.nlctl, 'manifest', str(content / '1006' / 'ordinary.gma')], expect=1)

    plan = json.loads(run([a.nlctl, 'plan', str(game), '--json', '--steam-dir', str(scratch / 'no-steam')], expect=0).stdout)
    decisions = {(d['source'], d['label']): d for d in plan['decisions']}
    check(len(plan['decisions']) == 9, f'expected 9 decisions, got {len(plan["decisions"])}')

    def expect(source, label, active, reason=''):
        d = decisions[(source, label)]
        check(d['active'] is active, f'{source} {label}: active {d["active"]}, reason {d["reason"]!r}')
        check(reason in d['reason'], f'{source} {label}: reason {d["reason"]!r} lacks {reason!r}')
        return d

    runtime = expect('dev_folder', str(dev), True)
    check(runtime['activate_runtime'] is True and runtime['package']['version'] == '1.1.0-dev', f'dev runtime: {runtime}')
    expect('local', 'garrysmod/addons/runtime-b.gma', False, 'only one remix-runtime')
    expect('workshop', '1001', False, 'shadowed by dev_folder')
    expect('workshop', '1003', True)
    expect('workshop', '1004', True)
    expect('workshop', '1005', False, 'missing "version"')
    expect('workshop', '1006', False, 'not a native package')
    expect('workshop', '2002', False, 'disabled')
    expect('workshop', '3003', False, 'not installed')
    check(plan['runtime'] == 'runtime-a', f'runtime {plan["runtime"]!r}')
    check(plan['disabled_workshop'] == 1, f'disabled count {plan["disabled_workshop"]}')

    # A broken config stops the plan with exit 2 rather than allowing anything.
    (game / 'native-loader' / 'config.json').write_text('{"schema": 1, "alow": {}}', encoding='utf-8')
    run([a.nlctl, 'plan', str(game), '--steam-dir', str(scratch / 'no-steam')], expect=2)

    shutil.rmtree(scratch, ignore_errors=True)
    print('e2e_plan OK: 9 sources, every decision as expected')


if __name__ == '__main__':
    main()
