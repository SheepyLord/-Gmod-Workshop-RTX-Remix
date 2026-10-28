"""Builds an RTX Remix runtime package (docs/PACKAGE_FORMAT.md) from a build of the user's
dxvk-remix fork: a package folder (usable as a development folder) and, optionally, a .gma packed
with tools/gmapack. Every file it lists is hashed while it is copied.

Usage: python tools/package_runtime.py --runtime <fork>\\_output --out <folder> [--gma <file.gma>]
See package_runtime.py.md for the options, outputs and exit codes."""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GMAPACK = os.path.join(HERE, 'gmapack', 'gmapack.py')

DEFAULT_ID = 'rtx-remix-runtime'
REQUIRES_LOADER = '>=0.1.0'  # the first loader version that activates a runtime (M4)
# RTXLauncher also passes +mat_disable_d3d9ex 1. Left out: the game archives that variable into
# config.cfg, so it would reach later RTX-off sessions, and -nod3d9ex already covers this one
# (docs/RESEARCH.md section 11).
LAUNCH_ARGS = ['-dxlevel', '90', '-nod3d9ex']
# Build by-products that the runtime never loads. PDBs only on request: d3d9.pdb alone is ~140 MB.
EXCLUDED = ('.exp', '.lib', '.ilk', '.bak')
PDB = '.pdb'
CHUNK = 1 << 20
MAX_PATH_BYTES = 1024
MAX_COMPONENT_BYTES = 255
DEVICE_NAMES = ({'con', 'prn', 'aux', 'nul', 'conin$', 'conout$', 'clock$'} |
                {'com%s' % c for c in '0123456789¹²³'} |
                {'lpt%s' % c for c in '0123456789¹²³'})
ENV_NAME = re.compile(r'^(DXVK|RTX)_[A-Z0-9_]{1,64}$')
ID = re.compile(r'^[a-z0-9][a-z0-9-]{0,63}$')
SEMVER = re.compile(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$')


class PackageError(Exception):
    pass


def path_problem(path):
    """The loader's path rules (nl::paths::problem, docs/PACKAGE_FORMAT.md), plus its ASCII rule for
    deployed paths. Returns why the path is refused, or ''."""
    if not path or len(path.encode('utf-8')) > MAX_PATH_BYTES:
        return 'empty or longer than %d bytes' % MAX_PATH_BYTES
    if any(not ' ' <= c <= '~' for c in path):
        return 'only printable ASCII is allowed in deployed paths'
    if any(c in '\\:<>"|?*' for c in path):
        return 'contains one of \\ : < > " | ? *'
    for part in path.split('/'):
        if part in ('', '.', '..'):
            return 'has an empty, "." or ".." component'
        if len(part) > MAX_COMPONENT_BYTES:
            return 'has a component longer than %d bytes' % MAX_COMPONENT_BYTES
        if part.startswith(' ') or part.endswith((' ', '.')):
            return 'has a component that starts with a space or ends with a space or "."'
        if part.split('.', 1)[0].lower() in DEVICE_NAMES:
            return 'names a Windows device (%s)' % part
        if re.search(r'~\d', part):
            return 'looks like an 8.3 short name (~ and a digit)'
    return ''


def is_link(path):
    return os.path.islink(path) or (hasattr(os.path, 'isjunction') and os.path.isjunction(path))


def runtime_files(runtime, with_pdbs):
    """{package-relative path under runtime/: source file}, sorted; links and odd files refused."""
    found = {}
    for folder, dirs, names in os.walk(runtime):
        dirs.sort()
        for name in dirs:
            if is_link(os.path.join(folder, name)):
                raise PackageError('refusing a linked folder in the runtime: %s' % os.path.join(folder, name))
        for name in sorted(names):
            source = os.path.join(folder, name)
            lower = name.lower()
            if lower.endswith(EXCLUDED) or (lower.endswith(PDB) and not with_pdbs):
                continue
            if is_link(source) or not stat.S_ISREG(os.stat(source, follow_symlinks=False).st_mode):
                raise PackageError('refusing a link or special file in the runtime: %s' % source)
            rel = os.path.relpath(source, runtime).replace(os.sep, '/')
            found[rel] = source
    return found


def copy_hashed(source, target):
    """Copies one file, hashing what it writes. The source must not change meanwhile."""
    expected = os.stat(source).st_size
    digest = hashlib.sha256()
    size = 0
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(source, 'rb') as src, open(target, 'xb') as dst:
        while True:
            block = src.read(CHUNK)
            if not block:
                break
            digest.update(block)
            dst.write(block)
            size += len(block)
    if size != expected or os.stat(source).st_size != expected:
        raise PackageError('%s changed while it was copied' % source)
    return size, digest.hexdigest()


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as fh:
        while True:
            block = fh.read(CHUNK)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def default_version(d3d9):
    """0.0.0-dev.<UTC build time of d3d9.dll>+<its SHA-256, 8 digits>: two builds never collide."""
    built = datetime.datetime.fromtimestamp(os.stat(d3d9).st_mtime, datetime.timezone.utc)
    return '0.0.0-dev.%s+%s' % (built.strftime('%Y%m%d%H%M'), sha256_of(d3d9)[:8])


def parse_env(entries):
    env = {}
    for entry in entries:
        name, sep, value = entry.partition('=')
        if not sep or not ENV_NAME.match(name):
            raise PackageError('--env %s: expected NAME=VALUE with NAME DXVK_* or RTX_* (A-Z, 0-9, _)' % entry)
        if name in ('DXVK_CONFIG_FILE', 'DXVK_RTX_CONFIG_FILE'):
            raise PackageError('--env %s: config files go in with --rtx-conf / --dxvk-conf' % name)
        if len(value) > 1024 or any(not ' ' <= c <= '~' for c in value):
            raise PackageError('--env %s: the value must be at most 1024 printable ASCII characters' % name)
        if name in env:
            raise PackageError('--env %s given twice' % name)
        env[name] = value
    return env


def layer_targets(kind, files):
    """Config layers keep their order: config/<kind>/01_<name>, 02_<name>, ..."""
    out = []
    for number, source in enumerate(files, 1):
        name = os.path.basename(source)
        if not name.lower().endswith('.conf'):
            raise PackageError('--%s-conf %s: a layer must be a .conf file' % (kind, source))
        if not os.path.isfile(source):
            raise PackageError('--%s-conf %s: file not found' % (kind, source))
        out.append(('config/%s/%02d_%s' % (kind, number, name), source))
    return out


def inside(parent, child):
    parent, child = os.path.normcase(os.path.abspath(parent)), os.path.normcase(os.path.abspath(child))
    return child == parent or child.startswith(parent.rstrip('\\/') + os.sep)


def build(args):
    runtime = os.path.abspath(args.runtime)
    if not os.path.isdir(runtime):
        raise PackageError('--runtime %s: folder not found' % args.runtime)
    if not args.out and not args.gma:
        raise PackageError('give --out, --gma or both')
    if not ID.match(args.id):
        raise PackageError('--id %s: 1-64 characters of a-z 0-9 -, starting with a letter or digit' % args.id)
    out = os.path.abspath(args.out) if args.out else None
    gma = os.path.abspath(args.gma) if args.gma else None
    for target in filter(None, (out, gma)):
        if inside(runtime, target) or inside(target, runtime):
            raise PackageError('the output %s must be outside the runtime folder' % target)
    if out and os.path.lexists(out):
        if is_link(out) or not os.path.isdir(out):
            raise PackageError('--out %s exists and is not a folder' % out)
        if os.listdir(out) and not (args.force and os.path.isfile(os.path.join(out, 'native', 'manifest.json'))):
            raise PackageError('--out %s is not empty (--force replaces an earlier package folder)' % out)
    if gma and os.path.lexists(gma) and not args.force:
        raise PackageError('--gma %s exists (use --force)' % gma)

    files = {'runtime/' + rel: source for rel, source in runtime_files(runtime, args.with_pdbs).items()}
    if args.d3d9_from:
        override = os.path.abspath(args.d3d9_from)
        for name in ('d3d9.dll', 'd3d9.pdb'):
            files.pop('runtime/' + name, None)
            source = os.path.join(override, name)
            if os.path.isfile(source) and (name == 'd3d9.dll' or args.with_pdbs):
                files['runtime/' + name] = source
    entry = 'runtime/d3d9.dll'
    if entry not in files:
        raise PackageError('no d3d9.dll in %s' % (args.d3d9_from or args.runtime))
    rtx_layers = layer_targets('rtx', args.rtx_conf)
    dxvk_layers = layer_targets('dxvk', args.dxvk_conf)
    for rel, source in rtx_layers + dxvk_layers:
        files[rel] = source
    for rel in files:
        problem = path_problem('native/payload/' + rel)
        if problem:
            raise PackageError('%s: %s' % (rel, problem))
    folded = {}
    for rel in files:
        if rel.lower() in folded:
            raise PackageError('%s and %s differ only in case' % (folded[rel.lower()], rel))
        folded[rel.lower()] = rel
    env = parse_env(args.env)
    version = args.version or default_version(files[entry])
    if not SEMVER.match(version):
        raise PackageError('--version %s is not a Semantic Versioning 2.0.0 version' % version)
    name = args.name or 'RTX Remix runtime %s' % version
    if not 1 <= len(name.encode('utf-8')) <= 128:
        raise PackageError('--name must be 1-128 bytes of UTF-8')

    # Built beside its destination and renamed into place, so a loader never sees half a package.
    work = (out or gma) + '.partial-%d' % os.getpid()
    if os.path.lexists(work):
        raise PackageError('%s is in the way; delete it' % work)
    os.makedirs(work)
    try:
        listed = {}
        for rel in sorted(files, key=str.lower):
            size, digest = copy_hashed(files[rel], os.path.join(work, 'native', 'payload', *rel.split('/')))
            listed['native/payload/' + rel] = {'size': size, 'sha256': digest}
        remix = {
            'entry': entry,
            'rtx_conf_layers': [rel for rel, _ in rtx_layers],
            'dxvk_conf_layers': [rel for rel, _ in dxvk_layers],
            'env': env,
            'launch_args': ([] if args.no_launch_args else list(LAUNCH_ARGS)) + (['-insecure'] if args.insecure else []),
            'prefer_system_vulkan_loader': not args.no_system_vulkan,
        }
        manifest = {
            'schema': 1,
            'id': args.id,
            'name': name,
            'version': version,
            'kinds': ['remix-runtime'],
            'requires_loader': REQUIRES_LOADER,
            'files': listed,
            'remix': remix,
        }
        text = (json.dumps(manifest, indent=2, ensure_ascii=True) + '\n').encode('utf-8')
        with open(os.path.join(work, 'native', 'manifest.json'), 'xb') as fh:
            fh.write(text)

        summary = {
            'id': args.id,
            'version': version,
            'files': len(listed),
            'bytes': sum(f['size'] for f in listed.values()),
            'manifest_sha256': hashlib.sha256(text).hexdigest(),
            'd3d9': files[entry],
            'd3d9_sha256': listed['native/payload/' + entry]['sha256'],
            'pdbs': bool(args.with_pdbs),
            'folder': out,
            'gma': gma,
        }
        if gma:
            pack(work, gma, name, files[entry], args.force)
        if out:
            replace_folder(work, out)
            work = None
        return summary
    finally:
        if work and os.path.isdir(work):
            shutil.rmtree(work)


def pack(folder, gma, title, d3d9, force):
    """gmapack keeps the case of every path and writes the archive through a temporary file. The
    timestamp is d3d9.dll's, so the same inputs give the same bytes."""
    command = [sys.executable, GMAPACK, 'create', '--folder', folder, '--out', gma, '--preserve-case', '--quiet',
               '--title', title, '--desc', 'RTX Remix runtime package for the native loader', '--type', 'tool',
               '--author', 'package_runtime.py', '--timestamp', str(int(os.stat(d3d9).st_mtime))]
    if force:
        command.append('--force')
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        raise PackageError('gmapack failed (%d): %s' % (done.returncode, (done.stderr or done.stdout).strip()))


def replace_folder(work, out):
    if not os.path.lexists(out):
        os.rename(work, out)
        return
    old = out + '.old-%d' % os.getpid()
    os.rename(out, old)
    os.rename(work, out)
    shutil.rmtree(old)


def main(argv=None):
    ap = argparse.ArgumentParser(description='Build an RTX Remix runtime package from a dxvk-remix build.')
    ap.add_argument('--runtime', required=True, help="the fork's complete runtime folder (_output)")
    ap.add_argument('--out', help='package folder to write (a development-folder source)')
    ap.add_argument('--gma', help='.gma archive to write (a local or Workshop source)')
    ap.add_argument('--d3d9-from', help='take d3d9.dll (and with --with-pdbs d3d9.pdb) from this build folder')
    ap.add_argument('--with-pdbs', action='store_true', help='include .pdb files')
    ap.add_argument('--rtx-conf', action='append', default=[], help='rtx.conf layer, lowest first (repeatable)')
    ap.add_argument('--dxvk-conf', action='append', default=[], help='dxvk.conf layer, lowest first (repeatable)')
    ap.add_argument('--env', action='append', default=[], help='NAME=VALUE for the runtime (DXVK_*, RTX_*; repeatable)')
    ap.add_argument('--id', default=DEFAULT_ID, help='package id (default %s)' % DEFAULT_ID)
    ap.add_argument('--version', help='package version (default 0.0.0-dev.<d3d9 build time>+<d3d9 hash>)')
    ap.add_argument('--name', help='display name')
    ap.add_argument('--no-launch-args', action='store_true', help='leave out -dxlevel 90 -nod3d9ex')
    ap.add_argument('--insecure', action='store_true',
                    help='add -insecure: patch sets (M5) apply only in insecure sessions, as the classic RTX launch line')
    ap.add_argument('--no-system-vulkan', action='store_true', help="do not ask for System32's vulkan-1.dll first")
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
        print('Package %s %s: %d files, %s bytes%s' % (summary['id'], summary['version'], summary['files'],
                                                      format(summary['bytes'], ','), '' if summary['pdbs'] else ' (no PDBs)'))
        print('  d3d9.dll   %s' % summary['d3d9'])
        print('  manifest   sha256 %s' % summary['manifest_sha256'])
        for key in ('folder', 'gma'):
            if summary[key]:
                print('  %-10s %s' % (key, summary[key]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
