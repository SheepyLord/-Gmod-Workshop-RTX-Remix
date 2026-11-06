"""Exercise the complete self-contained early renderer guard under LuaJIT."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
GUARD = REPO / "companion/nativeloader/lua/autorun/_nativeloader_guard.lua"
LUAJIT = shutil.which("luajit") or next((str(p) for p in [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/LuaJIT/bin/luajit.exe"
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class RenderGuardTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name("render_guard_harness.lua")),
                               str(GUARD), scenario], cwd=REPO, capture_output=True,
                              encoding="utf-8", errors="replace", timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("PASS " + scenario, done.stdout)

    def test_idempotent_early_and_autorun_install_preserves_existing_behavior(self):
        self.run_case("install")

    def test_dupe_camera_aliases_virtual_scopes_and_mismatched_closers(self):
        self.run_case("camera_aliases")

    def test_effect_observer_preserves_guard_policy_and_original_caller(self):
        self.run_case("effect_observer")

    def test_raster_previews_restore_each_original_submaterial_even_on_error(self):
        self.run_case("preview_materials")
        self.run_case("preview_late")

    def test_local_rtx_start_without_the_early_view_installs_from_the_autorun(self):
        self.run_case("autorun")

    def test_private_verified_multiplayer_environment_protects_only_owned_callbacks(self):
        self.run_case("verified_multiplayer")

    def test_multiplayer_owned_callbacks_remain_protected_through_a_cached_original_dispatcher(self):
        self.run_case("cached_multiplayer")

    def test_global_or_inherited_multiplayer_marker_is_not_installation_proof(self):
        self.run_case("inherited_proof")

    def test_a_served_initializer_or_an_rtx_off_start_installs_nothing(self):
        for scenario in ("remote_initializer", "inactive_start"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_server_and_menu_realms_do_not_install_or_send_the_client_guard(self):
        for scenario in ("realm_server", "realm_menu"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_console_and_typed_convar_pin_boundaries(self):
        self.run_case("pins")

    def test_native_console_and_material_strings_reject_embedded_nul(self):
        self.run_case("native_nul")

    def test_native_enum_snapshot_reserved_targets_and_normal_texture_controls(self):
        self.run_case("targets")

    def test_known_unsupported_shader_depth_and_mrt_paths(self):
        self.run_case("shaders")

    def test_nested_views_are_bounded_but_sequential_views_remain(self):
        self.run_case("views")

    def test_errors_are_reported_and_only_repeated_failures_quarantine_hooks(self):
        self.run_case("hooks")

    def test_refusal_floods_do_not_hide_error_records(self):
        self.run_case("report_caps")

    def test_only_owned_extra_stacks_are_restored_without_guessing_depth_or_mesh(self):
        self.run_case("cleanup")

    def test_caller_ownership_and_completed_cross_callback_scope_balance(self):
        self.run_case("stack_ownership")

    def test_successful_nested_work_unwinds_once_when_its_parent_fails(self):
        self.run_case("nested_cleanup")

    def test_scopes_leaked_outside_protected_callbacks_never_exhaust_the_stack_limit(self):
        for scenario in ("leaks", "prerender_boundary"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_hot_paths_skip_switch_reads_target_queries_and_repeated_shader_lookups(self):
        self.run_case("hot_paths")

    def test_timers_and_cvar_callbacks_keep_arguments_and_off_switch(self):
        self.run_case("callbacks")

    def test_disabled_guard_passes_through_without_policy_rejection(self):
        self.run_case("off")

    def test_absent_verified_early_rtx_proof_performs_no_mutation(self):
        self.run_case("no_proof")
