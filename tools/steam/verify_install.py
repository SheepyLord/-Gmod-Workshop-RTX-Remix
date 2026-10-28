"""Check a Steam install against its depot manifests: missing, resized or changed files.

Read-only. Exit code 0 = every depot file matches (user-config files may differ),
1 = at least one depot file is missing or different, 2 = setup error.
"""

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steam_manifest import locate_install, parse_manifest, safe_relpath, sha1_file  # noqa: E402


def verify(install, manifest_paths, progress=None):
    """Return a report dict; lists hold manifest-relative paths."""
    install = Path(install)
    report = {'install': str(install), 'depots': [], 'ok': 0, 'bytes_ok': 0, 'missing': [],
              'size_mismatch': [], 'hash_mismatch': [], 'userconfig_differs': [], 'skipped_symlinks': []}
    checked = 0
    for mpath in manifest_paths:
        m = parse_manifest(mpath)
        if m.filenames_encrypted:
            raise ValueError(f'{mpath}: filenames are encrypted; cannot verify')
        files = [f for f in m.files if not f.is_dir]
        report['depots'].append({'manifest': str(mpath), 'depot_id': m.depot_id,
                                 'manifest_id': m.manifest_id, 'files': len(files)})
        for f in files:
            if f.is_symlink:
                report['skipped_symlinks'].append(f.path)
                continue
            full = install / safe_relpath(f.path)
            checked += 1
            if progress and checked % 500 == 0:
                progress(checked)
            if not full.is_file():
                report['userconfig_differs' if f.is_userconfig else 'missing'].append(f.path)
            elif full.stat().st_size != f.size:
                report['userconfig_differs' if f.is_userconfig else 'size_mismatch'].append(f.path)
            elif f.sha1 and sha1_file(full) != f.sha1:
                report['userconfig_differs' if f.is_userconfig else 'hash_mismatch'].append(f.path)
            else:
                report['ok'] += 1
                report['bytes_ok'] += f.size
    return report


def extras(install, manifest_paths, under):
    """Files below the given install-relative directories that no manifest lists."""
    listed = set()
    for mpath in manifest_paths:
        listed.update(f.path.lower() for f in parse_manifest(mpath).files)
    install = Path(install)
    found = []
    for rel in under:
        base = install / rel
        if base.is_file():
            candidates = [base]
        else:
            candidates = [p for p in base.iterdir() if p.is_file()] if base.is_dir() else []
        for p in sorted(candidates):
            relpath = p.relative_to(install).as_posix()
            if relpath.lower() not in listed:
                found.append(relpath)
    return found


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('install', help='game folder, e.g. ...\\steamapps\\common\\GarrysMod')
    ap.add_argument('--manifest', action='append', help='manifest file; default: the cached ones for the install')
    ap.add_argument('--manifests-from', metavar='INSTALL',
                    help='use the installed manifests of this Steam-managed install (for copies Steam does not manage)')
    ap.add_argument('--steam-dir', help='Steam client folder (default: from the registry)')
    ap.add_argument('--report', help='write the full report as JSON here')
    ap.add_argument('--list-extras', action='append', default=[], metavar='REL',
                    help='also list non-depot files directly inside this install-relative folder (repeatable; "." = root)')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args(argv)

    try:
        manifests = a.manifest or locate_install(a.manifests_from or a.install, a.steam_dir).manifests
    except FileNotFoundError as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2
    progress = None if a.quiet else (lambda n: print(f'  checked {n} files', file=sys.stderr))
    report = verify(a.install, manifests, progress)
    if a.list_extras:
        report['extras'] = extras(a.install, manifests, a.list_extras)
    if a.report:
        Path(a.report).write_text(json.dumps(report, indent=1), encoding='utf-8')

    summary = {k: (len(v) if isinstance(v, list) else v) for k, v in report.items() if k not in ('install', 'depots')}
    print(json.dumps(summary, indent=1))
    for key in ('missing', 'size_mismatch', 'hash_mismatch', 'userconfig_differs', 'extras'):
        for rel in report.get(key, [])[:50]:
            print(f'{key}: {rel}')
    failed = report['missing'] or report['size_mismatch'] or report['hash_mismatch']
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
