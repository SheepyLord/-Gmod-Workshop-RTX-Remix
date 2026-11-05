"""R19: the Character Motion Importer's server Lua under LuaJIT (reviews H4, L-01 to L-06, L-09, M8, M9 and
the Force Reset miss). See test_motion_server.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MotionServerTests(unittest.TestCase):
    def run_lua(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('motion_server_harness.lua')), scenario, str(ADDON)],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_only_yourself_or_an_admin_selects_and_poses_a_player(self):
        self.run_lua('select')

    def test_a_dance_or_build_on_another_player_is_refused_where_it_starts(self):
        self.run_lua('play')

    def test_force_reset_and_death_leave_another_freeze_alone(self):
        self.run_lua('reset')

    def test_stop_all_stops_your_own_dances(self):
        self.run_lua('stop_all')

    def test_a_leavers_dances_stop(self):
        self.run_lua('disconnect')

    def test_debug_frames_are_paced(self):
        self.run_lua('debug_rate')

    def test_cvars_come_back_after_a_map_change(self):
        self.run_lua('cvar_shutdown')

    def test_cvars_come_back_after_a_crash(self):
        self.run_lua('cvar_crash')

    def test_a_lua_cvar_comes_back_at_shutdown(self):
        self.run_lua('cvar_lua')

    def test_an_admins_cvar_change_is_kept(self):
        self.run_lua('cvar_admin')

    def test_built_animations_stay_within_a_byte_budget(self):
        self.run_lua('built_budget')

    def test_build_limits_per_player(self):
        self.run_lua('build_limits')

    def test_the_main_chunk_stays_below_luas_local_limit(self):
        # sv_commands.lua's main chunk is near Lua's 200 locals: LuaJIT refuses to load it past that.
        result = subprocess.run([LUAJIT, '-e', f"assert(loadfile([[{ADDON / 'sv_commands.lua'}]]))"],
                                cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
