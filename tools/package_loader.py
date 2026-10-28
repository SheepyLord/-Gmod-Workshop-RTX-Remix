"""Builds the end-user bundle of the loader (ADR 0017): a zip to extract into the Garry's Mod folder,
holding the built bin\\win64\\winmm.dll, the default native-loader\\config.json (which allows the
project's Workshop item) and a short README, plus a second zip with winmm.pdb. The GitHub workflow
runs it after the build; it also runs locally. See package_loader.py.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DIST = REPO / 'dist'
NAME = 'gmod-native-loader'


class BundleError(Exception):
    pass


def project_version(repo: Path = REPO) -> str:
    text = (repo / 'CMakeLists.txt').read_text(encoding='utf-8')
    match = re.search(r'project\(\s*\w+\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)', text)
    if not match:
        raise BundleError('CMakeLists.txt names no project VERSION')
    return match.group(1)


def commit_id(repo: Path = REPO) -> str:
    sha = os.environ.get('GITHUB_SHA', '')
    if not sha:
        done = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=repo, capture_output=True, text=True)
        sha = done.stdout.strip()
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise BundleError('cannot tell the commit (no GITHUB_SHA, and git rev-parse HEAD failed)')
    return sha[:8]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_config(text: str) -> None:
    """The shipped config.json must be what the loader accepts: strict JSON, schema 1, an allowlist."""
    try:
        config = json.loads(text)
    except ValueError as error:
        raise BundleError(f'dist/native-loader/config.json is not JSON: {error}') from None
    if not isinstance(config, dict) or config.get('schema') != 1 or not isinstance(config.get('allow'), dict):
        raise BundleError('dist/native-loader/config.json must be schema 1 with an "allow" object')
    extra = set(config) - {'schema', 'enabled', 'allow', 'remix', 'patch_sets'}
    if extra:
        raise BundleError(f'dist/native-loader/config.json has keys the loader refuses: {", ".join(sorted(extra))}')


def write_zip(path: Path, members: dict[str, bytes]) -> None:
    """A zip whose members keep a fixed time, so two builds of the same files give the same bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.zip.part')
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name in sorted(members):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            bundle.writestr(info, members[name])
    os.replace(temporary, path)


def bundle(build_dir: Path, out: Path, version: str, commit: str, dist: Path = DIST) -> dict:
    dll, pdb = build_dir / 'winmm.dll', build_dir / 'winmm.pdb'
    if not dll.is_file():
        raise BundleError(f'{dll} does not exist: build first (tools\\build.ps1 -Config Release)')
    image = dll.read_bytes()
    if image[:2] != b'MZ':
        raise BundleError(f'{dll} is not a Windows image')
    config = (dist / 'native-loader' / 'config.json').read_text(encoding='utf-8')
    check_config(config)
    readme = (dist / 'README-native-loader.txt').read_text(encoding='utf-8')
    stem = f'{NAME}-{version}+{commit}'
    main_zip = out / f'{stem}.zip'
    write_zip(main_zip, {
        'bin/win64/winmm.dll': image,
        'native-loader/config.json': config.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'),
        'README-native-loader.txt': readme.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'),
    })
    summary = {'version': version, 'commit': commit, 'winmm_sha256': sha256(image), 'winmm_bytes': len(image),
               'bundle': str(main_zip), 'bundle_sha256': sha256(main_zip.read_bytes()), 'symbols': None}
    if pdb.is_file():
        symbols = out / f'{stem}-symbols.zip'
        write_zip(symbols, {'winmm.pdb': pdb.read_bytes()})
        summary['symbols'] = str(symbols)
    return summary


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--config', default='Release', choices=['Debug', 'Release'], help='which build to bundle (default Release)')
    parser.add_argument('--build-dir', type=Path, help='folder holding winmm.dll and winmm.pdb (default: the --config build)')
    parser.add_argument('--out', type=Path, default=REPO / 'out' / 'dist', help='where the zips go (default out\\dist)')
    parser.add_argument('--json', action='store_true', help='print the summary as JSON')
    args = parser.parse_args(argv)
    build_dir = args.build_dir or REPO / 'out' / 'build' / f'win64-{args.config.lower()}' / 'loader' / 'proxy'
    try:
        summary = bundle(build_dir, args.out, project_version(), commit_id())
    except (BundleError, OSError) as error:
        print(f'package_loader: {error}', file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"{summary['bundle']} (winmm.dll {summary['winmm_sha256'][:16]})")
        if summary['symbols']:
            print(summary['symbols'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
