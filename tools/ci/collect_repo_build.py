"""R16 (ADR 0106): this repository's own native modules in the RTX package (tools/ci/pins.json
"repository_builds": the RTX client module and the glass module), taken from the Release build the
workflow just made (tools/build.ps1 -Config Release) and laid out as their parts' files, with where each
came from.

  python tools/ci/collect_repo_build.py [--out out/ci/built] [--run-url URL]

Exit codes: 0 collected; 1 a module is missing from the build."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PINS = Path(__file__).with_name('pins.json')


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 22), b''):
            digest.update(block)
    return digest.hexdigest()


def git(*args: str) -> str:
    done = subprocess.run(['git', *args], cwd=REPO, capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else ''


def origin() -> dict:
    """This repository and the commit the build compiled (the workflow's checkout)."""
    if os.environ.get('GITHUB_REPOSITORY'):
        url = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}"
    else:
        url = git('remote', 'get-url', 'origin')
    commit = git('rev-parse', 'HEAD')
    if git('status', '--porcelain', '--untracked-files=no'):
        commit += ' (with uncommitted changes)'
    return {'repository': url, 'commit': commit}


def collect(out: Path, run_url: str | None = None) -> dict:
    entries = json.loads(PINS.read_text(encoding='utf-8'))['repository_builds']
    where = origin()
    binaries, missing = {}, []
    for entry in entries:
        source = REPO / entry['from']
        if not source.is_file():
            missing.append(entry['from'])
            continue
        target = out / entry['part'] / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        binaries[sha256(target)] = {'part': entry['part'], 'path': entry['path'], **where,
                                    'how': f"compiled: this repository's CMake target {entry['target']}, "
                                           'tools/build.ps1 -Config Release (preset win64-release)', 'run': run_url}
        print(f"{entry['part']}/{entry['path']}: {target.stat().st_size} bytes")
    record = {'binaries': binaries, 'missing': missing}
    (out / 'provenance-repository.json').write_text(json.dumps(record, indent=1), encoding='utf-8')
    return record


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--out', type=Path, default=REPO / 'out' / 'ci' / 'built')
    parser.add_argument('--run-url', help='the workflow run that built them (recorded with each module)')
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    record = collect(args.out, args.run_url)
    for path in record['missing']:
        print(f'collect_repo_build: {path} is missing (run tools/build.ps1 -Config Release first)', file=sys.stderr)
    return 1 if record['missing'] else 0


if __name__ == '__main__':
    sys.exit(main())
