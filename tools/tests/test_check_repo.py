import tempfile
import unittest
from pathlib import Path

import check_repo


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
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

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


if __name__ == '__main__':
    unittest.main()
