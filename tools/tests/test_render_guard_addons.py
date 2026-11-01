"""Replay audited graphics add-on API calls through the actual RTX guard, without add-on execution."""
import unittest

import test_render_guard as render_guard


@unittest.skipUnless(render_guard.LUAJIT, "LuaJIT is not installed")
class AddonRenderGuardTests(unittest.TestCase):
    run_case = render_guard.RenderGuardTests.run_case

    def test_gshader_world_position_and_normal_targets(self):
        self.run_case("r8_gshader_targets")

    def test_gshader_engine_depth_recreation_and_copies(self):
        self.run_case("r8_gshader_depth")

    def test_disk_shaders_patch_includes_cycles_and_lux_before_native_loading(self):
        self.run_case("r8_disk_shaders")

    def test_fxaa_ssdo_ssr_mrt_mesh_and_surface_draws(self):
        self.run_case("r8_effect_draws")

    def test_gshader_world_and_entity_material_changes(self):
        self.run_case("r8_world_materials")

    def test_exact_quick_bloom_initialize_signature_continues(self):
        self.run_case("r8_quick_bloom")

    def test_realcsm_eight_shadow_targets_projectors_and_resolution(self):
        self.run_case("r8_realcsm")

    def test_lifemod_dof_and_video_distortion_dispatch_and_direct_calls(self):
        self.run_case("r8_lifemod")

    def test_niknaks_normal_color_atlas_remains_usable(self):
        self.run_case("r8_niknaks")

    def test_unreviewed_formats_nonfinite_dimensions_and_cubemaps(self):
        self.run_case("r8_limits")

    def test_persistent_resource_name_quota_returns_shared_target(self):
        self.run_case("r8_budget")

    def test_persistent_resource_byte_budget_returns_shared_target(self):
        self.run_case("r8_byte_budget")

    def test_ignored_pushes_and_pops_preserve_toolgun_caller_state(self):
        self.run_case("r8_pair_fallback")

    def test_gshader_projector_and_dynamic_light_metatable_edits_are_private(self):
        self.run_case("r8_light_wrappers")

    def test_remote_effects_cannot_bypass_policy_with_cached_dispatch(self):
        self.run_case("r8_mp_callbacks")

    def test_setup_and_legitimate_hook_identity_and_returns(self):
        self.run_case("r8_callbacks")

    def test_rtx_guard_off_restores_original_addon_calls(self):
        self.run_case("r8_off_replays")

    def test_native_allocator_lua_error_uses_existing_engine_texture(self):
        self.run_case("r8_allocator_failure")
