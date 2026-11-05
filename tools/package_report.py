"""The RTX package's hash report (R16, ADR 0106): the SHA-256 of a built .gma and of every file in it,
and where each native binary in it came from. CI prints it in the run's summary and keeps it as an
artifact; tools/publish_workshop.py checks the .gma it uploads against it.

  python tools/package_report.py <package.gma> [--provenance a.json b.json ...] [--run-url URL]
                                 [--commit SHA] [--json out.json] [--markdown out.md] [--sums out.txt]

Exit codes: 0 report written; 2 the archive or a provenance file could not be read."""
import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'tools' / 'gmapack'))
import gmapack  # noqa: E402

CHUNK = 4 * 1024 * 1024
BINARY = ('.dll', '.exe', '.so', '.sys')


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(CHUNK), b''):
            digest.update(block)
    return digest.hexdigest()


def entries(gma: Path) -> list[dict]:
    """Every file of the archive in its order: path, size and SHA-256 of its bytes."""
    out = []
    with gmapack.read_gma(str(gma)) as g:
        for e in g.files:
            g.fh.seek(e['offset'])
            digest, left = hashlib.sha256(), e['size']
            while left > 0:
                block = g.fh.read(min(CHUNK, left))
                if not block:
                    raise ValueError('truncated archive at ' + e['name'])
                digest.update(block)
                left -= len(block)
            out.append({'path': e['name'], 'size': e['size'], 'sha256': digest.hexdigest()})
    return out


def merge(records: list[dict]) -> dict:
    """The provenance files of one run (tools/ci: runtime, modules, fetched, this repository's build),
    as one table: SHA-256 of a binary -> where it came from."""
    binaries = {}
    for record in records:
        for digest, source in (record.get('binaries') or {}).items():
            binaries[digest.lower()] = source
    return binaries


def origin(source: dict | None) -> str:
    if not source:
        return 'packages'
    return 'fetched' if str(source.get('how', '')).startswith('fetched') else 'compiled'


def report(gma: Path, provenance: list[dict] | dict | None = None, run_url: str | None = None,
           commit: str | None = None) -> dict:
    records = provenance if isinstance(provenance, list) else [provenance] if provenance else []
    built = merge(records)
    files = entries(gma)
    for f in files:
        source = built.get(f['sha256'])
        if source:
            f['built'] = source
        if f['path'].lower().endswith(BINARY):
            f['origin'] = origin(source)
    binaries = [f for f in files if 'origin' in f]
    count = {key: sum(1 for f in binaries if f['origin'] == key) for key in ('compiled', 'fetched', 'packages')}
    return {
        'schema': 2,
        'gma': {'name': gma.name, 'bytes': gma.stat().st_size, 'sha256': sha256_file(gma)},
        'run': run_url,
        'commit': commit,
        'count': len(files),
        'binaries': len(binaries),
        'compiled': count['compiled'],
        'fetched': count['fetched'],
        'from_packages': count['packages'],
        'files': files,
    }


def sums(data: dict) -> str:
    """sha256sum's format: the package first, then every file in archive order."""
    lines = [f"{data['gma']['sha256']}  {data['gma']['name']}"]
    lines += [f"{f['sha256']}  {f['path']}" for f in data['files']]
    return '\n'.join(lines) + '\n'


def markdown(data: dict) -> str:
    gma = data['gma']
    lines = [
        '## The RTX package',
        '',
        f"**{gma['name']}**, {gma['bytes']:,} bytes",
        '',
        f"SHA-256 of the package: `{gma['sha256']}`",
        '',
    ]
    if data.get('commit') or data.get('run'):
        lines += [f"Built from commit `{data.get('commit') or '?'}` by {data.get('run') or 'this run'}.", '']
    lines += [f"{data['count']} files. Native binaries: {data['binaries']}, {data['compiled']} compiled in this "
              f"workflow, {data['fetched']} downloaded by it from their publishers and checked against pinned "
              f"SHA-256 hashes, {data['from_packages']} taken from `packages/`.", '']
    for key, title in (('compiled', 'Native binaries compiled in this workflow'),
                       ('fetched', 'Native binaries this workflow downloaded (pinned SHA-256)')):
        rows = [f for f in data['files'] if f.get('origin') == key]
        if not rows:
            continue
        lines += [f'### {title}', '', '| File | SHA-256 | Source | How |', '|---|---|---|---|']
        for f in rows:
            b = f['built']
            source = f"{b.get('repository', '')} `{str(b.get('commit', ''))[:12]}`".strip()
            how = str(b.get('how', '')).split(':', 1)[-1].strip()
            lines.append(f"| `{f['path']}` | `{f['sha256']}` | {source} | {how} |")
        lines.append('')
    rest = [f for f in data['files'] if f.get('origin') == 'packages']
    if rest:
        lines += ['### Native binaries taken from packages/ (not built in this workflow)', '',
                  '| File | SHA-256 |', '|---|---|']
        lines += [f"| `{f['path']}` | `{f['sha256']}` |" for f in rest]
        lines.append('')
    lines += ['<details><summary>Every file in the package (path, bytes, SHA-256)</summary>', '',
              '| File | Bytes | SHA-256 |', '|---|---:|---|']
    lines += [f"| `{f['path']}` | {f['size']} | `{f['sha256']}` |" for f in data['files']]
    lines += ['', '</details>', '']
    return '\n'.join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('gma', type=Path)
    parser.add_argument('--provenance', type=Path, nargs='*', default=[],
                        help='JSON files from the build: {"binaries": {"<sha256>": {"repository", "commit", "how", ...}}}')
    parser.add_argument('--run-url', default=os.environ.get('NL_RUN_URL'), help='the workflow run that built the package')
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA'), help='the commit it was built from')
    parser.add_argument('--json', type=Path, help='write the report as JSON')
    parser.add_argument('--markdown', type=Path, help='append the report as Markdown (a GitHub job summary)')
    parser.add_argument('--sums', type=Path, help="write sha256sum's format: the package, then every file")
    args = parser.parse_args(argv)
    try:
        records = [json.loads(p.read_text(encoding='utf-8')) for p in args.provenance]
        data = report(args.gma, records, args.run_url, args.commit)
    except (OSError, ValueError, SystemExit) as error:
        print(f'package_report: {error}', file=sys.stderr)
        return 2
    if args.json:
        args.json.write_text(json.dumps(data, indent=1), encoding='utf-8')
    if args.sums:
        args.sums.write_text(sums(data), encoding='utf-8', newline='\n')
    if args.markdown:
        with open(args.markdown, 'a', encoding='utf-8') as out:
            out.write(markdown(data))
    print(f"{data['gma']['name']}: {data['gma']['bytes']} bytes, SHA-256 {data['gma']['sha256']}, {data['count']} files; "
          f"native binaries: {data['compiled']} compiled, {data['fetched']} fetched, {data['from_packages']} from packages/")
    return 0


if __name__ == '__main__':
    sys.exit(main())
