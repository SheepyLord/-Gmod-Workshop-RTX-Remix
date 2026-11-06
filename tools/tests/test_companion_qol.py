"""R20-B startup hint decisions/lifetime and the one-time sky-default migration under LuaJIT."""
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
class CompanionQoLTests(unittest.TestCase):
    def run_case(self, scenario, *args):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name('companion_qol_harness.lua')),
                               str(REPO), scenario, *map(str, args)], capture_output=True, text=True, timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn('PASS ' + scenario, done.stdout)

    def test_each_upscaler_and_frame_generation_combination_once_per_start(self):
        for up in range(6):
            for fg in range(3):
                with self.subTest(up=up, fg=fg):
                    self.run_case('matrix', up, fg)

    def test_only_supported_gpu_and_backend_suggestions(self):
        for gpu, expected in [('RTX 2060', 'FSR 3'), ('NVIDIA GeForce RTX 3090 Ti', 'FSR 3'),
                              ('NVIDIA GeForce RTX 4070 Laptop GPU', 'DLSS-G'), ('RTX 5090', 'DLSS-G'),
                              ('GeForce GTX 1080 Ti', 'silent'), ('RTX 6090', 'silent'), ('RTX A4000', 'silent'),
                              ('NVIDIA GeForce RTX 5090', 'mixed'), ('AMD Radeon RX 7900 XTX', 'amd')]:
            with self.subTest(gpu=gpu, expected=expected):
                self.run_case('gpu', gpu, expected)
        for flags, expected in [('no-dlfg', 'FSR 3'), ('no-fg', 'Upscaling is off.'),
                                ('no-dlss', 'Frame generation is off.'), ('none', '')]:
            with self.subTest(flags=flags):
                self.run_case('capabilities', flags, expected)

    def test_preferences_and_inactive_or_incomplete_loader_reports(self):
        for reason in ('hints', 'opt-out', 'inactive', 'schema', 'pid', 'utc', 'gpu', 'vendor', 'non-nvidia'):
            with self.subTest(reason=reason):
                self.run_case('suppressed', reason)

    def test_unknown_state_is_silent_and_retries_are_bounded(self):
        for reason in ('no-api', 'file-getter-only', 'not-ready', 'nil', 'not-table', 'bad-up', 'bad-fg',
                       'string', 'fraction', 'nan', 'inf', 'native', 'json', 'read', 'no-marker'):
            with self.subTest(reason=reason):
                self.run_case('unreadable', reason)

    def test_timing_and_persistent_process_lifetime(self):
        for scenario in ('ready-later', 'drawn', 'next-start', 'both-on-then-off'):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_migration_preserves_changed_pairs_and_marks_even_when_skipped(self):
        for passes, minutes in [('0', '30'), ('0.000000', '30.000000'), ('1', '20'), ('1', '30'),
                                ('0', '20'), ('0', '45'), ('0', '30.1')]:
            with self.subTest(passes=passes, minutes=minutes):
                self.run_case('migration', passes, minutes)
        self.run_case('migration-missing')


if __name__ == '__main__':
    unittest.main()
