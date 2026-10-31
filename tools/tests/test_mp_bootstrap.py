"""Verify the complete scoped client initializer without a game or GPU."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
RTX_LUA = Path(os.environ.get('NATIVELOADER_TEST_RTX_LUA',
    REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua'))
LUAJIT = shutil.which('luajit') or next((str(path) for path in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if path.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class MPBootstrapTests(unittest.TestCase):
    def run_case(self, scenario):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('mp_bootstrap_harness.lua')),
                                 str(REPO / 'loader/client/bootstrap.lua'), scenario, str(RTX_LUA)], cwd=REPO,
                                capture_output=True, encoding='utf-8', errors='replace', timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_scoped_loading_and_lifecycle(self):
        self.run_case('normal')

    def test_owned_script_error_is_reported_and_other_roots_continue(self):
        self.run_case('script_error')

    def test_scoped_missing_server_channels_preserve_normal_engine_networking(self):
        self.run_case('network')

    def test_normal_hardware_skinning_reloads_initially_and_after_map_initialization(self):
        for scenario in ('model_reload_normal_nil', 'model_reload_normal_false', 'model_reload_normal_retry'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_verified_late_hardware_skinning_never_flushes_world_model_cache(self):
        for scenario in ('model_reload_verified_match', 'model_reload_verified_mismatch',
                         'model_reload_verified_missing'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_realm_readiness_and_singleplayer_guards(self):
        for scenario in ('single_player', 'not_ready', 'server', 'menu', 'no_api', 'missing_api'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_a_payload_normal_loading_already_ran_is_not_run_twice(self):
        for scenario in ('normal_load', 'normal_load_allowcslua', 'normal_load_server', 'normal_load_marker'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_server_delivered_entity_definitions_are_kept(self):
        self.run_case('server_entity')
