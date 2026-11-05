"""R19: Model Hotloader's server and client Lua under LuaJIT (reviews L-02, L-07, L-08, MH-05). See
test_hotloader_server.py.md."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


def between(text: str, start: str, end: str) -> str:
    """The production code from `start` up to (not including) `end`."""
    first = text.index(start)
    return text[first:text.index(end, first)]


def slices(folder: Path) -> str:
    """Code the harness cannot load from whole files: carrier.lua uses Garry's Mod's `continue`,
    and sharing.lua's server part reads the cache at load."""
    sharing = (folder / 'sharing.lua').read_text(encoding='utf8')
    carrier = (folder / 'carrier.lua').read_text(encoding='utf8')
    return ('-- slice sharing\n' + between(sharing, ' function mmdhl.CanEdit(', ' local function save()') + '-- end sharing\n'
            '-- slice carrier\n' + between(carrier, " net.Receive('mmdhl_collision_mesh',function(_,p)",
                                             " net.Receive('mmdhl_native_morph',") + '-- end carrier\n')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class HotloaderServerTests(unittest.TestCase):
    def run_lua(self, scenario):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='hl-server-', dir=scratch) as folder:
            selected = Path(folder) / 'slices.lua'
            selected.write_bytes(slices(LUA).encode('utf8'))
            result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_server_harness.lua')), scenario,
                                     str(LUA), str(selected)], cwd=REPO, capture_output=True, encoding='utf8',
                                    errors='replace', timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS ' + scenario, result.stdout)

    def test_only_the_owner_or_an_admin_removes_or_replaces_a_character(self):
        self.run_lua('remove')

    def test_a_prop_attaches_only_to_a_target_within_reach(self):
        self.run_lua('attach')

    def test_collision_meshes_keep_the_clients_pace(self):
        self.run_lua('mesh')

    def test_remote_shapes_the_module_dropped_are_asked_for_again(self):
        self.run_lua('scene')


if __name__ == '__main__':
    unittest.main()
