"""poc_parity.py's path checks (R1-016) on two synthetic installs under out/tmp: every path a user names
and every path restore reads back from parity.json must be a plain relative path that resolves below
the PoC root. game_running is mocked; no real install is read or written."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import poc_parity as pp

REPO = Path(__file__).resolve().parents[2]
SCRATCH = REPO / 'out' / 'tmp'  # AGENTS.md rule 9

try:
    from _winapi import CreateJunction  # CPython on Windows; a junction needs no privilege
except ImportError:
    CreateJunction = None


class PathRuleTests(unittest.TestCase):
    def test_plain_relative_paths_pass(self):
        for rel in ('garrysmod/lua/bin/gmcl_x_win64.dll', 'garrysmod\\data\\advmat', 'garrysmod/saves/a b 04-08-30.gms',
                    'rtx-remix/mods/~gmod_topbr', '.hidden/x'):
            self.assertEqual(pp.path_problem(rel), '', rel)

    def test_everything_else_is_refused(self):
        for rel in ('', None, '..', '../outside.bin', 'garrysmod/../../outside.bin', 'a//b', 'a/./b', 'a/', '/abs',
                    '\\abs', 'C:/x', 'C:x', '\\\\server\\share\\x', '\\\\?\\C:\\x', 'a/b.', 'a/b ', 'x.txt:stream'):
            self.assertNotEqual(pp.path_problem(rel), '', rel)


class PrepareRestoreTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        folder = tempfile.TemporaryDirectory(dir=SCRATCH, prefix='poc-parity-')
        self.addCleanup(folder.cleanup)
        base = Path(folder.name)
        self.reference, self.root, self.evidence = base / 'reference' / 'install', base / 'poc' / 'install', base / 'evidence'
        self.outside = self.root.parent / 'outside.bin'  # beside the PoC root: never to be written
        for path, data in {self.reference.parent / 'outside.bin': b'REFERENCE BYTES',
                           self.reference / 'garrysmod/lua/bin/gmcl_x_win64.dll': b'MZ module',
                           self.reference / 'garrysmod/saves/my save.gms': b'save',
                           self.root / 'garrysmod/cfg/config_default.cfg': b'vanilla'}.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def args(self, **changes):
        values = dict(reference=str(self.reference), root=str(self.root), evidence=str(self.evidence), files=False,
                      mods=False, addons=False, data=[], native=[], save=None, map=None, copy_linked_mods=False,
                      copy_linked_addons=False, exclude_mod=[])
        values.update(changes)
        return SimpleNamespace(**values)

    def prepare(self, **changes):
        # A Workshop folder that does not exist: no test may open the real one.
        with mock.patch.object(pp, 'game_running', return_value=False), \
                mock.patch.object(pp, 'WORKSHOP', self.root.parent / 'no-workshop'):
            return pp.prepare(self.args(**changes))

    def restore(self):
        with mock.patch.object(pp, 'game_running', return_value=False):
            return pp.restore(SimpleNamespace(evidence=str(self.evidence)))

    def test_escaping_paths_are_refused_before_anything_is_written(self):
        # R1-016's repro is the first case: the reference's neighbour copied beside the PoC.
        for changes in (dict(native=['../outside.bin']), dict(native=['garrysmod/../../outside.bin']),
                        dict(native=[str(self.reference.parent / 'outside.bin')]), dict(native=['C:outside.bin']),
                        dict(native=['garrysmod/lua/bin/gmcl_x_win64.dll', '../outside.bin']),
                        dict(data=['..']), dict(data=['../../poc']), dict(save='../../outside'),
                        dict(map='944959992:../../outside'), dict(map='../x:gm_x')):
            with self.subTest(changes=changes), self.assertRaises(pp.Failure):
                self.prepare(**changes)
            self.assertFalse(self.outside.exists())
            self.assertFalse((self.evidence / 'parity.json').exists())
            self.assertEqual(sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob('*')),
                             ['garrysmod', 'garrysmod/cfg', 'garrysmod/cfg/config_default.cfg'])

    @unittest.skipUnless(CreateJunction, 'directory junctions need Windows')
    def test_a_junction_out_of_the_poc_is_refused(self):
        elsewhere = self.root.parent / 'elsewhere'
        elsewhere.mkdir()
        junction = self.root / 'garrysmod' / 'lua'  # the PoC's garrysmod/lua leads out of the PoC
        CreateJunction(str(elsewhere), str(junction))
        try:
            with self.assertRaises(pp.Failure) as caught:
                self.prepare(native=['garrysmod/lua/bin/gmcl_x_win64.dll'])
            self.assertIn('not below', str(caught.exception))
            self.assertEqual(list(elsewhere.iterdir()), [])
        finally:
            os.rmdir(junction)  # the junction only, never what it points to

    def test_prepare_and_restore_round_trip(self):
        state = self.prepare(native=['garrysmod/lua/bin/gmcl_x_win64.dll'], save='my save')
        self.assertEqual(state['created'], ['garrysmod/lua/bin/gmcl_x_win64.dll', 'garrysmod/saves/my save.gms'])
        self.assertEqual((self.root / 'garrysmod/lua/bin/gmcl_x_win64.dll').read_bytes(), b'MZ module')
        self.assertEqual(self.restore(), {'restored': 2})
        self.assertFalse((self.root / 'garrysmod/lua/bin/gmcl_x_win64.dll').exists())
        self.assertFalse((self.root / 'garrysmod/saves/my save.gms').exists())
        self.assertTrue((self.evidence / 'parity-restored.json').exists())

    def write_state(self, created, replaced=()):
        self.evidence.mkdir(parents=True, exist_ok=True)
        (self.evidence / 'parity.json').write_text(json.dumps(
            {'reference': str(self.reference), 'root': str(self.root), 'created': created, 'replaced': list(replaced)}),
            encoding='utf-8')

    def test_restore_checks_every_recorded_path_before_touching_anything(self):
        mine = self.root / 'garrysmod' / 'mine.txt'
        mine.write_bytes(b'created by prepare')
        self.outside.write_bytes(b'NOT THE POC')
        stray = self.root.parent / 'stray.cfg'
        stray.write_bytes(b'a backup from nowhere')
        for created, replaced in ((['garrysmod/mine.txt', '../outside.bin'], ()),
                                  (['garrysmod/mine.txt', str(self.outside)], ()),
                                  (['garrysmod/mine.txt'], [{'path': '../outside.bin', 'backup': None}]),
                                  (['garrysmod/mine.txt'], [{'path': 'garrysmod/cfg/config_default.cfg', 'backup': str(stray)}])):
            with self.subTest(created=created, replaced=replaced):
                self.write_state(created, replaced)
                with self.assertRaises(pp.Failure):
                    self.restore()
                self.assertEqual(mine.read_bytes(), b'created by prepare')
                self.assertEqual(self.outside.read_bytes(), b'NOT THE POC')
                self.assertEqual((self.root / 'garrysmod/cfg/config_default.cfg').read_bytes(), b'vanilla')
                self.assertTrue((self.evidence / 'parity.json').exists())


if __name__ == '__main__':
    unittest.main()
