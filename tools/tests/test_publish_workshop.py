"""Tests for publish_workshop.py: skip when nothing changed, upload when the content changed, the lock
and the git hooks. gmpublish is never run: the upload step is replaced by a recorder."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import publish_workshop as pub  # noqa: E402

SCRATCH = REPO / 'out' / 'tmp'


def write_package(folder: Path, manifest: dict, files: dict) -> Path:
    manifest = dict(manifest, files={})
    for rel, data in files.items():
        (folder / rel).parent.mkdir(parents=True, exist_ok=True)
        (folder / rel).write_bytes(data)
        manifest['files'][rel] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    (folder / 'native').mkdir(parents=True, exist_ok=True)
    (folder / 'native' / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
    return folder


class PublishTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-publish-workshop-', dir=SCRATCH))
        # Two valid packages, so the built nlctl (when present) accepts their combination.
        self.mods = write_package(self.root / 'mods', {'schema': 1, 'id': 'm', 'version': '1.0.0', 'kinds': ['root-files'],
                                                       'root_files': [{'path': 'rtx-remix/mods/m'}]},
                                  {'native/root/rtx-remix/mods/m/mod.usda': b'#usda 1.0\n'})
        self.module = write_package(self.root / 'module', {'schema': 1, 'id': 'b', 'version': '1.0.0', 'kinds': ['lua-binary-module'],
                                                           'root_files': [{'path': 'garrysmod/lua/bin/gmcl_b_win64.dll'}]},
                                    {'native/root/garrysmod/lua/bin/gmcl_b_win64.dll': b'MZ module'})
        self.config = {'item': '123', 'gmpublish': str(self.root / 'gmpublish.exe'),
                       'package': {'id': 'test-item', 'title': 'Test', 'type': 'tool', 'tags': ['build']},
                       'parts': [{'name': 'mods', 'package': str(self.mods)}, {'name': 'module', 'package': str(self.module)}]}
        self.saved_state, self.saved_upload = pub.STATE, pub.upload
        pub.STATE = self.root / 'state'
        self.uploads = []
        pub.upload = lambda config, gma, changes, log: self.uploads.append((Path(gma).name, changes)) or 'Success!'

    def tearDown(self):
        pub.STATE, pub.upload = self.saved_state, self.saved_upload
        shutil.rmtree(self.root, ignore_errors=True)

    def run_publish(self, **flags):
        args = argparse.Namespace(dry_run=False, force=False, allow_dirty=True, reason='test')
        for key, value in flags.items():
            setattr(args, key, value)
        return pub.publish(self.config, args, lambda text: None)

    def test_first_run_uploads_then_unchanged_inputs_stop_early(self):
        first = self.run_publish()
        self.assertEqual(first['result'], 'uploaded')
        self.assertEqual(len(self.uploads), 1)
        record = json.loads((pub.STATE / 'published.json').read_text(encoding='utf-8'))
        self.assertEqual((record['item'], record['digest'], record['version']), ('123', first['digest'], first['version']))
        self.assertIn(first['version'], self.uploads[0][1])  # the change notes name the version
        second = self.run_publish()
        self.assertEqual(second['result'], 'unchanged-inputs')
        self.assertEqual(len(self.uploads), 1)

    def test_changed_content_uploads_again(self):
        self.run_publish()
        write_package(self.mods, {'schema': 1, 'id': 'm', 'version': '1.0.0', 'kinds': ['root-files'],
                                  'root_files': [{'path': 'rtx-remix/mods/m'}]},
                      {'native/root/rtx-remix/mods/m/mod.usda': b'#usda 1.0\n# new\n'})
        again = self.run_publish()
        self.assertEqual(again['result'], 'uploaded')
        self.assertEqual(len(self.uploads), 2)

    def test_same_content_with_new_input_times_uploads_nothing(self):
        first = self.run_publish()
        target = self.mods / 'native/root/rtx-remix/mods/m/mod.usda'
        os.utime(target, ns=(target.stat().st_atime_ns, target.stat().st_mtime_ns + 10_000_000_000))
        again = self.run_publish()
        self.assertEqual(again['result'], 'unchanged-content')
        self.assertEqual(again['digest'], first['digest'])
        self.assertEqual(len(self.uploads), 1)
        self.assertEqual(self.run_publish()['result'], 'unchanged-inputs')  # the new fingerprint was kept

    def test_dry_run_and_force(self):
        dry = self.run_publish(dry_run=True)
        self.assertEqual(dry['result'], 'dry-run')
        self.assertEqual(self.uploads, [])
        self.assertFalse((pub.STATE / 'published.json').exists())
        self.run_publish()
        self.assertEqual(self.run_publish(force=True)['result'], 'uploaded')
        self.assertEqual(len(self.uploads), 2)

    def test_only_the_newest_archive_is_kept(self):
        self.run_publish()
        self.run_publish(force=True)
        self.assertEqual(len(list(pub.STATE.glob('test-item-*.gma'))), 1)

    def test_config_errors(self):
        path = self.root / 'bad.json'
        for bad, message in (({**self.config, 'item': 'abc'}, 'item id'),
                             ({**self.config, 'parts': [{'name': 'x'}]}, 'exactly one'),
                             ({**self.config, 'parts': [{'name': 'x', 'build': 'make_coffee'}]}, 'unknown builder')):
            path.write_text(json.dumps(bad), encoding='utf-8')
            with self.assertRaisesRegex(pub.PublishError, message):
                pub.load_config(path)

    def test_the_fingerprint_ignores_unpacked_inputs_and_the_working_folder(self):
        # A part read from out/inputs is derived from packages/ (fingerprinted by its git tree). Its
        # state there must not count: the first run after a merge fingerprinted it before unpacking
        # it, every later run after, and the two never matched (2026-10-30).
        config = {**self.config, 'parts': [*self.config['parts'],
                                           {'name': 'u', 'package': 'out/inputs/test-fingerprint/u.gma'}]}
        unpacked = REPO / 'out' / 'inputs' / 'test-fingerprint'
        shutil.rmtree(unpacked, ignore_errors=True)
        before = pub.fingerprint(config)
        unpacked.mkdir(parents=True)
        try:
            (unpacked / 'u.gma').write_bytes(b'GMAD')
            saved = os.getcwd()
            os.chdir(TOOLS)
            try:
                self.assertEqual(pub.fingerprint(config), before)
            finally:
                os.chdir(saved)
        finally:
            shutil.rmtree(unpacked, ignore_errors=True)
        self.assertTrue(pub.unpacked_input('out/inputs/x/y'))
        self.assertTrue(pub.unpacked_input(str(REPO / 'out' / 'inputs' / 'x')))
        self.assertFalse(pub.unpacked_input('out/packages/x.gma'))
        # An absolute path elsewhere still counts.
        other = self.root / 'other.gma'
        other.write_bytes(b'one')
        with_other = {**self.config, 'parts': [{'name': 'o', 'package': str(other)}]}
        first = pub.fingerprint(with_other)
        other.write_bytes(b'two!')
        self.assertNotEqual(pub.fingerprint(with_other), first)

    def test_one_publish_at_a_time_and_no_lock_left_behind(self):
        # R3-005: the lock is the system's, on an open handle. A second run cannot take it, not even
        # while the first is still setting it up, and it is free again when its holder ends.
        lock = self.root / 'publish.lock'
        lock.write_text('999999', encoding='ascii')  # what an earlier version left: no matter
        first = pub.acquire_lock(lock, 0)
        self.assertIsNotNone(first)
        self.assertIsNone(pub.acquire_lock(lock, 0))  # another handle, as another run has
        pub.release_lock(first)
        held = subprocess.run([sys.executable, '-c', 'import os, sys; sys.path.insert(0, sys.argv[1]); '
                               'import publish_workshop as p; from pathlib import Path; '
                               'assert p.acquire_lock(Path(sys.argv[2]), 0); os._exit(0)', str(TOOLS), str(lock)])
        self.assertEqual(held.returncode, 0)
        again = pub.acquire_lock(lock, 0)  # that process ended without letting go
        self.assertIsNotNone(again)
        pub.release_lock(again)
        self.assertTrue(lock.exists())


class HookTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.repo = Path(tempfile.mkdtemp(prefix='test-publish-hooks-', dir=SCRATCH))
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_install_refuse_foreign_and_uninstall(self):
        hooks = pub.hooks_folder(self.repo)
        written = pub.install_hooks(False, self.repo)
        self.assertEqual(sorted(Path(p).name for p in written), ['post-checkout', 'post-commit', 'post-merge', 'pre-push'])
        for name in ('post-checkout', 'post-commit', 'post-merge', 'pre-push'):
            text = (hooks / name).read_bytes()
            self.assertIn(pub.HOOK_MARKER.encode(), text)
            self.assertNotIn(b'\r\n', text)
            # Each runs Git LFS's own step, as the hooks `git lfs install` writes would (ADR 0033).
            self.assertIn(b'git lfs ' + name.encode(), text)
        self.assertIn(b'"main"', (hooks / 'post-commit').read_bytes())
        self.assertIn(b'refs/heads/main', (hooks / 'pre-push').read_bytes())
        for name in ('post-commit', 'post-merge', 'pre-push'):
            self.assertIn(b'--commit', (hooks / name).read_bytes(), name)  # R3-004
        pub.install_hooks(False, self.repo)  # ours: replaced quietly
        (hooks / 'pre-push').write_text('#!/bin/sh\necho mine\n', encoding='utf-8')
        with self.assertRaisesRegex(pub.PublishError, 'not ours'):
            pub.install_hooks(False, self.repo)
        removed = pub.uninstall_hooks(self.repo)
        self.assertEqual(sorted(Path(p).name for p in removed), ['post-checkout', 'post-commit', 'post-merge'])
        self.assertEqual((hooks / 'pre-push').read_text(encoding='utf-8'), '#!/bin/sh\necho mine\n')
        pub.install_hooks(True, self.repo)
        self.assertIn(pub.HOOK_MARKER, (hooks / 'pre-push').read_text(encoding='utf-8'))

    def test_a_push_publishes_from_the_checkout_of_the_pushed_commit(self):
        # R3-004: a push of main from a worktree on another branch builds main's checkout, not its own.
        def git(*args, cwd=self.repo):
            return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()
        for args in (('config', 'user.email', 't@example.invalid'), ('config', 'user.name', 't'),
                     ('commit', '-q', '--allow-empty', '-m', 'one'), ('branch', '-M', 'main')):
            git(*args)
        main_sha = git('rev-parse', 'HEAD')
        other = self.repo / 'out' / 'worktrees' / 'side'
        git('worktree', 'add', '-q', '-b', 'side', str(other))
        git('commit', '-q', '--allow-empty', '-m', 'two', cwd=other)
        side_sha = git('rev-parse', 'HEAD', cwd=other)
        same = lambda a, b: os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))
        self.assertTrue(same(pub.checkout_at(main_sha, other), self.repo))
        self.assertTrue(same(pub.checkout_at(side_sha, self.repo), other))
        git('commit', '-q', '--allow-empty', '-m', 'three', cwd=other)
        self.assertIsNone(pub.checkout_at(side_sha, self.repo))  # checked out nowhere now
        git('worktree', 'remove', '--force', str(other))

    def test_the_hooks_are_valid_sh(self):
        # The sh git runs hooks with: on Windows, Git for Windows' own, beside git.exe (not on the path
        # in PowerShell or cmd).
        sh = shutil.which('sh')
        git = shutil.which('git')
        if not sh and git:
            root = Path(git).resolve().parents[1]
            sh = next((str(p) for p in (root / 'bin' / 'sh.exe', root / 'usr' / 'bin' / 'sh.exe') if p.is_file()), None)
        if not sh:
            self.skipTest('no sh beside git or on the path')
        for name, text in pub.HOOKS:
            path = self.repo / (name + '.sh')
            path.write_bytes(text.encode('utf-8'))
            done = subprocess.run([sh, '-n', str(path)], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, f'{name}: {done.stderr}')

    def test_old_source_hooks_are_removed_and_only_ours(self):
        # ADR 0024 put hooks in the add-ons' repositories; since ADR 0033 the parts live in packages/,
        # and --uninstall-source-hooks takes them out again without touching anyone else's hooks.
        source = self.repo / '!add-on'
        subprocess.run(['git', 'init', '-q', str(source)], check=True)
        hooks = pub.hooks_folder(source)
        hooks.mkdir(parents=True, exist_ok=True)
        (hooks / 'post-commit').write_text(f'#!/bin/sh\n{pub.HOOK_MARKER}: a commit on main of this repository\n',
                                           encoding='utf-8')
        (hooks / 'post-merge').write_text('#!/bin/sh\necho mine\n', encoding='utf-8')
        self.assertEqual(pub.main(['--uninstall-source-hooks', str(source)]), 0)
        self.assertFalse((hooks / 'post-commit').exists())
        self.assertEqual((hooks / 'post-merge').read_text(encoding='utf-8'), '#!/bin/sh\necho mine\n')
        self.assertFalse(hasattr(pub, 'install_source_hooks'))

    def test_the_parts_a_config_unpacks(self):
        config = {'parts': [{'name': 'a', 'build': 'package_runtime', 'args': ['--runtime', 'out/inputs/runtime/files']},
                            {'name': 'b', 'package': 'out\\inputs\\emissives\\emissives.gma'},
                            {'name': 'c', 'package': str(self.repo / 'elsewhere.gma')},
                            {'name': 'd', 'build': 'package_content', 'args': ['--addon', 'out/inputs/runtime/x']}]}
        self.assertEqual(pub.input_parts(config), ['emissives', 'runtime'])

    def test_a_source_repositorys_hook_environment_does_not_redirect_git(self):
        # Git runs hooks with the hooked repository in GIT_DIR and GIT_INDEX_FILE. The script must
        # still read this repository: its shared state (where the log goes) and its own HEAD.
        source = self.repo / 'add-on'
        subprocess.run(['git', 'init', '-q', str(source)], check=True)
        env = dict(os.environ, GIT_DIR=str(source / '.git'), GIT_INDEX_FILE=str(source / '.git' / 'index'),
                   GIT_WORK_TREE=str(source), PYTHONPATH=str(TOOLS))
        probe = ('import json, os, publish_workshop as p; '
                 'print(json.dumps([str(p.STATE), p.git("rev-parse", "--show-toplevel"), '
                 '[n for n in p.GIT_LOCAL_ENV if n in os.environ]]))')
        done = subprocess.run([sys.executable, '-c', probe], cwd=source, env=env, capture_output=True, text=True,
                              encoding='utf-8', check=True)
        state, top, left = json.loads(done.stdout)
        self.assertEqual(Path(state), pub.STATE)
        self.assertEqual(Path(top).resolve(), REPO.resolve())
        self.assertEqual(left, [])


if __name__ == '__main__':
    unittest.main()
