"""Combines native packages into one package, so a single Workshop item can carry everything a
subscriber needs: for example the RTX Remix runtime and the RTX fixes (ADR 0016).

Each --part is a package folder (native/manifest.json beside its files) or a .gma archive. The
manifests are merged: kinds and the session extras are united, exactly one part may carry the
runtime ("remix") and at most one ReShade ("reshade"), and no file may come from two parts. Every
file is copied and checked against its part's manifest (size, SHA-256). The result is a package folder (--out) and/or a .gma packed
with gmapack (--gma), with addon.json giving the Workshop title, type and tags. A content digest
(the merged manifest without its version and name, plus the Workshop metadata) tells whether two
builds differ. See package_workshop.py.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'tools' / 'gmapack'))
import gmapack  # noqa: E402

MANIFEST = 'native/manifest.json'
KNOWN_KEYS = {'schema', 'id', 'name', 'version', 'kinds', 'requires_loader', 'requires_remix', 'files', 'remix', 'root_files',
              'module_overrides', 'patch_sets', 'session_cvars', 'module_dependencies', 'reshade'}
ADDON_TYPES = ('gamemode', 'map', 'weapon', 'vehicle', 'npc', 'entity', 'tool', 'effects', 'model', 'servercontent')
ADDON_TAGS = ('fun', 'roleplay', 'scenic', 'movie', 'realism', 'cartoon', 'water', 'comic', 'build')
CHUNK = 1 << 20


class CombineError(Exception):
    pass


def check_file_path(rel) -> str:
    """A package path as the loader takes it (manifest.cpp): under native/payload/ or native/root/, forward
    slashes, no empty, . or .. segment, no drive, colon or control character. Checked for every file of
    every part before anything is written: pathlib drops the staging folder before an absolute path, and
    a copy would then open, and empty, that file."""
    if (not isinstance(rel, str) or not rel.startswith(('native/payload/', 'native/root/')) or '\\' in rel or ':' in rel
            or any(ord(c) < 32 or ord(c) == 127 for c in rel) or any(s in ('', '.', '..') for s in rel.split('/'))):
        raise CombineError(f'{rel!r}: not a package path under native/payload/ or native/root/')
    return rel


class Part:
    """One input package: a package folder or a .gma archive (read in place, never extracted whole)."""

    def __init__(self, path: Path):
        self.path = path
        self.gma = None
        self.entries: dict[str, dict] = {}
        try:
            if path.is_dir():
                manifest = path / 'native' / 'manifest.json'
                if not manifest.is_file():
                    raise CombineError(f'{path}: no native/manifest.json')
                self.manifest = json.loads(manifest.read_text(encoding='utf-8'))
            elif path.is_file():
                self.gma = gmapack.read_gma(str(path))
                self.entries = {e['name'].replace('\\', '/').lower(): e for e in self.gma.files}
                entry = self.entries.get(MANIFEST)
                if not entry:
                    raise CombineError(f'{path}: no native/manifest.json')
                self.manifest = json.loads(self._read(entry).decode('utf-8'))
            else:
                raise CombineError(f'{path}: not found')
        except SystemExit as error:  # gmapack reports a damaged archive this way
            raise CombineError(f'{path}: {error}') from None
        except json.JSONDecodeError as error:
            raise CombineError(f'{path}: native/manifest.json is not JSON: {error}') from None
        if not isinstance(self.manifest, dict) or self.manifest.get('schema') != 1:
            raise CombineError(f'{path}: manifest schema must be 1')
        unknown = sorted(set(self.manifest) - KNOWN_KEYS)
        if unknown:
            raise CombineError(f'{path}: manifest keys this tool does not know how to merge: {", ".join(unknown)}')
        files = self.manifest.get('files', {})
        if not isinstance(files, dict):
            raise CombineError(f'{path}: "files" must be an object')
        for rel in files:
            if rel != MANIFEST:
                try:
                    check_file_path(rel)
                except CombineError as error:
                    raise CombineError(f'{path}: {error}') from None

    def _read(self, entry: dict) -> bytes:
        self.gma.fh.seek(entry['offset'])
        return self.gma.fh.read(entry['size'])

    def copy(self, rel: str, target: Path, info: dict) -> None:
        """Copies one listed file to `target`; its size and SHA-256 must match the part's manifest."""
        digest, size = hashlib.sha256(), 0
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, 'wb') as out:
            if self.gma:
                entry = self.entries.get(rel.lower())
                if not entry:
                    raise CombineError(f'{self.path}: {rel} is listed but not in the archive')
                self.gma.fh.seek(entry['offset'])
                remaining = entry['size']
                while remaining:
                    chunk = self.gma.fh.read(min(CHUNK, remaining))
                    if not chunk:
                        raise CombineError(f'{self.path}: {rel} ends early')
                    out.write(chunk)
                    digest.update(chunk)
                    size += len(chunk)
                    remaining -= len(chunk)
            else:
                source = self.path / rel
                if not source.is_file() or source.is_symlink():
                    raise CombineError(f'{self.path}: {rel} is listed but not a plain file')
                with open(source, 'rb') as handle:
                    for chunk in iter(lambda: handle.read(CHUNK), b''):
                        out.write(chunk)
                        digest.update(chunk)
                        size += len(chunk)
        if size != info.get('size') or digest.hexdigest() != info.get('sha256'):
            raise CombineError(f'{self.path}: {rel} does not match its manifest (size or SHA-256)')

    def close(self) -> None:
        if self.gma:
            self.gma.close()


def loader_key(requirement: str) -> tuple[int, int, int]:
    match = re.fullmatch(r'>=(\d+)\.(\d+)\.(\d+)', requirement or '')
    if not match:
        raise CombineError(f'requires_loader "{requirement}" is not of the form >=X.Y.Z')
    return tuple(int(n) for n in match.groups())


def merge(manifests: list[dict], ident: str, version: str, name: str | None) -> dict:
    """The combined manifest. Raises CombineError where the parts cannot share one package."""
    out: dict = {'schema': 1, 'id': ident}
    if name:
        out['name'] = name
    out['version'] = version
    kinds: list[str] = []
    for m in manifests:
        for kind in m.get('kinds', []):
            if kind not in kinds:
                kinds.append(kind)
    out['kinds'] = kinds
    loaders = [m['requires_loader'] for m in manifests if 'requires_loader' in m]
    if loaders:
        out['requires_loader'] = max(loaders, key=loader_key)
    if any(m.get('requires_remix') for m in manifests):
        out['requires_remix'] = True
    files: dict[str, dict] = {}
    seen: set[str] = set()
    for m in manifests:
        for rel, info in m.get('files', {}).items():
            if rel == MANIFEST:
                continue
            if rel.lower() in seen:
                raise CombineError(f'{rel} is in more than one part')
            seen.add(rel.lower())
            files[rel] = info
    out['files'] = files
    remix = [m['remix'] for m in manifests if 'remix' in m]
    if len(remix) > 1:
        raise CombineError('more than one part carries a runtime ("remix")')
    if remix:
        out['remix'] = remix[0]
    reshade = [m['reshade'] for m in manifests if 'reshade' in m]
    if len(reshade) > 1:
        raise CombineError('more than one part carries ReShade ("reshade")')
    if reshade:
        out['reshade'] = reshade[0]
    for key in ('root_files', 'module_overrides', 'patch_sets', 'module_dependencies'):
        items = [item for m in manifests for item in m.get(key, [])]
        if items:
            out[key] = items
    cvars: dict[str, str] = {}
    for m in manifests:
        for cvar, value in m.get('session_cvars', {}).items():
            clash = next((k for k in cvars if k.lower() == cvar.lower()), None)
            if clash is not None and cvars[clash] != value:
                raise CombineError(f'session variable {cvar} has different values in two parts')
            cvars[clash or cvar] = value
    if cvars:
        out['session_cvars'] = cvars
    return out


def content_digest(manifest: dict, addon: dict) -> str:
    """SHA-256 of what the package delivers: the manifest without version and name (every file's
    SHA-256 is in it), and the Workshop metadata. Two builds with the same digest are the same item."""
    body = {k: v for k, v in manifest.items() if k not in ('version', 'name')}
    text = json.dumps({'manifest': body, 'addon': addon}, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(CHUNK), b''):
            digest.update(chunk)
    return digest.hexdigest()


def find_nlctl() -> Path | None:
    for preset in ('win64-release', 'win64-debug'):
        candidate = REPO / 'out' / 'build' / preset / 'loader' / 'cli' / 'nlctl.exe'
        if candidate.is_file():
            return candidate
    return None


def combine(parts: list[Path], ident: str, version: str, name: str | None, addon: dict, out: Path | None, gma: Path | None,
            force: bool = False, nlctl: Path | None = None, validate: bool = True) -> dict:
    if len(parts) < 2:
        raise CombineError('give at least two parts')
    if not out and not gma:
        raise CombineError('give --out, --gma or both')
    for target in (out, gma):
        if target and target.exists() and not force:
            raise CombineError(f'{target} exists; --force replaces it')
    opened = [Part(p) for p in parts]
    try:
        manifest = merge([p.manifest for p in opened], ident, version, name)
        scratch_root = REPO / 'out' / 'tmp'
        scratch_root.mkdir(parents=True, exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix='package-workshop-', dir=scratch_root))
        try:
            folder = work / 'package'
            inside = os.path.normcase(str(folder.resolve())) + os.sep
            for part in opened:
                for rel, info in part.manifest.get('files', {}).items():
                    if rel != MANIFEST:
                        target = folder / check_file_path(rel)
                        if not os.path.normcase(str(target.resolve())).startswith(inside):
                            raise CombineError(f'{part.path}: {rel} would be written outside the package folder')
                        part.copy(rel, target, info)
            (folder / 'native').mkdir(parents=True, exist_ok=True)
            (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
            (folder / 'addon.json').write_text(json.dumps(addon, indent=2) + '\n', encoding='utf-8')
            checker = (nlctl or find_nlctl()) if validate else None
            validated = None
            if checker:
                done = subprocess.run([str(checker), 'manifest', str(folder)], capture_output=True, text=True)
                if done.returncode:
                    raise CombineError('nlctl refuses the combined manifest: ' + (done.stdout + done.stderr).strip()[-1500:])
                validated = str(checker)
            summary = {'id': ident, 'version': version, 'digest': content_digest(manifest, addon), 'files': len(manifest['files']),
                       'bytes': sum(info['size'] for info in manifest['files'].values()), 'kinds': manifest['kinds'],
                       'parts': [str(p) for p in parts], 'validated_by': validated, 'out': None, 'gma': None}
            if gma:
                gma.parent.mkdir(parents=True, exist_ok=True)
                pack = [sys.executable, '-I', '-B', str(REPO / 'tools' / 'gmapack' / 'gmapack.py'), 'create', '--folder', str(folder),
                        '--out', str(gma), '--quiet']
                if force:
                    pack.append('--force')
                done = subprocess.run(pack, capture_output=True, text=True)
                if done.returncode:
                    raise CombineError('gmapack could not pack the package: ' + (done.stdout + done.stderr).strip()[-1500:])
                summary['gma'] = str(gma)
                summary['gma_bytes'] = gma.stat().st_size
                summary['gma_sha256'] = sha256_file(gma)
            if out:
                if out.exists():
                    shutil.rmtree(out)
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(folder), str(out))
                summary['out'] = str(out)
            return summary
        finally:
            shutil.rmtree(work, ignore_errors=True)
    finally:
        for part in opened:
            part.close()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--part', action='append', required=True, type=Path,
                        help='a package folder or .gma archive (repeatable; at least two)')
    parser.add_argument('--id', required=True, help='the combined package id')
    parser.add_argument('--version', required=True, help='the combined package version (SemVer)')
    parser.add_argument('--name', help='display name')
    parser.add_argument('--title', required=True, help='the Workshop title (addon.json)')
    parser.add_argument('--description', default='', help='the addon.json description (the Workshop page has its own)')
    parser.add_argument('--type', default='tool', choices=ADDON_TYPES, help='GMod add-on type (default tool)')
    parser.add_argument('--tag', action='append', default=[], choices=ADDON_TAGS, help='GMod add-on tag (repeatable, at most two)')
    parser.add_argument('--out', type=Path, help='package folder to write')
    parser.add_argument('--gma', type=Path, help='.gma archive to write')
    parser.add_argument('--nlctl', type=Path, help='nlctl.exe that validates the result (default: the built one, if any)')
    parser.add_argument('--no-validate', action='store_true', help='skip the nlctl check (tests with partial manifests)')
    parser.add_argument('--force', action='store_true', help='replace an earlier folder or archive')
    parser.add_argument('--json', action='store_true', help='print the summary as JSON')
    args = parser.parse_args(argv)
    if len(args.tag) > 2:
        parser.error('at most two tags')
    addon = {'title': args.title, 'type': args.type, 'tags': args.tag, 'description': args.description}
    try:
        summary = combine(args.part, args.id, args.version, args.name, addon, args.out, args.gma, args.force, args.nlctl,
                          not args.no_validate)
    except CombineError as error:
        print(f'package_workshop: {error}', file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"{summary['id']} {summary['version']}: {summary['files']} files, {summary['bytes']} bytes, digest {summary['digest'][:16]}")
        for key in ('out', 'gma'):
            if summary[key]:
                print(f'  {key}: {summary[key]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
