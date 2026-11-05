"""Tests for inputs.py: what is stored plain and what xz-compressed, unpacking back to the exact bytes
and times, verifying against the index (also with Git LFS pointers in place of the content), and
importing from a packager's inventory."""
import hashlib
import json
import lzma
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import inputs  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'
OLD_TIME = 1_600_000_000_000_000_000  # 2020-09-13, so a time that survives is the recorded one


def quiet(_text):
    pass


class InputsTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-inputs-', dir=SCRATCH))
        self.packages, self.dest, self.src = self.root / 'packages', self.root / 'inputs', self.root / 'source'
        self.files = {
            'addon/lua/a.lua': b'print("hi")\r\n',            # CRLF text: kept byte for byte
            'addon/models/m.mdl': b'IDST\0\1\2' * 100,        # binary
            'addon/big.txt': b'x' * (inputs.PLAIN_LIMIT + 1),  # text, but too large to keep plain
            'addon/latin.txt': 'caf\xe9'.encode('latin-1'),   # not UTF-8
            'bin/gmcl_x_win64.dll': b'MZ' + bytes(range(256)) * 64,
        }
        for rel, data in self.files.items():
            path = self.src / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            os.utime(path, ns=(OLD_TIME, OLD_TIME))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def store_all(self, **kw):
        return inputs.import_files('p', [(self.src, '')], [], None, prune=kw.get('prune', False),
                                   packages=self.packages, log=quiet, workers=2)

    def test_plain_and_xz_and_the_index(self):
        result = self.store_all()
        self.assertEqual(result['files'], len(self.files))
        index = inputs.read_index('p', self.packages)
        stored = {rel: e['stored'] for rel, e in index['files'].items()}
        self.assertEqual(stored, {'addon/lua/a.lua': 'plain', 'addon/models/m.mdl': 'xz', 'addon/big.txt': 'xz',
                                  'addon/latin.txt': 'xz', 'bin/gmcl_x_win64.dll': 'xz'})
        base = self.packages / 'p'
        self.assertEqual((base / 'addon/lua/a.lua').read_bytes(), self.files['addon/lua/a.lua'])
        self.assertFalse((base / 'addon/models/m.mdl').exists())
        packed = (base / 'addon/models/m.mdl.xz').read_bytes()
        self.assertEqual(lzma.decompress(packed), self.files['addon/models/m.mdl'])
        entry = index['files']['addon/models/m.mdl']
        self.assertEqual(entry['stored_sha256'], hashlib.sha256(packed).hexdigest())
        self.assertEqual(entry['stored_size'], len(packed))
        self.assertEqual(entry['mtime_ns'], OLD_TIME)
        self.assertEqual(index['origins']['.']['source'], str(self.src))
        self.assertEqual(inputs.verify(['p'], self.packages, deep=True), [])
        # Unchanged sources are not stored again.
        self.assertEqual(self.store_all()['stored'], 0)

    def test_unpack_restores_bytes_and_times_and_removes_stale_files(self):
        self.store_all()
        stale = self.dest / 'p' / 'old' / 'gone.txt'
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b'stale')
        first = inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=2)
        self.assertEqual(first['p'], {'files': len(self.files), 'written': len(self.files), 'removed': 1})
        for rel, data in self.files.items():
            path = self.dest / 'p' / rel
            self.assertEqual(path.read_bytes(), data, rel)
            self.assertEqual(path.stat().st_mtime_ns, OLD_TIME, rel)
        self.assertFalse(stale.parent.exists())
        again = inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=2)
        self.assertEqual(again['p']['written'], 0)

    def test_a_build_overlay_replaces_the_stored_binaries_without_reading_them(self):
        # R16 (ADR 0106): the workflow's binaries replace the stored ones, whose LFS content is not there.
        self.store_all()
        stored = self.packages / 'p' / 'bin/gmcl_x_win64.dll.xz'
        stored.write_bytes(b'version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 1\n')
        overlay = self.root / 'built'
        (overlay / 'p' / 'bin').mkdir(parents=True)
        (overlay / 'p' / 'bin' / 'gmcl_x_win64.dll').write_bytes(b'MZ built in CI')
        result = inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=2, overlay=overlay)
        self.assertEqual(result['p']['built'], ['bin/gmcl_x_win64.dll'])
        self.assertEqual((self.dest / 'p' / 'bin/gmcl_x_win64.dll').read_bytes(), b'MZ built in CI')
        self.assertEqual((self.dest / 'p' / 'addon/lua/a.lua').read_bytes(), self.files['addon/lua/a.lua'])
        # Without the overlay the stored file is needed again (and here it is only a pointer).
        with self.assertRaisesRegex(inputs.InputsError, 'Git LFS pointer'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)

    def test_with_an_overlay_every_native_binary_must_come_from_the_build(self):
        self.store_all()
        overlay = self.root / 'built'
        (overlay / 'p').mkdir(parents=True)
        with self.assertRaisesRegex(inputs.InputsError, 'did not provide: bin/gmcl_x_win64.dll'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1, overlay=overlay)
        # Unless it is named as still taken from packages/ (a file, or a folder ending in /).
        for keep in (('p/bin/gmcl_x_win64.dll',), ('p/bin/',)):
            result = inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1, overlay=overlay,
                                   keep_packaged=keep)
            self.assertEqual(result['p']['built'], [])
            self.assertEqual((self.dest / 'p' / 'bin/gmcl_x_win64.dll').read_bytes(), self.files['bin/gmcl_x_win64.dll'])

    def test_an_overlay_file_the_index_does_not_list_is_refused(self):
        self.store_all()
        overlay = self.root / 'built'
        (overlay / 'p' / 'bin').mkdir(parents=True)
        (overlay / 'p' / 'bin' / 'gmcl_x_win64.dll').write_bytes(b'MZ')
        (overlay / 'p' / 'bin' / 'extra.dll').write_bytes(b'MZ')
        with self.assertRaisesRegex(inputs.InputsError, 'does not list: bin/extra.dll'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1, overlay=overlay)

    def test_extract_writes_one_folder_of_a_part_without_its_prefix(self):
        # R16 (ADR 0107): a source tree kept in a part (model-hotloader's source/mmdhl/) is written out for
        # a build; only those files are read, so the part's other LFS content need not be there.
        self.store_all()
        stored = self.packages / 'p' / 'bin/gmcl_x_win64.dll.xz'
        stored.write_bytes(b'version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 1\n')
        dest = self.root / 'src'
        self.assertEqual(inputs.extract('p', 'addon/', dest, self.packages), 4)
        self.assertEqual((dest / 'lua/a.lua').read_bytes(), self.files['addon/lua/a.lua'])
        self.assertEqual((dest / 'big.txt').read_bytes(), self.files['addon/big.txt'])  # xz in the store
        self.assertEqual((dest / 'models/m.mdl').stat().st_mtime_ns, OLD_TIME)
        self.assertFalse((dest / 'bin').exists())
        with self.assertRaisesRegex(inputs.InputsError, 'ending in /'):
            inputs.extract('p', 'addon', dest, self.packages)
        with self.assertRaisesRegex(inputs.InputsError, 'no file under nothing/'):
            inputs.extract('p', 'nothing/', dest, self.packages)

    def test_unpack_refuses_content_that_does_not_match(self):
        self.store_all()
        (self.packages / 'p' / 'addon/lua/a.lua').write_bytes(b'print("changed")\r\n')
        with self.assertRaisesRegex(inputs.InputsError, 'does not match'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)
        self.assertFalse((self.dest / 'p' / 'addon/lua/a.lua').exists())  # nothing half-written

    def test_unpack_rewrites_a_change_that_kept_the_size_and_time(self):
        # R3-003: an unpacked file is kept only with the indexed content, whatever its size and time say.
        self.store_all()
        inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=2)
        target = self.dest / 'p' / 'addon/lua/a.lua'
        target.write_bytes(b'print("HI")\r\n')  # the same length
        os.utime(target, ns=(OLD_TIME, OLD_TIME))
        again = inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=2)
        self.assertEqual(again['p']['written'], 1)
        self.assertEqual(target.read_bytes(), self.files['addon/lua/a.lua'])

    def test_unpack_refuses_links_and_junctions(self):
        # R3-006: a junction would take the writes, and the removal of stale files, out of the tree.
        import _winapi
        self.store_all()
        victim = self.root / 'victim'
        victim.mkdir()
        (victim / 'unrelated.txt').write_bytes(b'keep me')
        self.dest.mkdir()
        _winapi.CreateJunction(str(victim), str(self.dest / 'p'))
        with self.assertRaisesRegex(inputs.InputsError, 'link or junction'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)
        self.assertEqual(os.listdir(victim), ['unrelated.txt'])
        os.rmdir(self.dest / 'p')  # the junction, not its target
        inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)
        inner = self.dest / 'p' / 'addon' / 'lua'
        shutil.rmtree(inner)
        _winapi.CreateJunction(str(victim), str(inner))
        with self.assertRaisesRegex(inputs.InputsError, 'link or junction'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)
        self.assertEqual(os.listdir(victim), ['unrelated.txt'])
        os.rmdir(inner)

    def test_import_stores_a_change_that_kept_the_size_and_time(self):
        # R3-007: the bytes decide whether a source changed, not its size and time.
        self.store_all()
        source = self.src / 'addon/lua/a.lua'
        source.write_bytes(b'print("HI")\r\n')
        os.utime(source, ns=(OLD_TIME, OLD_TIME))
        self.assertEqual(self.store_all()['stored'], 1)
        self.assertEqual((self.packages / 'p' / 'addon/lua/a.lua').read_bytes(), b'print("HI")\r\n')

    def test_verify_finds_missing_extra_and_changed_files(self):
        self.store_all()
        base = self.packages / 'p'
        (base / 'addon/big.txt.xz').unlink()
        (base / 'stray.bin').write_bytes(b'?')
        (base / 'README.md').write_text('about the part\n', encoding='utf-8')  # allowed beside the index
        (base / 'addon/lua/a.lua').write_bytes(b'other')
        problems = '\n'.join(inputs.verify(['p'], self.packages))
        self.assertIn('addon/big.txt.xz is missing', problems)
        self.assertIn('stray.bin is not in files.json', problems)
        self.assertIn('addon/lua/a.lua does not match', problems)
        self.assertNotIn('README.md', problems)

    def test_lfs_pointers_verify_by_oid_and_cannot_be_unpacked(self):
        self.store_all()
        base = self.packages / 'p'
        entry = inputs.read_index('p', self.packages)['files']['addon/models/m.mdl']
        pointer = (f'version https://git-lfs.github.com/spec/v1\noid sha256:{entry["stored_sha256"]}\n'
                   f'size {entry["stored_size"]}\n').encode('ascii')
        (base / 'addon/models/m.mdl.xz').write_bytes(pointer)
        self.assertEqual(inputs.verify(['p'], self.packages), [])
        with self.assertRaisesRegex(inputs.InputsError, 'git lfs pull'):
            inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1)
        (base / 'addon/models/m.mdl.xz').write_bytes(pointer.replace(b'size ', b'size 9'))
        self.assertIn('LFS pointer to other content', '\n'.join(inputs.verify(['p'], self.packages)))

    def test_import_from_an_inventory_maps_roots_and_prunes(self):
        other = self.root / 'modules'
        other.mkdir()
        (other / 'gmcl_y_win64.dll').write_bytes(b'MZ y')
        lines = ['# part 1.0.0: 3 files', 'size\tsha256\tpath\tsource\tnote']
        for pkg, src in (('native/root/garrysmod/addons/a/lua/a.lua', self.src / 'addon/lua/a.lua'),
                         ('native/root/garrysmod/lua/bin/gmcl_y_win64.dll', other / 'gmcl_y_win64.dll'),
                         ('native/manifest.json', '(written by the packager)'),
                         ('native/root/garrysmod/addons/nativeloader/x.lua', REPO / 'companion' / 'README.md')):
            digest = inputs.sha256_file(src) if isinstance(src, Path) else '0'
            lines.append(f'1\t{digest}\t{pkg}\t{src}\t')
        inventory = self.root / 'part.inventory.txt'
        inventory.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        roots = [(self.src, 'repo'), (other, 'modules')]
        inputs.import_files('q', roots, [], inventory, prune=True, packages=self.packages, log=quiet, workers=1)
        files = set(inputs.read_index('q', self.packages)['files'])
        self.assertEqual(files, {'repo/addon/lua/a.lua', 'modules/gmcl_y_win64.dll'})  # the repo's own source skipped
        # A source that changed after the packager read it no longer matches the part: refused.
        (other / 'gmcl_y_win64.dll').write_bytes(b'MZ z')
        with self.assertRaisesRegex(inputs.InputsError, 'changed since the packager read it'):
            inputs.import_files('q', roots, [], inventory, prune=True, packages=self.packages, log=quiet, workers=1)
        (other / 'gmcl_y_win64.dll').write_bytes(b'MZ y')
        # A source in no root is an error, not a silent omission.
        with self.assertRaisesRegex(inputs.InputsError, 'in no --root'):
            inputs.import_files('q', [(other, 'modules')], [], inventory, prune=True, packages=self.packages, log=quiet)
        # Pruning drops what a later import of the same prefix no longer brings.
        lines = [l for l in lines if 'gmcl_y' not in l]
        inventory.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        result = inputs.import_files('q', roots, [], inventory, prune=True, packages=self.packages, log=quiet, workers=1)
        self.assertEqual(result['removed'], ['modules/gmcl_y_win64.dll'])
        self.assertFalse((self.packages / 'q' / 'modules/gmcl_y_win64.dll.xz').exists())

    def test_single_files_and_refused_paths(self):
        inputs.import_files('r', [], [(self.src / 'bin/gmcl_x_win64.dll', 'bin/x.dll')], None, prune=False,
                            packages=self.packages, log=quiet, workers=1)
        self.assertEqual(set(inputs.read_index('r', self.packages)['files']), {'bin/x.dll'})
        for bad in ('../x', 'a//b', 'C:/x', 'a\\b', '/abs', 'files.json'):
            with self.assertRaises(inputs.InputsError, msg=bad):
                inputs.import_files('r', [], [(self.src / 'addon/lua/a.lua', bad)], None, prune=False,
                                    packages=self.packages, log=quiet, workers=1)
        with self.assertRaisesRegex(inputs.InputsError, 'differ only in case'):
            inputs.import_files('r', [], [(self.src / 'addon/lua/a.lua', 'A.lua'), (self.src / 'addon/latin.txt', 'a.lua')],
                                None, prune=False, packages=self.packages, log=quiet, workers=1)
        with self.assertRaises(inputs.InputsError):
            inputs.part_dir('../escape', self.packages)

    def test_names_windows_reads_as_other_files_are_refused(self):
        # Review R19, F-09: `files/foo.dll.` is `files/foo.dll` to Windows, and `foo.dll..xz` stores beside
        # `foo.dll.xz` while both unpack to one file: whichever thread wrote last went into the package.
        for bad in ('bin/x.dll.', 'bin/x.dll ', 'bin./x.dll', 'bin/NUL', 'bin/com1.dll', 'bin/aux.txt',
                    'bin/LONGNA~1.DLL', 'bin/x?.dll', 'bin/x<y', 'bin/x\x01'):
            with self.subTest(bad=bad), self.assertRaises(inputs.InputsError):
                inputs.import_files('r', [], [(self.src / 'addon/lua/a.lua', bad)], None, prune=False,
                                    packages=self.packages, log=quiet, workers=1)
        self.assertFalse((self.packages / 'r').exists())  # refused before anything was stored
        # Folders named like the add-ons' own (`~gmod_topbr`) stay allowed: no digit after the tilde.
        inputs.check_rel('garrysmod/rtx-remix/mods/~gmod_topbr/mod.usda')
        # A hand-edited index is checked whole before verify, unpack, extract or import read by it.
        self.store_all()
        index_path = self.packages / 'p' / inputs.INDEX
        good = json.loads(index_path.read_text(encoding='utf-8'))
        entry = good['files']['bin/gmcl_x_win64.dll']
        for files, message in (({'bin/gmcl_x_win64.dll': entry, 'bin/gmcl_x_win64.dll.': entry}, 'ends in a dot'),
                               ({'bin/gmcl_x_win64.dll': entry, 'BIN/gmcl_x_win64.dll': entry}, 'differ only in case'),
                               ({'bin/gmcl_x_win64.dll': entry, 'bin/gmcl_x_win64.dll.xz': {**entry, 'stored': 'plain'}},
                                'stored under one name')):
            index_path.write_text(json.dumps({**good, 'files': {**good['files'], **files}}), encoding='utf-8')
            with self.subTest(message=message):
                self.assertIn(message, '\n'.join(inputs.verify(['p'], self.packages)))
                for read in (lambda: inputs.unpack(['p'], self.packages, self.dest, log=quiet, workers=1),
                             lambda: inputs.extract('p', 'bin/', self.root / 'extracted', self.packages),
                             lambda: self.store_all()):
                    with self.assertRaisesRegex(inputs.InputsError, message):
                        read()
        self.assertFalse((self.dest / 'p').exists())
        index_path.write_text(json.dumps(good), encoding='utf-8')
        self.assertEqual(inputs.verify(['p'], self.packages), [])
        # A new path naming an indexed path's file is refused before it is stored over that file.
        before = (self.packages / 'p' / 'addon/lua/a.lua').read_bytes()
        with self.assertRaisesRegex(inputs.InputsError, 'differ only in case'):
            inputs.import_files('p', [], [(self.src / 'addon/latin.txt', 'ADDON/lua/a.lua')], None, prune=False,
                                packages=self.packages, log=quiet, workers=1)
        self.assertEqual((self.packages / 'p' / 'addon/lua/a.lua').read_bytes(), before)
        self.assertEqual(inputs.verify(['p'], self.packages), [])

    def test_an_index_that_cannot_be_read_stops_an_import(self):
        # It was replaced by a new index that held only the imported files.
        self.store_all()
        index_path = self.packages / 'p' / inputs.INDEX
        index_path.write_text('{not json', encoding='utf-8')
        with self.assertRaises(inputs.InputsError):
            self.store_all()
        self.assertEqual(index_path.read_text(encoding='utf-8'), '{not json')

    def test_the_repository_packages_verify(self):
        # Every part committed under packages/ matches its index (LFS pointers are checked by oid).
        problems = inputs.verify()
        self.assertEqual(problems, [], '\n'.join(problems[:20]))


if __name__ == '__main__':
    unittest.main()
