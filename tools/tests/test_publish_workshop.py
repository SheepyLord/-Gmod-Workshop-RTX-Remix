"""Tests for publish_workshop.py: skip when nothing changed, upload when the content changed, the lock
and the git hooks. gmpublish is never run: the upload step is replaced by a recorder."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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


class PublisherPreflightTests(unittest.TestCase):
    """No Steam calls: synthetic reviewed bytes, and mocked API/process boundaries."""
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-publisher-preflight-', dir=SCRATCH))
        self.game = self.root / 'game'
        self.tool = self.game / 'bin' / 'win64' / 'gmpublish.exe'
        self.tool.parent.mkdir(parents=True)
        data = bytearray(pub.COMPAT_PREFLIGHT_OFFSET + len(pub.COMPAT_PREFLIGHT_BYTES) + 32)
        data[:2] = b'MZ'
        data[pub.COMPAT_PREFLIGHT_OFFSET:pub.COMPAT_PREFLIGHT_OFFSET + len(pub.COMPAT_PREFLIGHT_BYTES)] = pub.COMPAT_PREFLIGHT_BYTES
        self.original = bytes(data)
        self.tool.write_bytes(self.original)
        self.api = self.tool.with_name('steam_api64.dll')
        self.dependency = b'MZ synthetic Steam API dependency'
        self.api.write_bytes(self.dependency)
        self.config = {'item': '123', 'gmpublish': str(self.tool)}
        self.gma = self.root / 'package.gma'
        self.log = []
        self.patches = [mock.patch.object(pub, 'REPO', self.root),
                        mock.patch.object(pub, 'COMPAT_PUBLISHER_SHA256', hashlib.sha256(self.original).hexdigest()),
                        mock.patch.object(pub, 'COMPAT_STEAM_API_SHA256', hashlib.sha256(self.dependency).hexdigest()),
                        mock.patch.object(pub, 'steam_running', return_value=True)]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in reversed(self.patches):
            patch.stop()
        shutil.rmtree(self.root)

    @staticmethod
    def done(output, returncode=0):
        return subprocess.CompletedProcess([], returncode, stdout=output, stderr='')

    def test_success_uses_original_publisher_without_probe(self):
        with mock.patch.object(pub.subprocess, 'run', return_value=self.done('Success!')) as run, \
                mock.patch.object(pub, 'steam_api_ready') as probe:
            self.assertEqual(pub.upload(self.config, self.gma, 'notes', self.log.append), 'Success!')
        probe.assert_not_called()
        self.assertEqual(run.call_args.args[0][0], str(self.tool))

    def test_exact_preflight_failure_retries_only_reviewed_copy(self):
        commands = []

        def run(command, **kwargs):
            commands.append(list(command))
            self.assertEqual(kwargs['cwd'], self.game)
            if len(commands) == 1:
                return self.done('Publisher\r\nError:\r\n\r\n' + pub.COMPAT_PREFLIGHT_ERROR.replace('\n', '\r\n'))
            copy = Path(command[0])
            self.assertTrue(copy.is_relative_to(self.root / 'out' / 'tmp'))
            patched = copy.read_bytes()
            changed = [i for i, pair in enumerate(zip(self.original, patched)) if pair[0] != pair[1]]
            self.assertEqual(changed, [pub.COMPAT_BRANCH_OFFSET])
            self.assertEqual(self.original[pub.COMPAT_BRANCH_OFFSET:pub.COMPAT_BRANCH_OFFSET + 2], b'\x75\x0c')
            self.assertEqual(patched[pub.COMPAT_BRANCH_OFFSET:pub.COMPAT_BRANCH_OFFSET + 2], b'\xeb\x0c')
            self.assertEqual(copy.with_name('steam_api64.dll').read_bytes(), self.dependency)
            return self.done('Success!')

        with mock.patch.object(pub.subprocess, 'run', side_effect=run), \
                mock.patch.object(pub, 'steam_api_ready', return_value=True) as probe:
            self.assertEqual(pub.upload(self.config, self.gma, 'notes', self.log.append), 'Success!')
        self.assertEqual(commands[0][1:], commands[1][1:])  # same item, archive and notes
        probe.assert_called_once()
        self.assertEqual(probe.call_args.args[1], self.game)
        self.assertEqual(self.tool.read_bytes(), self.original)
        self.assertEqual(self.api.read_bytes(), self.dependency)
        self.assertFalse(Path(commands[1][0]).exists())  # isolated copy cleaned after child exits

    def test_later_api_login_and_owner_failures_do_not_retry(self):
        for text in ("Couldn't initialize Steam!\nMake sure it is running and is not in compatibility/administrator mode!\nerror",
                     'You must own this item', 'Not logged in', 'Access denied'):
            with self.subTest(text=text), \
                    mock.patch.object(pub.subprocess, 'run', return_value=self.done(text)) as run, \
                    mock.patch.object(pub, 'steam_api_ready') as probe:
                with self.assertRaises(pub.PublishError):
                    pub.upload(self.config, self.gma, 'notes', self.log.append)
                self.assertEqual(run.call_count, 1)
                probe.assert_not_called()

    def test_unknown_binary_dependency_and_changed_code_fail_closed(self):
        folder = self.root / 'isolated'
        folder.mkdir()
        cases = ('publisher', 'dependency', 'code')
        for case in cases:
            with self.subTest(case=case), mock.patch.object(pub, 'steam_api_ready') as probe:
                self.tool.write_bytes(self.original)
                self.api.write_bytes(self.dependency)
                patch = mock.patch.object(pub, 'COMPAT_PREFLIGHT_BYTES', b'changed') if case == 'code' else mock.patch.object(pub, 'LOCK_WAIT', pub.LOCK_WAIT)
                if case == 'publisher': self.tool.write_bytes(self.original + b'new build')
                if case == 'dependency': self.api.write_bytes(b'MZ different dependency')
                with patch, self.assertRaisesRegex(pub.PublishError, 'fallback refused'):
                    pub.compatibility_publisher(self.tool, self.game, folder)
                probe.assert_not_called()
                self.assertFalse((folder / 'gmpublish.exe').exists())

    def test_actual_api_initialization_must_succeed(self):
        with mock.patch.object(pub.subprocess, 'run', return_value=self.done(pub.COMPAT_PREFLIGHT_ERROR)) as run, \
                mock.patch.object(pub, 'steam_api_ready', return_value=False):
            with self.assertRaisesRegex(pub.PublishError, 'initialization failed'):
                pub.upload(self.config, self.gma, 'notes', self.log.append)
            self.assertEqual(run.call_count, 1)
        self.assertEqual(self.tool.read_bytes(), self.original)

    def test_a_copy_still_held_after_a_good_upload_is_not_an_error(self):
        # Review R4: removing the temporary folder failed while the copy was still held (Windows, a
        # scanner), the error escaped upload() after a successful upload, published.json was not
        # written, and the next hook run uploaded again.
        handles = []

        def run(command, **kwargs):
            if Path(command[0]) == self.tool:
                return self.done(pub.COMPAT_PREFLIGHT_ERROR)
            handles.append(open(command[0], 'rb'))  # still open when the retry is over
            return self.done('Success!')

        try:
            with mock.patch.object(pub.subprocess, 'run', side_effect=run), \
                    mock.patch.object(pub, 'steam_api_ready', return_value=True):
                self.assertEqual(pub.upload(self.config, self.gma, 'notes', self.log.append), 'Success!')
            self.assertEqual(len(handles), 1)
            self.assertTrue(any('could not be removed' in line for line in self.log), self.log)
        finally:
            for handle in handles:
                handle.close()

    def test_failed_compatibility_upload_is_not_reported_as_success(self):
        with mock.patch.object(pub.subprocess, 'run', side_effect=[self.done(pub.COMPAT_PREFLIGHT_ERROR),
                                                                 self.done('Access denied')]) as run, \
                mock.patch.object(pub, 'steam_api_ready', return_value=True):
            with self.assertRaises(pub.PublishError):
                pub.upload(self.config, self.gma, 'notes', self.log.append)
            self.assertEqual(run.call_count, 2)

    def test_probe_is_process_local_bounded_and_hides_raw_diagnostics(self):
        with mock.patch.object(pub.subprocess, 'run', return_value=self.done('private diagnostics')) as run:
            self.assertTrue(pub.steam_api_ready(self.api, self.game))
        self.assertEqual(run.call_args.kwargs['env']['SteamAppId'], '4000')
        self.assertEqual(run.call_args.kwargs['cwd'], self.game)
        self.assertEqual(run.call_args.kwargs['timeout'], 30)
        self.assertTrue(run.call_args.kwargs['capture_output'])
        for outcome in (self.done('bad', 1), subprocess.TimeoutExpired([], 30), OSError('unavailable')):
            with self.subTest(outcome=outcome), mock.patch.object(pub.subprocess, 'run') as run:
                if isinstance(outcome, BaseException): run.side_effect = outcome
                else: run.return_value = outcome
                self.assertFalse(pub.steam_api_ready(self.api, self.game))


class BackgroundLaunchTests(unittest.TestCase):
    def test_the_background_run_shares_one_hidden_console(self):
        """Children of a console-less run each opened a window (a Windows Terminal tab that stayed)."""
        SCRATCH.mkdir(parents=True, exist_ok=True)
        state = Path(tempfile.mkdtemp(prefix='test-publish-background-', dir=SCRATCH))
        saved = pub.STATE
        pub.STATE = state
        try:
            with mock.patch.object(pub.subprocess, 'Popen') as popen, \
                    mock.patch('sys.stdout', new_callable=lambda: open(os.devnull, 'w')):
                self.assertEqual(pub.main(['--background', '--reason', 'test']), 0)
        finally:
            pub.STATE = saved
            shutil.rmtree(state, ignore_errors=True)
        flags = popen.call_args.kwargs['creationflags']
        self.assertTrue(flags & 0x08000000)       # CREATE_NO_WINDOW
        self.assertFalse(flags & 0x00000008)      # never DETACHED_PROCESS
        self.assertNotIn('--background', popen.call_args.args[0])


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


class FromCiTests(unittest.TestCase):
    """--from-ci (ADR 0106): the run of the pushed commit, its artifacts checked against its report. gh and
    gmpublish are replaced by recorders."""
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='test-publish-ci-', dir=SCRATCH))
        self.config = {'item': '123', 'gmpublish': str(self.root / 'gmpublish.exe'), 'package': {'id': 'p'}, 'parts': []}
        self.gma_bytes = b'GMAD fake package'
        self.report = {'gma': {'name': 'p-1.gma', 'bytes': len(self.gma_bytes),
                               'sha256': hashlib.sha256(self.gma_bytes).hexdigest()},
                       'binaries': 54, 'compiled': 9, 'fetched': 41, 'from_packages': 4}
        self.runs = [{'id': 77, 'run_number': 5, 'status': 'completed', 'conclusion': 'success',
                      'html_url': 'https://github.com/o/r/actions/runs/77'}]
        self.calls, self.uploads = [], []
        self.patches = [mock.patch.object(pub, 'STATE', self.root / 'state'),
                        mock.patch.object(pub, 'gh', side_effect=self.fake_gh),
                        mock.patch.object(pub, 'upload', side_effect=lambda c, gma, changes, log:
                                          self.uploads.append((Path(gma).read_bytes(), changes)) or 'Success!')]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in reversed(self.patches):
            patch.stop()
        shutil.rmtree(self.root, ignore_errors=True)

    def fake_gh(self, *args):
        self.calls.append(args)
        if args[0] == 'api':
            return json.dumps({'workflow_runs': self.runs})
        dest = Path(args[args.index('-D') + 1])
        dest.mkdir(parents=True, exist_ok=True)
        if args[args.index('-n') + 1] == 'rtx-package-report':
            (dest / 'package-report.json').write_text(json.dumps(self.report), encoding='utf-8')
            (dest / 'package-summary.json').write_text(json.dumps({'version': '1', 'digest': 'd1'}), encoding='utf-8')
        else:
            (dest / 'p-1.gma').write_bytes(self.gma_bytes)
        return ''

    def publish(self, **flags):
        args = argparse.Namespace(**{'dry_run': False, 'force': False, 'reason': 'push abc', 'commit': 'HEAD', **flags})
        return pub.publish_from_ci(self.config, args, lambda text: None)

    def test_the_runs_package_is_checked_and_uploaded_once(self):
        result = self.publish()
        self.assertEqual(result['result'], 'uploaded')
        self.assertEqual(len(self.uploads), 1)
        data, changes = self.uploads[0]
        self.assertEqual(data, self.gma_bytes)
        self.assertIn('https://github.com/o/r/actions/runs/77', changes)
        self.assertIn(self.report['gma']['sha256'], changes)
        record = json.loads((pub.STATE / 'published.json').read_text(encoding='utf-8'))
        self.assertEqual((record['source'], record['run_id'], record['gma_sha256']),
                         ('github', 77, self.report['gma']['sha256']))
        self.assertEqual(self.publish()['result'], 'unchanged')  # the same run again
        self.assertEqual(len(self.uploads), 1)

    def test_a_package_that_does_not_match_its_report_is_not_uploaded(self):
        self.report['gma']['sha256'] = '0' * 64
        with self.assertRaisesRegex(pub.PublishError, 'not the package its report describes'):
            self.publish()
        self.assertEqual(self.uploads, [])
        self.assertFalse((pub.STATE / 'published.json').exists())

    def test_a_failed_or_cancelled_run_uploads_nothing(self):
        self.runs[0]['conclusion'] = 'failure'
        with self.assertRaisesRegex(pub.PublishError, 'ended failure'):
            self.publish()
        self.runs[0]['conclusion'] = 'cancelled'
        self.assertEqual(self.publish()['result'], 'cancelled')
        self.assertEqual(self.uploads, [])

    def test_a_commit_without_a_package_run_uploads_nothing(self):
        self.runs = []
        now = [0.0]
        run = pub.wait_for_run('abc', lambda text: None, sleep=lambda s: now.__setitem__(0, now[0] + s),
                               clock=lambda: now[0])
        self.assertIsNone(run)
        self.assertGreater(now[0], pub.RUN_APPEARS)
        with mock.patch.object(pub, 'wait_for_run', return_value=None):
            self.assertEqual(self.publish()['result'], 'no-run')
        self.assertEqual(self.uploads, [])

    def test_a_running_build_is_waited_for(self):
        states = [{**self.runs[0], 'status': 'queued', 'conclusion': None},
                  {**self.runs[0], 'status': 'in_progress', 'conclusion': None}, self.runs[0]]
        with mock.patch.object(pub, 'package_runs', side_effect=lambda sha: [states.pop(0)]):
            run = pub.wait_for_run('abc', lambda text: None, sleep=lambda s: None)
        self.assertEqual((run['status'], run['conclusion']), ('completed', 'success'))

    def test_dry_run_downloads_and_checks_but_uploads_nothing(self):
        result = self.publish(dry_run=True)
        self.assertEqual(result['result'], 'dry-run')
        self.assertEqual(self.uploads, [])
        self.assertTrue(any(call[:2] == ('run', 'download') for call in self.calls))


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
            # ADR 0108: during development the hooks publish a build made here; GitHub builds only releases.
            self.assertNotIn(b'--from-ci', (hooks / name).read_bytes(), name)
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

    def test_every_repository_file_a_packager_reads_is_a_publish_input(self):
        # Review R4: tools/companion_i18n.py (it builds the shipped i18n_data.lua), LICENSE and
        # third_party/gmod/LICENSE (shipped as notices) were not inputs, so a change to them did not
        # change the fingerprint and was never published; nor was a change to .gitattributes, which
        # sets the bytes a checkout gives /LICENSE and the guard (2026-10-31).
        def covered(rel):
            return any(rel == p or rel.startswith(p + '/') for p in pub.REPO_INPUTS)
        read = set()
        for builder in [*pub.BUILDERS.values(), 'tools/package_workshop.py', 'tools/companion_i18n.py']:
            text = (REPO / builder).read_text(encoding='utf-8')
            for module in re.findall(r'^(?:import|from)\s+(\w+)', text, re.M):
                if (TOOLS / f'{module}.py').is_file():
                    read.add(f'tools/{module}.py')
            for parts in re.findall(r"os\.path\.join\(REPO((?:,\s*'[^']+')+)", text):
                read.add('/'.join(re.findall(r"'([^']+)'", parts)))
            for parts in re.findall(r"REPO((?:\s*/\s*'[^']+')+)", text):
                read.add('/'.join(re.findall(r"'([^']+)'", parts)))
        files = sorted(rel for rel in read if not rel.startswith('out/') and (REPO / rel).is_file())
        for rel in ('tools/companion_i18n.py', 'LICENSE', 'third_party/gmod/LICENSE'):
            self.assertIn(rel, files)  # what the review found missing is found by this scan
        self.assertEqual([rel for rel in files if not covered(rel)], [])
        self.assertIn('.gitattributes', pub.REPO_INPUTS)

    def test_the_package_workflow_starts_only_by_hand(self):
        # ADR 0108: the package workflow (the large .gma and every native binary) runs only when a person
        # starts it, for a release; no push, pull request, tag or schedule starts it.
        text = (REPO / '.github' / 'workflows' / 'package.yml').read_text(encoding='utf-8')
        trigger = text.split('\non:', 1)[1].split('\n\n', 1)[0]
        self.assertEqual([line.strip() for line in trigger.strip().splitlines()], ['workflow_dispatch:'])

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
