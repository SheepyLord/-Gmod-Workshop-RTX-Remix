"""The RTX package's inputs, kept in this repository under packages/<part>/ (ADR 0033).

Text files up to 1 MB are stored as they are; every other file is stored xz-compressed as
<name>.xz, which .gitattributes puts in Git LFS. packages/<part>/files.json indexes each file's
size, SHA-256 and time, how it is stored, and where the part came from. The packagers read the
unpacked tree under out/inputs/<part>/, which `unpack` builds from the index. See inputs.py.md.

  python tools/inputs.py unpack [--part NAME ...]       # packages/ -> out/inputs/, verified
  python tools/inputs.py verify [--part NAME ...] [--deep]
  python tools/inputs.py import PART [--inventory FILE] [--root SRC=DST ...] [--file SRC=DST ...] [--prune]
  python tools/inputs.py list
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as _dt
import hashlib
import json
import lzma
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PACKAGES = REPO / 'packages'
INPUTS = REPO / 'out' / 'inputs'
INDEX = 'files.json'
# Files of a part folder that are about the part, not in it: the index, notes, and the part's licences
# (a top-level licenses/ folder holds those of the code it bundles).
PART_DOCS = {INDEX, 'README.md', 'LICENSE', 'LICENSE.txt', 'COPYING'}
PART_DOC_DIRS = {'licenses'}
PLAIN_LIMIT = 1 << 20
CHUNK = 1 << 20
XZ_PRESET = 6
LFS_POINTER = b'version https://git-lfs.github.com/spec/v1'
# Never imported: version-control metadata and Explorer/Finder files (the packagers skip them too).
JUNK = {'.git', '.gitattributes', '.gitignore', '.gitkeep', '.gitmodules', '.ds_store', 'desktop.ini', 'thumbs.db'}


class InputsError(Exception):
    pass


# ---------------------------------------------------------------- index

def part_dir(part: str, packages: Path = PACKAGES) -> Path:
    if not part or part.startswith('.') or any(c in part for c in '/\\:'):
        raise InputsError(f'part name {part!r}: one folder name under packages/')
    return packages / part


def read_index(part: str, packages: Path = PACKAGES) -> dict:
    path = part_dir(part, packages) / INDEX
    try:
        index = json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        raise InputsError(f'{path} not found') from None
    except ValueError as error:
        raise InputsError(f'{path}: {error}') from None
    if index.get('schema') != 1 or index.get('part') != part or not isinstance(index.get('files'), dict):
        raise InputsError(f'{path}: not a schema 1 index of part {part}')
    return index


def write_index(index: dict, packages: Path = PACKAGES) -> None:
    path = part_dir(index['part'], packages) / INDEX
    path.parent.mkdir(parents=True, exist_ok=True)
    index['files'] = dict(sorted(index['files'].items(), key=lambda kv: kv[0].lower()))
    path.write_bytes((json.dumps(index, indent=1, sort_keys=False) + '\n').encode('utf-8'))


def parts(packages: Path = PACKAGES) -> list[str]:
    if not packages.is_dir():
        return []
    return sorted(p.name for p in packages.iterdir() if p.is_dir() and (p / INDEX).is_file())


def stored_name(rel: str, entry: dict) -> str:
    return rel + '.xz' if entry['stored'] == 'xz' else rel


def check_rel(rel: str) -> str:
    """A file's path inside its part: forward slashes, relative, no . or .. segments."""
    if not rel or rel.startswith('/') or '\\' in rel or ':' in rel:
        raise InputsError(f'{rel!r}: not a relative path with forward slashes')
    if any(seg in ('', '.', '..') for seg in rel.split('/')):
        raise InputsError(f'{rel!r}: empty, . or .. segment')
    return rel


# ---------------------------------------------------------------- storing

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(CHUNK), b''):
            digest.update(chunk)
    return digest.hexdigest()


def is_plain(path: Path, size: int) -> bool:
    """Stored as it is: UTF-8 text without NUL bytes, up to PLAIN_LIMIT."""
    if size > PLAIN_LIMIT:
        return False
    data = path.read_bytes()
    if b'\0' in data:
        return False
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return False
    return True


def store(source: Path, target_base: Path, rel: str) -> dict:
    """Copies or compresses one file into the part folder. Returns its index entry."""
    info = source.stat()
    plain = is_plain(source, info.st_size)
    entry = {'size': info.st_size, 'sha256': '', 'mtime_ns': info.st_mtime_ns, 'stored': 'plain' if plain else 'xz'}
    target = target_base / stored_name(rel, entry)
    target.parent.mkdir(parents=True, exist_ok=True)
    digest, packed = hashlib.sha256(), hashlib.sha256()
    tmp = target.with_name(target.name + '.tmp')
    with open(source, 'rb') as src, open(tmp, 'wb') as out:
        compressor = None if plain else lzma.LZMACompressor(format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=XZ_PRESET)
        stored_size = 0
        for chunk in iter(lambda: src.read(CHUNK), b''):
            digest.update(chunk)
            data = chunk if compressor is None else compressor.compress(chunk)
            if data:
                out.write(data)
                packed.update(data)
                stored_size += len(data)
        if compressor is not None:
            data = compressor.flush()
            out.write(data)
            packed.update(data)
            stored_size += len(data)
    os.replace(tmp, target)
    entry['sha256'] = digest.hexdigest()
    if not plain:
        entry['stored_size'] = stored_size
        entry['stored_sha256'] = packed.hexdigest()
    return entry


def git_origin(path: Path) -> dict | None:
    """The git repository a source lies in: its origin URL, commit and whether it has local changes."""
    folder = path if path.is_dir() else path.parent
    def run(*args):
        done = subprocess.run(['git', '-C', str(folder), *args], capture_output=True, text=True)
        return done.stdout.strip() if done.returncode == 0 else None
    top = run('rev-parse', '--show-toplevel')
    if not top:
        return None
    return {'repository': top, 'remote': run('remote', 'get-url', 'origin'), 'commit': run('rev-parse', 'HEAD'),
            'dirty': bool(run('status', '--porcelain', '--', str(path)))}


def read_inventory(path: Path) -> list[tuple[str, str]]:
    """(package path, source) rows of a packager's .inventory.txt (size, sha256, path, source, note)."""
    rows = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#') or line.startswith('size\t'):
            continue
        cols = line.split('\t')
        if len(cols) >= 4:
            rows.append((cols[2], cols[3]))
    return rows


def import_files(part: str, roots: list[tuple[Path, str]], files: list[tuple[Path, str]], inventory: Path | None,
                 prune: bool, packages: Path = PACKAGES, log=print, workers: int | None = None,
                 skip: list[Path] | None = None) -> dict:
    """Stores sources into packages/<part>/ and updates its index.

    roots: (source folder, target prefix) pairs; with an inventory, every inventory source must lie in
    one of them, except sources in this repository or under `skip` (the build takes those from the
    repository itself, such as the companion). Without an inventory each root is copied whole.
    files: single (source file, target path) pairs. prune: remove indexed files under the target
    prefixes that this import did not bring."""
    base = part_dir(part, packages)
    try:
        index = read_index(part, packages)
    except InputsError:
        index = {'schema': 1, 'part': part, 'origins': {}, 'files': {}}
    wanted: dict[str, Path] = {}
    roots = [(Path(os.path.abspath(src)), dst.strip('/')) for src, dst in roots]

    def add(rel: str, source: Path) -> None:
        rel = check_rel(rel)
        clash = next((r for r in wanted if r.lower() == rel.lower() and r != rel), None)
        if clash:
            raise InputsError(f'{rel} and {clash} differ only in case')
        if rel in wanted and wanted[rel] != source:
            raise InputsError(f'{rel} comes from both {wanted[rel]} and {source}')
        wanted[rel] = source

    if inventory is not None:
        skipped = [os.path.normcase(os.path.abspath(p)) + os.sep for p in (skip or [])]
        repo, scratch = os.path.normcase(str(REPO)) + os.sep, os.path.normcase(str(REPO / 'out')) + os.sep
        for _, source in read_inventory(inventory):
            src = Path(source)
            if not src.is_absolute() or not src.is_file():
                continue  # written by the packager, or built from this repository (companion\i18n)
            where = os.path.normcase(str(src))
            if (where.startswith(repo) and not where.startswith(scratch)) or any(where.startswith(s) for s in skipped):
                continue  # the build takes it from this repository (the companion)
            match = max((r for r in roots if os.path.normcase(str(src)).startswith(os.path.normcase(str(r[0])) + os.sep)),
                        key=lambda r: len(str(r[0])), default=None)
            if match is None:
                raise InputsError(f'{src}: in no --root of this import')
            rel = Path(os.path.relpath(src, match[0])).as_posix()
            add(f'{match[1]}/{rel}' if match[1] else rel, src)
    else:
        for src, dst in roots:
            if not src.is_dir():
                raise InputsError(f'--root {src}: not a folder')
            for folder, dirs, names in os.walk(src):
                dirs[:] = sorted(d for d in dirs if d.lower() not in JUNK)
                for name in sorted(names):
                    if name.lower() in JUNK:
                        continue
                    rel = Path(os.path.relpath(os.path.join(folder, name), src)).as_posix()
                    add(f'{dst}/{rel}' if dst else rel, Path(folder) / name)
    for src, dst in files:
        src = Path(os.path.abspath(src))
        if not src.is_file():
            raise InputsError(f'--file {src}: not a file')
        add(dst, src)
    if not wanted:
        raise InputsError(f'nothing to import into {part}')
    for rel in wanted:
        top = rel.split('/')[0]
        if (top in PART_DOCS and '/' not in rel) or (top in PART_DOC_DIRS and '/' in rel):
            raise InputsError(f'{rel}: that name is kept for the part folder itself')

    prefixes = {dst for _, dst in roots} | {dst for _, dst in files}
    old = index['files']
    todo = []
    for rel, src in wanted.items():
        info = src.stat()
        entry = old.get(rel)
        stored = base / stored_name(rel, entry) if entry else None
        if entry and entry['size'] == info.st_size and entry['mtime_ns'] == info.st_mtime_ns and stored.is_file():
            continue  # unchanged since the last import
        todo.append((rel, src))
    log(f'{part}: {len(wanted)} files, {len(todo)} to store')
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers or max(1, (os.cpu_count() or 2) - 2)) as pool:
        futures = {pool.submit(store, src, base, rel): rel for rel, src in todo}
        for future in concurrent.futures.as_completed(futures):
            rel = futures[future]
            entry = future.result()
            previous = old.get(rel)
            if previous and stored_name(rel, previous) != stored_name(rel, entry):
                (base / stored_name(rel, previous)).unlink(missing_ok=True)
            old[rel] = entry
    removed = []
    if prune:
        for rel in list(old):
            under = any(rel == p or rel.startswith(p + '/') or not p for p in prefixes)
            if under and rel not in wanted:
                (base / stored_name(rel, old[rel])).unlink(missing_ok=True)
                del old[rel]
                removed.append(rel)
    now = _dt.datetime.now(_dt.timezone.utc).isoformat(timespec='seconds')
    for src, dst in roots:
        index['origins'][dst or '.'] = {'source': str(src), 'git': git_origin(src), 'imported': now}
    for src, dst in files:
        index['origins'][dst] = {'source': str(Path(os.path.abspath(src))), 'git': git_origin(Path(src)), 'imported': now}
    write_index(index, packages)
    return {'part': part, 'files': len(old), 'stored': len(todo), 'removed': removed}


# ---------------------------------------------------------------- reading back

def lfs_pointer(path: Path) -> dict | None:
    """The oid and size of a Git LFS pointer file, or None if the file is real content."""
    try:
        with open(path, 'rb') as handle:
            head = handle.read(512)
    except OSError:
        return None
    if not head.startswith(LFS_POINTER):
        return None
    fields = dict(line.split(' ', 1) for line in head.decode('ascii', 'replace').splitlines() if ' ' in line)
    oid = fields.get('oid', '')
    return {'oid': oid.split(':', 1)[1] if oid.startswith('sha256:') else oid, 'size': int(fields.get('size', '-1'))}


def unpack_file(stored: Path, target: Path, entry: dict) -> None:
    if lfs_pointer(stored) is not None:
        raise InputsError(f'{stored} is a Git LFS pointer: run "git lfs pull" first')
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + '.tmp')
    digest, size = hashlib.sha256(), 0
    with open(stored, 'rb') as src, open(tmp, 'wb') as out:
        decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_XZ) if entry['stored'] == 'xz' else None
        for chunk in iter(lambda: src.read(CHUNK), b''):
            data = chunk if decompressor is None else decompressor.decompress(chunk)
            out.write(data)
            digest.update(data)
            size += len(data)
        if decompressor is not None and not decompressor.eof:
            tmp.unlink(missing_ok=True)
            raise InputsError(f'{stored}: truncated xz stream')
    if size != entry['size'] or digest.hexdigest() != entry['sha256']:
        tmp.unlink(missing_ok=True)
        raise InputsError(f'{stored}: content does not match its index entry (size or SHA-256)')
    os.replace(tmp, target)
    os.utime(target, ns=(entry['mtime_ns'], entry['mtime_ns']))


def unpack(names: list[str] | None = None, packages: Path = PACKAGES, dest: Path = INPUTS, log=print,
           workers: int | None = None) -> dict:
    """Builds dest/<part>/ from packages/<part>/ for every part (or the named ones): files whose size
    and time already match are kept, others are written and checked against the index, and files the
    index does not list are removed."""
    result = {}
    for part in names or parts(packages):
        index = read_index(part, packages)
        base, out = part_dir(part, packages), dest / part
        todo = []
        for rel, entry in index['files'].items():
            target = out / rel
            try:
                info = target.stat()
                if info.st_size == entry['size'] and info.st_mtime_ns == entry['mtime_ns']:
                    continue
            except FileNotFoundError:
                pass
            todo.append((base / stored_name(rel, entry), target, entry))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers or max(1, (os.cpu_count() or 2) - 2)) as pool:
            for future in [pool.submit(unpack_file, *job) for job in todo]:
                future.result()
        listed = {os.path.normcase(str(out / rel)) for rel in index['files']}
        stale = 0
        if out.is_dir():
            for folder, dirs, names_ in os.walk(out, topdown=False):
                for name in names_:
                    path = os.path.join(folder, name)
                    if os.path.normcase(path) not in listed:
                        os.unlink(path)
                        stale += 1
                if folder != str(out) and not os.listdir(folder):
                    os.rmdir(folder)
        log(f'{part}: {len(index["files"])} files, {len(todo)} written, {stale} stale removed')
        result[part] = {'files': len(index['files']), 'written': len(todo), 'removed': stale}
    return result


def verify(names: list[str] | None = None, packages: Path = PACKAGES, deep: bool = False) -> list[str]:
    """Problems with the stored files: missing, unindexed, or not matching the index. A Git LFS pointer
    is checked by its oid and size (so a checkout without the LFS content still verifies); --deep
    decompresses real xz content and checks the original SHA-256."""
    problems = []
    for part in names or parts(packages):
        try:
            index = read_index(part, packages)
        except InputsError as error:
            problems.append(str(error))
            continue
        base = part_dir(part, packages)
        expected = set()
        for rel, entry in index['files'].items():
            try:
                check_rel(rel)
            except InputsError as error:
                problems.append(f'{part}: {error}')
                continue
            stored = base / stored_name(rel, entry)
            expected.add(os.path.normcase(str(stored)))
            if not stored.is_file():
                problems.append(f'{part}: {stored_name(rel, entry)} is missing')
                continue
            if entry['stored'] == 'plain':
                if stored.stat().st_size != entry['size'] or sha256_file(stored) != entry['sha256']:
                    problems.append(f'{part}: {rel} does not match its index entry')
                continue
            pointer = lfs_pointer(stored)
            if pointer is not None:
                if pointer['oid'] != entry.get('stored_sha256') or pointer['size'] != entry.get('stored_size'):
                    problems.append(f'{part}: {rel}.xz is an LFS pointer to other content')
                continue
            if stored.stat().st_size != entry.get('stored_size') or sha256_file(stored) != entry.get('stored_sha256'):
                problems.append(f'{part}: {rel}.xz does not match its index entry')
                continue
            if deep:
                digest, size = hashlib.sha256(), 0
                decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
                with open(stored, 'rb') as handle:
                    for chunk in iter(lambda: handle.read(CHUNK), b''):
                        data = decompressor.decompress(chunk)
                        digest.update(data)
                        size += len(data)
                if size != entry['size'] or digest.hexdigest() != entry['sha256']:
                    problems.append(f'{part}: {rel}.xz does not decompress to its indexed content')
        for folder, dirs, names_ in os.walk(base):
            if folder == str(base):
                dirs[:] = [d for d in dirs if d not in PART_DOC_DIRS]
            for name in names_:
                path = os.path.join(folder, name)
                if os.path.normcase(path) in expected:
                    continue
                if folder == str(base) and name in PART_DOCS:
                    continue
                problems.append(f'{part}: {Path(os.path.relpath(path, base)).as_posix()} is not in {INDEX}')
    return problems


# ---------------------------------------------------------------- main

def pair(text: str) -> tuple[Path, str]:
    if '=' not in text:
        raise argparse.ArgumentTypeError(f'{text!r}: SOURCE=TARGET')
    src, dst = text.rsplit('=', 1)
    return Path(src), dst.replace('\\', '/')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('unpack', help='build out/inputs/<part>/ from packages/<part>/')
    p.add_argument('--part', action='append', help='only this part (repeatable)')
    p.add_argument('--dest', type=Path, default=INPUTS)
    p = sub.add_parser('verify', help='check packages/ against the indexes')
    p.add_argument('--part', action='append')
    p.add_argument('--deep', action='store_true', help='also decompress xz content and check it')
    p = sub.add_parser('import', help='store files into packages/<part>/')
    p.add_argument('part')
    p.add_argument('--inventory', type=Path, help="a packager's .inventory.txt: import exactly its sources")
    p.add_argument('--root', action='append', type=pair, default=[], metavar='SRC=DST',
                   help='a source folder and its place in the part (repeatable)')
    p.add_argument('--file', action='append', type=pair, default=[], metavar='SRC=DST',
                   help='a single source file and its path in the part (repeatable)')
    p.add_argument('--prune', action='store_true', help='remove indexed files under the targets that were not imported')
    sub.add_parser('list', help='the parts, their files and sizes')
    args = parser.parse_args(argv)
    try:
        if args.command == 'unpack':
            unpack(args.part, dest=args.dest)
        elif args.command == 'verify':
            problems = verify(args.part, deep=args.deep)
            for problem in problems:
                print(problem, file=sys.stderr)
            print(f'{len(parts())} parts checked, {len(problems)} problems')
            return 1 if problems else 0
        elif args.command == 'import':
            print(json.dumps(import_files(args.part, args.root, args.file, args.inventory, args.prune), indent=1))
        elif args.command == 'list':
            for part in parts():
                index = read_index(part)
                size = sum(e['size'] for e in index['files'].values())
                stored = sum(e.get('stored_size', e['size']) for e in index['files'].values())
                print(f'{part:34s} {len(index["files"]):6d} files {size / 1e6:10.1f} MB, stored {stored / 1e6:9.1f} MB')
    except (InputsError, OSError, lzma.LZMAError) as error:
        print(f'inputs: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
