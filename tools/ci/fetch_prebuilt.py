"""R16 (ADR 0106): the RTX package's binaries that this workflow does not compile, fetched from where
they are published and checked against pinned SHA-256 hashes (tools/ci/pins.json "fetched"): ReShade's
signed setup from reshade.me, the RTX fixes' stdshader_dx6.dll from the public fixes repository (built by
its author from source that was never published), and CoACD's lib_coacd.dll from its PyPI wheel. Each
lands at <out>/<part>/<path> and is recorded with where it came from.

  python tools/ci/fetch_prebuilt.py [--out out/ci/built] [--run-url URL] [--only NAME ...] [--from DIR]

Exit codes: 0 every file fetched and verified; 1 a download failed or a hash did not match (the file is
not kept)."""
import argparse
import hashlib
import io
import json
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PINS = Path(__file__).with_name('pins.json')
AGENT = 'gmod-native-loader-ci/1 (+https://github.com/SheepyLord)'


def download(url: str, attempts: int = 3) -> bytes:
    error = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': AGENT})
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except OSError as e:  # urllib's errors are OSErrors
            error = e
            time.sleep(5 * (attempt + 1))
    raise OSError(f'{url}: {error}')


def member(archive: bytes, name: str) -> bytes:
    """The one file called `name` (any folder) in a zip archive, such as a wheel."""
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        found = [n for n in z.namelist() if n.rsplit('/', 1)[-1] == name]
        if len(found) != 1:
            raise ValueError(f'{len(found)} files called {name} in the archive')
        return z.read(found[0])


def fetch(entries: list[dict], out: Path, run_url: str | None, local: Path | None = None) -> dict:
    """Downloads each entry (or, for a test without network, takes <local>/<part>/<path>), checks it
    against its pins and writes it with its provenance."""
    binaries, problems = {}, []
    out.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        if local is not None:
            try:
                data = (local / entry['part'] / entry['path']).read_bytes()
            except OSError as error:
                problems.append(f"{entry['name']}: {error}")
                continue
        else:
            try:
                data = download(entry['url'])
            except OSError as error:
                problems.append(str(error))
                continue
        if entry.get('archive_sha256') and local is None:
            # A file taken out of a pinned archive: the archive is checked first, then the file.
            got = hashlib.sha256(data).hexdigest()
            if got != entry['archive_sha256']:
                problems.append(f"{entry['name']}: the archive's SHA-256 is {got}; pinned {entry['archive_sha256']}")
                continue
            try:
                data = member(data, entry['member'])
            except (ValueError, zipfile.BadZipFile) as error:
                problems.append(f"{entry['name']}: {error}")
                continue
        digest = hashlib.sha256(data).hexdigest()
        if digest != entry['sha256'] or (entry.get('size') and len(data) != entry['size']):
            problems.append(f"{entry['name']}: {len(data)} bytes, SHA-256 {digest}; pinned "
                            f"{entry.get('size')} bytes, {entry['sha256']}")
            continue
        target = out / entry['part'] / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        binaries[digest] = {'part': entry['part'], 'path': entry['path'], 'repository': entry.get('repository', ''),
                            'commit': entry.get('commit', ''), 'url': entry['url'],
                            'how': 'fetched: ' + entry['why'], 'run': run_url}
        if local is not None:
            binaries[digest]['how'] = f"fetched: (a local test: the pinned bytes from {local}) " + entry['why']
        # Files a packager takes out of this one (ReShade64.dll out of the setup), by their pinned hashes.
        for name, inner in (entry.get('contains') or {}).items():
            binaries[inner] = {**binaries[digest], 'path': f"{entry['path']}!{name}",
                               'how': f"fetched: {name} out of {entry['path']} (its packager checks this hash); " + entry['why']}
        print(f"{entry['name']}: {len(data)} bytes, SHA-256 {digest} (pinned)")
    record = {'binaries': binaries, 'problems': problems}
    (out / 'provenance-fetched.json').write_text(json.dumps(record, indent=1), encoding='utf-8')
    return record


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--out', type=Path, default=REPO / 'out' / 'ci' / 'built')
    parser.add_argument('--run-url')
    parser.add_argument('--only', nargs='*', help='fetch only these names (pins.json "fetched" names)')
    parser.add_argument('--from', dest='local', type=Path, metavar='DIR',
                        help='a test without network: take <DIR>/<part>/<path> (such as out/inputs) instead of '
                             'downloading; the hashes are checked the same way')
    args = parser.parse_args(argv)
    entries = json.loads(PINS.read_text(encoding='utf-8'))['fetched']
    if args.only:
        entries = [e for e in entries if e['name'] in args.only]
    args.out.mkdir(parents=True, exist_ok=True)
    record = fetch(entries, args.out, args.run_url, args.local)
    for problem in record['problems']:
        print('fetch_prebuilt: ' + problem, file=sys.stderr)
    return 1 if record['problems'] else 0


if __name__ == '__main__':
    sys.exit(main())
