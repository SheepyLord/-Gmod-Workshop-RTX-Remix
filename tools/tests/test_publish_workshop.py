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

    def test_the_lock_takes_over_a_dead_owner_and_waits_for_a_live_one(self):
        lock = self.root / 'publish.lock'
        lock.write_text('999999', encoding='ascii')  # no such process
        self.assertTrue(pub.acquire_lock(lock, 0))
        self.assertEqual(lock.read_text(encoding='ascii'), str(os.getpid()))
        self.assertFalse(pub.acquire_lock(lock, 0))  # this process holds it


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
        self.assertEqual(sorted(Path(p).name for p in written), ['post-commit', 'post-merge', 'pre-push'])
        for name in ('post-commit', 'post-merge', 'pre-push'):
            text = (hooks / name).read_bytes()
            self.assertIn(pub.HOOK_MARKER.encode(), text)
            self.assertNotIn(b'\r\n', text)
        self.assertIn(b'"main"', (hooks / 'post-commit').read_bytes())
        self.assertIn(b'refs/heads/main', (hooks / 'pre-push').read_bytes())
        pub.install_hooks(False, self.repo)  # ours: replaced quietly
        (hooks / 'pre-push').write_text('#!/bin/sh\necho mine\n', encoding='utf-8')
        with self.assertRaisesRegex(pub.PublishError, 'not ours'):
            pub.install_hooks(False, self.repo)
        removed = pub.uninstall_hooks(self.repo)
        self.assertEqual(sorted(Path(p).name for p in removed), ['post-commit', 'post-merge'])
        self.assertEqual((hooks / 'pre-push').read_text(encoding='utf-8'), '#!/bin/sh\necho mine\n')
        pub.install_hooks(True, self.repo)
        self.assertIn(pub.HOOK_MARKER, (hooks / 'pre-push').read_text(encoding='utf-8'))

    def test_source_hooks_call_this_checkouts_script_by_absolute_path(self):
        source = self.repo / '!add-on'
        subprocess.run(['git', 'init', '-q', str(source)], check=True)
        hooks = pub.hooks_folder(source)
        written = pub.install_source_hooks(source, False)
        self.assertEqual(sorted(Path(p).name for p in written), ['post-commit', 'post-merge'])
        script = (pub.main_checkout() / 'tools' / 'publish_workshop.py').as_posix()
        for name in ('post-commit', 'post-merge'):
            text = (hooks / name).read_bytes()
            self.assertIn(pub.HOOK_MARKER.encode(), text)
            self.assertIn(f'python "{script}" --background'.encode(), text)
            self.assertIn(b'"!add-on ', text)  # the add-on's name in the change notes
            self.assertIn(b'"main"', text)
            self.assertNotIn(b'\r\n', text)
        self.assertFalse((hooks / 'pre-push').exists())
        (hooks / 'post-merge').write_text('#!/bin/sh\necho mine\n', encoding='utf-8')
        before = (hooks / 'post-commit').read_bytes()
        with self.assertRaisesRegex(pub.PublishError, 'not ours'):
            pub.install_source_hooks(source, False)
        self.assertEqual((hooks / 'post-commit').read_bytes(), before)  # nothing written when one is foreign
        removed = pub.uninstall_hooks(source, pub.source_hooks(source, Path('x')))
        self.assertEqual([Path(p).name for p in removed], ['post-commit'])
        self.assertEqual((hooks / 'post-merge').read_text(encoding='utf-8'), '#!/bin/sh\necho mine\n')
        # A repository whose builds reach the classic install from feature branches: every branch.
        (hooks / 'post-merge').unlink()
        pub.install_source_hooks(source, False, any_branch=True)
        text = (hooks / 'post-commit').read_text(encoding='utf-8')
        self.assertNotIn('"main"', text)
        self.assertIn('any branch', text)


if __name__ == '__main__':
    unittest.main()
