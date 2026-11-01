"""Offline R7-C scene, bullet and debris integration regressions; never starts a game."""
from pathlib import Path
import subprocess
import unittest

from test_glass_map import luajit

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'glass/addon/lua'


@unittest.skipUnless(luajit(), 'LuaJIT is not installed')
class GlassInteractionTests(unittest.TestCase):
    def run_case(self, case):
        result = subprocess.run([luajit(), str(REPO / 'tools/tests/glass_interaction_harness.lua'),
                                 str(LUA), case], cwd=REPO, capture_output=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('interaction ' + case + ' OK', result.stdout)

    def test_living_hulls_ragdoll_bones_prop_shapes_and_physics_replacement(self):
        self.run_case('scene_kinds')

    def test_scene_candidate_body_shape_region_and_cleanup_bounds(self):
        self.run_case('scene_caps')

    def test_remote_ragdoll_hitboxes_oriented_boxes_and_bad_convex_fallback(self):
        self.run_case('scene_fallback')

    def test_recent_glass_pvs_source_endpoint_and_unchanged_weapon_callback(self):
        self.run_case('bullets_filter')

    def test_per_shooter_global_and_interest_region_caps(self):
        self.run_case('bullets_rate')

    def test_clients_receive_only_server_traces_and_send_no_requests(self):
        self.run_case('bullets_client')

    def run_manager(self, case):
        result = subprocess.run([luajit(), str(REPO / 'tools/tests/glass_debris_harness.lua'), str(LUA),
                                 str(REPO / 'tools/qa/glass_debris_jolt_probe.lua'), case],
                                cwd=REPO, capture_output=True, encoding='utf-8', timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('interaction manager ' + case + ' OK', result.stdout)

    def test_damage_bursts_adopt_children_at_one_replacement_per_frame(self):
        self.run_manager('interaction_manager')

    def test_oldest_first_budget_minimum_size_refusal_and_one_piece_budget(self):
        self.run_manager('interaction_budget')

    def test_descendants_inherit_original_deadline_and_lifetime_changes(self):
        self.run_manager('interaction_lifetime')

    def test_disable_during_worker_clears_interaction_but_preserves_blast_push(self):
        self.run_manager('interaction_off')

    def test_client_ray_queue_per_frame_cap_expiration_and_input_validation(self):
        self.run_manager('interaction_rays')

    def test_qa_fixtures_stats_format_and_per_pane_minimum_size_metadata(self):
        self.run_manager('interaction_qa')


if __name__ == '__main__':
    unittest.main()
