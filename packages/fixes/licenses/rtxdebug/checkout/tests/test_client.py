"""Target selection and response binding without controlling a game window."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('rtxdebug_client', Path(__file__).resolve().parents[1] / 'tools/rtxdebug_client.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class ClientSelectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.roots = [Path(self.temp.name) / name for name in ('first', 'second')]
        for root in self.roots:
            (root / 'garrysmod').mkdir(parents=True)
        self.candidates = [(11, self.roots[0] / 'bin/win64/gmod.exe', 100),
                           (22, self.roots[1] / 'bin/win64/gmod.exe', 200)]

    def test_ambiguous_clients_are_not_chosen_arbitrarily(self):
        with self.assertRaisesRegex(RuntimeError, 'Multiple'):
            client._select_game(self.candidates)

    def test_explicit_pid_and_root(self):
        self.assertEqual(client._select_game(self.candidates, pid=200), (22, self.roots[1]))
        self.assertEqual(client._select_game(self.candidates, root=self.roots[0]), (11, self.roots[0]))

    def test_conflicting_filters_refuse_target(self):
        with self.assertRaisesRegex(RuntimeError, 'No Garry'):
            client._select_game(self.candidates, pid=200, root=self.roots[0])

    def test_one_process_with_duplicate_windows_is_one_target(self):
        one = self.candidates[:1]
        self.assertEqual(client._select_game(one + one), (11, self.roots[0]))

    def test_response_identity(self):
        result = {'id': 'request', 'process_id': 100, 'ok': True}
        self.assertEqual(client._decode_response(json.dumps(result), 'request', 100), result)
        for bad in ({**result, 'process_id': 200}, {**result, 'id': 'other'}, [], {'id': 'request'}):
            with self.subTest(value=bad), self.assertRaises(RuntimeError):
                client._decode_response(json.dumps(bad), 'request', 100)


if __name__ == '__main__':
    unittest.main()
