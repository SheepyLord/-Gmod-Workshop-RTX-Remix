"""Builds the ReShade part of the RTX package (ADR 0028): ReShade's 64-bit DLL, unchanged, from its
official setup (reshade.me), as a Vulkan layer the loader enables in RTX sessions. The setup's and
the DLL's SHA-256 are pinned below, so any other file is refused. The layer manifest is the loader's
own: layer VK_LAYER_nativeloader_reshade, so it never collides with the layer ReShade's setup
registers for every Vulkan application. ReShade's licence (third_party/reshade/LICENSE.md) and a
notice go beside the DLL. Writes a package folder (--out) and/or a .gma (--gma); never runs the setup.

Usage: python tools/package_reshade.py --setup ReShade_Setup_6.8.0.exe --out <folder>
See package_reshade.py.md for the options, outputs and exit codes."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile

from package_runtime import GMAPACK, PackageError, replace_folder, sha256_of
from package_workshop import find_nlctl

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LICENSE = os.path.join(REPO, 'third_party', 'reshade', 'LICENSE.md')
REQUIRES_LOADER = '>=0.5.0'  # the first loader that reads a "reshade" section (ADR 0028)
LAYER_NAME = 'VK_LAYER_nativeloader_reshade'
LAYER_FILE = 'VkLayer_nativeloader_reshade.json'
FOLDER = 'native/payload/reshade'
# Versions this tool packages: the setup from reshade.me, the DLL inside it, and ReShade's licence at
# that version's tag (github.com/crosire/reshade, LICENSE.md).
PINNED = {
    '6.8.0': {
        'setup': '207aea16205fbf952bc8fe1879966672454cf04002e7ad34237c7990a5b3c0b4',
        'dll': 'b2945c29e7095491a901746b400e58db9b1592ab092bacf2a888ce37f02d08da',
        'dll_size': 5255448,
        'license': '237ded5b8344f820113efab1e65e91e1f159d9202c5b4856606a0590d3ffdab0',
    },
}
# Upstream's ReShade64.json with the loader's layer name, and without the implicit-layer switch
# (disable_environment): the loader enables this layer for an RTX session through VK_INSTANCE_LAYERS.
LAYER = {
    'file_format_version': '1.0.0',
    'layer': {
        'name': LAYER_NAME,
        'type': 'GLOBAL',
        'library_path': '.\\ReShade64.dll',
        'api_version': '1.3.268',
        'implementation_version': '1',
        'description': "crosire's ReShade post-processing injector for 64-bit, enabled by the GMod native loader in RTX sessions",
        'device_extensions': [
            {'name': 'VK_EXT_tooling_info', 'spec_version': '1', 'entrypoints': ['vkGetPhysicalDeviceToolPropertiesEXT']},
        ],
    },
}
NOTICE = """# ReShade {version} for RTX sessions

This folder holds ReShade {version} by crosire (https://reshade.me, source:
https://github.com/crosire/reshade), unchanged: `ReShade64.dll` comes from the official setup
`ReShade_Setup_{version}.exe` (SHA-256 {setup}). ReShade is licensed under the BSD 3-clause licence
in `LICENSE.md`. It includes open-source libraries whose licences ReShade shows on the About page of
its overlay: MinHook, Dear ImGui, ImGuiColorTextEdit, glad, UTF8-CPP, stb_image and stb_image_write,
DDS loading from SOIL, fpng, SPIR-V headers, Vulkan Memory Allocator, OpenVR, OpenXR, Solarized,
Fork Awesome and the libjxl simple lossless encoder.

The GMod native loader enables it as the Vulkan layer `{layer}` (`{layer_file}`) in RTX
sessions only. Its settings live in `native-loader\\reshade` in the game folder; the first RTX
session takes them from a ReShade set up for the game (`bin\\win64\\ReShade.ini`), whose own files
are never changed. See the loader's README for `remix.reshade` ("auto", "on", "off").
"""


def extract_dll(setup, pinned):
    """ReShade64.dll from the ZIP the setup carries at its end, checked against the pinned hash."""
    if sha256_of(setup) != pinned['setup']:
        raise PackageError('%s is not the pinned ReShade setup (SHA-256 %s)' % (setup, pinned['setup']))
    try:
        with zipfile.ZipFile(setup) as archive:
            data = archive.read('ReShade64.dll')
    except (zipfile.BadZipFile, KeyError) as error:
        raise PackageError('%s holds no ReShade64.dll: %s' % (setup, error))
    if len(data) != pinned['dll_size'] or hashlib.sha256(data).hexdigest() != pinned['dll']:
        raise PackageError('ReShade64.dll in %s is not the pinned one' % setup)
    return data


def build(args):
    pinned = PINNED.get(args.version)
    if not pinned:
        raise PackageError('ReShade %s is not pinned in this tool (pinned: %s)' % (args.version, ', '.join(PINNED)))
    out = os.path.abspath(args.out) if args.out else None
    gma = os.path.abspath(args.gma) if args.gma else None
    if not out and not gma:
        raise PackageError('give --out, --gma or both')
    for target in (out, gma):
        if target and os.path.lexists(target) and not args.force:
            raise PackageError('%s exists; --force replaces it' % target)
    with open(LICENSE, 'rb') as fh:
        license_text = fh.read()
    if hashlib.sha256(license_text).hexdigest() != pinned['license']:
        raise PackageError('%s is not ReShade %s\'s LICENSE.md' % (LICENSE, args.version))
    contents = {
        FOLDER + '/ReShade64.dll': extract_dll(args.setup, pinned),
        FOLDER + '/' + LAYER_FILE: (json.dumps(LAYER, indent=2) + '\n').encode('utf-8'),
        FOLDER + '/LICENSE.md': license_text,
        FOLDER + '/README.md': NOTICE.format(version=args.version, setup=pinned['setup'], layer=LAYER_NAME,
                                             layer_file=LAYER_FILE).replace('\n', '\r\n').encode('utf-8'),
    }
    work = (out or gma) + '.partial-%d' % os.getpid()
    if os.path.lexists(work):
        raise PackageError('%s is in the way; delete it' % work)
    os.makedirs(work)
    try:
        listed = {}
        for rel in sorted(contents, key=str.lower):
            path = os.path.join(work, *rel.split('/'))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'xb') as fh:
                fh.write(contents[rel])
            listed[rel] = {'size': len(contents[rel]), 'sha256': hashlib.sha256(contents[rel]).hexdigest()}
        manifest = {
            'schema': 1,
            'id': 'reshade',
            'name': 'ReShade %s for RTX sessions' % args.version,
            'version': args.version,
            'kinds': ['reshade'],
            'requires_loader': REQUIRES_LOADER,
            'files': listed,
            'reshade': {'layer': 'reshade/' + LAYER_FILE},
        }
        text = (json.dumps(manifest, indent=2, ensure_ascii=True) + '\n').encode('utf-8')
        with open(os.path.join(work, 'native', 'manifest.json'), 'xb') as fh:
            fh.write(text)
        addon = {'title': 'ReShade %s for RTX sessions (native loader package)' % args.version, 'type': 'tool', 'tags': [],
                 'description': 'ReShade as a Vulkan layer for RTX sessions of the GMod native loader.'}
        with open(os.path.join(work, 'addon.json'), 'x', encoding='utf-8', newline='\n') as fh:
            fh.write(json.dumps(addon, indent=2) + '\n')
        checker = find_nlctl() if not args.no_validate else None
        if checker:
            done = subprocess.run([str(checker), 'manifest', work], capture_output=True, text=True)
            if done.returncode:
                raise PackageError('nlctl refuses the package: ' + (done.stdout + done.stderr).strip()[-1500:])
        summary = {'id': manifest['id'], 'version': args.version, 'files': len(listed),
                   'bytes': sum(f['size'] for f in listed.values()), 'manifest_sha256': hashlib.sha256(text).hexdigest(),
                   'layer': LAYER_NAME, 'dll_sha256': pinned['dll'], 'validated_by': str(checker) if checker else None,
                   'folder': out, 'gma': gma}
        if gma:
            staged = gma + '.unchecked-%d' % os.getpid()
            try:
                command = [sys.executable, GMAPACK, 'create', '--folder', work, '--out', staged, '--preserve-case', '--quiet',
                           '--author', 'package_reshade.py', '--timestamp', str(int(os.stat(args.setup).st_mtime))]
                done = subprocess.run(command, capture_output=True, text=True)
                if done.returncode:
                    raise PackageError('gmapack failed (%d): %s' % (done.returncode, (done.stderr or done.stdout).strip()))
                os.replace(staged, gma)
            finally:
                if os.path.lexists(staged):
                    os.remove(staged)
            summary['gma_bytes'] = os.stat(gma).st_size
            summary['gma_sha256'] = sha256_of(gma)
        if out:
            replace_folder(work, out)
            work = None
        return summary
    finally:
        if work and os.path.isdir(work):
            shutil.rmtree(work)


def main(argv=None):
    ap = argparse.ArgumentParser(description='Build the ReShade part of the RTX package (a Vulkan layer for RTX sessions).')
    ap.add_argument('--setup', required=True, help="ReShade's official setup, ReShade_Setup_<version>.exe (never run)")
    ap.add_argument('--version', default='6.8.0', help='the ReShade version it is (default 6.8.0; must be pinned)')
    ap.add_argument('--out', help='package folder to write')
    ap.add_argument('--gma', help='.gma archive to write')
    ap.add_argument('--no-validate', action='store_true', help='skip the nlctl check of the manifest')
    ap.add_argument('--force', action='store_true', help='replace an earlier package folder or archive')
    ap.add_argument('--json', action='store_true', help='print the summary as JSON')
    args = ap.parse_args(argv)
    try:
        summary = build(args)
    except (PackageError, OSError) as err:
        print('error: %s' % err, file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print('Package %s %s: %d files, %s bytes, layer %s' % (summary['id'], summary['version'], summary['files'],
                                                               format(summary['bytes'], ','), summary['layer']))
        print('  manifest   sha256 %s, %s' % (summary['manifest_sha256'], 'checked by ' + summary['validated_by']
                                             if summary['validated_by'] else 'not checked (no nlctl built)'))
        for key in ('folder', 'gma'):
            if summary[key]:
                print('  %-10s %s' % (key, summary[key]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
