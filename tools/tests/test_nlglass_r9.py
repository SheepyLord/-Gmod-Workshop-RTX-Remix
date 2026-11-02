"""R9 production Lua regressions: deterministic shards, zero-frame previews, blasts and clear UI."""
from pathlib import Path
import subprocess
import unittest
import json
from test_glass_map import luajit

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(luajit(), 'LuaJIT is not installed')
class R9GlassTests(unittest.TestCase):
    def test_qa_modes_compile_in_plain_luajit(self):
        for path in (ROOT / 'tools/qa/nlglass_qa').rglob('*.lua'):
            result = subprocess.run([luajit(), '-e', 'assert(loadfile(' + json.dumps(path.as_posix()) + '))'], cwd=ROOT,
                                    capture_output=True, encoding='utf-8', timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    def test_new_catalog_entries_are_actual_translations(self):
        import glass_i18n
        for language, table in glass_i18n.check().items():
            for key in ('Broken glass sounds', 'Clear broken glass', 'Clear broken glass for everyone'):
                self.assertNotIn('?', table[key], language + ': ' + key)
    def run_lua(self, harness, mode, debris=False):
        args = [luajit(), str(ROOT / 'tools/tests' / harness), str(ROOT / 'glass/addon/lua')]
        if debris:
            args.append(str(ROOT / 'tools/qa/glass_debris_jolt_probe.lua'))
        result = subprocess.run(args + [mode], cwd=ROOT, capture_output=True, encoding='utf-8', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_empty_blast_exact_radius_thrower_origin_rates_and_cleanup(self):
        self.run_lua('nlglass_engine_harness.lua', 'r9_blasts')

    def test_native_inputs_and_grenade_sounds_without_source_victims(self):
        self.run_lua('nlglass_engine_harness.lua', 'r9_native_signals')

    def test_local_everyone_permissions_panes_and_sound_reset(self):
        self.run_lua('nlglass_engine_harness.lua', 'r9_clear')

    def test_queued_geometry_draws_in_receipt_frame_and_cancels(self):
        self.run_lua('glass_debris_harness.lua', 'r9_preview', True)

    def test_native_sounds_are_distance_frame_second_and_piece_limited(self):
        self.run_lua('glass_debris_harness.lua', 'r9_sounds', True)

    def test_six_children_retain_expiry_and_original_fragment_budget(self):
        self.run_lua('glass_debris_harness.lua', 'r9_multi', True)

    def test_seeded_fracture_small_core_irregular_tempered_and_area(self):
        self.run_lua('nlglass_fracture_harness.lua', 'r9_shards')
