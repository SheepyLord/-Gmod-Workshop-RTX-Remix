"""List the DLLs a PE file imports (static and delay-load) and, optionally, its exports.

Used to find DLL search-order hook points (which non-KnownDLL names a process
loads from its own folder) and to check what a runtime DLL needs beside it.
Requires the third-party package pefile (pip install pefile).
"""

import argparse
import json
import sys

try:
    import pefile
except ImportError:  # pragma: no cover - depends on the machine
    sys.exit('pe_imports.py needs pefile: python -m pip install pefile')


def describe(path, with_exports):
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT'],
        pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT'],
    ])
    info = {
        'path': path,
        'machine': hex(pe.FILE_HEADER.Machine),
        'static': [e.dll.decode() for e in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', [])],
        'delay': [e.dll.decode() for e in getattr(pe, 'DIRECTORY_ENTRY_DELAY_IMPORT', [])],
    }
    if with_exports:
        exports = getattr(pe, 'DIRECTORY_ENTRY_EXPORT', None)
        info['exports'] = [s.name.decode() if s.name else f'#{s.ordinal}' for s in exports.symbols] if exports else []
    pe.close()
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('files', nargs='+', help='.exe or .dll files')
    ap.add_argument('--exports', action='store_true', help='also list exported names')
    ap.add_argument('--json', action='store_true', help='print JSON instead of text')
    a = ap.parse_args(argv)

    results = []
    status = 0
    for path in a.files:
        try:
            results.append(describe(path, a.exports))
        except (OSError, pefile.PEFormatError) as exc:
            print(f'{path}: {exc}', file=sys.stderr)
            status = 1
    if a.json:
        print(json.dumps(results, indent=1))
        return status
    for r in results:
        print(f"== {r['path']} [{r['machine']}]")
        print('  static:', ', '.join(r['static']))
        if r['delay']:
            print('  delay :', ', '.join(r['delay']))
        if 'exports' in r:
            print(f"  exports ({len(r['exports'])}):", ', '.join(r['exports']))
    return status


if __name__ == '__main__':
    sys.exit(main())
