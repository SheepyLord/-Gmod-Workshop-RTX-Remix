"""Build a vanilla copy of a Steam app from an existing install, verified file by file.

Copies exactly the files the cached depot manifests list, hashing each byte stream
while copying and keeping only files whose SHA-1 matches the manifest. A file that
does not verify is looked up in --fallback folders; otherwise it is left out and
reported. A non-empty depot file the manifest gives no SHA-1 cannot verify: it is
left out and reported too. The result is byte-identical to a fresh download of the
same build.

Never writes to the source or fallback folders. Refuses a non-empty destination.
Exit code 0 = every depot file copied (user-config files may be skipped),
1 = some depot files could not be verified, 2 = setup error.
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steam_manifest import locate_install, parse_manifest, safe_relpath  # noqa: E402


def _copy_verified(src, dst, expected_sha1):
    h = hashlib.sha1()
    tmp = dst.with_name(dst.name + '.partial')
    with open(src, 'rb') as fin, open(tmp, 'wb') as fout:
        for block in iter(lambda: fin.read(8 << 20), b''):
            h.update(block)
            fout.write(block)
    if expected_sha1 and h.hexdigest() != expected_sha1:
        tmp.unlink()
        return False
    os.replace(tmp, dst)
    st = src.stat()
    os.utime(dst, ns=(st.st_atime_ns, st.st_mtime_ns))
    return True


def _overlaps(a, b):
    a, b = Path(a).resolve(), Path(b).resolve()
    return a == b or a in b.parents or b in a.parents


def clone(src, dst, manifest_paths, fallbacks=(), progress=None):
    src, dst = Path(src), Path(dst)
    if dst.exists() and any(dst.iterdir()):
        raise FileExistsError(f'destination {dst} exists and is not empty')
    for root in (src, *fallbacks):
        if _overlaps(root, dst):
            raise ValueError(f'destination {dst} overlaps source {root}')
    dst.mkdir(parents=True, exist_ok=True)

    report = {'src': str(src), 'dst': str(dst), 'copied': 0, 'bytes': 0, 'from_fallback': [],
              'unverified': [], 'skipped_userconfig': [], 'skipped_symlinks': []}
    for mpath in manifest_paths:
        m = parse_manifest(mpath)
        if m.filenames_encrypted:
            raise ValueError(f'{mpath}: filenames are encrypted; cannot copy')
        for f in m.files:
            rel = safe_relpath(f.path)
            target = dst / rel
            if f.is_dir:
                target.mkdir(parents=True, exist_ok=True)
                continue
            if f.is_symlink:
                report['skipped_symlinks'].append(f.path)
                continue
            if f.sha1 is None and f.size and not f.is_userconfig:
                # No SHA-1 in the manifest (Steam writes 20 zero bytes): a file of the right size proves
                # nothing about its bytes, so it would make a copy that is not vanilla while the run says it
                # is. verify_install.py calls such a file unverified too (review R19, F-05).
                report['unverified'].append(f.path)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            for root in (src, *fallbacks):
                candidate = Path(root) / rel
                if candidate.is_file() and candidate.stat().st_size == f.size and _copy_verified(candidate, target, f.sha1):
                    report['copied'] += 1
                    report['bytes'] += f.size
                    if root is not src:
                        report['from_fallback'].append({'file': f.path, 'root': str(root)})
                    if progress and report['copied'] % 500 == 0:
                        progress(report['copied'])
                    break
            else:
                report['skipped_userconfig' if f.is_userconfig else 'unverified'].append(f.path)
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('src', help='existing install, e.g. ...\\steamapps\\common\\GarrysMod')
    ap.add_argument('dst', help='new folder for the vanilla copy (must not exist or be empty)')
    ap.add_argument('--manifest', action='append', help='manifest file; default: the cached ones for src')
    ap.add_argument('--steam-dir', help='Steam client folder (default: from the registry)')
    ap.add_argument('--fallback', action='append', default=[], help='other folder to take unverified files from')
    ap.add_argument('--report', help='write the full report as JSON here')
    ap.add_argument('--no-appid-file', action='store_true',
                    help='do not write steam_appid.txt (needed to launch a copy Steam does not manage)')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args(argv)

    appid = None
    try:
        if a.manifest:
            manifests = a.manifest
        else:
            info = locate_install(a.src, a.steam_dir)
            manifests, appid = info.manifests, info.appid
        progress = None if a.quiet else (lambda n: print(f'  copied {n} files', file=sys.stderr))
        report = clone(a.src, a.dst, manifests, a.fallback, progress)
    except (FileNotFoundError, FileExistsError, ValueError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2
    if appid and not a.no_appid_file:
        appid_file = Path(a.dst) / 'steam_appid.txt'
        if not appid_file.exists():
            appid_file.write_text(appid, encoding='ascii')
            report['wrote_appid_file'] = appid
    if a.report:
        Path(a.report).write_text(json.dumps(report, indent=1), encoding='utf-8')
    print(json.dumps({k: (len(v) if isinstance(v, list) else v) for k, v in report.items()}, indent=1))
    for key in ('unverified', 'skipped_userconfig'):
        for rel in report[key]:
            print(f'{key}: {rel}')
    return 1 if report['unverified'] else 0


if __name__ == '__main__':
    sys.exit(main())
