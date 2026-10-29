"""Tests for tools/classic_defaults.py: which saved variables become first-run defaults, and the
generated Lua table."""
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools'))
import classic_defaults as cd  # noqa: E402

CLIENT = '"cfg"\n{\n\t"rtx_pseudoplayer"\t\t"0"\n\t"rtx_debug_hud"\t\t"1"\n\t"cl_drawhud"\t\t"1"\n' \
         '\t"mmd_vmd_npc_flashlight_rtx_radius"\t\t"30"\n\t"mmd_vmd_npc_flashlight_key"\t\t"0"\n' \
         '\t"r_forcehwskin"\t\t"0"\n\t"rtx_water_color"\t\t"0.62 0.89 0.97"\n}\n'
SERVER = '"cfg"\n{\n\t"rtx_pseudoplayer_unique_hashes"\t\t"0"\n\t"sv_gravity"\t\t"600"\n}\n'


class ClassicDefaultsTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(dir=REPO / 'out' / 'tmp' if (REPO / 'out' / 'tmp').is_dir() else None))
        cfg = self.root / 'ref' / 'garrysmod' / 'cfg'
        cfg.mkdir(parents=True)
        (cfg / 'client.vdf').write_text(CLIENT, encoding='utf-8')
        (cfg / 'server.vdf').write_text(SERVER, encoding='utf-8')

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_only_rtx_settings_without_debug_switches_or_keys(self):
        text, counts = cd.generate(self.root / 'ref', version=7)
        self.assertEqual(counts, {'client': 4, 'server': 1})
        self.assertIn('version = 7,', text)
        for kept in ('rtx_pseudoplayer = "0"', 'mmd_vmd_npc_flashlight_rtx_radius = "30"', 'r_forcehwskin = "0"',
                     'rtx_water_color = "0.62 0.89 0.97"', 'rtx_pseudoplayer_unique_hashes = "0"'):
            self.assertIn(kept, text)
        for dropped in ('rtx_debug_hud', 'cl_drawhud', 'mmd_vmd_npc_flashlight_key', 'sv_gravity'):
            self.assertNotIn(dropped, text)

    def test_check_mode_and_missing_reference(self):
        out = self.root / 'classic_defaults.lua'
        self.assertEqual(cd.main(['--reference', str(self.root / 'ref'), '--out', str(out)]), 0)
        self.assertEqual(cd.main(['--reference', str(self.root / 'ref'), '--out', str(out), '--check']), 0)
        out.write_text(out.read_text(encoding='utf-8').replace('"0"', '"1"', 1), encoding='utf-8')
        self.assertEqual(cd.main(['--reference', str(self.root / 'ref'), '--out', str(out), '--check']), 1)
        self.assertEqual(cd.main(['--reference', str(self.root / 'nowhere'), '--out', str(out)]), 1)


if __name__ == '__main__':
    unittest.main()
