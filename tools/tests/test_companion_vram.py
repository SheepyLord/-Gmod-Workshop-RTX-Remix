"""Run the shipped companion VRAM sampler with mocked clock, files and Remix API under LuaJIT."""
import subprocess
import unittest
from pathlib import Path

from test_companion import LUAJIT, REPO


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class CompanionVramTests(unittest.TestCase):
    def test_sampler_lifecycle_and_retention(self):
        source = REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_vram.lua'
        harness = Path(__file__).with_name('companion_vram_harness.lua')
        for scenario in ('normal', 'missing', 'disabled', 'late_api', 'invalid', 'rotation',
                         'restart', 'foreign_file', 'oversized', 'truncated_tail', 'nul_tail',
                         'crlf', 'partial_row', 'excess_rows', 'rename_error', 'file_error',
                         'nil_backoff', 'error_backoff', 'failure_reset', 'server'):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(harness), str(source), scenario],
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


if __name__ == '__main__':
    unittest.main()
