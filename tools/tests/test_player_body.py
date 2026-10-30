"""Execute the shipped player body, categorizer and menu against a small GMod API double."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
ADDON = REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua'


class PlayerBodyTest(unittest.TestCase):
    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
    def test_actual_proxy_categories_offsets_and_spawnmenu(self):
        result = subprocess.run([LUA, str(REPO / 'tools/tests/player_body_harness.lua'),
                                 str(ADDON / 'entities/rtx_pseudoplayer.lua'),
                                 str(ADDON / 'remixlua/cl/remixapi/cl_remix_category_1_pseudoplayer.lua'),
                                 str(REPO / 'companion/nativeloader/lua/autorun/client/nativeloader_menu.lua')],
                                cwd=REPO, capture_output=True, text=True, encoding='utf-8', timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: private body categories', result.stdout)

    @unittest.skipUnless(Path(LUA).is_file(), 'LuaJIT is not installed')
    def test_model_fixer_preserves_proxy_draw_hooks(self):
        source = (ADDON / 'remixlua/cl/cl_rtx_misc.lua').read_text(encoding='utf-8-sig')
        function = source[source.index('local function FixupEntity('):source.index('local function FixupEntities(')]
        script = '''
local DrawFix = function() end
local function IsValid(v) return v ~= nil end
''' + function + '''
local custom = function() end
for _, class in ipairs({'rtx_pseudoplayer','procedural_shard'}) do
 local ent = {GetClass=function() return class end,RenderOverride=custom}
 FixupEntity(ent) assert(ent.RenderOverride==custom,class)
end
local ent = {GetClass=function() return 'prop_dynamic' end,RenderOverride=custom,RTXCustomDraw=true}
FixupEntity(ent) assert(ent.RenderOverride==custom)
ent.RTXCustomDraw=nil FixupEntity(ent) assert(ent.RenderOverride==DrawFix)
'''
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            path = Path(folder) / 'draw_guard.lua'
            path.write_text(script, encoding='utf-8')
            result = subprocess.run([LUA, str(path)], capture_output=True, text=True, encoding='utf-8', timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
