"""Exercise the actual tier panel and stability-guide navigation with shipping gettext catalogs."""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import companion_i18n
from test_companion import LUAJIT, REPO, lua_value


# Schema-1 status writer shape (loader/core/src/status.cpp), with R6's additive I2/I5 fields.
# Generated under out/tmp: no captured player data or installed-game fixture is needed.
STATUS_JSON = r'''{
  "schema": 1, "loader_version": "0.10.1", "utc": "2026-10-31T20:00:00.000Z",
  "process_id": 1234, "startup_elapsed_ms": 350,
  "deployment": {"outcome": "unchanged", "reason": "", "blocked_by": "none", "generation": 7,
    "recovered": false, "change_count": 0, "operations": 0, "elapsed_ms": 10,
    "packages": ["gmod-rtx-remix"], "notes": [], "skipped": []},
  "activation": {"outcome": "active", "reason": "runtime gmod-rtx-remix 1.0.0", "elapsed_ms": 300,
    "windows_error": 0, "rolled_back": false,
    "runtime": {"id": "gmod-rtx-remix", "version": "1.0.0", "folder": "native-loader/packages/runtime",
      "dll": "native-loader/packages/runtime/d3d9.dll"},
    "system_vulkan_path": "C:\\Windows\\System32\\vulkan-1.dll", "gpu_vendors": [4318], "non_nvidia": false,
    "environment": {"requested": [{"name": "DXVK_CONFIG_FILE", "value": "native-loader/remix/tier.conf,dxvk.conf"}],
      "set": [], "user_values_kept": []},
    "layers": {"rtx": ["rtx.conf"], "dxvk": ["native-loader/remix/tier.conf", "dxvk.conf"]},
    "layer_copies": [{"copy": "native-loader/remix/tier.conf", "source": "native-loader/packages/runtime/config/dxvk-tiers/low.conf"}],
    "launch_arguments": {"requested": ["-windowed"], "added": ["-windowed"], "already_present": [], "fallback_launch_options": ""},
    "missing_system_dependencies": [], "preloaded": [],
    "reshade": {"outcome": "off", "reason": "", "package": "", "layer": "", "layer_manifest": "", "folder": "",
      "settings": "", "presets": [], "environment": [], "notes": []},
    "performance_tier": {"tier": "low", "source": "auto", "reason": "8192 MiB dedicated VRAM -> low; RTX class (including laptop adjustment) -> low",
      "adapter": "NVIDIA GeForce RTX 4060 Laptop GPU", "dedicated_vram_mib": 8192, "layer": "native-loader/remix/tier.conf"}},
  "session": {"cvars": 2, "cvars_exec": "nativeloader_session.cfg", "recorded": 2, "restore_values": 0,
    "restore_exec": "", "patches": 0, "patches_allowed": false, "overrides": [], "hooks": "",
    "hidden_addons": [], "module_dependencies": [], "notes": []},
  "packages": [{"id": "gmod-rtx-remix", "version": "1.0.0", "source": "workshop", "label": "3829070317", "time_updated": null}],
  "errors": [], "previous_session": {"reason": "device_lost", "time_utc": "2026-10-31T19:00:00Z",
    "folder": "native-loader/logs/sessions/20261031-device_lost"}
}'''


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionStabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(dir=scratch)
        cls.addClassCleanup(cls.temp.cleanup)
        cls.catalog = Path(cls.temp.name) / 'i18n_data.lua'
        companion_i18n.build(cls.catalog)

    def run_scenario(self, scenario, language, status_path=None):
        lua = REPO / 'companion/nativeloader/lua'
        args = [
            LUAJIT, str(Path(__file__).with_name('companion_stability_harness.lua')),
            str(lua / 'autorun/client/nativeloader_menu.lua'),
            str(lua / 'autorun/client/nativeloader_guide.lua'),
            str(lua / 'nativeloader/i18n.lua'), str(self.catalog), scenario, language,
        ]
        if status_path:
            args.extend((str(status_path), str(Path(__file__).resolve())))
        result = subprocess.run(args, capture_output=True, encoding='utf-8', timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario + ' ' + language, result.stdout)
        return result.stdout

    def test_tier_selection_sources_and_refresh_in_every_language(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            for scenario in ('low_auto', 'medium_fallback', 'high_config', 'unknown_source', 'refresh',
                             'no_layer_medium', 'no_layer_low', 'no_layer_reason_missing'):
                with self.subTest(language=language, scenario=scenario):
                    self.run_scenario(scenario, language)

    def test_memory_profile_line_in_every_language(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            for scenario in ('memory_below_minimum', 'memory_minimum', 'memory_recommended', 'memory_high'):
                with self.subTest(language=language, scenario=scenario):
                    self.run_scenario(scenario, language)
        self.run_scenario('memory_invalid', 'en')  # an unknown profile shows no line

    def test_absent_or_invalid_reports_show_no_tier_line(self):
        for scenario in ('absent', 'no_activation', 'bad_field', 'missing', 'malformed',
                         'unreadable', 'bad_schema', 'invalid_tier', 'unknown_hardware',
                         'non_nvidia', 'query_failed', 'non_nvidia_with_adapter'):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario, 'en')

    def test_stability_link_selects_the_translated_guide_page(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            with self.subTest(language=language):
                output = self.run_scenario('guide', language)
                example = output.split('CONFIG_BEGIN\n')[1].split('\nCONFIG_END')[0]
                self.check_config_example(example)

    def check_config_example(self, example):
        config = json.loads(example)
        shipped = json.loads((REPO / 'dist/native-loader/config.json').read_text(encoding='utf-8'))
        self.assertEqual(config['schema'], shipped['schema'])
        self.assertEqual(config['allow'], shipped['allow'])
        self.assertEqual(config['remix'], {'performance_tier': 'low'})
        self.assertEqual(config['diagnostics'], {'gpu_crash_dumps': 'off'})

    def test_player_doc_example_is_complete_valid_json_and_keeps_allow(self):
        doc = (REPO / 'docs/STABILITY.md').read_text(encoding='utf-8')
        examples = re.findall(r'```json\n(.*?)\n```', doc, re.S)
        self.assertEqual(len(examples), 1)
        self.check_config_example(examples[0])

    def test_older_loaders_get_update_and_manual_evidence_guidance_in_every_language(self):
        for language in ('en', *companion_i18n.LANGUAGES):
            for scenario in ('guide_absent', 'guide_missing', 'guide_malformed', 'guide_bad_field',
                             'guide_no_activation', 'guide_bad_schema', 'guide_unreadable'):
                with self.subTest(language=language, scenario=scenario):
                    self.run_scenario(scenario, language)

    def test_guide_rechecks_loader_capability_on_reopen(self):
        self.run_scenario('guide_refresh', 'en')

    def test_full_status_json_is_parsed_for_menu_and_guide(self):
        for scenario in ('low', 'non_nvidia', 'query_failed', 'no_layer_medium', 'no_layer_low', 'absent'):
            with self.subTest(scenario=scenario):
                status = json.loads(STATUS_JSON)
                activation = status['activation']
                tier = activation['performance_tier']
                if scenario == 'absent':
                    del activation['performance_tier']  # 0.10.1, irrespective of companion version
                    del status['previous_session']
                elif scenario in ('non_nvidia', 'query_failed'):
                    activation['non_nvidia'] = scenario == 'non_nvidia'
                    activation['gpu_vendors'] = [4098] if activation['non_nvidia'] else []
                    tier.update(tier='high', source='auto', adapter='', dedicated_vram_mib=0,
                                layer='', reason='no NVIDIA adapter detected; no performance tier layer')
                elif scenario.startswith('no_layer_'):
                    name = scenario.removeprefix('no_layer_')
                    tier.update(tier=name, layer='', reason=f'package has no {name} tier file, retaining classic defaults')
                if not tier.get('layer') or scenario == 'absent':
                    activation['environment']['requested'] = []
                    activation['layers']['dxvk'] = ['dxvk.conf']
                    activation['layer_copies'] = []
                path = Path(self.temp.name) / 'status.json'
                path.write_text(json.dumps(status, ensure_ascii=False), encoding='utf-8')
                self.run_scenario('json_' + scenario, 'en', path)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--decode-status':
        # Test-only replacement for native util.JSONToTable: parse the document, then return a
        # Lua table over stdout. No fixture-to-table lookup or hand-built status stub is used.
        value = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
        print('return ' + lua_value(value))
    else:
        unittest.main()
