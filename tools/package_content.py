"""Builds an add-on package for the native loader (docs/PACKAGE_FORMAT.md): Lua add-on folders, Remix
mod folders and binary Lua modules. Each --addon folder is deployed to garrysmod/addons/<name> (kind
lua-addon; only the files gmad would publish), each --mod folder to rtx-remix/mods/<name> (kind
root-files), each --lua-bin file to garrysmod/lua/bin/<name> (kind lua-binary-module), all
replace-owned; --load-first declares a module's runtime DLL (ADR 0024); --addon-file takes one file
of an add-on from elsewhere (ADR 0026). Writes a package folder and/or a .gma packed with
tools/gmapack, with addon.json giving the Workshop title, type and tags; every file is hashed as it is
copied.

Usage: python tools/package_content.py --id <id> [--addon <folder>]... [--mod <folder>]... --gma <file.gma>
See package_content.py.md for the options, outputs and exit codes."""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

from package_fixes import collect, regular_file
from package_runtime import (GMAPACK, ID, SEMVER, PackageError, check_private, copy_hashed, inside, inventory_paths,
                             is_link, path_problem, replace_folder, sha256_of, write_inventories)
from package_workshop import ADDON_TAGS, ADDON_TYPES, find_nlctl

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gmapack'))
import gmapack  # noqa: E402

REQUIRES_LOADER = '>=0.2.0'       # the first loader with lua-addon and requires_remix (M5)
REQUIRES_LOADER_DEPS = '>=0.3.0'  # the first loader that reads module_dependencies (ADR 0024)
KINDS = ('lua-binary-module', 'lua-addon', 'root-files')  # manifest order, as package_fixes.py writes it
# A deployed folder name: [A-Za-z0-9_.-], with GMod's leading "!" that sorts an add-on first.
FOLDER_NAME = re.compile(r'^!?[A-Za-z0-9_.-]{1,64}$')
FILE_NAME = re.compile(r'^[A-Za-z0-9_.-]{1,64}$')


def addon_filter(folder, found, prefix, extra_ignores=()):
    """The files of an add-on folder that gmad would publish: GMod's whitelist, minus the patterns of
    the folder's own addon.json "ignore" list and of --ignore; addon.json itself is kept. Returns
    (kept, left out)."""
    ignores = [p.replace('\\', '/').lower() for p in extra_ignores]
    metadata = os.path.join(folder, 'addon.json')
    if os.path.isfile(metadata):
        try:
            with open(metadata, encoding='utf-8-sig') as fh:
                ignores += [str(p).lower() for p in json.load(fh).get('ignore', []) if isinstance(p, str)]
        except (OSError, ValueError, AttributeError) as error:
            raise PackageError('%s: addon.json cannot be read: %s' % (folder, error))
    kept, left_out = {}, []
    for rel, source in found.items():
        inner = rel[len(prefix) + 1:]
        lowered = inner.lower()
        if lowered == 'addon.json' or (gmapack.whitelisted(lowered) and not any(gmapack.wildcard(p, lowered) for p in ignores)):
            kept[rel] = source
        else:
            left_out.append(rel)
    return kept, left_out


def link_hashed(source, target):
    """Hard-links one file into the work folder and hashes it; copies it when a link is not possible
    (another volume). Only for a work folder that is packed and deleted, never for --out: a linked
    package folder would change with its sources."""
    os.makedirs(os.path.dirname(target), exist_ok=True)
    try:
        os.link(source, target)
    except OSError:
        return copy_hashed(source, target)
    size = os.stat(target).st_size
    return size, sha256_of(target)


def sources(args):
    """{package path: source file}, the root_files entries [(path, kind)], the junk and the add-on
    files left out by the gmad filter, the module dependencies and the add-on files --addon-file
    replaced ({package path: given file}), from every input option."""
    files, roots, junk, filtered, names, addons = {}, [], [], [], {}, {}
    folders = [('addon', 'garrysmod/addons', 'lua-addon', given, None) for given in args.addon]
    folders += [('addon-as', 'garrysmod/addons', 'lua-addon', given, name) for name, given in args.addon_as]
    folders += [('mod', 'rtx-remix/mods', 'root-files', given, None) for given in args.mod]
    for option, area, kind, given, name in folders:
        folder = os.path.abspath(given)
        name = name or os.path.basename(folder.rstrip('\\/'))
        if not os.path.isdir(folder):
            raise PackageError('--%s %s: no such folder' % (option, given))
        if is_link(folder):
            raise PackageError('--%s %s: refusing a linked folder' % (option, given))
        if not FOLDER_NAME.match(name):
            raise PackageError('--%s %s: the folder name "%s" must be 1-64 characters of A-Z a-z 0-9 _ . -, '
                               'optionally after a "!"' % (option, given, name))
        key = (area, name.lower())
        if key in names:
            raise PackageError('--%s %s and %s deploy to the same folder %s/%s' % (option, given, names[key], area, name))
        names[key] = given
        prefix = 'native/root/%s/%s' % (area, name)
        found = collect(folder, prefix, junk)
        if kind == 'lua-addon' and not args.no_addon_filter:
            found, left_out = addon_filter(folder, found, prefix, args.ignore)
            filtered += left_out
        if not found:
            raise PackageError('--%s %s has no files%s' % (option, given, '' if args.no_addon_filter or kind != 'lua-addon'
                                                               else ' that gmad would publish'))
        files.update(found)
        roots.append(('%s/%s' % (area, name), kind))
        if kind == 'lua-addon':
            addons[name.lower()] = name
    # One file of an add-on from elsewhere, such as a fix its own repository has and the add-on
    # folder does not yet (ADR 0026). Only a file the add-on has can be replaced, so a misspelled
    # path never adds one.
    replaced = {}
    for target, given in args.addon_file:
        name, slash, inner = target.replace('\\', '/').strip('/').partition('/')
        if not slash or not inner:
            raise PackageError('--addon-file %s: expected an add-on folder name and a path in it, such as '
                               'name/lua/file.lua' % target)
        if name.lower() not in addons:
            raise PackageError('--addon-file %s: %s is not an add-on given with --addon or --addon-as' % (target, name))
        wanted = ('native/root/garrysmod/addons/%s/%s' % (addons[name.lower()], inner)).lower()
        rel = next((r for r in files if r.lower() == wanted), None)
        if rel is None:
            raise PackageError('--addon-file %s: the add-on has no such file to replace' % target)
        if wanted in (r.lower() for r in replaced):
            raise PackageError('--addon-file %s is given twice' % target)
        source = os.path.abspath(given)
        if not os.path.isfile(source):
            raise PackageError('--addon-file %s %s: no such file' % (target, given))
        regular_file(source)
        files[rel] = source
        replaced[rel] = given
    lua_bin = {}
    for given in args.lua_bin:
        source = os.path.abspath(given)
        name = os.path.basename(source)
        if not os.path.isfile(source):
            raise PackageError('--lua-bin %s: no such file' % given)
        regular_file(source)
        if not FILE_NAME.match(name):
            raise PackageError('--lua-bin %s: the file name must be 1-64 characters of A-Z a-z 0-9 _ . -' % given)
        if name.lower() in lua_bin:
            raise PackageError('--lua-bin %s and %s have the same name' % (given, lua_bin[name.lower()]))
        lua_bin[name.lower()] = given
        files['native/root/garrysmod/lua/bin/' + name] = source
        roots.append(('garrysmod/lua/bin/' + name, 'lua-binary-module'))
    dependencies = []
    for rule in args.load_first:
        module, sep, first = rule.partition('=')
        if not sep or not module or not first:
            raise PackageError('--load-first %s: expected MODULE=FILE, two --lua-bin file names' % rule)
        for name in (module, first):
            if name.lower() not in lua_bin or not name.lower().endswith('.dll'):
                raise PackageError('--load-first %s: %s is not a .dll given with --lua-bin' % (rule, name))
        if module.lower() == first.lower():
            raise PackageError('--load-first %s: a module cannot be loaded before itself' % rule)
        spelled = {n.lower(): os.path.basename(g) for n, g in lua_bin.items()}
        entry = next((d for d in dependencies if d['module'].lower() == 'garrysmod/lua/bin/' + module.lower()), None)
        if entry is None:
            entry = {'module': 'garrysmod/lua/bin/' + spelled[module.lower()], 'load_first': []}
            dependencies.append(entry)
        path = 'garrysmod/lua/bin/' + spelled[first.lower()]
        if path.lower() in (p.lower() for p in entry['load_first']):
            raise PackageError('--load-first %s is given twice' % rule)
        entry['load_first'].append(path)
    if not roots:
        raise PackageError('give at least one --addon, --addon-as, --mod or --lua-bin')
    return files, roots, junk, filtered, dependencies, replaced


def build(args):
    if not args.out and not args.gma:
        raise PackageError('give --out, --gma or both')
    if not ID.match(args.id):
        raise PackageError('--id %s: 1-64 characters of a-z 0-9 -, starting with a letter or digit' % args.id)
    if args.version and not SEMVER.match(args.version):
        raise PackageError('--version %s is not a Semantic Versioning 2.0.0 version' % args.version)
    if args.name is not None and not 1 <= len(args.name.encode('utf-8')) <= 128:
        raise PackageError('--name must be 1-128 bytes of UTF-8')
    if len(args.tag) > 2:
        raise PackageError('at most two --tag')
    files, roots, junk, filtered, dependencies, replaced = sources(args)
    out = os.path.abspath(args.out) if args.out else None
    gma = os.path.abspath(args.gma) if args.gma else None
    for target in filter(None, (out, gma)):
        for folder in args.addon + [given for _, given in args.addon_as] + args.mod:
            if inside(folder, target) or inside(target, folder):
                raise PackageError('the output %s must be outside %s' % (target, folder))
    if out and gma and inside(out, gma):
        raise PackageError('--gma %s must be outside --out' % gma)
    if out and os.path.lexists(out):
        if is_link(out) or not os.path.isdir(out):
            raise PackageError('--out %s exists and is not a folder' % out)
        if os.listdir(out) and not (args.force and os.path.isfile(os.path.join(out, 'native', 'manifest.json'))):
            raise PackageError('--out %s is not empty (--force replaces an earlier package folder)' % out)
    if gma and os.path.lexists(gma) and not args.force:
        raise PackageError('--gma %s exists (use --force)' % gma)
    inventories = inventory_paths([o for o in (out, gma) if o])

    for rel, source in files.items():
        problem = path_problem(rel)
        if problem:
            raise PackageError('%s: %s (from %s)' % (rel, problem, source))
    folded = {}
    for rel in files:
        if rel.lower() in folded:
            raise PackageError('%s and %s differ only in case' % (folded[rel.lower()], rel))
        folded[rel.lower()] = rel
    allowed = check_private(files, args.allow_private)
    used = {kind for _, kind in roots}
    kinds = [kind for kind in KINDS if kind in used]
    newest = max(os.stat(path).st_mtime for path in files.values())
    # With --link, a work folder that is only packed holds hard links to the sources instead of copies
    # (several GB of textures are not written twice); one that becomes --out always holds copies. Not the
    # default: a link changes the source file's record (its link count), and some sources are only read.
    place = link_hashed if args.link and not out else copy_hashed

    work = (out or gma) + '.partial-%d' % os.getpid()
    if os.path.lexists(work):
        raise PackageError('%s is in the way; delete it' % work)
    os.makedirs(work)
    try:
        listed = {}
        for rel in sorted(files, key=str.lower):
            size, digest = place(files[rel], os.path.join(work, *rel.split('/')))
            listed[rel] = {'size': size, 'sha256': digest}
        content = hashlib.sha256(''.join('%s\0%s\n' % (rel.lower(), listed[rel]['sha256'])
                                         for rel in sorted(listed, key=str.lower)).encode('utf-8')).hexdigest()
        # 0.0.0-dev.<UTC time of the newest input>+<the files' digest, 8 digits>: the same inputs give
        # the same version, and any change of a file a new one.
        version = args.version or '0.0.0-dev.%s+%s' % (
            datetime.datetime.fromtimestamp(newest, datetime.timezone.utc).strftime('%Y%m%d%H%M'), content[:8])
        name = args.name or args.id
        manifest = {
            'schema': 1,
            'id': args.id,
            'name': name,
            'version': version,
            'kinds': kinds,
            'requires_loader': REQUIRES_LOADER_DEPS if dependencies else REQUIRES_LOADER,
            'requires_remix': bool(args.requires_remix),
            'files': listed,
            'root_files': [{'path': path, 'policy': 'replace-owned'} for path, _ in sorted(roots, key=lambda r: r[0].lower())],
        }
        if dependencies:
            manifest['module_dependencies'] = dependencies
        text = (json.dumps(manifest, indent=2, ensure_ascii=True) + '\n').encode('utf-8')
        with open(os.path.join(work, 'native', 'manifest.json'), 'xb') as fh:
            fh.write(text)
        addon = {'title': args.title or name, 'type': args.type, 'tags': args.tag, 'description': args.description}
        with open(os.path.join(work, 'addon.json'), 'x', encoding='utf-8', newline='\n') as fh:
            fh.write(json.dumps(addon, indent=2) + '\n')

        # nlctl refuses a folder with hard-linked files (packages may not alias other files), so a work
        # folder of links is checked as the packed archive instead.
        checker = find_nlctl() if not args.no_validate else None
        if checker and place is copy_hashed:
            validate(checker, work)
        summary = {
            'id': args.id,
            'version': version,
            'files': len(listed),
            'bytes': sum(f['size'] for f in listed.values()),
            'manifest_sha256': hashlib.sha256(text).hexdigest(),
            'kinds': kinds,
            'requires_remix': bool(args.requires_remix),
            'addons': [path.split('/')[-1] for path, kind in roots if kind == 'lua-addon'],
            'mods': [path.split('/')[-1] for path, kind in roots if kind == 'root-files'],
            'lua_bin': [path.split('/')[-1] for path, kind in roots if kind == 'lua-binary-module'],
            'module_dependencies': dependencies,
            'replaced': {rel: replaced[rel] for rel in sorted(replaced, key=str.lower)},
            'workshop': addon,
            'junk': sorted(junk, key=str.lower),
            'filtered': sorted(filtered, key=str.lower),
            'allowed_private': sorted(allowed, key=str.lower),
            'validated_by': str(checker) if checker else None,
            'linked': place is link_hashed,
            'folder': out,
            'gma': gma,
        }
        if gma:
            staged = gma + '.unchecked-%d' % os.getpid()
            try:
                pack(work, staged, int(newest))
                if checker and place is link_hashed:
                    validate(checker, staged)
                os.replace(staged, gma)
            finally:
                if os.path.lexists(staged):
                    os.remove(staged)
            summary['gma_bytes'] = os.stat(gma).st_size
            summary['gma_sha256'] = sha256_of(gma)
        if out:
            replace_folder(work, out)
            work = None
        summary['inventory'] = write_inventories(
            inventories, '%s %s: %d files and native/manifest.json, %s bytes; written by package_content.py' % (
                args.id, version, len(listed), format(summary['bytes'], ',')),
            listed, files, text, {rel: 'allowed with --allow-private: ' + reason for rel, reason in allowed.items()})
        return summary
    finally:
        if work and os.path.isdir(work):
            shutil.rmtree(work)


def validate(checker, location):
    done = subprocess.run([str(checker), 'manifest', location], capture_output=True, text=True)
    if done.returncode:
        raise PackageError('nlctl refuses the package: ' + (done.stdout + done.stderr).strip()[-1500:])


def pack(folder, gma, timestamp):
    """gmapack takes the title, type and tags from addon.json, keeps the case of every path and writes
    the archive through a temporary file. The timestamp is the newest input's, so the same inputs give
    the same bytes."""
    command = [sys.executable, GMAPACK, 'create', '--folder', folder, '--out', gma, '--preserve-case', '--quiet',
               '--author', 'package_content.py', '--timestamp', str(timestamp)]
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        raise PackageError('gmapack failed (%d): %s' % (done.returncode, (done.stderr or done.stdout).strip()))


def print_summary(s):
    print('Package %s %s: %d files, %s bytes' % (s['id'], s['version'], s['files'], format(s['bytes'], ',')))
    print('  kinds      %s%s' % (', '.join(s['kinds']), ', requires Remix' if s['requires_remix'] else ''))
    if s['addons']:
        print('  add-ons    %s' % ', '.join(s['addons']))
    if s['mods']:
        print('  mods       %s' % ', '.join(s['mods']))
    if s['lua_bin']:
        print('  lua/bin    %s' % ', '.join(s['lua_bin']))
    for item in s['module_dependencies']:
        print('  load first %s before %s' % (', '.join(p.split('/')[-1] for p in item['load_first']), item['module'].split('/')[-1]))
    for rel, given in s['replaced'].items():
        print('  replaced   %s from %s' % (rel[len('native/root/garrysmod/addons/'):], given))
    print('  workshop   "%s", type %s, tags %s' % (s['workshop']['title'], s['workshop']['type'],
                                                   ', '.join(s['workshop']['tags']) or 'none'))
    if s['junk']:
        print('  junk       %d files left out (--json lists them)' % len(s['junk']))
    if s['filtered']:
        print('  filtered   %d add-on files gmad would not publish left out (--json lists them)' % len(s['filtered']))
    for rel in s['allowed_private']:
        print('  private    %s (allowed with --allow-private)' % rel)
    print('  manifest   sha256 %s, %s' % (s['manifest_sha256'], 'checked by ' + s['validated_by'] if s['validated_by']
                                         else 'not checked (no nlctl built)'))
    if s['folder']:
        print('  folder     %s' % s['folder'])
    if s['gma']:
        print('  gma        %s (%s bytes, sha256 %s)' % (s['gma'], format(s['gma_bytes'], ','), s['gma_sha256']))
    for path in s['inventory']:
        print('  inventory  %s' % path)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='backslashreplace')
    ap = argparse.ArgumentParser(description='Build an add-on package (Lua add-ons, Remix mods, binary modules) for the loader.')
    ap.add_argument('--addon', action='append', default=[], metavar='FOLDER',
                    help='a Lua add-on folder, deployed to garrysmod/addons/<its name> (repeatable)')
    ap.add_argument('--addon-as', action='append', default=[], nargs=2, metavar=('NAME', 'FOLDER'),
                    help='a Lua add-on folder, deployed to garrysmod/addons/NAME (repeatable)')
    ap.add_argument('--no-addon-filter', action='store_true',
                    help='package every file of the add-on folders, not only those gmad would publish')
    ap.add_argument('--ignore', action='append', default=[], metavar='PATTERN',
                    help='leave out add-on files matching this gmad pattern, as addon.json "ignore" does (repeatable)')
    ap.add_argument('--addon-file', action='append', default=[], nargs=2, metavar=('PATH', 'FILE'),
                    help='take PATH, an add-on folder name and a file the add-on has (name/lua/file.lua), from FILE '
                         'instead (repeatable; ADR 0026)')
    ap.add_argument('--mod', action='append', default=[], metavar='FOLDER',
                    help='a Remix mod folder, deployed to rtx-remix/mods/<its name> (repeatable)')
    ap.add_argument('--lua-bin', action='append', default=[], metavar='FILE',
                    help='a binary module or one of its files, deployed to garrysmod/lua/bin/<its name> (repeatable)')
    ap.add_argument('--load-first', action='append', default=[], metavar='MODULE=FILE',
                    help='load the --lua-bin FILE (a runtime DLL) before GMod loads the --lua-bin MODULE (repeatable; ADR 0024)')
    ap.add_argument('--id', required=True, help='package id (a-z 0-9 -)')
    ap.add_argument('--name', help='display name (default: the id)')
    ap.add_argument('--version', help='package version (default 0.0.0-dev.<newest input time>+<files digest>)')
    ap.add_argument('--requires-remix', action='store_true',
                    help='hide the add-ons in sessions without an active Remix runtime (ADR 0013)')
    ap.add_argument('--title', help='the Workshop title written to addon.json (default: the name)')
    ap.add_argument('--description', default='', help='the addon.json description')
    ap.add_argument('--type', default='tool', choices=ADDON_TYPES, help='GMod add-on type (default tool)')
    ap.add_argument('--tag', action='append', default=[], choices=ADDON_TAGS, help='GMod add-on tag (at most two)')
    ap.add_argument('--out', help='package folder to write (a development-folder source)')
    ap.add_argument('--gma', help='.gma archive to write (a local or Workshop source)')
    ap.add_argument('--allow-private', action='append', default=[], metavar='PATH',
                    help='package this file although it looks private or machine-specific: its package path (repeatable)')
    ap.add_argument('--link', action='store_true',
                    help='with --gma alone: hard-link the sources into the work folder instead of copying them')
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
        print_summary(summary)
    return 0


if __name__ == '__main__':
    sys.exit(main())
