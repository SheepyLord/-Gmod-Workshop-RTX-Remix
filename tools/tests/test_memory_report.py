"""R13 memory report: telemetry windows and phases, rotated files, bad input, and a census of this process."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
RAM_HEADER = ('time_utc,private_bytes,working_set_bytes,system_commit_bytes,system_commit_limit_bytes,available_ram_bytes,'
              'gpu_local_usage_bytes,gpu_local_budget_bytes,gpu_nonlocal_usage_bytes,gpu_nonlocal_budget_bytes\n')
VRAM_HEADER = ('time_utc,driverBudgetBytes,driverAllocatedBytes,totalAllocatedBytes,totalUsedBytes,poolRetainedBytes,'
               'usedReplacementGeometryBytes,usedBufferBytes,usedAccelerationStructureBytes,usedOpacityMicromapBytes,'
               'usedMaterialTextureBytes,usedRenderTargetBytes,forkTextureCacheCount,usedAppTextureBytes,usedAppBufferBytes\n')


class MemoryReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('memory_report', REPO / 'tools/qa/memory_report.py')
        cls.tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.tool)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=REPO / 'out' if (REPO / 'out').is_dir() else None)
        self.root = Path(self.temp.name)
        logs = self.root / 'native-loader/logs'
        data = self.root / 'garrysmod/data/native-loader'
        logs.mkdir(parents=True)
        data.mkdir(parents=True)
        # An older session's row, rotated rows, then this session's: private 10, 14, 12 GB; one empty counter.
        (logs / 'memory.1.csv').write_text(RAM_HEADER + '2026-11-03T09:59:50Z,30000000000,1,1,1,1,1,1,1,1\n'
                                           '2026-11-03T10:00:00Z,10000000000,6000000000,40000000000,1,1,3000000000,9000000000,1,1\n',
                                           encoding='utf-8')
        (logs / 'memory.csv').write_text(RAM_HEADER + '2026-11-03T10:00:10Z,14000000000,7000000000,41000000000,1,1,,9000000000,1,1\n'
                                         '2026-11-03T10:00:20Z,12000000000,6500000000,40500000000,1,1,4000000000,9000000000,1,1\n'
                                         'not a time,1,1,1,1,1,1,1,1,1\n', encoding='utf-8')
        (data / 'vram.csv').write_text(VRAM_HEADER + '2026-11-03T10:00:05Z,9,8,7,6000000000,0,0,0,0,0,2000000000,500000000,3,1000000000,0\n'
                                       '2026-11-03T10:00:35Z,9,8,7,6500000000,0,0,0,0,0,2500000000,500000000,3,900000000,0\n',
                                       encoding='utf-8')

    def tearDown(self):
        self.temp.cleanup()

    def test_session_and_phases_report_peak_and_last(self):
        idle = self.tool.phase('idle=2026-11-03T10:00:15Z/2026-11-03T10:00:40Z')
        result = self.tool.report(self.root, '2026-11-03T10:00:00Z', None, [idle])
        session = result['phases']['session']
        self.assertEqual(session['ram_samples'], 3)  # the older session's row and the bad row are left out
        self.assertEqual(session['ram']['private'], {'peak_gb': 14.0, 'last_gb': 12.0})
        self.assertEqual(session['ram']['gpu_local_usage'], {'peak_gb': 4.0, 'last_gb': 4.0})  # empty counter skipped
        self.assertEqual(session['vram']['game_textures'], {'peak_gb': 1.0, 'last_gb': 0.9})
        self.assertEqual(session['vram']['replacement_textures'], {'peak_gb': 2.5, 'last_gb': 2.5})
        phase = result['phases']['idle']
        self.assertEqual((phase['ram_samples'], phase['vram_samples']), (1, 1))
        self.assertEqual(phase['ram']['working_set'], {'peak_gb': 6.5, 'last_gb': 6.5})
        self.assertEqual(phase['vram']['dxvk_used'], {'peak_gb': 6.5, 'last_gb': 6.5})

    def test_command_line_writes_the_report_and_refuses_empty_windows(self):
        out = self.root / 'report.json'
        self.assertEqual(self.tool.main(['--root', str(self.root), '--since', '2026-11-03T10:00:00Z',
                                         '--until', '2026-11-03T10:00:10Z', '--out', str(out)]), 0)
        self.assertEqual(json.loads(out.read_text(encoding='utf-8'))['phases']['session']['ram_samples'], 2)
        self.assertEqual(self.tool.main(['--root', str(self.root), '--since', '2026-11-04T00:00:00Z']), 1)
        with self.assertRaises(SystemExit) as stop:
            self.tool.main(['--root', str(self.root), '--since', '2026-11-03T10:00:00Z', '--phase', 'broken'])
        self.assertEqual(stop.exception.code, 2)
        with self.assertRaises(self.tool.ReportError):
            self.tool.utc('2026-11-03 10:00')

    @unittest.skipUnless(os.name == 'nt', 'VirtualQueryEx census')
    def test_census_of_this_process(self):
        result = self.tool.census(os.getpid())
        self.assertGreater(result['committed_gb'].get('private', 0) + result['committed_gb'].get('image', 0), 0)
        self.assertGreater(result['private_allocations'], 0)
        self.assertAlmostEqual(sum(result['private_by_allocation_size_gb'].values()),
                               result['committed_gb'].get('private', 0), delta=0.01)


if __name__ == '__main__':
    unittest.main()
