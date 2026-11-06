import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_repo

REPO = Path(__file__).resolve().parents[2]
SCRATCH = REPO / 'out' / 'tmp'  # AGENTS.md rule 9, whoever runs the tests and whatever TEMP says


def scratch_folder():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    return tempfile.TemporaryDirectory(dir=SCRATCH, prefix='check-repo-')


def make_repo(root, extra=None):
    """A minimal repo that satisfies every rule; `extra` adds or overrides files."""
    files = {
        'AGENTS.md': '# Agents\n',
        'CLAUDE.md': '@AGENTS.md\n',
        'CHANGELOG.md': '# Changelog\n\n## [Unreleased]\n',
        'docs/COMPONENTS.md': 'loader/core and tools/lib\n',
        'loader/core/CMakeLists.txt': '',
        'loader/core/README.md': 'version.cpp builds the version string.\n',
        'loader/core/src/version.cpp': '',
        'tools/lib/env.ps1': '',
        'tools/lib/env.ps1.md': 'Imports the build environment. See [the docs](../../docs/COMPONENTS.md).\n',
    }
    files.update(extra or {})
    for rel, text in files.items():
        if text is None:
            continue
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')


class CheckRepoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = scratch_folder()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_scratch_is_in_the_repo_whatever_the_temp_folder(self):
        # A temp folder that does not exist: a fixture that used it would fail to start.
        with mock.patch.object(tempfile, 'tempdir', str(REPO / 'out' / 'no-such-temp-folder')):
            self.tearDown()
            self.setUp()
        self.assertEqual(self.root.resolve().parent, SCRATCH.resolve())

    def problems(self, extra=None):
        make_repo(self.root, extra)
        return check_repo.check(self.root)

    def test_clean_repo_passes(self):
        self.assertEqual(self.problems(), [])

    def test_script_without_doc(self):
        self.assertEqual(self.problems({'tools/lib/new.py': ''}), ['tools/lib/new.py: missing new.py.md beside it'])

    def test_module_readme_must_name_sources(self):
        self.assertEqual(self.problems({'loader/core/src/gma.cpp': ''}),
                         ['loader/core/README.md: does not mention src/gma.cpp'])

    def test_nested_module_has_its_own_readme(self):
        found = self.problems({'loader/core/sub/CMakeLists.txt': '', 'loader/core/sub/x.cpp': ''})
        self.assertEqual(found, ['loader/core/sub/: module folder has no README.md'])

    def test_broken_relative_link(self):
        found = self.problems({'docs/A.md': 'see [b](B.md), [web](https://example.com) and `[x](nope.md)`\n'})
        self.assertEqual(found, ['docs/A.md: broken link -> B.md'])

    def test_links_inside_code_fences_are_ignored(self):
        self.assertEqual(self.problems({'docs/A.md': '```\n[x](missing.md)\n```\n'}), [])

    def test_changelog_needs_unreleased_section(self):
        self.assertEqual(self.problems({'CHANGELOG.md': '# Changelog\n'}),
                         ['CHANGELOG.md has no "## [Unreleased]" section'])

    def test_components_must_list_every_folder(self):
        self.assertEqual(self.problems({'tools/steam/README.txt': ''}),
                         ['docs/COMPONENTS.md does not mention tools/steam'])

    def test_claude_md_imports_agents_md(self):
        self.assertEqual(self.problems({'CLAUDE.md': 'nothing here\n'}), ['CLAUDE.md must exist and import @AGENTS.md'])

    def test_other_checkouts_inside_are_not_this_repos_files(self):
        # A worktree another session keeps in .claude/worktrees has its own .git file; its files are not
        # this checkout's (it had failed the checks of main with every script of its packages/).
        self.assertEqual(self.problems({'.claude/worktrees/side/.git': 'gitdir: elsewhere\n',
                                        '.claude/worktrees/side/tools/new.py': ''}), [])

    def test_the_stored_runtime_must_be_what_runtime_builds(self):
        # R3-014: a patch, a submodule setting or a clone changed without a new build fails the checks.
        import hashlib
        import json
        patch = 'From 1\nSubject: [PATCH] x\n\n'
        files = {'runtime/patches/0001-x.patch': patch, 'runtime/submodules/a.patch': 'diff\n',
                 'packages/runtime/files.json': json.dumps({'files': {'files/d3d9.dll': {'sha256': 'dd'}}})}
        make_repo(self.root, files)  # the record holds the bytes as written (Windows writes CRLF)
        sha = lambda rel: hashlib.sha256((self.root / 'runtime' / rel).read_bytes()).hexdigest()
        subs = {'submodules/a': {'commit': 'abc', 'why': 'because'}}
        record = {'d3d9.dll': 'dd', 'commit': 'c1', 'submodules': subs, 'clones': {},
                  'files': {'patches/0001-x.patch': sha('patches/0001-x.patch'), 'submodules/a.patch': sha('submodules/a.patch')}}
        base = {'commit': 'c1', 'submodules': subs, 'packaged': record}
        files['runtime/base.json'] = json.dumps(base)
        self.assertEqual(self.problems(files), [])
        reworded = dict(base, submodules={'submodules/a': {'commit': 'abc', 'why': 'reworded'}})
        self.assertEqual(self.problems({**files, 'runtime/base.json': json.dumps(reworded)}), [])  # explanations aside
        changed = self.problems({**files, 'runtime/patches/0001-x.patch': patch + 'more\n'})
        self.assertEqual(len(changed), 1)
        self.assertIn('the files differ', changed[0])
        other = dict(base, submodules={'submodules/a': {'commit': 'def'}})
        self.assertIn('the submodules differ', self.problems({**files, 'runtime/patches/0001-x.patch': patch,
                                                               'runtime/base.json': json.dumps(other)})[0])
        stored = self.problems({**files, 'runtime/base.json': json.dumps(base),
                                'packages/runtime/files.json': json.dumps({'files': {'files/d3d9.dll': {'sha256': 'ee'}}})})
        self.assertEqual(stored, ['packages/runtime/files/d3d9.dll is not the d3d9.dll runtime/base.json "packaged" records'])

    def test_the_stored_repository_modules_must_be_what_their_sources_build(self):
        # ADR 0126 (after R20-Q: an R4 build of the client module shipped until R20): a module this repository
        # compiles and stores in packages/ fails the checks while a source differs from its record.
        import json
        import repo_builds
        entry = {'part': 'glass', 'path': 'bin/m.dll', 'from': 'out/build/win64-release/m/m.dll', 'target': 'm',
                 'sources': ['CMakeLists.txt', 'mod'], 'not_sources': ['mod/tests']}
        files = {'docs/COMPONENTS.md': 'loader/core, tools/lib and tools/ci\n', 'CMakeLists.txt': 'project(x)\n',
                 'mod/a.cpp': 'int a;\n', 'mod/a.h': '#pragma once\n', 'mod/README.md': 'a.cpp\n',
                 'mod/tests/t.cpp': 'int t;\n',
                 'packages/glass/files.json': json.dumps({'files': {'bin/m.dll': {'sha256': 'aa'}}})}
        make_repo(self.root, files)  # write_text: CRLF on Windows
        record = {'sha256': 'aa', 'sources': repo_builds.source_digests(self.root, entry)}
        files['tools/ci/pins.json'] = json.dumps({'repository_builds': [dict(entry, packaged=record)]})
        self.assertEqual(self.problems(files), [])
        # Documentation, what not_sources leaves out, and a checkout's line endings are not sources.
        self.assertEqual(self.problems({**files, 'mod/README.md': 'more\n', 'mod/tests/t.cpp': 'int u;\n'}), [])
        (self.root / 'mod' / 'a.cpp').write_bytes(b'int a;\n')
        self.assertEqual(check_repo.check(self.root), [])
        changed = self.problems({**files, 'mod/a.cpp': 'int b;\n'})
        self.assertEqual(len(changed), 1)
        self.assertIn('packages/glass/bin/m.dll was built from other sources', changed[0])
        self.assertIn(': mod changed;', changed[0])
        self.assertIn('repo_builds.py refresh glass/bin/m.dll', changed[0])
        self.assertEqual(self.problems(files), [])
        (self.root / 'mod' / 'a.cpp').rename(self.root / 'mod' / 'b.cpp')  # the same content under another name
        self.assertIn(': mod changed;', check_repo.check(self.root)[0])
        (self.root / 'mod' / 'b.cpp').rename(self.root / 'mod' / 'a.cpp')
        more = json.dumps({'repository_builds': [dict(entry, sources=['CMakeLists.txt', 'mod', 'extra.h'], packaged=record)]})
        self.assertIn(': extra.h is missing;', self.problems({**files, 'tools/ci/pins.json': more})[0])
        self.assertIn(': extra.h is new;', self.problems({**files, 'extra.h': '', 'tools/ci/pins.json': more})[0])
        fewer = json.dumps({'repository_builds': [dict(entry, sources=['mod'], packaged=record)]})
        self.assertIn(': CMakeLists.txt is no longer a source;', self.problems({**files, 'tools/ci/pins.json': fewer})[0])
        self.assertEqual(self.problems({**files, 'packages/glass/files.json': json.dumps(
            {'files': {'bin/m.dll': {'sha256': 'bb'}}})}),
            ['packages/glass/bin/m.dll is not the module tools/ci/pins.json "packaged" records; '
             'python tools/ci/repo_builds.py refresh glass/bin/m.dll'])
        unrecorded = self.problems({**files, 'tools/ci/pins.json': json.dumps({'repository_builds': [entry]})})
        self.assertEqual(len(unrecorded), 1)
        self.assertIn('has no "packaged" record', unrecorded[0])


if __name__ == '__main__':
    unittest.main()
