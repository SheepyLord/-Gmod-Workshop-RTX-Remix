"""R21-B: run the shipped Hotloader installation check and UI under LuaJIT."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class HotloaderInstallationTests(unittest.TestCase):
    def run_scenario(self, scenario):
        for realm in ('client', 'server'):
            with self.subTest(realm=realm):
                result = subprocess.run([
                    LUAJIT, str(Path(__file__).with_name('hotloader_installation_harness.lua')),
                    str(REPO / 'packages/model-hotloader'), realm, scenario,
                ], cwd=REPO, capture_output=True, encoding='utf8', errors='replace', timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + realm + ' ' + scenario, result.stdout)

    def test_current_and_future_build_findings_are_diagnostics_only(self):
        self.run_scenario('findings')

    def test_matching_build_is_quiet_and_keeps_its_report(self):
        self.run_scenario('matched')

    def test_a_failed_or_throwing_check_is_diagnostic_only(self):
        for scenario in ('failed', 'throws'):
            self.run_scenario(scenario)

    def test_unchecked_module_keeps_its_separate_outdated_warning(self):
        self.run_scenario('unchecked')

    def test_pending_waits_and_logs_the_complete_report_once(self):
        self.run_scenario('pending')

    def test_pending_timeout_keeps_its_existing_warning(self):
        self.run_scenario('pending-timeout')

    def test_other_installation_warnings_survive(self):
        for scenario in ('fallback', 'identity', 'missing', 'outdated', 'policy'):
            self.run_scenario(scenario)


if __name__ == '__main__':
    unittest.main()
