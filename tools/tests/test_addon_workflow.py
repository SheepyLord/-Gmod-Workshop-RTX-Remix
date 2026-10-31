"""Offline behavior checks for imported normals, AME navigation and the motion launcher."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class AddonWorkflowTests(unittest.TestCase):
    def run_lua(self, scenario, *paths):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('addon_workflow_harness.lua')),
                                 scenario, *map(str, paths)], cwd=REPO, capture_output=True,
                                encoding='utf-8', errors='replace', timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_material_names_and_workspace_selection(self):
        folder = REPO / 'packages/advanced-material-editor/!advanced_material_editor/lua/advmat'
        source = (folder / 'cl_76_rtx_editor.lua').read_text(encoding='utf-8')
        # Exercise the actual navigation methods without the unrelated GLua/render/editor runtime.
        methods = source[source.index('function PANEL:SelectSourceMaterial('):
                         source.index('function PANEL:UpdateActionMode(')]
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='addon-workflow-', dir=scratch) as tmp:
            path = Path(tmp) / 'navigation.lua'
            path.write_text('PANEL = {}\n' + methods, encoding='utf-8')
            self.run_lua('ame', folder / 'sh_15_mmd.lua', path)

    def test_imported_normals_lifecycle(self):
        self.run_lua('normals', REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_imported_normals.lua')

    def test_motion_tab_opens_existing_manager(self):
        self.run_lua('motion', REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_motion_tab.lua')
