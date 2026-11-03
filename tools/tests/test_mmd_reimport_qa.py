"""R12-A field-game ending and lock ownership: no actual game, registry or UI operations."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

REPO = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == 'nt', 'Windows QA driver')
class ReimportQATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('mmd_reimport_qa', REPO / 'tools/qa/mmd_reimport_session.py')
        cls.qa = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.qa)

    def test_a_running_field_game_is_ended_not_waited_for(self):
        # The field game is a test session (the user, 2026-11-02): close it, force it after 60 s.
        q = self.qa
        for case, closes in [('none', None), ('closes', True), ('stuck', False)]:
            with self.subTest(case=case):
                state = {'running': [] if closes is None else [7]}
                def terminate(left):
                    state['running'] = []
                    return sorted(left)
                def run(command, **_):
                    if closes:
                        state['running'] = []
                clock = SimpleNamespace(monotonic=Mock(side_effect=[0, 61] if closes is False else [0, 1]), sleep=Mock())
                with patch.object(q.poc, 'game_processes', side_effect=lambda root: list(state['running'])), \
                     patch.object(q.poc, 'process_created', return_value=123), \
                     patch.object(q.poc, 'terminate', side_effect=terminate) as ended, \
                     patch.object(q.subprocess, 'run', side_effect=run) as close, \
                     patch.object(q, 'time', clock):
                    record = q.end_field_games()
                self.assertEqual(record['field_pids'], [] if closes is None else [7])
                self.assertEqual(record['forced'], [7] if closes is False else [])
                self.assertEqual(record['remaining'], [])
                self.assertEqual(close.call_count, 0 if closes is None else 1)
                if closes is False:
                    ended.assert_called_once_with({7: 123})

    def test_lock_refusal_release_and_failed_restore(self):
        q = self.qa
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mmd-reimport-guard-', dir=scratch) as folder:
            root = Path(folder)
            source, lock = root / 'copied.pmx', root / 'poc.lock'
            source.write_bytes(b'not parsed: game operations are mocked')
            for mode in ('foreign', 'success', 'restore_failure', 'changed_owner'):
                with self.subTest(mode=mode):
                    if lock.exists():
                        lock.unlink()  # generated fixture only
                    out = root / mode
                    probe = Mock(restored=mode != 'restore_failure')
                    if mode == 'foreign':
                        lock.write_text('{"task":"R12-B"}', encoding='utf8')
                    elif mode == 'restore_failure':
                        probe.run.side_effect = RuntimeError('synthetic restoration failure')
                    elif mode == 'changed_owner':
                        probe.run.side_effect = lambda: lock.write_text('{"task":"R12-B","pid":0}', encoding='utf8')
                    with patch.object(sys, 'argv', ['probe', '--out', str(out), '--source', str(source)]), \
                         patch.object(q, 'LOCK', lock), patch.object(q, 'Probe', return_value=probe), \
                         patch.object(q.poc, 'game_processes', return_value=[]), patch.object(q.ctypes, 'windll', Mock()):
                        if mode == 'restore_failure':
                            with self.assertRaisesRegex(RuntimeError, 'restoration failure'):
                                q.main()
                        else:
                            self.assertEqual(q.main(), 3 if mode == 'foreign' else 0)
                    self.assertEqual(lock.exists(), mode != 'success')
                    if mode in ('foreign', 'changed_owner'):
                        self.assertEqual(json.loads(lock.read_text())['task'], 'R12-B')
                    if mode == 'foreign':
                        probe.run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
