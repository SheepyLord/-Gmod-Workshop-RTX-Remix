"""Builds the RTX fixes package (docs/PACKAGE_FORMAT.md, with the M5 additions of
docs/handover/M5-plan.md) from the user's fork of garrys-mod-rtx-remixed, which it only reads: the
fork's Lua add-ons and Remix mods, its built gmcl_ modules, its stdshader_dx6.dll as a module
override, the RTX block of its autoexec.cfg as session console variables, the seven patches64 patch
sets, and this repo's Lua companion. Writes a package folder and/or a .gma packed with
tools/gmapack, hashing every file while it is copied.

Usage: python tools/package_fixes.py --out <folder> [--gma <file.gma>] [--repo <fixes repo>]
See package_fixes.py.md for the options, outputs and exit codes."""

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

import companion_i18n
from package_runtime import (GMAPACK, ID, SEMVER, PackageError, check_private, copy_hashed, inside, inventory_paths,
                             is_link, path_problem, replace_folder, write_inventories)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_FIXES = os.path.join(os.path.dirname(REPO), 'garrys-mod-rtx-remixed')  # the checkout beside this repo
COMPANION = os.path.join(REPO, 'companion', 'nativeloader')
COMPANION_NAME = 'nativeloader'
PRESENTATION = os.path.join(REPO, 'companion', 'presentation')
# The companion's translations, built from companion/i18n/*.po into the add-on (companion_i18n.py).
COMPANION_I18N = 'native/root/garrysmod/addons/nativeloader/lua/nativeloader/i18n_data.lua'

DEFAULT_ID = 'rtx-fixes'
REQUIRES_LOADER = '>=0.2.0'  # the first loader with lua-addon, patch sets, module overrides, session cvars (M5)
MAIN_MODULE = 'gmcl_RTXFixesBinary_win64.dll'
MODULES = (MAIN_MODULE, 'gmcl_rtxwater_win64.dll')
DEBUG_MODULE = 'gmcl_rtxdebug_win64.dll'
DEBUG_ADDON = 'rtx_debug'
CLIENT_BOOTSTRAP = 'gmsv_nlrtxclient_win64.dll'
SHADER_DLL = 'stdshader_dx6.dll'
# Folders the fixes rewrite at run time (the ToPBR converter writes its results and its generation
# counter into its own Remix mod): create-only, like the seed data, so a reinstall or an update never
# finds them "not placed by the loader" and the converter's work is kept.
RUNTIME_WRITTEN = ('rtx-remix/mods/~gmod_topbr',)
SHADER_FILE = 'native/payload/shaders/' + SHADER_DLL
KINDS = ('lua-binary-module', 'lua-addon', 'root-files', 'patch-set', 'module-override')  # manifest order
# Never packaged: version-control metadata (submodules leave a .git file), Explorer and Finder files,
# backups. gmapack drops the first three kinds too, so the folder and the archive hold the same files.
JUNK = {'.git', '.gitattributes', '.gitignore', '.gitkeep', '.gitmodules', '.ds_store', 'desktop.ini', 'thumbs.db'}
ADDON_NAME = re.compile(r'^[A-Za-z0-9_.-]{1,64}$')  # [a-z0-9_.-] plus the fixes' mixed-case names (M5 plan)

# In-memory patch sets: the seven patches of patches64 from sambow23/SourceRTXTweaks (applied on disk by
# its applypatch.py, which RTXLauncher fetches at install time), as tabled in docs/RESEARCH.md section
# 12; each pattern matches exactly once in the PoC's build. (module, ((name, find, offset, replace), ...)):
# find is lowercase hex with ?? for any byte, replace is written at offset inside the matched bytes.
PATCH_SETS = (
    ('engine.dll', (
        ('mod_loadlighting_hdr', 'ff90????????85c0742b', 0, 'b80200000090'),             # Mod_LoadLighting: HDR type 2
        ('mod_loadworldlights_hdr', 'ff90????????85c00f84fa000000', 0, 'b80200000090'),  # Mod_LoadWorldlights: HDR
    )),
    ('shaderapidx9.dll', (
        ('zero_size_buffer_returns_4', '4833cce8????03004881c448', 0, '85c0750466b80400'),
        ('shader_constants_return_0', '4883ec084c', 0, '31c0c3'),
        ('skip_invalid_vertex_format_error', '4885db75??498b4500', 3, 'eb'),
    )),
    ('materialsystem.dll', (
        ('zero_size_buffer_guard', 'f77c24683bc10f4fc1488b8c24300100004833cce8????04004881c448010000', 0,
         '448b4424684585c0740341f7f839c80f4fc14881c448010000c3'),
    )),
    ('datacache.dll', (
        ('dx80_vtx_to_dx90_vtx', '647838302e767478', 0, '647839302e767478'),            # "dx80.vtx" -> "dx90.vtx"
    )),
)
PATCH_MODULE = re.compile(r'^[a-z0-9_]+\.dll$')
PATCH_NAME = re.compile(r'^[a-z0-9_]{1,64}$')
PATCH_FIND = re.compile(r'^(?:[0-9a-f]{2}|\?\?){1,256}$')
PATCH_REPLACE = re.compile(r'^(?:[0-9a-f]{2}){1,256}$')

# Session console variables (M5 plan): assignments only, so the generated .cfg cannot run anything else.
CVAR_NAME = re.compile(r'^[A-Za-z0-9_]{1,64}$')
CVAR_VALUE = re.compile(r'^[A-Za-z0-9_.+-]{0,32}$')
# Console commands that take an argument, so "name value" would run them. The name and value rules
# cannot tell a command from a variable; this list is a second guard, not a complete one.
COMMANDS = {'alias', 'bind', 'bind_mac', 'changelevel', 'cmd', 'connect', 'disconnect', 'echo', 'exec', 'exit',
            'host_writeconfig', 'incrementvar', 'kill', 'load', 'lua_openscript', 'lua_openscript_cl', 'lua_run',
            'lua_run_cl', 'map', 'multvar', 'playdemo', 'plugin_load', 'plugin_unload', 'quit', 'rcon', 'record',
            'retry', 'save', 'say', 'say_team', 'timedemo', 'toggle', 'unbind', 'unbindall', 'wait'}
# A banner is a rule line (// and 10 or more of one of = - * # ~), comment lines, and another rule
# line; its first non-empty comment line is its title. The RTX section is the text below a banner whose
# title says RTX, up to the next banner.
RULE = re.compile(r'^//\s*([=*#~-])\1{9,}\s*$')
RTX_TITLE = re.compile(r'\bRTX\b', re.I)


def policy_for(root_path):
    """Seed data and the folders the fixes rewrite at run time are create-only; the rest replace-owned."""
    lowered = root_path.lower()
    if lowered.startswith('garrysmod/data/') or lowered in RUNTIME_WRITTEN:
        return 'create-only'
    return 'replace-owned'


def walk_error(err):
    raise err


def is_junk(name):
    lower = name.lower()
    # GMod enumerates every loose file in lua/entities and tries to include it, including docs.
    return lower in JUNK or lower.endswith(('.bak', '.lua.md')) or (lower.startswith('.gmapack-') and lower.endswith('.part'))


def is_map_log(folder, name):
    """A map compiler's log beside its map (<add-on>/maps/<map>.log, as vbsp, vvis and vrad write it):
    the game never reads it and it holds the mapper's own paths, so it is left out as junk."""
    return name.lower().endswith('.log') and os.path.basename(folder).lower() == 'maps'


def regular_file(path):
    if is_link(path) or not stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode):
        raise PackageError('refusing a link or special file: %s' % path)


def collect(top, prefix, junk, docs=True):
    """{package path: source} for every file below top, as <prefix>/<relative path>. Junk (and, with
    docs=False, .md files) is left out, junk recorded in the junk list; links are refused."""
    found = {}
    for folder, dirs, names in os.walk(top, onerror=walk_error):
        for name in list(dirs):
            path = os.path.join(folder, name)
            if is_link(path):
                raise PackageError('refusing a linked folder: %s' % path)
            if is_junk(name):
                dirs.remove(name)
                junk.append(path)
        dirs.sort()
        for name in sorted(names):
            source = os.path.join(folder, name)
            if not docs and name.lower().endswith('.md'):
                continue
            if is_junk(name) or is_map_log(folder, name):
                junk.append(source)
                continue
            regular_file(source)
            found[prefix + '/' + os.path.relpath(source, top).replace(os.sep, '/')] = source
    return found


def subfolders(parent, what):
    """Names of the folders in parent, sorted without case; junk folders skipped, links refused."""
    if not os.path.isdir(parent):
        raise PackageError('%s not found: %s (is --repo the fixes repo?)' % (what, parent))
    names = []
    for name in sorted(os.listdir(parent), key=str.lower):
        path = os.path.join(parent, name)
        if is_junk(name) or not os.path.isdir(path):
            continue
        if is_link(path):
            raise PackageError('refusing a linked folder: %s' % path)
        names.append(name)
    return names


def add_to_addons(pairs, addons, files, junk):
    """--add-to-addon: files an add-on folder lacks, such as the licence texts a part keeps beside it in
    packages/ (its LICENSE and licenses/, ADR 0033). (PATH, SOURCE) pairs: PATH an add-on's name and a
    path in it, SOURCE a file or a folder (whose files go below PATH). Only new paths: a file the
    package already has is refused, so nothing of the add-on is replaced (--addon-file replaces).
    `addons` maps lower-case add-on names to their folder names. Adds to `files`; returns the added."""
    taken = {rel.lower() for rel in files}
    added = {}
    for target, given in pairs:
        name, slash, inner = target.replace('\\', '/').strip('/').partition('/')
        if not slash or not inner:
            raise PackageError('--add-to-addon %s: expected an add-on folder name and a path in it, such as name/LICENSE' % target)
        if name.lower() not in addons:
            raise PackageError('--add-to-addon %s: %s is not an add-on of this package' % (target, name))
        prefix = 'native/root/garrysmod/addons/%s/%s' % (addons[name.lower()], inner)
        source = os.path.abspath(given)
        if os.path.isdir(source):
            if is_link(source):
                raise PackageError('--add-to-addon %s %s: refusing a linked folder' % (target, given))
            found = collect(source, prefix, junk)
        elif os.path.isfile(source):
            regular_file(source)
            found = {prefix: source}
        else:
            raise PackageError('--add-to-addon %s %s: no such file or folder' % (target, given))
        for rel, src in found.items():
            if rel.lower() in taken:
                raise PackageError('--add-to-addon %s: the package already has %s' % (target, rel))
            taken.add(rel.lower())
            files[rel] = src
            added[rel] = src
    return added


def patch_sets():
    """The manifest's patch_sets from PATCH_SETS, checked against the loader's rules."""
    names = set()
    sets = []
    for module, patches in PATCH_SETS:
        if not PATCH_MODULE.match(module) or not patches:
            raise PackageError('patch set %s breaks the patch-set rules' % module)
        entries = []
        for name, find, offset, replace in patches:
            if (not PATCH_NAME.match(name) or name in names or not PATCH_FIND.match(find) or set(find) == {'?'}
                    or not PATCH_REPLACE.match(replace) or offset < 0 or offset + len(replace) // 2 > len(find) // 2):
                raise PackageError('patch %s breaks the patch-set rules' % name)
            names.add(name)
            entries.append({'name': name, 'find': find, 'offset': offset, 'replace': replace})
        sets.append({'module': module, 'patches': entries})
    return sets


def assignment(line):
    """(name, value, '') for a plain 'name value' assignment (the value unquoted or in double
    quotes, a // comment after it allowed), else (None, None, why not)."""
    if ';' in line:
        return None, None, "has ';' (several commands on one line)"
    tokens = []
    i = 0
    while i < len(line):
        if line[i].isspace():
            i += 1
        elif line.startswith('//', i):
            break
        elif line[i] == '"':
            end = line.find('"', i + 1)
            if end < 0:
                return None, None, 'unterminated quote'
            tokens.append((line[i + 1:end], True))
            i = end + 1
        else:
            start = i
            while i < len(line) and not line[i].isspace() and line[i] != '"' and not line.startswith('//', i):
                i += 1
            tokens.append((line[start:i], False))
    if not tokens or tokens[0][1]:
        return None, None, 'not of the form name value'
    name = tokens[0][0]
    if name.lower() in COMMANDS:
        return None, None, 'a command (%s), not a variable' % name.lower()
    if len(tokens) == 1:
        return None, None, 'no value: a command or a query, not an assignment'
    if len(tokens) > 2:
        return None, None, 'more than one value'
    value = tokens[1][0]
    if not CVAR_NAME.match(name):
        return None, None, 'the name is not 1-64 characters of A-Z a-z 0-9 _'
    if not CVAR_VALUE.match(value):
        return None, None, 'the value is not 0-32 characters of A-Z a-z 0-9 _ . + -'
    return name, value, ''


def rtx_sections(lines):
    """[(title, first line, end line)] (0-based, end exclusive) of every banner section titled RTX."""
    banners = []
    i = 0
    while i < len(lines):
        if RULE.match(lines[i].strip()):
            j = i + 1
            header = []
            while j < len(lines) and lines[j].strip().startswith('//') and not RULE.match(lines[j].strip()):
                header.append(lines[j].strip()[2:].strip())
                j += 1
            title = next((h for h in header if h), '')
            if title and j < len(lines) and RULE.match(lines[j].strip()):
                banners.append((i, j + 1, title))
                i = j + 1
                continue
        i += 1
    ends = [start for start, _, _ in banners[1:]] + [len(lines)]
    return [(title, body, end) for (_, body, title), end in zip(banners, ends) if RTX_TITLE.search(title)]


# Read when the device is created, before any cfg runs: in a session cfg it would only reach the next
# session (an RTX-off one included). The runtime's -nod3d9ex covers RTX sessions.
NEXT_SESSION_ONLY = {'mat_disable_d3d9ex': 'read before cfgs run; -nod3d9ex covers RTX sessions'}
# Names nl::manifest accepts in session_cvars (ADR 0010).
CVAR_PREFIXES = ('r_', 'mat_', 'cl_', 'gmod_', 'rtx_', 'studio_')


def session_cvars(path):
    """Session console variables from a .cfg: ({name: value}, report). Only the RTX section(s) when the
    file has one, else every line. Later assignments win (names compare without case, as the console's
    do); every other non-comment line is reported with the reason it was skipped."""
    with open(path, 'rb') as fh:
        lines = fh.read().decode('utf-8-sig', errors='replace').splitlines()
    sections = rtx_sections(lines)
    ranges = [(body, end) for _, body, end in sections] or [(0, len(lines))]
    taken = {}  # folded name -> (name, value, line number)
    skipped = []
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith('//'):
            continue
        if not any(body < number <= end for body, end in ranges):
            skipped.append({'line': number, 'text': line, 'reason': 'outside the RTX section'})
            continue
        name, value, why = assignment(line)
        if not why and name.lower() in NEXT_SESSION_ONLY:
            why = NEXT_SESSION_ONLY[name.lower()]
        if not why and not name.lower().startswith(CVAR_PREFIXES) and name.lower() != 'sv_cheats':
            why = 'the loader only accepts rendering variables (%s or sv_cheats)' % ', '.join(CVAR_PREFIXES)
        if why:
            skipped.append({'line': number, 'text': line, 'reason': why})
            continue
        earlier = taken.pop(name.lower(), None)
        if earlier:
            skipped.append({'line': earlier[2], 'text': lines[earlier[2] - 1].strip(),
                            'reason': 'set again on line %d' % number})
        taken[name.lower()] = (name, value, number)
    cvars = {name: value for name, value, _ in taken.values()}
    report = {
        'source': path,
        'section': ' + '.join(title for title, _, _ in sections) or None,  # None: the whole file
        'count': len(cvars),
        'skipped': sorted(skipped, key=lambda s: s['line']),
    }
    return cvars, report


def build(args):
    repo = os.path.abspath(args.repo)
    tree = os.path.join(repo, 'garrysmod')
    if not os.path.isdir(tree):
        raise PackageError('--repo %s: no garrysmod folder (is it the fixes repo?)' % args.repo)
    modules_from = os.path.abspath(args.modules_from or os.path.join(repo, 'x86_64', 'Release'))
    if not args.out and not args.gma:
        raise PackageError('give --out, --gma or both')
    if not ID.match(args.id):
        raise PackageError('--id %s: 1-64 characters of a-z 0-9 -, starting with a letter or digit' % args.id)
    if args.version and not SEMVER.match(args.version):
        raise PackageError('--version %s is not a Semantic Versioning 2.0.0 version' % args.version)
    if args.name is not None and not 1 <= len(args.name.encode('utf-8')) <= 128:
        raise PackageError('--name must be 1-128 bytes of UTF-8')
    cvars_source = None
    if not args.no_session_cvars:
        cvars_source = os.path.abspath(args.cvars_from or os.path.join(tree, 'garrysmod', 'cfg', 'autoexec.cfg'))
        if not os.path.isfile(cvars_source):
            raise PackageError('%s not found (give --cvars-from or --no-session-cvars)' % cvars_source)
    out = os.path.abspath(args.out) if args.out else None
    gma = os.path.abspath(args.gma) if args.gma else None
    for target in filter(None, (out, gma)):
        for source in filter(None, (repo, modules_from, COMPANION, cvars_source)):
            if inside(source, target) or inside(target, source):
                raise PackageError('the output %s must be outside %s' % (target, source))
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

    files = {}  # package path -> source file
    generated = None  # the companion's built translations (a scratch file, removed at the end)
    roots = []  # (root_files path, kind)
    junk = []
    addons_dir = os.path.join(tree, 'garrysmod', 'addons')
    addons = subfolders(addons_dir, 'the add-ons folder')
    known = {name.lower(): name for name in addons}
    if COMPANION_NAME in known:
        raise PackageError('the fixes have an add-on named %s, which is the companion\'s name' % known[COMPANION_NAME])
    excluded = set()
    for name in args.exclude_addon:
        if name.lower() not in known and name.lower() != COMPANION_NAME:
            raise PackageError('--exclude-addon %s: no such add-on (%s)' % (name, ', '.join(addons + [COMPANION_NAME])))
        excluded.add(name.lower())
    sources = [(name, os.path.join(addons_dir, name)) for name in addons if name.lower() not in excluded]
    if COMPANION_NAME not in excluded:
        if not os.path.isdir(COMPANION):
            raise PackageError('the companion folder %s is missing' % COMPANION)
        sources.append((COMPANION_NAME, COMPANION))
    if args.with_debug_module:
        # The debug module comes with its one-file add-on (require("rtxdebug")), from the fixes' debug
        # submodule, as the classic install has it.
        debug_addon = os.path.join(repo, 'source', 'debug', 'addon')
        if DEBUG_ADDON in known:
            raise PackageError('the fixes have an add-on named %s, which is the debug add-on\'s name' % known[DEBUG_ADDON])
        if not os.path.isdir(debug_addon):
            raise PackageError('--with-debug-module: %s is missing (git submodule update --init in the fixes repo)' % debug_addon)
        sources.append((DEBUG_ADDON, debug_addon))
    for name, folder in sources:
        if not ADDON_NAME.match(name):
            raise PackageError('add-on folder "%s": a name must be 1-64 characters of A-Z a-z 0-9 _ . - '
                               '(leave it out with --exclude-addon)' % name)
        found = collect(folder, 'native/root/garrysmod/addons/' + name, junk, docs=folder != COMPANION)
        if not found:
            raise PackageError('add-on %s has no files (an uninitialised git submodule?): run "git submodule '
                               'update --init" in the fixes repo, or leave it out with --exclude-addon %s' % (name, name))
        files.update(found)
        if folder == COMPANION:
            generated = companion_translations()
            files[COMPANION_I18N] = generated
            files.update(companion_catalog_sources())
        roots.append(('garrysmod/addons/' + name, 'lua-addon'))
    add_to_addons(args.add_to_addon, {name.lower(): name for name, _ in sources}, files, junk)
    if COMPANION_NAME not in excluded:
        files.update(collect(PRESENTATION, 'native/root/garrysmod/data/nativeloader_ui', junk, docs=False))
        roots.append(('garrysmod/data/nativeloader_ui', 'root-files'))
    mods_dir = os.path.join(tree, 'rtx-remix', 'mods')
    mods, empty_mods = [], []
    for name in subfolders(mods_dir, 'the Remix mods folder'):
        found = collect(os.path.join(mods_dir, name), 'native/root/rtx-remix/mods/' + name, junk)
        if not found:
            empty_mods.append(name)  # nothing to deploy
            continue
        files.update(found)
        mods.append(name)
        roots.append(('rtx-remix/mods/' + name, 'root-files'))
    # Seed data the fixes read from garrysmod/data (remix_map_configs/default.txt): create-only, so
    # what the fixes write there later at run time stays the user's.
    data_dir = os.path.join(tree, 'garrysmod', 'data')
    seeds = []
    if os.path.isdir(data_dir):
        for name in subfolders(data_dir, 'the data folder'):
            if name.lower() == 'native-loader':
                continue  # the loader's own reports
            found = collect(os.path.join(data_dir, name), 'native/root/garrysmod/data/' + name, junk)
            if found:
                files.update(found)
                seeds.append(name)
                roots.append(('garrysmod/data/' + name, 'root-files'))
    modules = MODULES + ((DEBUG_MODULE,) if args.with_debug_module else ())
    bootstrap = getattr(args, 'client_bootstrap', None)
    if bootstrap:
        if COMPANION_NAME in excluded:
            raise PackageError('--client-bootstrap requires the nativeloader companion')
        bootstrap = os.path.abspath(bootstrap)
        modules += (CLIENT_BOOTSTRAP,)
        notices = 'native/root/garrysmod/addons/nativeloader/resource/native-client/'
        files[notices + 'LICENSE-MIT.txt'] = os.path.join(REPO, 'LICENSE')
        files[notices + 'LICENSE-GarrysModSDK.txt'] = os.path.join(REPO, 'third_party', 'gmod', 'LICENSE')
    for name in modules:
        source = bootstrap if name == CLIENT_BOOTSTRAP else os.path.join(modules_from, name)
        if not os.path.isfile(source):
            raise PackageError('%s not found in %s (build the fixes, or give --modules-from)' % (name, modules_from))
        regular_file(source)
        files['native/root/garrysmod/lua/bin/' + name] = source
        roots.append(('garrysmod/lua/bin/' + name, 'lua-binary-module'))
    shader = os.path.join(tree, 'bin', 'win64', SHADER_DLL)
    if not os.path.isfile(shader):
        raise PackageError('%s not found' % shader)
    regular_file(shader)
    files[SHADER_FILE] = shader

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
    sets = [] if args.no_patch_sets else patch_sets()
    cvars, cvar_report = session_cvars(cvars_source) if cvars_source else ({}, None)
    used = {kind for _, kind in roots} | {'module-override'} | ({'patch-set'} if sets else set())
    kinds = [kind for kind in KINDS if kind in used]
    inputs = list(files.values()) + ([cvars_source] if cvars_source else [])
    newest = max(os.stat(path).st_mtime for path in inputs)
    left_out = left_out_files(tree, set(os.path.normcase(p) for p in files.values()),
                              [os.path.join(addons_dir, n) for n in addons if n.lower() in excluded])

    # Built beside its destination and renamed into place, so a loader never sees half a package.
    work = (out or gma) + '.partial-%d' % os.getpid()
    if os.path.lexists(work):
        raise PackageError('%s is in the way; delete it' % work)
    os.makedirs(work)
    try:
        listed = {}
        for rel in sorted(files, key=str.lower):
            size, digest = copy_hashed(files[rel], os.path.join(work, *rel.split('/')))
            listed[rel] = {'size': size, 'sha256': digest}
        main_sha256 = listed['native/root/garrysmod/lua/bin/' + MAIN_MODULE]['sha256']
        # 0.0.0-dev.<UTC time of the newest input>+<the main module's SHA-256, 8 digits>
        version = args.version or '0.0.0-dev.%s+%s' % (
            datetime.datetime.fromtimestamp(newest, datetime.timezone.utc).strftime('%Y%m%d%H%M'), main_sha256[:8])
        name = args.name or 'RTX fixes %s' % version
        manifest = {
            'schema': 1,
            'id': args.id,
            'name': name,
            'version': version,
            'kinds': kinds,
            'requires_loader': '>=0.9.0' if bootstrap else REQUIRES_LOADER,
            # The fixes' Lua runs only with Remix: without a runtime the loader hides the add-ons (ADR 0013).
            'requires_remix': True,
            'files': listed,
            'root_files': [{'path': path, 'policy': policy_for(path)} for path, _ in sorted(roots, key=lambda r: r[0].lower())],
        }
        if sets:
            manifest['patch_sets'] = sets
        manifest['module_overrides'] = [{'module': SHADER_DLL, 'file': SHADER_FILE}]
        if cvars:
            manifest['session_cvars'] = cvars
        text = (json.dumps(manifest, indent=2, ensure_ascii=True) + '\n').encode('utf-8')
        with open(os.path.join(work, 'native', 'manifest.json'), 'xb') as fh:
            fh.write(text)

        summary = {
            'id': args.id,
            'version': version,
            'files': len(listed),
            'bytes': sum(f['size'] for f in listed.values()),
            'manifest_sha256': hashlib.sha256(text).hexdigest(),
            'kinds': kinds,
            'addons': [n for n, _ in sources],
            'excluded_addons': sorted((known.get(n, n) for n in excluded), key=str.lower),
            'mods': mods,
            'empty_mods': empty_mods,
            'modules_from': modules_from,
            'modules': {n: listed['native/root/garrysmod/lua/bin/' + n]['sha256'] for n in modules},
            'module_override': shader,
            'patches': sum(len(s['patches']) for s in sets),
            'session_cvars': cvar_report,
            'junk': sorted((shown(path, tree) for path in junk), key=str.lower),
            'left_out': left_out,
            'allowed_private': sorted(allowed, key=str.lower),
            'repo': repo,
            'folder': out,
            'gma': gma,
        }
        if gma:
            pack(work, gma, name, int(newest), args.force)
        if out:
            replace_folder(work, out)
            work = None
        sources, notes = dict(files), {rel: 'allowed with --allow-private: ' + reason for rel, reason in allowed.items()}
        if generated:
            sources[COMPANION_I18N] = companion_i18n.I18N  # the scratch file is gone by now
            notes[COMPANION_I18N] = 'built from the .po files by companion_i18n.py'
        summary['inventory'] = write_inventories(
            inventories, '%s %s: %d files and native/manifest.json, %s bytes; written by package_fixes.py' % (
                args.id, version, len(listed), format(summary['bytes'], ',')),
            listed, sources, text, notes)
        return summary
    finally:
        if work and os.path.isdir(work):
            shutil.rmtree(work)
        if generated and os.path.exists(generated):
            os.remove(generated)


def companion_catalog_sources():
    """Keep the GPL-derived interface text's editable sources and license with the generated table."""
    prefix = 'native/root/garrysmod/addons/nativeloader/resource/bundled-translations/'
    names = ['COPYING', 'README.md', 'unchanged.json', companion_i18n.POT]
    names += [language + '.po' for language in companion_i18n.LANGUAGES]
    return {prefix + name: os.path.join(companion_i18n.ADDON_I18N, name) for name in names}


def companion_translations():
    """The companion's translations as the Lua table it reads (companion_i18n.py build), in a scratch
    file under out\\tmp that the caller removes. Its time is the newest translation file's, so the same
    .po files give the same package version."""
    scratch = os.path.join(REPO, 'out', 'tmp')
    os.makedirs(scratch, exist_ok=True)
    path = os.path.join(scratch, 'companion-i18n-%d.lua' % os.getpid())
    try:
        companion_i18n.build(path)
    except companion_i18n.I18nError as error:
        raise PackageError('the companion translations (companion/i18n) do not check: %s' % error)
    sources = [os.path.join(folder, name) for folder, _, names in os.walk(companion_i18n.I18N)
               for name in names if name.endswith('.po')]
    newest = max(os.stat(source).st_mtime for source in sources)
    os.utime(path, (newest, newest))
    return path


def shown(path, tree):
    """A path relative to the fixes' garrysmod folder when it is inside it, else as it is."""
    return os.path.relpath(path, tree).replace(os.sep, '/') if inside(tree, path) else path


def left_out_files(tree, packaged, excluded):
    """Files of the fixes' garrysmod tree that are not packaged (junk and excluded add-ons aside), as
    paths relative to it: the Steam files the fixes overwrite, the root configs, ..."""
    out = []
    for folder, dirs, names in os.walk(tree, onerror=walk_error):
        dirs[:] = sorted(d for d in dirs if not is_junk(d) and not any(
            os.path.normcase(os.path.join(folder, d)) == os.path.normcase(e) for e in excluded))
        for name in names:
            path = os.path.join(folder, name)
            if not is_junk(name) and os.path.normcase(path) not in packaged:
                out.append(shown(path, tree))
    return sorted(out, key=str.lower)


def pack(folder, gma, title, timestamp, force):
    """gmapack keeps the case of every path and writes the archive through a temporary file. The
    timestamp is the newest input's, so the same inputs give the same bytes."""
    command = [sys.executable, GMAPACK, 'create', '--folder', folder, '--out', gma, '--preserve-case', '--quiet',
               '--title', title, '--desc', 'RTX fixes package for the native loader', '--type', 'tool',
               '--author', 'package_fixes.py', '--timestamp', str(timestamp)]
    if force:
        command.append('--force')
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        raise PackageError('gmapack failed (%d): %s' % (done.returncode, (done.stderr or done.stdout).strip()))


def print_summary(s):
    print('Package %s %s: %d files, %s bytes' % (s['id'], s['version'], s['files'], format(s['bytes'], ',')))
    print('  kinds      %s' % ', '.join(s['kinds']))
    print('  add-ons    %d: %s' % (len(s['addons']), ', '.join(s['addons'])))
    if s['excluded_addons']:
        print('  excluded   %s' % ', '.join(s['excluded_addons']))
    print('  mods       %d: %s%s' % (len(s['mods']), ', '.join(s['mods']),
                                     ' (empty, left out: %s)' % ', '.join(s['empty_mods']) if s['empty_mods'] else ''))
    print('  modules    %s (from %s)' % (', '.join(s['modules']), s['modules_from']))
    print('  override   %s' % s['module_override'])
    print('  patches    %d' % s['patches'])
    cv = s['session_cvars']
    if cv:
        print('  cvars      %d from %s, %s' % (cv['count'], cv['source'],
                                               'section "%s"' % cv['section'] if cv['section'] else 'whole file (no RTX section)'))
        for skip in cv['skipped']:
            print('               skipped line %d: %s (%s)' % (skip['line'], skip['text'], skip['reason']))
    else:
        print('  cvars      none (--no-session-cvars)')
    print('  left out   %d files of the fixes\' garrysmod folder, %d junk files (--json lists them)'
          % (len(s['left_out']), len(s['junk'])))
    for rel in s['allowed_private']:
        print('  private    %s (allowed with --allow-private)' % rel)
    print('  manifest   sha256 %s' % s['manifest_sha256'])
    for key in ('folder', 'gma'):
        if s[key]:
            print('  %-10s %s' % (key, s[key]))
    for path in s['inventory']:
        print('  inventory  %s' % path)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='backslashreplace')
    ap = argparse.ArgumentParser(description='Build the RTX fixes package from the fixes repo.')
    ap.add_argument('--repo', default=DEFAULT_FIXES, help='the fixes repo, read only (default %s)' % DEFAULT_FIXES)
    ap.add_argument('--modules-from', help='folder with the built gmcl_ modules (default <repo>\\x86_64\\Release)')
    ap.add_argument('--with-debug-module', action='store_true', help='also package %s' % DEBUG_MODULE)
    ap.add_argument('--client-bootstrap', metavar='DLL', help='also package the verified RTX multiplayer bootstrap as %s' % CLIENT_BOOTSTRAP)
    ap.add_argument('--exclude-addon', action='append', default=[], metavar='NAME', help='leave an add-on out (repeatable)')
    ap.add_argument('--add-to-addon', action='append', default=[], nargs=2, metavar=('PATH', 'SOURCE'),
                    help='add SOURCE, a file or a folder, to an add-on as PATH (name/LICENSE), such as a licence text '
                         'the add-on folder does not have; never over a file it has (repeatable)')
    ap.add_argument('--no-patch-sets', action='store_true', help='leave out the seven patch sets')
    ap.add_argument('--cvars-from', metavar='FILE', help='take the session console variables from this .cfg '
                                                         '(default <repo>\\garrysmod\\garrysmod\\cfg\\autoexec.cfg)')
    ap.add_argument('--no-session-cvars', action='store_true', help='leave out the session console variables')
    ap.add_argument('--out', help='package folder to write (a development-folder source)')
    ap.add_argument('--gma', help='.gma archive to write (a local or Workshop source)')
    ap.add_argument('--id', default=DEFAULT_ID, help='package id (default %s)' % DEFAULT_ID)
    ap.add_argument('--version', help='package version (default 0.0.0-dev.<newest input time>+<module hash>)')
    ap.add_argument('--name', help='display name')
    ap.add_argument('--allow-private', action='append', default=[], metavar='PATH',
                    help='package this file although it looks private or machine-specific: its package path, '
                         'as the refusal lists it (repeatable)')
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
