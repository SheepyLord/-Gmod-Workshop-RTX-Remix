"""Keeps the project's Workshop item up to date (ADR 0016): builds the combined RTX package from the
inputs in tools/workshop.json, and uploads it with GMod's gmpublish when its content changed.

The git hooks this script installs (--install-hooks) run it in the background after every commit
or merge on main and before every push of main, so a commit updates the item and a push updates
GitHub and the item. A run that finds its inputs unchanged since the last upload stops at once; a run whose
build matches the uploaded content (same digest) uploads nothing. See publish_workshop.py.md.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as _dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CONFIG = REPO / 'tools' / 'workshop.json'


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
# What goes into the item from this repository: a change here can change the package.
REPO_INPUTS = ('companion', 'tools/package_fixes.py', 'tools/package_runtime.py', 'tools/package_workshop.py',
               'tools/package_content.py', 'tools/gmapack/gmapack.py', 'tools/workshop.json')
BUILDERS = {'package_fixes': 'tools/package_fixes.py', 'package_runtime': 'tools/package_runtime.py',
            'package_content': 'tools/package_content.py'}
LOCK_WAIT = 2 * 60 * 60


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


def fingerprint(config: dict, repo: Path = REPO) -> str:
    """Changes whenever an input of the item may have changed: this repository's packaging inputs
    (their tree in HEAD and any uncommitted change) and every path a part names."""
    state: dict = {'config': config, 'repo': {}}
    for rel in REPO_INPUTS:
        tree = subprocess.run(['git', 'rev-parse', f'HEAD:{rel}'], cwd=repo, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(['git', 'status', '--porcelain', '--', rel], cwd=repo, capture_output=True, text=True).stdout
        state['repo'][rel] = [tree, dirty]
    state['parts'] = []
    for part in config['parts']:
        paths = [part['package']] if 'package' in part else [a for a in part.get('args', []) if os.path.isabs(a)]
        state['parts'].append({p: path_state(Path(p)) for p in paths})
    text = json.dumps(state, sort_keys=True, default=str)
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


# ---------------------------------------------------------------- lock

def process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    handle = kernel32.OpenProcess(0x00100000, False, pid)  # SYNCHRONIZE
    if not handle:
        return False
    try:
        return kernel32.WaitForSingleObject(handle, 0) == 0x102  # WAIT_TIMEOUT: still running
    finally:
        kernel32.CloseHandle(handle)


def acquire_lock(path: Path, wait: float) -> bool:
    """One publish at a time: an O_EXCL file holding the owner's PID. A lock whose owner is gone is
    taken over. Waits up to `wait` seconds for a running publish to finish."""
    path.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + wait
    while True:
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode('ascii'))
            os.close(fd)
            return True
        except FileExistsError:
            try:
                owner = int(path.read_text(encoding='ascii').strip() or '0')
            except (OSError, ValueError):
                owner = 0
            if not process_alive(owner):
                path.unlink(missing_ok=True)
                continue
            if time.monotonic() >= deadline:
                return False
            time.sleep(10)


# ---------------------------------------------------------------- build and upload

def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None


def build(config: dict, version: str, work: Path, log) -> dict:
    """Builds the parts (runs the packagers for "build" parts) and combines them into one .gma."""
    parts = []
    for part in config['parts']:
        if 'package' in part:
            source = Path(part['package'])
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
    gma = STATE / f'{package["id"]}-{version.replace("+", "_")}.gma'
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
    if done.returncode or 'Success!' not in output:
        raise PublishError(f'gmpublish failed (exit {done.returncode})')
    return output


def publish(config: dict, args, log) -> dict:
    STATE.mkdir(parents=True, exist_ok=True)
    published_file = STATE / 'published.json'
    published = read_json(published_file) or {}
    print_state = {'item': str(config['item'])}
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

POST_COMMIT = f"""#!/bin/sh
{HOOK_MARKER}: a commit on main updates the Workshop item in the background (tools/publish_workshop.py).
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 0
python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --reason "commit $(git rev-parse --short HEAD)" || true
exit 0
"""

POST_MERGE = f"""#!/bin/sh
{HOOK_MARKER}: a merge into main (how milestone branches land) updates the Workshop item too.
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 0
python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --reason "merge $(git rev-parse --short HEAD)" || true
exit 0
"""

PRE_PUSH = f"""#!/bin/sh
{HOOK_MARKER}: a push of main also brings the Workshop item up to date, in the background.
while read local_ref local_sha remote_ref remote_sha; do
  if [ "$remote_ref" = "refs/heads/main" ]; then
    python "$(git rev-parse --show-toplevel)/tools/publish_workshop.py" --background --reason "push $(git rev-parse --short "$local_sha")" || true
  fi
done
exit 0
"""


HOOKS = (('post-commit', POST_COMMIT), ('post-merge', POST_MERGE), ('pre-push', PRE_PUSH))


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


def main_checkout(repo: Path = REPO) -> Path:
    """The main checkout of this repository: the folder of its common .git, whichever worktree runs this."""
    common = Path(git('rev-parse', '--git-common-dir', cwd=repo))
    return (common if common.is_absolute() else repo / common).resolve().parent


def source_hooks(source: Path, script: Path, any_branch: bool = False) -> tuple:
    """Hooks for the git repository of an add-on that a part is built from (ADR 0024): a commit or a
    merge on its main branch (or, with any_branch, on any branch: for repositories whose builds reach
    the classic install from feature-branch worktrees) runs this repository's publish script, which
    rebuilds the parts and uploads only if the item's content changed."""
    def text(what: str) -> str:
        where = 'any branch' if any_branch else 'main'
        return (f'#!/bin/sh\n{HOOK_MARKER}: a {what} on {where} of this repository also updates the RTX package\'s Workshop item,\n'
                f'# whose parts are rebuilt from what it delivers ({script.as_posix()}).\n' +
                ('' if any_branch else '[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || exit 0\n') +
                f'python "{script.as_posix()}" --background --reason "{source.name} {what} $(git rev-parse --short HEAD)" || true\n'
                'exit 0\n')
    return (('post-commit', text('commit')), ('post-merge', text('merge')))


def install_source_hooks(source: Path, force: bool, repo: Path = REPO, any_branch: bool = False) -> list[str]:
    script = main_checkout(repo) / 'tools' / 'publish_workshop.py'
    folder = hooks_folder(source)
    folder.mkdir(parents=True, exist_ok=True)
    hooks = source_hooks(source.resolve(), script, any_branch)
    for name, _ in hooks:  # check every hook before writing any
        target = folder / name
        if target.exists() and HOOK_MARKER not in target.read_text(encoding='utf-8', errors='replace') and not force:
            raise PublishError(f'{target} exists and is not ours; --force-hooks replaces it')
    written = []
    for name, text in hooks:
        (folder / name).write_bytes(text.encode('utf-8'))  # LF line endings: git runs hooks with sh
        written.append(str(folder / name))
    return written


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--config', type=Path, default=CONFIG, help='the item and its inputs (default tools/workshop.json)')
    parser.add_argument('--reason', default='', help='why this run happens (goes into the change notes)')
    parser.add_argument('--dry-run', action='store_true', help='build and compare, upload nothing')
    parser.add_argument('--force', action='store_true', help='build and upload even if nothing changed')
    parser.add_argument('--allow-dirty', action='store_true', help='publish although packaging inputs have uncommitted changes')
    parser.add_argument('--background', action='store_true', help='run detached, logging to out/workshop/logs (what the hooks use)')
    parser.add_argument('--install-hooks', action='store_true', help='install the post-commit and pre-push hooks, then stop')
    parser.add_argument('--uninstall-hooks', action='store_true', help='remove this script\'s hooks, then stop')
    parser.add_argument('--force-hooks', action='store_true', help='with --install-hooks: replace hooks that are not ours')
    parser.add_argument('--install-source-hooks', action='append', default=[], type=Path, metavar='REPO',
                        help='install hooks in the git repository of an add-on a part is built from: a commit or merge on its '
                             'main runs this script (repeatable), then stop')
    parser.add_argument('--uninstall-source-hooks', action='append', default=[], type=Path, metavar='REPO',
                        help='remove this script\'s hooks from such a repository (repeatable), then stop')
    parser.add_argument('--any-branch', action='store_true',
                        help='with --install-source-hooks: publish after commits on any branch, not only main')
    args = parser.parse_args(argv)
    try:
        if args.install_hooks:
            print('\n'.join(install_hooks(args.force_hooks)))
            return 0
        if args.uninstall_hooks:
            print('\n'.join(uninstall_hooks()) or 'no hooks of ours')
            return 0
        if args.install_source_hooks or args.uninstall_source_hooks:
            for source in args.install_source_hooks:
                print('\n'.join(install_source_hooks(source, args.force_hooks, any_branch=args.any_branch)))
            for source in args.uninstall_source_hooks:
                print('\n'.join(uninstall_hooks(source, source_hooks(source, Path('x')))) or f'no hooks of ours in {source}')
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
        config = load_config(args.config)

        def log(text: str) -> None:
            print(f'[{_dt.datetime.now().strftime("%H:%M:%S")}] {text}', flush=True)

        if not acquire_lock(STATE / 'publish.lock', LOCK_WAIT):
            raise PublishError('another publish has held the lock for two hours')
        try:
            result = publish(config, args, log)
        finally:
            (STATE / 'publish.lock').unlink(missing_ok=True)
    except (PublishError, OSError, subprocess.SubprocessError, ValueError) as error:
        print(f'publish_workshop: {error}', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())
