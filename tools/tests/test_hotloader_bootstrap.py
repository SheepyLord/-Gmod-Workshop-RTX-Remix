"""R19 (review F-03): the Model Hotloader's bootstrap fetches its locked sources with git. See
test_hotloader_bootstrap.py.md."""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
BOOTSTRAP = REPO / 'packages/model-hotloader/source/mmdhl/scripts/bootstrap.py'
SCRATCH = REPO / 'out' / 'tmp'
IDENTITY = ['-c', 'user.name=Bootstrap Test', '-c', 'user.email=bootstrap@test.invalid', '-c', 'commit.gpgsign=false']


def git(*args, cwd=None):
    return subprocess.run(['git', *IDENTITY, *map(str, args)], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


@unittest.skipUnless(shutil.which('git'), 'git is not installed')
class BootstrapTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.folder = Path(tempfile.mkdtemp(prefix='hl-bootstrap-', dir=SCRATCH))
        self.addCleanup(self.remove, self.folder)
        # The add-on's root as the script sees it: scripts/bootstrap.py and vendor/ beside it.
        scripts = self.folder / 'addon' / 'scripts'
        scripts.mkdir(parents=True)
        shutil.copy(BOOTSTRAP, scripts / 'bootstrap.py')
        spec = importlib.util.spec_from_file_location('mmdhl_bootstrap_under_test', scripts / 'bootstrap.py')
        self.bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.bootstrap)
        self.vendor = self.folder / 'addon' / 'vendor'
        # A repository standing in for GitHub's owner/name, reached as <base>/owner/name.git.
        work = self.folder / 'work'
        work.mkdir()
        git('init', '-q', work)
        (work / 'a.txt').write_bytes(b'first\n')
        (work / 'sub').mkdir()
        (work / 'sub' / 'b.txt').write_bytes(b'below\n')
        (work / 'left-out.txt').write_bytes(b'export-ignore\n')
        (work / '.gitattributes').write_bytes(b'left-out.txt export-ignore\n')
        git('-c', 'core.autocrlf=false', 'add', '-A', cwd=work)
        git('commit', '-q', '-m', 'locked', cwd=work)
        self.locked = git('rev-parse', 'HEAD', cwd=work)
        remote = self.folder / 'remote' / 'owner' / 'name.git'
        git('clone', '-q', '--bare', work, remote)
        git('config', 'uploadpack.allowAnySHA1InWant', 'true', cwd=remote)
        # The locked commit is no longer the branch's tip: it is fetched by its hash.
        (work / 'a.txt').write_bytes(b'later\n')
        git('-c', 'core.autocrlf=false', 'commit', '-q', '-am', 'later', cwd=work)
        git('push', '-q', remote, 'HEAD:refs/heads/main', '--force', cwd=work)
        self.bootstrap.GIT_BASE = (self.folder / 'remote').as_uri()

    @staticmethod
    def remove(path):
        # git's object files are read-only on Windows.
        def writable(function, name, _):
            Path(name).chmod(0o700)
            function(name)
        if sys.version_info >= (3, 12):
            shutil.rmtree(path, onexc=writable)
        else:
            shutil.rmtree(path, onerror=writable)

    def test_a_locked_commit_is_fetched_with_git(self):
        # As Git for Windows is set up by default: line endings converted on the way out.
        crlf = {'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.autocrlf', 'GIT_CONFIG_VALUE_0': 'true'}
        with mock.patch.dict(os.environ, crlf):
            result = self.bootstrap.fetch(('dep', ('owner/name', self.locked)))
        self.assertEqual(result, 'dep: fetched ' + self.locked)
        target = self.vendor / 'dep'
        # The stored bytes, as GitHub's archives held them: Git for Windows' line endings do not apply.
        self.assertEqual((target / 'a.txt').read_bytes(), b'first\n')
        self.assertEqual((target / 'sub' / 'b.txt').read_bytes(), b'below\n')
        self.assertFalse((target / 'left-out.txt').exists(), 'export-ignore is honoured as in the archives')
        self.assertEqual((target / '.mmdhl-revision').read_text(), self.locked)
        self.assertFalse((self.vendor / '.dep.git').exists(), 'the scratch repository was left behind')
        self.assertEqual(self.bootstrap.fetch(('dep', ('owner/name', self.locked))), 'dep: ready')

    def test_a_commit_the_repository_does_not_have_is_refused(self):
        with self.assertRaises(RuntimeError):
            self.bootstrap.fetch(('dep', ('owner/name', 'f' * 40)))
        self.assertFalse((self.vendor / 'dep').exists(), 'a failed fetch left a vendor folder')
        self.assertFalse((self.vendor / '.dep.git').exists(), 'a failed fetch left its scratch repository')

    def test_only_full_commit_hashes_and_plain_repository_names(self):
        with self.assertRaisesRegex(RuntimeError, 'full commit hash'):
            self.bootstrap.fetch(('dep', ('owner/name', self.locked[:12])))
        with self.assertRaisesRegex(RuntimeError, 'owner/name'):
            self.bootstrap.fetch(('dep', ('owner/../name', self.locked)))
        self.assertFalse((self.vendor / 'dep').exists())

    def test_the_archive_download_is_gone(self):
        text = BOOTSTRAP.read_text(encoding='utf-8')
        self.assertNotIn('codeload.github.com', text)
        self.assertIn("'fetch'", text)


if __name__ == '__main__':
    unittest.main()
