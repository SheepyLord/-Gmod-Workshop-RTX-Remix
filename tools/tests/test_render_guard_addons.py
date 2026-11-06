"""Replay audited graphics add-on API calls through the actual RTX guard, without add-on execution."""
import hashlib
import json
import re
import unittest

import test_render_guard as render_guard


@unittest.skipUnless(render_guard.LUAJIT, "LuaJIT is not installed")
class AddonRenderGuardTests(unittest.TestCase):
    run_case = render_guard.RenderGuardTests.run_case

    def test_gshader_world_position_and_normal_targets(self):
        self.run_case("r8_gshader_targets")

    def test_gshader_engine_depth_recreation_and_copies(self):
        self.run_case("r8_gshader_depth")

    def test_native_material_reads_and_untrusted_shader_bindings_without_disk_preflight(self):
        self.run_case("r8_disk_shaders")

    def test_fixes_pbr_readers_receive_real_exopbr_and_gpbr_materials(self):
        self.run_case("r8_pbr_readers")

    def test_hotloader_immediate_shaders_are_native_for_owned_draws(self):
        self.run_case("r8_hotloader_materials")

    def test_every_bundled_virtual_path_keeps_native_material_operations(self):
        self.run_case("r8_bundled_paths")

    def test_exact_source_collisions_and_lookalikes_have_documented_scope(self):
        self.run_case("r8_source_collisions")

    def test_custom_program_metadata_cached_names_and_mutations_keep_binding_checks(self):
        self.run_case("r8_material_mutations")

    def test_1200_distinct_image_material_and_repeat_paths_add_no_disk_reads(self):
        self.run_case("r8_material_cost")

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


class BundledMaterialPathTests(unittest.TestCase):
    def test_exemptions_are_exact_indexed_package_and_companion_virtual_paths(self):
        repo = render_guard.REPO
        expected, ordinary = set(), set()
        for index in sorted((repo / "packages").glob("*/files.json")):
            for rel, entry in json.loads(index.read_text(encoding="utf-8"))["files"].items():
                if "/lua/" not in rel or not rel.endswith(".lua") or "/glass-rewrite-remix/" in rel.lower():
                    continue
                source = index.parent / rel
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), entry["sha256"], rel)
                virtual = "lua/" + rel.split("/lua/", 1)[1].lower()
                self.assertNotIn(virtual, expected, "bundled virtual path collision: " + rel)
                expected.add(virtual)
                # R20-C deliberately uses the ordinary rendering API, covered by R20-D's general
                # compatibility work. Shipping a new part must not silently expand exemptions.
                if index.parent.name in {"toolgun-screen", "blood-overhaul-rtx"}:
                    ordinary.add(virtual)
        for root in (repo / "companion/nativeloader/lua", repo / "glass/addon/lua"):
            for source in root.rglob("*.lua"):
                virtual = "lua/" + source.relative_to(root).as_posix().lower()
                self.assertNotIn(virtual, expected, "bundled virtual path collision: " + str(source))
                expected.add(virtual)
                if source.name in {"!nativeloader_blood.lua", "nativeloader_blood_menu.lua", "blood_core.lua",
                                   "blood_budget.lua", "blood_impacts.lua", "dts_package.lua", "dts_bootstrap.lua"}:
                    ordinary.add(virtual)
        text = render_guard.GUARD.read_text(encoding="utf-8")
        block = re.search(r"for path in \(\[\[(.*?)\]\]\)", text, re.S)
        self.assertIsNotNone(block)
        actual = block.group(1).split()
        self.assertEqual(len(actual), len(set(actual)), "duplicate exemptions")
        self.assertGreater(len(expected), 300)
        self.assertTrue(ordinary.isdisjoint(actual), "new blood/screen paths must use ordinary rendering policy")
        self.assertEqual(set(actual), expected - ordinary)
