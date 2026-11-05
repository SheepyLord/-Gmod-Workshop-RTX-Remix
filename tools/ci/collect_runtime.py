"""R16 (ADR 0106): the runtime a GitHub workflow built, laid out as the runtime part's files.

Copies from the runtime build's install folder (runtime/build_runtime.ps1 -Install: <tree>/_output) every
file the runtime part indexes under files/ (packages/runtime/files.json), except this repository's own
content (files/atmosphere/), into <out>/runtime/files/, and records where each native binary came from.
A binary the part ships that the build did not produce stops it: the package never takes a local copy.

  python tools/ci/collect_runtime.py <tree>/_output --out out/ci/built [--run-url URL]

Exit codes: 0 collected; 1 a shipped binary is missing from the build, or the folder is not a build."""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BINARY = ('.dll', '.exe')
OWN = ('files/atmosphere/',)  # this repository's content (tools/sky), not the runtime build's


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 22), b''):
            digest.update(block)
    return digest.hexdigest()


def source_of(rel: str, base: dict) -> dict:
    """Where a runtime file comes from: compiled from the fork with this repository's patches, or a
    vendor or OpenUSD file the same build fetches."""
    name = rel.rsplit('/', 1)[-1].lower()
    fork = {'repository': base['repository'], 'commit': base['commit'], 'patches': 'runtime/patches (this repository)'}
    if name == 'd3d9.dll' or name.startswith('remix') and rel.startswith('files/usd/plugins/'):
        return {**fork, 'how': 'compiled: Meson release build of the fork with runtime/patches (runtime/build_runtime.ps1)'}
    return {**fork, 'how': 'fetched by the same build (packman, a submodule or a clone that runtime/base.json names); '
                           'prebuilt by its vendor'}


def collect(output: Path, out: Path, run_url: str | None = None) -> dict:
    index = json.loads((REPO / 'packages' / 'runtime' / 'files.json').read_text(encoding='utf-8'))['files']
    base = json.loads((REPO / 'runtime' / 'base.json').read_text(encoding='utf-8'))
    if not (output / 'd3d9.dll').is_file():
        raise SystemExit(f'collect_runtime: {output} has no d3d9.dll (not a runtime build output)')
    target = out / 'runtime'
    shutil.rmtree(target, ignore_errors=True)
    copied, missing, binaries = [], [], {}
    for rel in sorted(index):
        if not rel.startswith('files/') or rel.startswith(OWN):
            continue
        source = output / rel[len('files/'):]
        if not source.is_file():
            missing.append(rel)
            continue
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        copied.append(rel)
        if rel.lower().endswith(BINARY):
            binaries[sha256(dest)] = {'part': 'runtime', 'path': rel, **source_of(rel, base), 'run': run_url}
    shipped = {r.lower() for r in index if r.startswith('files/')}
    extra = sorted(p.relative_to(output).as_posix() for p in output.rglob('*')
                   if p.is_file() and not p.name.lower().endswith(('.pdb', '.lib', '.exp'))
                   and ('files/' + p.relative_to(output).as_posix()).lower() not in shipped)
    missing_binaries = [r for r in missing if r.lower().endswith(BINARY)]
    record = {'part': 'runtime', 'copied': len(copied), 'missing': missing, 'built_not_shipped': extra,
              'binaries': binaries}
    (out / 'provenance-runtime.json').write_text(json.dumps(record, indent=1), encoding='utf-8')
    if missing_binaries:
        raise SystemExit('collect_runtime: the build did not produce ' + ', '.join(missing_binaries))
    return record


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('output', type=Path, help='the runtime build install folder (<tree>/_output)')
    parser.add_argument('--out', type=Path, default=REPO / 'out' / 'ci' / 'built')
    parser.add_argument('--run-url', help='the workflow run that built it (recorded with each binary)')
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    try:
        record = collect(args.output, args.out, args.run_url)
    except SystemExit as error:
        print(error, file=sys.stderr)
        return 1
    print(f"runtime: {record['copied']} files, {len(record['binaries'])} binaries; "
          f"{len(record['missing'])} indexed files not built, {len(record['built_not_shipped'])} built files not shipped")
    return 0


if __name__ == '__main__':
    sys.exit(main())
