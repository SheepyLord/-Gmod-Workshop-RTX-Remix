"""R16 (ADR 0106): the cache key of a binary build in the RTX package's workflow, a SHA-256 of exactly the
sources that build reads, so a cached build is reused only for the same sources.

  python tools/ci/cache_key.py runtime     # runtime/ (patches, base.json, the build script), the collector,
                                           # and which files the runtime part ships
  python tools/ci/cache_key.py modules     # tools/ci/build_modules.ps1, its pins, the fixes' patches and the
                                           # debug module's and the bridge's sources in packages/
  python tools/ci/cache_key.py hotloader   # the Model Hotloader's source copy, its build script and policy

Prints the key (64 hex digits). Exit codes: 0 printed; 2 an unknown build name."""
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PINS = REPO / 'tools' / 'ci' / 'pins.json'


def files_under(*paths: str) -> list[Path]:
    found = []
    for rel in paths:
        path = REPO / rel
        if path.is_file():
            found.append(path)
        elif path.is_dir():
            found.extend(p for p in path.rglob('*') if p.is_file())
    return sorted(set(found))


def digest(paths: list[Path], extra: object = None) -> str:
    h = hashlib.sha256()
    for path in paths:
        h.update(path.relative_to(REPO).as_posix().encode('utf-8') + b'\0')
        # Line endings as git stores them: a checkout's conversion must not change the key.
        h.update(path.read_bytes().replace(b'\r\n', b'\n') + b'\0')
    h.update(json.dumps(extra, sort_keys=True).encode('utf-8'))
    return h.hexdigest()


def runtime() -> str:
    index = json.loads((REPO / 'packages' / 'runtime' / 'files.json').read_text(encoding='utf-8'))['files']
    # Which files the part ships decides what is collected, not their recorded hashes.
    shipped = sorted(rel for rel in index if rel.startswith('files/') and not rel.startswith('files/atmosphere/'))
    # runtime/'s Markdown documents the build; it is not read by it.
    sources = [p for p in files_under('runtime') if p.suffix.lower() != '.md']
    return digest(sorted(sources + files_under('tools/ci/collect_runtime.py', 'tools/lib/VsDevEnv.psm1')), shipped)


def modules() -> str:
    pins = json.loads(PINS.read_text(encoding='utf-8'))
    used = {key: pins[key] for key in ('garrysmod_common', 'premake', 'fixes', 'rtxdebug', 'advmat_bridge')}
    sources = ['tools/ci/build_modules.ps1', 'tools/lib/VsDevEnv.psm1', *pins['fixes']['patches'],
               pins['rtxdebug']['source'], pins['advmat_bridge']['source']]
    return digest(files_under(*sources), used)


def hotloader() -> str:
    """The Model Hotloader's natives (ADR 0107): its source copy in packages/, the build script, the policy
    the build rewrites, and pins.json's hotloader entry."""
    pins = json.loads(PINS.read_text(encoding='utf-8'))
    sources = ['tools/ci/build_hotloader.ps1', 'tools/lib/VsDevEnv.psm1', 'tools/inputs.py', pins['hotloader']['source'],
               pins['hotloader']['policy']]
    return digest(files_under(*sources), pins['hotloader'])


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    builds = {'runtime': runtime, 'modules': modules, 'hotloader': hotloader}
    if len(argv) != 1 or argv[0] not in builds:
        print('usage: cache_key.py runtime|modules|hotloader', file=sys.stderr)
        return 2
    print(builds[argv[0]]())
    return 0


if __name__ == '__main__':
    sys.exit(main())
