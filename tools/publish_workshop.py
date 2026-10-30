"""Keeps the project's Workshop item up to date (ADR 0016): builds the combined RTX package from the
inputs in tools/workshop.json, and uploads it with GMod's gmpublish when its content changed.

The parts are built from this repository alone: packages/ holds their inputs (ADR 0033), unpacked
into out/inputs/ before every build (tools/inputs.py). The git hooks this script installs
(--install-hooks) run it in the background after every commit or merge on main and before every push
of main, so a commit updates the item and a push updates GitHub and the item; they also run Git
LFS's own hook steps. A run that finds its inputs unchanged since the last upload stops at once; a
run whose build matches the uploaded content (same digest) uploads nothing. See publish_workshop.py.md.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import msvcrt
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CONFIG = REPO / 'tools' / 'workshop.json'
# Git runs a hook with the repository it hooks in GIT_DIR, GIT_INDEX_FILE and the like (githooks(5)).
# A part's source repository runs this script from its hooks, and every git call here would then read
# that repository instead of this one, down to where the log goes. Without them, git finds this
# repository from each call's working directory. The names are `git rev-parse --local-env-vars`.
GIT_LOCAL_ENV = ('GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT',
                 'GIT_OBJECT_DIRECTORY', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_IMPLICIT_WORK_TREE', 'GIT_GRAFT_FILE',
                 'GIT_INDEX_FILE', 'GIT_NO_REPLACE_OBJECTS', 'GIT_REPLACE_REF_BASE', 'GIT_PREFIX', 'GIT_SHALLOW_FILE',
                 'GIT_COMMON_DIR')
for _name in GIT_LOCAL_ENV:
    os.environ.pop(_name, None)


def shared_state() -> Path:
    """out\\workshop of the main checkout, whichever worktree runs this: every checkout then shares
    one record of what the item holds, and no worktree uploads the same content again."""
    done = subprocess.run(['git', 'rev-parse', '--git-common-dir'], cwd=REPO, capture_output=True, text=True)
    if done.returncode or not done.stdout.strip():
        return REPO / 'out' / 'workshop'
    common = Path(done.stdout.strip())
    return (common if common.is_absolute() else REPO / common).resolve().parent / 'out' / 'workshop'


STATE = shared_state()
HOOK_MARKER = '# nl-workshop-hook'
# What goes into the item from this repository: a change here can change the package. packages/ holds
# every part's inputs (its LFS files are pointers in git, so the tree hash covers their content).
REPO_INPUTS = ('companion', 'packages', 'tools/inputs.py', 'tools/package_fixes.py', 'tools/package_runtime.py',
               'tools/package_workshop.py', 'tools/package_content.py', 'tools/package_reshade.py', 'third_party/reshade',
               'tools/gmapack/gmapack.py', 'tools/workshop.json')
BUILDERS = {'package_fixes': 'tools/package_fixes.py', 'package_runtime': 'tools/package_runtime.py',
            'package_content': 'tools/package_content.py', 'package_reshade': 'tools/package_reshade.py'}
LOCK_WAIT = 2 * 60 * 60
# One reviewed Steam build: its obsolete process-presence check can reject an initialized client
# when Steam's ActiveProcess PID is stale. The actual Steam API/auth/ownership checks stay intact.
COMPAT_PUBLISHER_SHA256 = 'fd999f4f90ff1b7e3e1f293574f90a3e18fa056b65a574901eb1f4f2be27107e'
COMPAT_STEAM_API_SHA256 = 'eb17909a76668cf9ae0b92a618a34a50f6c73d3a6787cb4dd8ce36a8b10bfb75'
COMPAT_PREFLIGHT_OFFSET = 0x758d
COMPAT_PREFLIGHT_BYTES = bytes.fromhex('ff15c5d1030084c0750c488d0d82e80300e8dd3c0000')
COMPAT_BRANCH_OFFSET = COMPAT_PREFLIGHT_OFFSET + 8
COMPAT_PREFLIGHT_ERROR = "Couldn't initialize Steam!\nMake sure it is running!"


class PublishError(Exception):
    pass


def stamp() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime('%Y%m%d%H%M%S')


def git(*args: str, cwd: Path = REPO) -> str:
    done = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if done.returncode:
        raise PublishError(f'git {" ".join(args)}: {done.stderr.strip()}')
    return done.stdout.strip()


def load_config(path: Path) -> dict:
    config = json.loads(path.read_text(encoding='utf-8'))
    for key in ('item', 'package', 'parts', 'gmpublish'):
        if key not in config:
            raise PublishError(f'{path}: "{key}" is missing')
    if not str(config['item']).isdigit():
        raise PublishError(f'{path}: "item" must be a Workshop item id')
    for part in config['parts']:
        if ('package' in part) == ('build' in part):
            raise PublishError(f'{path}: each part needs exactly one of "package" and "build"')
        if 'build' in part and part['build'] not in BUILDERS:
            raise PublishError(f'{path}: unknown builder "{part["build"]}"')
    return config


# ---------------------------------------------------------------- fingerprint

def path_state(path: Path) -> object:
    """What identifies an input path's content cheaply: a git repository by its commit and changed
    files, a folder by every file's name, size and time, a file by its size and time."""
    if not path.exists():
        return None
    if path.is_dir() and (path / '.git').exists():
        return {'git': git('rev-parse', 'HEAD', cwd=path), 'dirty': git('status', '--porcelain', cwd=path)}
    if path.is_dir():
        entries = []
        for folder, dirs, files in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d != '.git')
            for name in sorted(files):
                info = os.stat(os.path.join(folder, name))
                entries.append((os.path.relpath(os.path.join(folder, name), path), info.st_size, info.st_mtime_ns))
        return entries
    info = path.stat()
    return [info.st_size, info.st_mtime_ns]


def unpacked_input(text: str, repo: Path = REPO) -> bool:
    """A path under out/inputs: unpacked from packages/, whose git tree the fingerprint already holds."""
    path = Path(text) if os.path.isabs(text) else repo / text
    inputs_dir = os.path.normcase(os.path.abspath(repo / 'out' / 'inputs')) + os.sep
    return os.path.normcase(os.path.abspath(path)).startswith(inputs_dir)


def fingerprint(config: dict, repo: Path = REPO) -> str:
    """Changes whenever an input of the item may have changed: this repository's packaging inputs
    (their tree in HEAD and any uncommitted change) and every other path a part names. Paths under
    out/inputs are left out: they are derived from packages/, and depend on whether an unpack has run."""
    state: dict = {'config': config, 'repo': {}}
    for rel in REPO_INPUTS:
        tree = subprocess.run(['git', 'rev-parse', f'HEAD:{rel}'], cwd=repo, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(['git', 'status', '--porcelain', '--', rel], cwd=repo, capture_output=True, text=True).stdout
        state['repo'][rel] = [tree, dirty]
    state['parts'] = []
    for part in config['parts']:
        paths = [part['package']] if 'package' in part else [a for a in part.get('args', []) if os.path.isabs(a)]
        # Relative paths are relative to this repository, wherever the script runs from.
        state['parts'].append({p: path_state(Path(p) if os.path.isabs(p) else repo / p)
                               for p in paths if not unpacked_input(p, repo)})
    text = json.dumps(state, sort_keys=True, default=str)
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


# ---------------------------------------------------------------- lock

def acquire_lock(path: Path, wait: float):
    """One publish at a time: an exclusive lock on the first byte of `path`, held through an open handle
    for the whole run. Windows lets go of it when the process ends, however it ends, so no lock is left
    behind, and no run can take a lock that is still being set up for a stale one. Waits up to `wait`
    seconds for a running publish to finish. Returns the handle for release_lock, or None."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(path, 'a+b')  # never emptied or deleted: other runs may have it open
    deadline = time.monotonic() + wait
    while True:
        try:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            return handle
        except OSError:
            if time.monotonic() >= deadline:
                handle.close()
                return None
            time.sleep(10)


def release_lock(handle) -> None:
    try:
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
    finally:
        handle.close()


def checkout_at(commit: str, repo: Path = REPO) -> Path | None:
    """The working tree of this repository (this checkout first, then the others `git worktree list`
    names) that has `commit` checked out, or None. A push of main publishes from there: the pushed
    commit, not the branch of the worktree the push ran in."""
    want = git('rev-parse', '--verify', commit + '^{commit}', cwd=repo)
    if git('rev-parse', 'HEAD', cwd=repo) == want:
        return repo
    tree = None
    for line in git('worktree', 'list', '--porcelain', cwd=repo).splitlines():
        key, _, value = line.partition(' ')
        if key == 'worktree':
            tree = Path(value)
        elif key == 'HEAD' and value == want and tree is not None:
            return tree
    return None


# ---------------------------------------------------------------- build and upload

def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None


def input_parts(config: dict) -> list[str]:
    """The packages/ parts the config reads: every out/inputs/<part>/... path a part names."""
    names = set()
    for part in config['parts']:
        for text in [part.get('package', ''), *part.get('args', [])]:
            segments = str(text).replace('\\', '/').split('/')
            if len(segments) > 2 and segments[0] == 'out' and segments[1] == 'inputs':
                names.add(segments[2])
    return sorted(names)


def build(config: dict, version: str, work: Path, log, dest: Path | None = None) -> dict:
    """Unpacks the packages/ parts the config reads into out/inputs/, builds the parts (runs the
    packagers for "build" parts) and combines them into one .gma in `dest` (default: this checkout's
    shared out/workshop). Relative paths in the config are relative to this repository."""
    import inputs  # tools/inputs.py, beside this script
    names = input_parts(config)
    if names:
        try:
            inputs.unpack(names, log=log)
        except inputs.InputsError as error:
            raise PublishError(f'unpacking packages/: {error}') from None
    parts = []
    for part in config['parts']:
        if 'package' in part:
            source = REPO / part['package']
            if not source.exists():
                raise PublishError(f'part {part.get("name")}: {source} does not exist')
            parts.append(source)
            continue
        folder = work / part.get('name', part['build'])
        command = [sys.executable, str(REPO / BUILDERS[part['build']]), *part.get('args', []), '--out', str(folder), '--force', '--json']
        log(f'building part {part.get("name")}: {" ".join(command[1:])}')
        done = subprocess.run(command, cwd=REPO, capture_output=True, text=True, encoding='utf-8', errors='replace')
        if done.returncode:
            raise PublishError(f'part {part.get("name")}: {(done.stdout + done.stderr).strip()[-2000:]}')
        parts.append(folder)
    package = config['package']
    gma = (dest or STATE) / f'{package["id"]}-{version.replace("+", "_")}.gma'
    gma.parent.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, str(REPO / 'tools' / 'package_workshop.py'), *[a for p in parts for a in ('--part', str(p))],
               '--id', package['id'], '--version', version, '--title', package['title'], '--type', package.get('type', 'tool'),
               '--description', package.get('description', ''), '--gma', str(gma), '--force', '--json']
    if package.get('name'):
        command += ['--name', package['name']]
    for tag in package.get('tags', []):
        command += ['--tag', tag]
    log('combining: ' + ' '.join(str(a) for a in command[1:]))
    done = subprocess.run(command, cwd=REPO, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if done.returncode:
        raise PublishError('combining: ' + (done.stdout + done.stderr).strip()[-2000:])
    return json.loads(done.stdout)


def steam_running() -> bool:
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq steam.exe', '/FO', 'CSV', '/NH'], capture_output=True, text=True).stdout
    return 'steam.exe' in out.lower()


def steam_api_ready(api: Path, root: Path) -> bool:
    """Read-only client initialization probe in a child; keep Steam's diagnostic identifiers private.
    It neither uploads nor changes Steam settings. gmpublish still performs its own initialization.
    """
    probe = ('import ctypes,sys; '
             'api=ctypes.CDLL(sys.argv[1]); '
             'api.SteamAPI_InitFlat.argtypes=[ctypes.c_char_p]; '
             'api.SteamAPI_InitFlat.restype=ctypes.c_int; '
             'error=ctypes.create_string_buffer(1024); '
             'result=api.SteamAPI_InitFlat(error); '
             'api.SteamAPI_Shutdown() if result == 0 else None; '
             'sys.exit(0 if result == 0 else 1)')
    env = dict(os.environ, SteamAppId='4000')
    try:
        done = subprocess.run([sys.executable, '-c', probe, str(api.resolve())], cwd=root, env=env,
                              capture_output=True, stdin=subprocess.DEVNULL, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return done.returncode == 0


def compatibility_publisher(tool: Path, root: Path, folder: Path) -> Path:
    """Make an isolated, exact-build copy that skips only the stale process-presence veto."""
    original = tool.read_bytes()
    if hashlib.sha256(original).hexdigest() != COMPAT_PUBLISHER_SHA256:
        raise PublishError('Steam preflight fallback refused: unreviewed gmpublish build')
    if original[COMPAT_PREFLIGHT_OFFSET:COMPAT_PREFLIGHT_OFFSET + len(COMPAT_PREFLIGHT_BYTES)] != COMPAT_PREFLIGHT_BYTES:
        raise PublishError('Steam preflight fallback refused: publisher code does not match')
    api = tool.with_name('steam_api64.dll')
    dependency = api.read_bytes()
    if hashlib.sha256(dependency).hexdigest() != COMPAT_STEAM_API_SHA256:
        raise PublishError('Steam preflight fallback refused: unreviewed Steam API build')
    copied_api = folder / 'steam_api64.dll'
    copied_api.write_bytes(dependency)
    if not steam_api_ready(copied_api, root):
        raise PublishError('Steam API initialization failed; preflight fallback refused')
    patched = bytearray(original)
    # JNZ +0x0c -> JMP +0x0c, past this one error only. The next instruction calls real API init.
    patched[COMPAT_BRANCH_OFFSET] = 0xeb
    copy = folder / 'gmpublish.exe'
    copy.write_bytes(patched)
    return copy


def upload(config: dict, gma: Path, changes: str, log) -> str:
    """gmpublish update of the item with the new archive. gmpublish needs Steam running, logged in to
    the item's owner, and a steam_appid.txt in its working folder (the game root)."""
    tool = Path(config['gmpublish'])
    if not tool.is_file():
        raise PublishError(f'gmpublish not found: {tool}')
    if not steam_running():
        raise PublishError('Steam is not running; the next commit or push of main tries again')
    root = tool.parents[2] if tool.parent.name.lower() == 'win64' else tool.parents[1]
    command = [str(tool), 'update', '-id', str(config['item']), '-addon', str(gma), '-changes', changes]
    log('uploading: ' + ' '.join(command[1:]))
    done = subprocess.run(command, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace',
                          stdin=subprocess.DEVNULL, timeout=4 * 60 * 60)
    output = (done.stdout + done.stderr).strip()
    log(output[-3000:])
    # Match the early process-presence error exactly. Later init/login/ownership/network failures
    # are not eligible. No Steam/depot files or registry values are changed by this fallback.
    if 'Success!' not in output and output.replace('\r\n', '\n').endswith(COMPAT_PREFLIGHT_ERROR):
        scratch = (REPO / 'out' / 'tmp').resolve()
        if not scratch.is_relative_to(REPO.resolve() / 'out'):
            raise PublishError('Steam preflight fallback scratch path leaves repository out/')
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='gmpublish-preflight-', dir=scratch) as temporary:
            folder = Path(temporary).resolve()
            if not folder.is_relative_to(scratch):
                raise PublishError('Steam preflight fallback directory leaves its scratch root')
            retry_tool = compatibility_publisher(tool, root, folder)
            log('Steam API initialization succeeded; retrying the reviewed publisher copy with only '
                'its obsolete process-presence veto skipped (Steam authentication remains unchanged)')
            command[0] = str(retry_tool)
            done = subprocess.run(command, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace',
                                  stdin=subprocess.DEVNULL, timeout=4 * 60 * 60)
            output = (done.stdout + done.stderr).strip()
            log(output[-3000:])
    if done.returncode or 'Success!' not in output:
        raise PublishError(f'gmpublish failed (exit {done.returncode})')
    return output


def publish(config: dict, args, log) -> dict:
    STATE.mkdir(parents=True, exist_ok=True)
    published_file = STATE / 'published.json'
    published = read_json(published_file) or {}
    print_state = {'item': str(config['item'])}
    if getattr(args, 'commit', None):
        want, have = git('rev-parse', '--verify', args.commit + '^{commit}'), git('rev-parse', 'HEAD')
        if want != have:
            raise PublishError(f'this checkout is at {have[:8]}, not at {want[:8]} as asked: nothing published')
    head = git('log', '-1', '--format=%h %s')
    dirty = git('status', '--porcelain', '--', *REPO_INPUTS)
    if dirty and not (args.dry_run or args.allow_dirty):
        raise PublishError('uncommitted changes in the packaging inputs would go into the item:\n' + dirty)
    print_state['fingerprint'] = current = fingerprint(config)
    if not args.force and published.get('item') == str(config['item']) and published.get('fingerprint') == current:
        log('inputs unchanged since the last upload: nothing to do')
        return {**print_state, 'result': 'unchanged-inputs', 'version': published.get('version')}
    version = f'0.0.0-dev.{stamp()}+{current[:8]}'
    work = STATE / 'work'
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    try:
        summary = build(config, version, work, log)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    gma = Path(summary['gma'])
    record = {'item': str(config['item']), 'fingerprint': current, 'digest': summary['digest'], 'version': version,
              'gma': str(gma), 'gma_bytes': summary['gma_bytes'], 'gma_sha256': summary['gma_sha256'], 'commit': head,
              'reason': args.reason, 'utc': _dt.datetime.now(_dt.timezone.utc).isoformat(timespec='seconds')}
    (STATE / 'build.json').write_text(json.dumps(record, indent=1), encoding='utf-8')
    for old in STATE.glob(f'{config["package"]["id"]}-*.gma'):
        if old != gma:
            old.unlink(missing_ok=True)  # keep only the newest build (about 1.4 GB each)
    if not args.force and published.get('item') == str(config['item']) and published.get('digest') == summary['digest']:
        log('the build matches the uploaded content: nothing to upload')
        published['fingerprint'] = current
        published_file.write_text(json.dumps(published, indent=1), encoding='utf-8')
        return {**print_state, 'result': 'unchanged-content', 'version': published.get('version'), 'digest': summary['digest']}
    if args.dry_run:
        log(f'dry run: {gma} ({summary["gma_bytes"]} bytes) would be uploaded')
        return {**print_state, 'result': 'dry-run', 'version': version, 'digest': summary['digest'], 'gma': str(gma)}
    changes = f'{version} from {head}' + (f' ({args.reason})' if args.reason else '')
    upload(config, gma, changes, log)
    published_file.write_text(json.dumps(record, indent=1), encoding='utf-8')
    return {**print_state, 'result': 'uploaded', 'version': version, 'digest': summary['digest'], 'gma': str(gma)}


# ---------------------------------------------------------------- hooks

# packages/ keeps its binaries in Git LFS (ADR 0033). These hooks replace the ones `git lfs install`
# would write, so each runs Git LFS's step first: above all pre-push, which uploads the LFS files a
# push needs (without it GitHub would get pointers to content it does not have).
LFS_MISSING = ('printf >&2 "\\nThis repository keeps packages/ in Git LFS, and git-lfs is not on the path.\\n'
               'Install Git LFS (https://git-lfs.com) and run: python tools/publish_workshop.py --install-hooks\\n"')

POST_COMMIT = f"""#!/bin/sh
{HOOK_MARKER}: a commit on main updates the Workshop item in the background (tools/publish_workshop.py).
command -v git-lfs >/dev/null 2>&1 && git lfs post-commit "$@"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 0
python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --commit "$(git rev-parse HEAD)" --reason "commit $(git rev-parse --short HEAD)" || true
exit 0
"""

POST_MERGE = f"""#!/bin/sh
{HOOK_MARKER}: a merge into main (how milestone branches land) updates the Workshop item too.
command -v git-lfs >/dev/null 2>&1 && git lfs post-merge "$@"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 0
python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --commit "$(git rev-parse HEAD)" --reason "merge $(git rev-parse --short HEAD)" || true
exit 0
"""

POST_CHECKOUT = f"""#!/bin/sh
{HOOK_MARKER}: Git LFS's post-checkout step (packages/ keeps its binaries in Git LFS).
command -v git-lfs >/dev/null 2>&1 || exit 0
git lfs post-checkout "$@"
"""

PRE_PUSH = f"""#!/bin/sh
{HOOK_MARKER}: a push of main also brings the Workshop item up to date, in the background.
# Git LFS uploads the large files of packages/ first; without git-lfs the push stops.
command -v git-lfs >/dev/null 2>&1 || {{ {LFS_MISSING}; exit 2; }}
refs=$(cat)
if [ -n "$refs" ]; then
  printf '%s\\n' "$refs" | git lfs pre-push "$@" || exit $?
fi
printf '%s\\n' "$refs" | while read local_ref local_sha remote_ref remote_sha; do
  [ "$remote_ref" = "refs/heads/main" ] || continue
  case "$local_sha" in *[!0]*) ;; *) continue ;; esac  # all zeros: main is being deleted
  # The script builds in the checkout that has the pushed commit checked out, not necessarily this one.
  python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --commit "$local_sha" --reason "push $(git rev-parse --short "$local_sha")" || true
done
exit 0
"""


HOOKS = (('post-commit', POST_COMMIT), ('post-merge', POST_MERGE), ('post-checkout', POST_CHECKOUT), ('pre-push', PRE_PUSH))


def hooks_folder(repo: Path = REPO) -> Path:
    common = Path(git('rev-parse', '--git-common-dir', cwd=repo))
    return (common if common.is_absolute() else repo / common) / 'hooks'


def install_hooks(force: bool, repo: Path = REPO) -> list[str]:
    folder = hooks_folder(repo)
    folder.mkdir(parents=True, exist_ok=True)
    written = []
    for name, text in HOOKS:
        target = folder / name
        if target.exists() and HOOK_MARKER not in target.read_text(encoding='utf-8', errors='replace') and not force:
            raise PublishError(f'{target} exists and is not ours; --force replaces it')
        target.write_bytes(text.encode('utf-8'))  # LF line endings: git runs hooks with sh
        written.append(str(target))
    return written


def uninstall_hooks(repo: Path = REPO, hooks=HOOKS) -> list[str]:
    removed = []
    for name, _ in hooks:
        target = hooks_folder(repo) / name
        if target.exists() and HOOK_MARKER in target.read_text(encoding='utf-8', errors='replace'):
            target.unlink()
            removed.append(str(target))
    return removed


# Until ADR 0033 the parts were built from the add-ons' own repositories, and these hooks in them
# (ADR 0024) republished the item after their commits. The parts now live in packages/; only the
# removal remains (--uninstall-source-hooks), and it removes only hooks with HOOK_MARKER.
SOURCE_HOOK_NAMES = ('post-commit', 'post-merge')


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--config', type=Path, default=CONFIG, help='the item and its inputs (default tools/workshop.json)')
    parser.add_argument('--reason', default='', help='why this run happens (goes into the change notes)')
    parser.add_argument('--dry-run', action='store_true', help='build and compare, upload nothing')
    parser.add_argument('--force', action='store_true', help='build and upload even if nothing changed')
    parser.add_argument('--allow-dirty', action='store_true', help='publish although packaging inputs have uncommitted changes')
    parser.add_argument('--commit', metavar='SHA', help='publish this commit, from whichever checkout has it checked out '
                                                         '(what the hooks pass); nothing if none has')
    parser.add_argument('--background', action='store_true', help='run detached, logging to out/workshop/logs (what the hooks use)')
    parser.add_argument('--install-hooks', action='store_true', help='install the post-commit and pre-push hooks, then stop')
    parser.add_argument('--uninstall-hooks', action='store_true', help='remove this script\'s hooks, then stop')
    parser.add_argument('--force-hooks', action='store_true', help='with --install-hooks: replace hooks that are not ours')
    parser.add_argument('--uninstall-source-hooks', action='append', default=[], type=Path, metavar='REPO',
                        help='remove the hooks ADR 0024 put in an add-on\'s git repository (repeatable), then stop')
    args = parser.parse_args(argv)
    try:
        if args.install_hooks:
            print('\n'.join(install_hooks(args.force_hooks)))
            return 0
        if args.uninstall_hooks:
            print('\n'.join(uninstall_hooks()) or 'no hooks of ours')
            return 0
        if args.uninstall_source_hooks:
            for source in args.uninstall_source_hooks:
                removed = uninstall_hooks(source, [(name, None) for name in SOURCE_HOOK_NAMES])
                print('\n'.join(removed) or f'no hooks of ours in {source}')
            return 0
        logs = STATE / 'logs'
        logs.mkdir(parents=True, exist_ok=True)
        if args.background:
            log_path = logs / f'publish-{stamp()}-{os.getpid()}.log'
            forward = [a for a in (argv if argv is not None else sys.argv[1:]) if a != '--background']
            with open(log_path, 'ab') as handle:
                subprocess.Popen([sys.executable, str(Path(__file__).resolve()), *forward], cwd=REPO, stdout=handle,
                                 stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                 creationflags=0x00000008 | 0x00000200)  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
            print(f'publish_workshop: running in the background; log {log_path}')
            return 0
        def log(text: str) -> None:
            print(f'[{_dt.datetime.now().strftime("%H:%M:%S")}] {text}', flush=True)

        if args.commit:
            # A push of main from another worktree (R3-004): the build belongs to the checkout of the
            # pushed commit, with that checkout's own script and inputs.
            target = checkout_at(args.commit)
            if target is None:
                raise PublishError(f'no checkout has {args.commit[:8]} checked out, so the item was not updated; '
                                   'run tools/publish_workshop.py in a checkout of that commit')
            if os.path.normcase(os.path.abspath(target)) != os.path.normcase(str(REPO)):
                log(f'{target} has {args.commit[:8]} checked out: publishing from there')
                forward = argv if argv is not None else sys.argv[1:]
                return subprocess.run([sys.executable, str(Path(target) / 'tools' / 'publish_workshop.py'), *forward],
                                      cwd=target).returncode
        config = load_config(args.config)
        lock = acquire_lock(STATE / 'publish.lock', LOCK_WAIT)
        if lock is None:
            raise PublishError('another publish has held the lock for two hours')
        try:
            result = publish(config, args, log)
        finally:
            release_lock(lock)
    except (PublishError, OSError, subprocess.SubprocessError, ValueError) as error:
        print(f'publish_workshop: {error}', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())
