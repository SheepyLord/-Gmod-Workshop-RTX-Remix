"""Cross-check nlctl against the Python reference reader in tools/gmapack.

Packs synthetic addons with gmapack.py, then requires `nlctl inspect --json` to report exactly what
gmapack.read_gma() reads, `nlctl verify` to pass intact archives and catch damage, and `nlctl scan`
to count them. Run by CTest (loader/cli/CMakeLists.txt); all files go to --scratch.
"""

import argparse
import json
import lzma
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ADDONS = {
    'basic': {
        'addon.json': json.dumps({'title': 'Crosscheck Basic', 'description': 'Plain files',
                                  'type': 'model', 'tags': ['fun'], 'ignore': []}),
        'lua/autorun/crosscheck.lua': 'print("crosscheck")\n',
        'materials/crosscheck/wall.vmt': '"LightmappedGeneric" { "$basetexture" "dev/dev_measuregeneric01" }\n',
        'materials/crosscheck/äöü.vmt': '"UnlitGeneric" {}\n',
        'data_static/empty.txt': '',
    },
    'native': {
        'addon.json': json.dumps({'title': 'Crosscheck Native', 'type': 'servercontent', 'tags': []}),
        'native/manifest.json': json.dumps({'schema': 1, 'id': 'crosscheck', 'version': '0.0.1'}),
        'native/payload/runtime/readme.txt': 'not a real runtime\n' * 200,
    },
}


def run(cmd, expect=None):
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if expect is not None and proc.returncode != expect:
        sys.exit(f'{cmd!r} exited {proc.returncode}, expected {expect}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}')
    return proc


def check(condition, message):
    if not condition:
        sys.exit('crosscheck failed: ' + message)


def lzma_wrap(gma_bytes, declare_size):
    """LZMA-alone stream as gmpublish uploads use: 13-byte header, then data with an end marker."""
    stream = bytearray(lzma.compress(gma_bytes, format=lzma.FORMAT_ALONE))
    if declare_size:
        stream[5:13] = struct.pack('<Q', len(gma_bytes))
    return bytes(stream)


def compare(nlctl, gmapack, archive, container):
    report = json.loads(run([nlctl, 'inspect', '--json', str(archive)], expect=0).stdout)
    check(report['container'] == container, f'{archive.name}: container {report["container"]!r}')
    g = gmapack.read_gma(str(archive))
    try:
        for ours, theirs in (('version', g.version), ('steamid', g.steamid), ('timestamp', g.timestamp),
                             ('required_content', g.required), ('title', g.title),
                             ('description', g.description), ('author', g.author),
                             ('addon_version', g.addon_version), ('data_offset', g.data_offset),
                             ('data_end', g.data_end)):
            check(report[ours] == theirs, f'{archive.name}: {ours} {report[ours]!r} != {theirs!r}')
        expected_complete = None if container == 'lzma' and report['stream_size'] is None else True
        check(report['complete'] is expected_complete, f'{archive.name}: complete {report["complete"]!r}')
        expected = [{'number': e['num'], 'path': e['name'], 'size': e['size'], 'crc32': e['crc'],
                     'offset': e['offset']} for e in g.files]
        check(report['entries'] == expected, f'{archive.name}: entries differ\n{report["entries"]}\n{expected}')
    finally:
        g.close()
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--nlctl', required=True)
    ap.add_argument('--gmapack', required=True)
    ap.add_argument('--scratch', required=True)
    a = ap.parse_args()

    sys.path.insert(0, str(Path(a.gmapack).resolve().parent))
    import gmapack  # noqa: E402  (the vendored reference implementation)

    scratch = Path(a.scratch)
    shutil.rmtree(scratch, ignore_errors=True)
    good_dir, bad_dir = scratch / 'good', scratch / 'bad'
    good_dir.mkdir(parents=True)
    bad_dir.mkdir()

    archives = {}
    for name, files in ADDONS.items():
        folder = scratch / 'src' / name
        for rel, text in files.items():
            path = folder / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        for variant, extra in (('crc', []), ('nocrc', ['--nocrc'])):
            out = good_dir / f'{name}_{variant}.gma'
            run([sys.executable, '-I', '-B', a.gmapack, 'create', '--folder', str(folder), '--out', str(out),
                 '--timestamp', '1700000000', '--require', 'base', '--quiet', *extra], expect=0)
            archives[out.name] = out

    # LZMA-wrapped copies (Workshop *_legacy.bin), with and without a declared size.
    plain = dict(archives)
    for name, path in plain.items():
        stem = name[:-len('.gma')]
        for variant, declare in (('sized', True), ('unsized', False)):
            out = good_dir / f'{stem}_{variant}_legacy.bin'
            out.write_bytes(lzma_wrap(path.read_bytes(), declare))
            archives[out.name] = out

    # A copy without the 4-byte CRC trailer, like 19 legacy Workshop items: valid, nothing to check.
    notrailer = good_dir / 'basic_notrailer.gma'
    notrailer.write_bytes(archives['basic_crc.gma'].read_bytes()[:-4])
    archives[notrailer.name] = notrailer

    for archive in archives.values():
        container = 'lzma' if archive.suffix == '.bin' else 'gmad'
        compare(a.nlctl, gmapack, archive, container)
        verdict = json.loads(run([a.nlctl, 'verify', '--json', str(archive)], expect=0).stdout)
        check(verdict['ok'] is True and verdict['container'] == container, f'{archive.name}: verify {verdict}')
        check(verdict['crc_trailer'] is (archive != notrailer), f'{archive.name}: crc_trailer {verdict}')
    report = json.loads(run([a.nlctl, 'inspect', '--json', str(notrailer)], expect=0).stdout)
    check(report['complete'] is True and report['crc_trailer'] is False, f'notrailer inspect: {report}')

    # Damage: flip the last content byte (the native readme), cut the file short, add junk.
    data = archives['native_crc.gma'].read_bytes()
    flipped = bytearray(data)
    flipped[-5] ^= 0x01
    (bad_dir / 'flipped.gma').write_bytes(bytes(flipped))
    verdict = json.loads(run([a.nlctl, 'verify', '--json', str(bad_dir / 'flipped.gma')], expect=1).stdout)
    check(verdict['bad_entries'] == ['native/payload/runtime/readme.txt'], f'flipped: {verdict}')

    (bad_dir / 'truncated.gma').write_bytes(data[:-100])
    report = json.loads(run([a.nlctl, 'inspect', '--json', str(bad_dir / 'truncated.gma')], expect=0).stdout)
    check(report['complete'] is False, 'truncated archive reported complete')
    run([a.nlctl, 'verify', str(bad_dir / 'truncated.gma')], expect=2)

    (bad_dir / 'trailing.gma').write_bytes(data + b'junk')
    verdict = json.loads(run([a.nlctl, 'verify', '--json', str(bad_dir / 'trailing.gma')], expect=1).stdout)
    check(verdict['trailing_bytes'] == 4, f'trailing: {verdict}')

    (bad_dir / 'not_an_archive.gma').write_bytes(b'\xff' * 32)
    run([a.nlctl, 'inspect', str(bad_dir / 'not_an_archive.gma')], expect=2)

    # LZMA damage: a cut stream and bytes after the stream are format errors (exit 2).
    wrapped = archives['native_crc_sized_legacy.bin'].read_bytes()
    (bad_dir / 'cut_legacy.bin').write_bytes(wrapped[:-10])  # end marker and last data gone
    run([a.nlctl, 'verify', str(bad_dir / 'cut_legacy.bin')], expect=2)
    (bad_dir / 'tail_legacy.bin').write_bytes(wrapped + b'junk')
    run([a.nlctl, 'verify', str(bad_dir / 'tail_legacy.bin')], expect=2)

    lzma_count = sum(1 for p in archives.values() if p.suffix == '.bin')
    summary = json.loads(run([a.nlctl, 'scan', '--json', str(good_dir)], expect=0).stdout)
    check(summary['total'] == len(archives) and summary['parsed'] == len(archives), f'scan good: {summary}')
    check(summary['lzma'] == lzma_count, f'scan good lzma: {summary}')
    check(summary['without_crc_trailer'] == 1, f'scan good trailer: {summary}')
    summary = json.loads(run([a.nlctl, 'scan', '--json', str(bad_dir)], expect=1).stdout)
    failed = sorted(Path(f['file']).name for f in summary['failures'])
    # cut/tail LZMA files still have intact indexes, so only a full verify catches them.
    check(failed == ['not_an_archive.gma', 'truncated.gma'], f'scan bad: {failed}')
    check(summary['with_trailing_data'] == 1, f'scan bad trailing: {summary}')

    shutil.rmtree(scratch, ignore_errors=True)
    print(f'crosscheck OK: {len(archives)} archives ({lzma_count} LZMA-wrapped) match gmapack; damage detected')


if __name__ == '__main__':
    main()
