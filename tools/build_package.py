"""Builds the combined RTX package from this repository alone (ADR 0033): unpacks packages/ into
out/inputs/, runs the packagers tools/workshop.json names, combines the parts and checks the result
with the built nlctl.exe, into out/dist/. It uploads nothing; publish_workshop.py does that.

  python tools/build_package.py [--config tools/workshop.json] [--out out/dist] [--version V]
                                [--require-nlctl] [--compare <published .gma or its build.json>] [--json]
                                [--built out/ci/built [--keep-packaged PART/PATH ...]]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import publish_workshop as pw  # noqa: E402
from package_workshop import find_nlctl  # noqa: E402


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--config', type=Path, default=pw.CONFIG, help='the package and its parts (default tools/workshop.json)')
    parser.add_argument('--out', type=Path, default=REPO / 'out' / 'dist', help='where the .gma and its summary go (default out/dist)')
    parser.add_argument('--version', help='package version (default 0.0.0-dev.<UTC time>+<input fingerprint>)')
    parser.add_argument('--require-nlctl', action='store_true',
                        help='fail unless a built nlctl.exe checks every part and the result (what CI uses)')
    parser.add_argument('--compare', type=Path, metavar='RECORD',
                        help='a publish record (out/workshop/published.json or build.json): report whether this build '
                             'delivers the same content (digest)')
    parser.add_argument('--keep-work', action='store_true', help='keep the built part folders in out/tmp/package-work')
    parser.add_argument('--built', type=Path, metavar='DIR',
                        help='the native binaries a workflow built or fetched (<part>/<path>, tools/ci): they replace the '
                             'stored ones, and every native binary must come from there (ADR 0106)')
    parser.add_argument('--keep-packaged', action='append', default=[], metavar='PART/PATH',
                        help='with --built: a native binary, or a folder ending in /, still taken from packages/')
    parser.add_argument('--json', action='store_true', help='print the summary as JSON')
    args = parser.parse_args(argv)
    try:
        config = pw.load_config(args.config)
        nlctl = find_nlctl()
        if args.require_nlctl and nlctl is None:
            raise pw.PublishError('no built nlctl.exe (run tools\\build.ps1 -Config Release first)')
        version = args.version or f'0.0.0-dev.{pw.stamp()}+{pw.fingerprint(config)[:8]}'
        work = REPO / 'out' / 'tmp' / 'package-work'
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir(parents=True)

        def log(text: str) -> None:
            print(text, file=sys.stderr if args.json else sys.stdout, flush=True)

        try:
            summary = pw.build(config, version, work, log, dest=args.out.resolve(),
                               overlay=args.built.resolve() if args.built else None,
                               keep_packaged=tuple(args.keep_packaged))
        finally:
            if not args.keep_work:
                shutil.rmtree(work, ignore_errors=True)
        summary['nlctl'] = str(nlctl) if nlctl else None
        if args.built:
            summary['built'] = {'folder': str(args.built), 'kept_packaged': args.keep_packaged}
        if args.compare:
            record = json.loads(args.compare.read_text(encoding='utf-8'))
            summary['compared_with'] = {'record': str(args.compare), 'version': record.get('version'),
                                        'digest': record.get('digest'), 'same_content': record.get('digest') == summary['digest']}
        gma = Path(summary['gma'])
        (gma.parent / (gma.stem + '.json')).write_text(json.dumps(summary, indent=1), encoding='utf-8')
    except (pw.PublishError, OSError, ValueError) as error:
        print(f'build_package: {error}', file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(summary, indent=1))
    else:
        print(f"{summary['id']} {summary['version']}: {summary['files']} files, {summary['gma_bytes']:,} bytes, "
              f"digest {summary['digest'][:16]}")
        print(f"  gma      {summary['gma']}")
        print(f"  checked  {'with ' + summary['nlctl'] if summary['nlctl'] else 'without nlctl (none built)'}")
        if 'compared_with' in summary:
            same = summary['compared_with']['same_content']
            print(f"  content  {'the same as' if same else 'differs from'} {summary['compared_with']['version']}")
    if args.compare and not summary['compared_with']['same_content']:
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
