"""What the native modules this repository compiles itself were built from (ADR 0126).

tools/ci/pins.json "repository_builds" names, for each such module the RTX package ships, its `sources`
(files and folders of this repository; `not_sources` leaves some out) and its "packaged" record: the
SHA-256 of the copy stored in packages/<part>/ and of each source when it was built. tools/check_repo.py
fails while a source differs from the record, or while packages/ holds another file than the recorded one.
`refresh` builds the module, checks that the build read nothing outside its sources, imports it with
tools/inputs.py (one file per import), and writes the record. When the stored module is already the same
image as the new build (apart from what every link changes), nothing is imported: only the record is
written again.

  python tools/ci/repo_builds.py status
  python tools/ci/repo_builds.py refresh [MODULE ...] [--build-dir DIR]

MODULE is <part>/<path> (glass/bin/gmcl_nlglass_win64.dll) or the CMake target (nl_glass_client); by
default every module whose record does not match. Without --build-dir, refresh first runs
tools/build.ps1 -Config Release -NoTests in this checkout.

Exit codes: 0 every module current (status) or refreshed; 1 a module not current (status) or a refresh
refused; 2 bad arguments."""
from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
import re
import struct
import subprocess
import sys
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[2]
PINS = 'tools/ci/pins.json'
BUILD = 'out/build/win64-release'  # tools/build.ps1 -Config Release (CMake preset win64-release)
REFRESH = 'python tools/ci/repo_builds.py refresh'


class RecordError(Exception):
    pass


# ---------------------------------------------------------------- the record

def load_pins(root: Path) -> dict:
    return json.loads((Path(root) / PINS).read_text(encoding='utf-8'))


def module_name(entry: dict) -> str:
    return f"{entry['part']}/{entry['path']}"


def excluded(rel: str, entry: dict) -> bool:
    """Not a build input: Markdown (documentation) and whatever `not_sources` names (such as tests/)."""
    if rel.lower().endswith('.md'):
        return True
    return any(rel == x.rstrip('/') or rel.startswith(x.rstrip('/') + '/') for x in entry.get('not_sources', []))


def source_files(root: Path, entry: dict, source: str) -> list[str]:
    """The files one declared source stands for (a file, or a folder and everything below it), as paths
    relative to root, sorted, without those `excluded` leaves out."""
    path = Path(root) / source
    if path.is_file():
        found = [source]
    elif path.is_dir():
        found = [p.relative_to(root).as_posix() for p in path.rglob('*') if p.is_file()]
    else:
        found = []
    return sorted(rel for rel in found if not excluded(rel, entry))


def source_digests(root: Path, entry: dict) -> dict[str, str | None]:
    """Each declared source's SHA-256 over its files' paths and contents, with line endings as git stores
    them (a checkout's CRLF does not change it, as in cache_key.py); None for a source that is not there."""
    digests = {}
    for source in entry.get('sources', []):
        files = source_files(root, entry, source)
        if not files:
            digests[source] = None
            continue
        digest = hashlib.sha256()
        for rel in files:
            digest.update(rel.encode('utf-8') + b'\0')
            digest.update((Path(root) / rel).read_bytes().replace(b'\r\n', b'\n') + b'\0')
        digests[source] = digest.hexdigest()
    return digests


def changed_sources(root: Path, entry: dict) -> list[str]:
    """How the declared sources differ from the record: "<source> changed", "<source> is missing" (declared,
    not in the tree), "<source> is new" (declared, not recorded), "<source> is no longer a source"."""
    now = source_digests(root, entry)
    built = (entry.get('packaged') or {}).get('sources') or {}
    found = []
    for source, digest in now.items():
        if digest is None:
            found.append(f'{source} is missing')
        elif source not in built:
            found.append(f'{source} is new')
        elif built[source] != digest:
            found.append(f'{source} changed')
    return found + [f'{source} is no longer a source' for source in built if source not in now]


def indexed_sha256(root: Path, entry: dict) -> str | None:
    """The SHA-256 packages/<part>/files.json lists for the module, '' when it lists none, None when this
    tree has no index for the part."""
    index = Path(root) / 'packages' / entry['part'] / 'files.json'
    if not index.is_file():
        return None
    files = json.loads(index.read_text(encoding='utf-8')).get('files', {})
    return (files.get(entry['path']) or {}).get('sha256', '')


def entry_problems(root: Path, entry: dict) -> list[str]:
    name = module_name(entry)
    fix = f'{REFRESH} {name}'
    if not entry.get('sources'):
        return [f'{PINS}: repository build {name} names no sources']
    record = entry.get('packaged')
    if not isinstance(record, dict):
        return [f'{PINS}: {name} has no "packaged" record of what it was built from; {fix}']
    problems = []
    changed = changed_sources(root, entry)
    if changed:
        problems.append(f'packages/{name} was built from other sources ({PINS} "packaged"): {", ".join(changed)}; '
                        f'{fix} to build it again and import it')
    stored = indexed_sha256(root, entry)
    if stored is not None and stored != record.get('sha256'):
        problems.append(f'packages/{name} is not the module {PINS} "packaged" records; {fix}')
    return problems


def problems(root: Path) -> list[str]:
    """What tools/check_repo.py reports: per module, a missing record, sources that differ from it, or a
    stored file that is not the recorded one. Nothing when the tree has no pins.json."""
    if not (Path(root) / PINS).is_file():
        return []
    found = []
    for entry in load_pins(root).get('repository_builds', []):
        found += entry_problems(root, entry)
    return found


def write_record(root: Path, name: str, record: dict) -> None:
    """Sets the module's "packaged" record in pins.json, keeping the file's layout and line endings."""
    path = Path(root) / PINS
    raw = path.read_bytes()
    pins = json.loads(raw)
    entry = next((e for e in pins.get('repository_builds', []) if module_name(e) == name), None)
    if entry is None:
        raise RecordError(f'{PINS} has no repository build {name}')
    entry['packaged'] = record
    text = json.dumps(pins, indent=2, ensure_ascii=False) + '\n'
    if b'\r\n' in raw:
        text = text.replace('\n', '\r\n')
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_bytes(text.encode('utf-8'))
    os.replace(tmp, path)


# ---------------------------------------------------------------- comparing images

ANONYMOUS_NAMESPACE = re.compile(rb'\?A0x[0-9a-fA-F]{8}@')


def normalized_image(data: bytes) -> bytes | None:
    """A PE32+ image with what differs between two links of the same sources zeroed: the time stamps of
    the file header and of the export and debug directories, the checksum, the CodeView record (the PDB's
    GUID, age and path), and the names MSVC gives anonymous namespaces (a hash of the source file's path).
    A PDB path of another length moves the data after it, so only builds in folders whose paths have the
    same length can compare equal. None if `data` is not a PE32+ image."""
    image = bytearray(data)
    u16 = lambda at: struct.unpack_from('<H', image, at)[0]  # noqa: E731
    u32 = lambda at: struct.unpack_from('<I', image, at)[0]  # noqa: E731

    def zero(at: int, size: int) -> None:
        if at < 0 or at + size > len(image):
            raise ValueError('outside the image')
        image[at:at + size] = bytes(size)

    try:
        if image[:2] != b'MZ':
            return None
        pe = u32(0x3C)
        if image[pe:pe + 4] != b'PE\0\0':
            return None
        header = pe + 4
        sections, optional_size = u16(header + 2), u16(header + 16)
        optional = header + 20
        if u16(optional) != 0x20B:
            return None
        zero(header + 4, 4)
        zero(optional + 64, 4)
        directories = [struct.unpack_from('<II', image, optional + 112 + 8 * i) for i in range(min(u32(optional + 108), 16))]
        table = [struct.unpack_from('<IIII', image, optional + optional_size + 40 * i + 8) for i in range(sections)]

        def offset(rva: int) -> int:
            for virtual_size, address, raw_size, pointer in table:
                if address <= rva < address + max(virtual_size, raw_size):
                    return pointer + rva - address
            raise ValueError(f'RVA {rva:#x} in no section')

        if len(directories) > 0 and directories[0][0]:  # export directory
            zero(offset(directories[0][0]) + 4, 4)
        if len(directories) > 6 and directories[6][0]:  # debug directory
            first = offset(directories[6][0])
            for at in range(first, first + directories[6][1] - 27, 28):
                zero(at + 4, 4)
                if u32(at + 12) == 2:  # IMAGE_DEBUG_TYPE_CODEVIEW
                    zero(u32(at + 24), u32(at + 16))
    except (struct.error, ValueError):
        return None
    return ANONYMOUS_NAMESPACE.sub(b'?A0x00000000@', bytes(image))


def same_image(a: bytes, b: bytes) -> bool:
    """Whether two PE32+ images are the same build apart from what `normalized_image` zeroes."""
    first = normalized_image(a)
    return first is not None and first == normalized_image(b)


# ---------------------------------------------------------------- the build

def read_cache(build_dir: Path) -> dict[str, str]:
    cache = Path(build_dir) / 'CMakeCache.txt'
    if not cache.is_file():
        raise RecordError(f'{build_dir} is not a CMake build folder (no CMakeCache.txt)')
    values = {}
    for line in cache.read_text(encoding='utf-8', errors='replace').splitlines():
        match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):[A-Z]+=(.*)$', line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def compiler(build_dir: Path) -> str:
    """The C++ compiler CMake found for the build, such as "MSVC 19.44.35228.0"."""
    for path in sorted(Path(build_dir).glob('CMakeFiles/*/CMakeCXXCompiler.cmake')):
        text = path.read_text(encoding='utf-8', errors='replace')
        kind = re.search(r'set\(CMAKE_CXX_COMPILER_ID "([^"]*)"\)', text)
        version = re.search(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]*)"\)', text)
        if kind and version:
            return f'{kind.group(1)} {version.group(1)}'
    return 'unknown'


def run(*args) -> str:
    done = subprocess.run([str(a) for a in args], capture_output=True, text=True, errors='replace')
    if done.returncode != 0:
        raise RecordError(f'{" ".join(str(a) for a in args)} failed ({done.returncode}): {done.stderr.strip() or done.stdout.strip()}')
    return done.stdout


def target_of(entry: dict) -> str:
    """The module's path in a Release build folder, from pins.json's `from`."""
    try:
        return PurePosixPath(entry['from']).relative_to(BUILD).as_posix()
    except ValueError:
        raise RecordError(f'{module_name(entry)}: "from" is not in {BUILD}') from None


def up_to_date(ninja: str, build_dir: Path, target: str) -> bool:
    """Whether Ninja has nothing to do for the target: the build has the sources' current content."""
    return 'no work to do' in run(ninja, '-C', build_dir, '-n', target)


def build_reads(ninja: str, build_dir: Path, target: str) -> set[str]:
    """Every file outside Ninja's own records that building the target read: the sources of it and of the
    libraries it links (ninja -t inputs) and every header they included (ninja -t deps), as normalized
    absolute paths. System headers are not in Ninja's log."""
    build_dir = Path(build_dir)
    resolve = lambda p: os.path.normcase(os.path.normpath(os.path.join(build_dir, p)))  # noqa: E731
    reads, objects = set(), set()
    for line in run(ninja, '-C', build_dir, '-t', 'inputs', target).splitlines():
        line = line.strip()
        if line.lower().endswith('.obj'):
            objects.add(resolve(line))
        elif line and not line.lower().endswith('.lib') and os.path.isfile(resolve(line)):
            reads.add(resolve(line))
    current = None
    for line in run(ninja, '-C', build_dir, '-t', 'deps').splitlines():
        if line and not line[0].isspace():
            current = resolve(line.split(': #deps', 1)[0]) if ': #deps' in line else None
        elif line.strip() and current in objects:
            reads.add(resolve(line.strip()))
    return reads


def undeclared_reads(source_root: Path, build_dir: Path, reads: set[str], entry: dict) -> list[str]:
    """The files of the source tree a build read that the module's sources do not cover. Generated files
    in the build folder and files outside the source tree (the compiler's, Windows') are not sources."""
    top = os.path.normcase(os.path.normpath(source_root)) + os.sep
    built = os.path.normcase(os.path.normpath(build_dir)) + os.sep
    declared = [s.rstrip('/') for s in entry.get('sources', [])]
    found = []
    for path in sorted(reads):
        if not path.startswith(top) or path.startswith(built):
            continue
        rel = Path(os.path.relpath(path, top)).as_posix()
        covered = any(rel.lower() == s.lower() or rel.lower().startswith(s.lower() + '/') for s in declared)
        if not covered or excluded(rel, entry):
            found.append(rel)
    return found


def build_release(root: Path) -> None:
    """tools/build.ps1 -Config Release -NoTests in that checkout (Ninja builds only what changed)."""
    done = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                           str(Path(root) / 'tools' / 'build.ps1'), '-Config', 'Release', '-NoTests'], cwd=root)
    if done.returncode != 0:
        raise RecordError(f'tools/build.ps1 -Config Release failed ({done.returncode})')


def git_commit(root: Path, entry: dict) -> str:
    """The checkout's commit, noting uncommitted changes to the module's sources."""
    def git(*args):
        done = subprocess.run(['git', '-C', str(root), *args], capture_output=True, text=True, errors='replace')
        return done.stdout if done.returncode == 0 else ''
    commit = git('rev-parse', 'HEAD').strip()
    if not commit:
        return 'unknown (not a git checkout)'
    sources = entry.get('sources', [])
    touched = git('diff', '--name-only', 'HEAD', '--', *sources).splitlines()
    touched += git('ls-files', '--others', '--exclude-standard', '--', *sources).splitlines()
    if any(rel.strip() and not excluded(rel.strip(), entry) for rel in touched):
        commit += ' (with uncommitted changes)'
    return commit


def inputs_tool():
    """tools/inputs.py, which stores and indexes the package's inputs (ADR 0033)."""
    tools = str(REPO / 'tools')
    if tools not in sys.path:
        sys.path.insert(0, tools)
    import inputs
    return inputs


def stored_image(root: Path, entry: dict) -> bytes | None:
    """The module packages/ holds now, checked against its index; None when the part does not list it."""
    inputs = inputs_tool()
    packages = Path(root) / 'packages'
    if not (packages / entry['part'] / inputs.INDEX).is_file():
        return None
    item = inputs.read_index(entry['part'], packages)['files'].get(entry['path'])
    if item is None:
        return None
    stored = packages / entry['part'] / inputs.stored_name(entry['path'], item)
    if inputs.lfs_pointer(stored) is not None:
        raise RecordError(f'{stored.relative_to(root).as_posix()} is a Git LFS pointer: run git lfs pull --include '
                          f'"packages/{entry["part"]}/{inputs.stored_name(entry["path"], item)}" first, so the build '
                          'can be compared with it')
    data = stored.read_bytes()
    data = lzma.decompress(data) if item['stored'] == 'xz' else data
    if hashlib.sha256(data).hexdigest() != item['sha256']:
        raise RecordError(f'{stored} does not match packages/{entry["part"]}/files.json')
    return data


def select(pins: dict, root: Path, wanted: list[str]) -> list[dict]:
    entries = pins.get('repository_builds', [])
    if not wanted:
        return [e for e in entries if entry_problems(root, e)]
    chosen = []
    for name in wanted:
        entry = next((e for e in entries if name in (module_name(e), e.get('target'))), None)
        if entry is None:
            raise RecordError(f'{name}: not a repository build in {PINS} (give <part>/<path> or the CMake target)')
        chosen.append(entry)
    return chosen


def refresh(root: Path = REPO, wanted: list[str] | None = None, build_dir: Path | None = None, log=print,
            build=build_release) -> list[dict]:
    """Builds (unless build_dir names a build to take) and records each chosen module; imports a build
    only when it is not the same image as the stored module. Returns what was done per module."""
    root = Path(root)
    chosen = select(load_pins(root), root, wanted or [])
    done = []
    for entry in list(chosen):
        if wanted and not entry_problems(root, entry):
            log(f'{module_name(entry)}: current, nothing to do')
            chosen.remove(entry)
    if not chosen:
        if not wanted:
            log('every repository build is current')
        return done
    before = {module_name(e): source_digests(root, e) for e in chosen}
    if build_dir is None:
        build_dir = root / BUILD
        build(root)
    build_dir = Path(build_dir)
    cache = read_cache(build_dir)
    if cache.get('CMAKE_BUILD_TYPE') != 'Release' or cache.get('CMAKE_GENERATOR') != 'Ninja':
        raise RecordError(f'{build_dir}: not a Ninja Release build (tools/build.ps1 -Config Release makes one)')
    source_root = Path(cache.get('CMAKE_HOME_DIRECTORY', ''))
    if os.path.normcase(os.path.abspath(source_root / BUILD)) != os.path.normcase(os.path.abspath(build_dir)):
        raise RecordError(f'{build_dir}: not the {BUILD} folder of the checkout it builds ({source_root})')
    ninja = cache.get('CMAKE_MAKE_PROGRAM', 'ninja')
    for entry in chosen:
        name = module_name(entry)
        sources = source_digests(root, entry)
        if sources != before[name]:
            raise RecordError(f'{name}: its sources changed while it was built; refresh again')
        same_tree = os.path.normcase(os.path.abspath(source_root)) == os.path.normcase(os.path.abspath(root))
        if not same_tree and source_digests(source_root, entry) != sources:
            raise RecordError(f'{name}: {build_dir} was built from {source_root}, whose sources of it are not '
                              "this checkout's")
        target = target_of(entry)
        built = build_dir / target
        if not built.is_file() or not up_to_date(ninja, build_dir, target):
            raise RecordError(f'{built} is missing or older than its sources: build it first')
        stray = undeclared_reads(source_root, build_dir, build_reads(ninja, build_dir, target), entry)
        if stray:
            raise RecordError(f'{name}: the build read files its sources in {PINS} do not cover: {", ".join(stray)}; '
                              'add them to "sources" (ADR 0126)')
        image = built.read_bytes()
        stored = stored_image(root, entry)
        if stored is not None and same_image(stored, image):
            sha, how = hashlib.sha256(stored).hexdigest(), 'kept: a build of these sources is the same image'
        else:
            inputs_tool().import_files(entry['part'], [], [(built, entry['path'])], None, False,
                                       packages=root / 'packages', log=log)
            sha, how = hashlib.sha256(image).hexdigest(), 'imported: built from these sources'
        record = {'sha256': sha, 'sources': sources, 'commit': git_commit(source_root, entry),
                  'build': f'{BUILD} (tools/build.ps1 -Config Release), {compiler(build_dir)}', 'how': how}
        write_record(root, name, record)
        log(f'{name}: {how} ({sha[:12]})')
        done.append({'module': name, **record})
    return done


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('status', help='each repository build: current, or what differs from its record')
    p = sub.add_parser('refresh', help='build, compare, import if needed, and record the modules')
    p.add_argument('module', nargs='*', help='<part>/<path> or CMake target (default: every module not current)')
    p.add_argument('--build-dir', type=Path, help='take the modules from this up-to-date Release build of a checkout '
                                                  'with the same sources (nothing is built)')
    args = parser.parse_args(argv)
    try:
        if args.command == 'status':
            stale = 0
            for entry in load_pins(REPO).get('repository_builds', []):
                found = entry_problems(REPO, entry)
                stale += bool(found)
                record = entry.get('packaged') or {}
                for line in found or [f'{module_name(entry)}: current ({record.get("how")}; {record.get("commit")})']:
                    print(line)
            return 1 if stale else 0
        refresh(REPO, args.module, args.build_dir)
    except RecordError as error:
        print(f'repo_builds: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
