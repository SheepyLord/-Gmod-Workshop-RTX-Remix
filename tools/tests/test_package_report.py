"""tools/package_report.py: hashes of a .gma and of every file in it, provenance of built binaries."""
import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools'))
import package_report  # noqa: E402


def gma(files: dict) -> bytes:
    """A minimal GMAD v3 archive with these files (name -> bytes)."""
    out = bytearray(b'GMAD' + bytes([3]) + struct.pack('<QQ', 0, 0) + b'\0')
    out += b'title\0' + b'{}\0' + b'author\0' + struct.pack('<i', 1)
    for i, (name, data) in enumerate(files.items(), 1):
        out += struct.pack('<I', i) + name.encode() + b'\0' + struct.pack('<q', len(data)) + struct.pack('<I', 0)
    out += struct.pack('<I', 0)
    for data in files.values():
        out += data
    out += struct.pack('<I', 0)
    return bytes(out)


class PackageReportTests(unittest.TestCase):
    def setUp(self):
        (REPO / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(dir=REPO / 'out' / 'tmp'))
        self.files = {'native/manifest.json': b'{"id": "x"}', 'native/payload/runtime/d3d9.dll': b'MZ' + bytes(5000),
                      'lua/autorun/a.lua': b'print(1)', 'native/payload/reshade/reshade64.dll': b'MZ' + bytes(10)}
        self.path = self.dir / 'p.gma'
        self.path.write_bytes(gma(self.files))

    def tearDown(self):
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_every_file_and_the_archive_are_hashed(self):
        data = package_report.report(self.path)
        self.assertEqual(data['gma']['sha256'], hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertEqual([f['path'] for f in data['files']], list(self.files))
        for f in data['files']:
            self.assertEqual(f['sha256'], hashlib.sha256(self.files[f['path']]).hexdigest())
            self.assertEqual(f['size'], len(self.files[f['path']]))
        self.assertEqual((data['count'], data['binaries'], data['compiled'], data['fetched']), (4, 2, 0, 0))

    def test_provenance_files_mark_compiled_and_fetched_binaries_by_their_hash(self):
        d3d9 = hashlib.sha256(self.files['native/payload/runtime/d3d9.dll']).hexdigest()
        reshade = hashlib.sha256(self.files['native/payload/reshade/reshade64.dll']).hexdigest()
        compiled = {'binaries': {d3d9.upper(): {'part': 'runtime', 'path': 'files/d3d9.dll',
            'repository': 'https://github.com/sambow23/dxvk-remix-gmod', 'commit': 'c6b48ed1a40f3451',
            'how': 'compiled: Meson release build'}}}
        fetched = {'binaries': {reshade: {'part': 'reshade', 'path': 'ReShade_Setup_6.8.0.exe',
            'repository': 'https://github.com/crosire/reshade', 'commit': 'v6.8.0', 'how': 'fetched: the signed setup'}}}
        paths = []
        for name, record in (('runtime.json', compiled), ('fetched.json', fetched)):
            paths.append(self.dir / name)
            paths[-1].write_text(json.dumps(record), encoding='utf-8')
        out_json, out_md, out_sums = self.dir / 'r.json', self.dir / 'r.md', self.dir / 'sums.txt'
        self.assertEqual(package_report.main([str(self.path), '--provenance', *map(str, paths), '--run-url',
                                              'https://github.com/o/r/actions/runs/7', '--commit', 'abc',
                                              '--json', str(out_json), '--markdown', str(out_md),
                                              '--sums', str(out_sums)]), 0)
        data = json.loads(out_json.read_text(encoding='utf-8'))
        self.assertEqual((data['binaries'], data['compiled'], data['fetched'], data['from_packages']), (2, 1, 1, 0))
        self.assertEqual((data['run'], data['commit']), ('https://github.com/o/r/actions/runs/7', 'abc'))
        by_path = {f['path']: f for f in data['files']}
        self.assertEqual(by_path['native/payload/runtime/d3d9.dll']['origin'], 'compiled')
        self.assertEqual(by_path['native/payload/reshade/reshade64.dll']['origin'], 'fetched')
        self.assertNotIn('origin', by_path['lua/autorun/a.lua'])
        text = out_md.read_text(encoding='utf-8')
        self.assertIn(data['gma']['sha256'], text)
        self.assertIn('https://github.com/sambow23/dxvk-remix-gmod `c6b48ed1a40f`', text)
        self.assertIn('Native binaries this workflow downloaded', text)
        self.assertNotIn('taken from packages/ (not built', text)
        sums = out_sums.read_text(encoding='utf-8').splitlines()
        self.assertEqual(sums[0], f"{data['gma']['sha256']}  p.gma")
        self.assertEqual(sums[1:], [f"{f['sha256']}  {f['path']}" for f in data['files']])

    def test_a_binary_no_provenance_names_is_reported_as_taken_from_packages(self):
        data = package_report.report(self.path, [{'binaries': {}}])
        self.assertEqual(data['from_packages'], 2)
        self.assertIn('taken from packages/ (not built in this workflow)', package_report.markdown(data))

    def test_an_unreadable_archive_exits_2(self):
        bad = self.dir / 'bad.gma'
        bad.write_bytes(b'nope')
        self.assertEqual(package_report.main([str(bad)]), 2)


if __name__ == '__main__':
    unittest.main()
