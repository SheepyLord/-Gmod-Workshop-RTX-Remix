"""R12-A launch gate and lock ownership: no actual game, registry or UI operations."""
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

    def test_activity_gate_requires_both_idle_input_and_background_field_game(self):
        q = self.qa
        for field, foreground, idle, blocked in [
            ([7], 8, 599, True), ([7], 7, 2000, True), ([7], 8, 600, False),
            ([], 8, 0, False), ([7, 9], 9, 2000, True)]:
            with self.subTest(field=field, foreground=foreground, idle=idle):
                user, kernel = Mock(), Mock()
                kernel.GetTickCount64.return_value = 3_000_000
                def last_input(pointer):
                    pointer._obj.dwTime = 3_000_000 - idle * 1000
                    return True
                def foreground_pid(_, pointer):
                    pointer._obj.value = foreground
                user.GetLastInputInfo.side_effect = last_input
                user.GetWindowThreadProcessId.side_effect = foreground_pid
                with patch.object(q.ctypes, 'windll', SimpleNamespace(user32=user, kernel32=kernel)), \
                     patch.object(q.poc, 'game_processes', return_value=field):
                    self.assertEqual(q.activity()['blocked'], blocked)

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
                         patch.object(q, 'LOCK', lock), patch.object(q, 'activity', return_value={'blocked': False}), \
                         patch.object(q, 'Probe', return_value=probe), \
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
