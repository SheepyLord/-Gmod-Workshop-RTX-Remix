"""Tests for tools/ci/repo_builds.py (ADR 0126): the records of the native modules this repository compiles
itself. Two links of the same sources compare as the same image; refresh imports a build only when it is
another image, refuses a build that read files outside the module's sources, one whose sources changed
while it ran, a Debug or stale build and another checkout's build of other sources, and writes the record
into pins.json without changing the rest of it. The declared sources are checked against what this
checkout's Ninja build read, when there is one."""
import hashlib
import json
import os
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS / 'ci'))
sys.path.insert(0, str(TOOLS))
import inputs  # noqa: E402
import repo_builds  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'
MODULE = 'glass/bin/m.dll'


def pe(stamp=1, guid=b'\x11' * 16, pdb=b'C:\\work\\out\\m.pdb', anon=b'1234abcd', code=b'\x90' * 16) -> bytes:
    """A minimal PE32+ image as MSVC links one: a section holding the debug directory with a CodeView record
    (the PDB's GUID, age and path), an RTTI name in an anonymous namespace, and some code."""
    lfanew, optional_size, raw, rva = 0x40, 240, 0x200, 0x1000
    codeview = b'RSDS' + guid + struct.pack('<I', 1) + pdb + b'\0'
    debug = struct.pack('<IIHHIIII', 0, stamp, 0, 0, 2, len(codeview), rva + 28, raw + 28)
    body = debug + codeview + b'.?AVPairFilter@?A0x' + anon + b'@glass@nl@@\0' + code
    size = (len(body) + 0x1FF) & ~0x1FF
    image = bytearray(raw + size)
    image[0:2] = b'MZ'
    struct.pack_into('<I', image, 0x3C, lfanew)
    image[lfanew:lfanew + 4] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', image, lfanew + 4, 0x8664, 1, stamp, 0, 0, optional_size, 0x2022)
    optional = lfanew + 24
    struct.pack_into('<H', image, optional, 0x20B)
    struct.pack_into('<I', image, optional + 64, stamp * 7)  # the checksum
    struct.pack_into('<I', image, optional + 108, 16)
    struct.pack_into('<II', image, optional + 112 + 8 * 6, rva, 28)
    struct.pack_into('<8sIIII', image, optional + optional_size, b'.rdata', len(body), rva, size, raw)
    image[raw:raw + len(body)] = body
    return bytes(image)


def norm(path) -> str:
    return os.path.normcase(os.path.normpath(str(path)))


class ImageTests(unittest.TestCase):
    def test_two_links_of_the_same_sources_are_the_same_image(self):
        # Another link time, PDB GUID, PDB path of the same length and source path (anonymous namespaces).
        one = pe(stamp=1, guid=b'\x11' * 16, pdb=b'C:\\one\\out\\m.pdb', anon=b'1234abcd')
        two = pe(stamp=2, guid=b'\x22' * 16, pdb=b'C:\\two\\out\\m.pdb', anon=b'89abcdef')
        self.assertNotEqual(one, two)
        self.assertTrue(repo_builds.same_image(one, two))

    def test_other_code_or_a_pdb_path_of_another_length_is_another_image(self):
        image = pe()
        self.assertFalse(repo_builds.same_image(image, pe(code=b'\xcc' * 16)))
        self.assertFalse(repo_builds.same_image(image, pe(pdb=b'C:\\longer\\out\\m.pdb')))
        self.assertFalse(repo_builds.same_image(b'MZ not an image', b'MZ not an image'))
        self.assertIsNone(repo_builds.normalized_image(image[:0x100]))
        self.assertFalse(repo_builds.same_image(image[:0x100], image[:0x100]))


class NinjaTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-repo-builds-', dir=SCRATCH))
        self.addCleanup(shutil.rmtree, self.root, True)

    def test_what_a_build_read_and_what_its_sources_cover(self):
        build = self.root / 'out' / 'build' / 'win64-release'
        (self.root / 'mod').mkdir(parents=True)
        (self.root / 'mod' / 'a.cpp').write_text('', encoding='utf-8')
        listed = {
            'inputs': f'{self.root / "mod" / "a.cpp"}\ncmake_object_order_depends_target_m\n'
                      'm\\CMakeFiles\\m.dir\\a.cpp.obj\nm\\m.lib\n',
            'deps': 'm/CMakeFiles/m.dir/a.cpp.obj: #deps 3, deps mtime 1 (VALID)\n    ../../../mod/a.h\n'
                    '    m/generated/g.h\n    C:/Program Files/x/string.h\n\n'
                    'o/CMakeFiles/o.dir/o.cpp.obj: #deps 1, deps mtime 1 (VALID)\n    ../../../other/o.h\n\n'}
        with mock.patch.object(repo_builds, 'run', side_effect=lambda *a: listed['inputs' if 'inputs' in a else 'deps']):
            reads = repo_builds.build_reads('ninja', build, 'm/m.dll')
        # The module's sources and headers; not the objects, libraries, phony targets or other objects' headers.
        self.assertEqual(reads, {norm(self.root / 'mod' / 'a.cpp'), norm(self.root / 'mod' / 'a.h'),
                                 norm(build / 'm' / 'generated' / 'g.h'), norm('C:/Program Files/x/string.h')})
        entry = {'sources': ['mod'], 'not_sources': ['mod/tests']}
        # Generated headers in the build folder and files outside the tree are not sources.
        self.assertEqual(repo_builds.undeclared_reads(self.root, build, reads, entry), [])
        self.assertEqual(repo_builds.undeclared_reads(self.root, build, reads, {'sources': ['mod/a.cpp']}), ['mod/a.h'])
        tests = reads | {norm(self.root / 'mod' / 'tests' / 't.h')}
        self.assertEqual(repo_builds.undeclared_reads(self.root, build, tests, entry), ['mod/tests/t.h'])


class RefreshTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-repo-builds-', dir=SCRATCH))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.entry = {'part': 'glass', 'path': 'bin/m.dll', 'from': 'out/build/win64-release/m/m.dll', 'target': 'm',
                      'sources': ['mod'], 'not_sources': ['mod/tests']}
        self.write('tools/ci/pins.json', json.dumps({'about': 'x', 'repository_builds': [self.entry]}, indent=2) + '\n')
        self.write('mod/a.cpp', 'int a;\n')
        self.build = self.root / 'out' / 'build' / 'win64-release'
        self.cache(self.root)
        self.write('out/build/win64-release/CMakeFiles/3.31.6/CMakeCXXCompiler.cmake',
                   'set(CMAKE_CXX_COMPILER_ID "MSVC")\nset(CMAKE_CXX_COMPILER_VERSION "19.44.1.0")\n')
        self.link(pe(stamp=1))
        self.reads = {str(self.root / 'mod' / 'a.cpp')}
        self.builds = 0
        for patch in (mock.patch.object(repo_builds, 'up_to_date', return_value=True),
                      mock.patch.object(repo_builds, 'build_reads', side_effect=lambda *a: {norm(p) for p in self.reads}),
                      mock.patch.object(repo_builds, 'git_commit', return_value='c0ffee')):
            patch.start()
            self.addCleanup(patch.stop)

    def write(self, rel, text, root=None):
        path = (root or self.root) / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def cache(self, home, kind='Release', root=None):
        self.write('out/build/win64-release/CMakeCache.txt',
                   f'CMAKE_BUILD_TYPE:STRING={kind}\nCMAKE_GENERATOR:INTERNAL=Ninja\n'
                   f'CMAKE_HOME_DIRECTORY:INTERNAL={Path(home).as_posix()}\nCMAKE_MAKE_PROGRAM:FILEPATH=ninja\n', root)

    def link(self, image, build=None):
        path = (build or self.build) / 'm' / 'm.dll'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(image)

    def count_build(self, root):
        self.builds += 1

    def refresh(self, *names, build=None, build_dir=None):
        return repo_builds.refresh(self.root, list(names), build_dir, log=lambda *_: None, build=build or self.count_build)

    def stored(self):
        return inputs.read_index('glass', self.root / 'packages')['files']['bin/m.dll']['sha256']

    def record(self):
        return repo_builds.load_pins(self.root)['repository_builds'][0]['packaged']

    def test_a_first_build_is_imported_and_recorded(self):
        self.assertIn('has no "packaged" record', repo_builds.problems(self.root)[0])
        self.refresh()
        self.assertEqual(self.builds, 1)
        self.assertEqual(self.stored(), hashlib.sha256(pe(stamp=1)).hexdigest())
        record = self.record()
        self.assertEqual(record, {'sha256': self.stored(), 'sources': repo_builds.source_digests(self.root, self.entry),
                                  'commit': 'c0ffee', 'how': 'imported: built from these sources',
                                  'build': 'out/build/win64-release (tools/build.ps1 -Config Release), MSVC 19.44.1.0'})
        self.assertEqual(repo_builds.problems(self.root), [])
        # A current module is left alone, named or not, and nothing is built for it.
        self.assertEqual(self.refresh(), [])
        self.assertEqual(self.refresh('m'), [])
        self.assertEqual(self.builds, 1)
        with self.assertRaisesRegex(repo_builds.RecordError, 'not a repository build'):
            self.refresh('glass/bin/other.dll')

    def test_the_same_image_is_kept_and_another_one_imported(self):
        self.refresh()
        first = self.stored()
        stored_file = self.root / 'packages' / 'glass' / 'bin' / 'm.dll.xz'
        stored_bytes = stored_file.read_bytes()
        self.write('mod/a.cpp', 'int a;  // a comment\n')
        self.assertIn(': mod changed;', repo_builds.problems(self.root)[0])
        self.link(pe(stamp=9, guid=b'\x22' * 16, pdb=b'D:\\work\\out\\m.pdb', anon=b'feedbeef'))
        self.refresh(MODULE)
        self.assertEqual((self.stored(), stored_file.read_bytes()), (first, stored_bytes))  # nothing imported
        self.assertEqual(self.record()['how'], 'kept: a build of these sources is the same image')
        self.assertEqual(self.record()['sources'], repo_builds.source_digests(self.root, self.entry))
        self.assertEqual(repo_builds.problems(self.root), [])
        self.write('mod/a.cpp', 'int a = 1;\n')
        self.link(pe(stamp=10, code=b'\xcc' * 16))
        self.refresh()
        self.assertEqual(self.stored(), hashlib.sha256(pe(stamp=10, code=b'\xcc' * 16)).hexdigest())
        self.assertEqual(self.record()['how'], 'imported: built from these sources')
        self.assertEqual(repo_builds.problems(self.root), [])
        # A stored module without its Git LFS content cannot be compared with the build.
        stored_file.write_bytes(b'version https://git-lfs.github.com/spec/v1\noid sha256:00\nsize 1\n')
        self.write('mod/a.cpp', 'int a = 2;\n')
        with self.assertRaisesRegex(repo_builds.RecordError, 'git lfs pull --include "packages/glass/bin/m.dll.xz"'):
            self.refresh()

    def test_a_build_that_read_files_outside_the_sources_is_refused(self):
        pins = (self.root / 'tools' / 'ci' / 'pins.json').read_bytes()
        self.reads |= {str(self.root / 'other' / 'x.h'), str(self.root / 'mod' / 'tests' / 't.h')}
        with self.assertRaisesRegex(repo_builds.RecordError, 'do not cover: mod/tests/t.h, other/x.h'):
            self.refresh()
        self.assertEqual((self.root / 'tools' / 'ci' / 'pins.json').read_bytes(), pins)
        self.assertFalse((self.root / 'packages').exists())
        # Generated files in the build folder and the compiler's files are not this repository's sources.
        self.reads = {str(self.root / 'mod' / 'a.cpp'), str(self.build / 'm' / 'generated' / 'g.h'),
                      'C:\\Program Files\\Microsoft Visual Studio\\include\\string'}
        self.refresh()
        self.assertEqual(repo_builds.problems(self.root), [])

    def test_only_an_up_to_date_release_build_of_these_sources_is_taken(self):
        def edit(root):
            self.write('mod/a.cpp', 'int edited;\n')
        with self.assertRaisesRegex(repo_builds.RecordError, 'changed while it was built'):
            self.refresh(build=edit)
        self.cache(self.root, 'Debug')
        with self.assertRaisesRegex(repo_builds.RecordError, 'not a Ninja Release build'):
            self.refresh()
        self.cache(self.root)
        with mock.patch.object(repo_builds, 'up_to_date', return_value=False):
            with self.assertRaisesRegex(repo_builds.RecordError, 'older than its sources'):
                self.refresh()
        self.assertFalse((self.root / 'packages').exists())
        # Another checkout's build is taken as it is (nothing is built) when its sources are these.
        other = self.root / 'out' / 'other'
        self.write('mod/a.cpp', 'int other;\n', other)
        self.cache(other, root=other)
        self.link(pe(stamp=3), other / 'out' / 'build' / 'win64-release')
        with self.assertRaisesRegex(repo_builds.RecordError, "whose sources of it are not this checkout's"):
            self.refresh(build_dir=other / 'out' / 'build' / 'win64-release')
        self.write('mod/a.cpp', 'int edited;\n', other)  # now this checkout's
        self.cache(self.root, root=other)  # a build folder that is not its checkout's out/build/win64-release
        with self.assertRaisesRegex(repo_builds.RecordError, 'not the out/build/win64-release folder'):
            self.refresh(build_dir=other / 'out' / 'build' / 'win64-release')
        self.cache(other, root=other)
        builds = self.builds
        self.refresh(build_dir=other / 'out' / 'build' / 'win64-release')
        self.assertEqual(self.builds, builds)
        self.assertEqual(self.stored(), hashlib.sha256(pe(stamp=3)).hexdigest())
        self.assertEqual(repo_builds.problems(self.root), [])

    def test_the_record_keeps_the_rest_of_pins_json(self):
        for newline in ('\n', '\r\n'):
            text = json.dumps({'about': 'x', 'repository_builds': [self.entry], 'fetched': []}, indent=2) + '\n'
            (self.root / 'tools' / 'ci' / 'pins.json').write_bytes(text.replace('\n', newline).encode('utf-8'))
            repo_builds.write_record(self.root, MODULE, {'sha256': 'aa'})
            raw = (self.root / 'tools' / 'ci' / 'pins.json').read_bytes()
            self.assertEqual(raw.count(b'\r\n'), raw.count(b'\n') if newline == '\r\n' else 0)
            pins = json.loads(raw)
            self.assertEqual(list(pins), ['about', 'repository_builds', 'fetched'])
            self.assertEqual(pins['repository_builds'][0], dict(self.entry, packaged={'sha256': 'aa'}))
        with self.assertRaisesRegex(repo_builds.RecordError, 'no repository build glass/bin/x.dll'):
            repo_builds.write_record(self.root, 'glass/bin/x.dll', {})


class ThisRepositoryTests(unittest.TestCase):
    def test_every_repository_build_names_its_sources(self):
        for entry in repo_builds.load_pins(REPO)['repository_builds']:
            name = repo_builds.module_name(entry)
            self.assertTrue(entry.get('sources'), name)
            for source in entry['sources']:
                self.assertTrue((REPO / source).exists(), f'{name}: {source}')
            for left_out in entry.get('not_sources', []):
                self.assertTrue(any(left_out.startswith(s + '/') for s in entry['sources']), f'{name}: {left_out}')
            repo_builds.target_of(entry)  # in the Release build folder

    def test_the_sources_cover_what_this_checkouts_build_read(self):
        """Every file of this repository a module's build read (Ninja's inputs and its header log) is under
        the module's sources, so a new include or library outside them fails here."""
        build = next((REPO / 'out' / 'build' / preset for preset in ('win64-release', 'win64-debug')
                      if (REPO / 'out' / 'build' / preset / 'build.ninja').is_file()), None)
        if build is None:
            self.skipTest('no Ninja build in this checkout (tools/build.ps1 makes one)')
        ninja = repo_builds.read_cache(build).get('CMAKE_MAKE_PROGRAM', '')
        if not Path(ninja).is_file():
            self.skipTest(f'Ninja not found: {ninja}')
        checked = 0
        for entry in repo_builds.load_pins(REPO)['repository_builds']:
            target = repo_builds.target_of(entry)
            if not (build / target).is_file():
                continue
            reads = repo_builds.build_reads(ninja, build, target)
            sources = [norm(REPO / s) for s in entry['sources']]
            self.assertTrue(any(r.startswith(s) for r in reads for s in sources), repo_builds.module_name(entry))
            self.assertEqual(repo_builds.undeclared_reads(REPO, build, reads, entry), [], repo_builds.module_name(entry))
            checked += 1
        if not checked:
            self.skipTest(f'no repository module built in {build}')


if __name__ == '__main__':
    unittest.main()
