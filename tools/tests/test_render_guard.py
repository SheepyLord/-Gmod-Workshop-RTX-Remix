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

    def test_private_verified_multiplayer_environment_installs_the_global_dispatcher(self):
        self.run_case("verified_multiplayer")

    def test_multiplayer_callbacks_remain_protected_through_a_cached_original_dispatcher(self):
        self.run_case("cached_multiplayer")

    def test_global_or_inherited_multiplayer_marker_is_not_installation_proof(self):
        self.run_case("inherited_proof")

    def test_server_and_menu_realms_do_not_install_the_client_guard(self):
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

    def test_hook_identity_object_self_returns_and_side_quarantine(self):
        self.run_case("hooks")

    def test_only_owned_extra_stacks_are_restored_without_guessing_depth_or_mesh(self):
        self.run_case("cleanup")

    def test_caller_ownership_and_completed_cross_callback_scope_balance(self):
        self.run_case("stack_ownership")

    def test_successful_nested_work_unwinds_once_when_its_parent_fails(self):
        self.run_case("nested_cleanup")

    def test_timers_and_cvar_callbacks_keep_arguments_and_off_switch(self):
        self.run_case("callbacks")

    def test_disabled_guard_passes_through_without_policy_rejection(self):
        self.run_case("off")

    def test_absent_verified_early_rtx_proof_performs_no_mutation(self):
        self.run_case("no_proof")
