"""Execute shipped Lua through delete/reimport with retained archives and separate realms."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class ReimportTests(unittest.TestCase):
    def test_production_delete_reimport_and_live_carrier_lifetimes(self):
        carrier = (SOURCE / 'carrier.lua').read_text(encoding='utf8')
        materials = (SOURCE / 'materials.lua').read_text(encoding='utf8')
        library = (SOURCE / 'library.lua').read_text(encoding='utf8')
        # Exclude the unrelated GLua continue loops. All exercised functions are
        # complete, unchanged production bodies, including both spawn factories.
        code = carrier[:carrier.index('-- On the client, networked strings')]
        code += "\nlocal function networkedRig(e) return e:GetNW2String('MMDHLRig','') end\n"
        code += carrier[carrier.index('function mmdhl.GetRig(ent)'):carrier.index('function mmdhl.GetMetadata(')]
        code += materials[materials.index('function mmdhl.GetRigForModel('):materials.index('if CLIENT then\n mmdhl.editorPreviews')]
        code += "\nlocal function save() end\n"
        code += carrier[carrier.index(' function mmdhl.SpawnNative('):carrier.index(' local function failure(ent,err)')]
        code += "\nlocal library=mmdhl.library\n"
        code += library[library.index('local function validId('):library.index('-- Folders organize')]
        code += library[library.index('function library.Delete('):library.index('-- Complete physical deletion')]
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mmd-reimport-', dir=scratch) as folder:
            selected = Path(folder) / 'production.lua'
            selected.write_text(code, encoding='utf8')
            for realm in ('server', 'client'):
                for scenario in ('retained_archive', 'changed_fit', 'withdraw_live', 'failed_write', 'missing_mount', 'orphan_variant', 'reload'):
                    with self.subTest(realm=realm, scenario=scenario):
                        result = subprocess.run([LUAJIT, str(Path(__file__).with_name('mmd_reimport_harness.lua')),
                            str(selected), str(SOURCE), realm, scenario], cwd=REPO,
                            capture_output=True, encoding='utf8', errors='replace', timeout=20)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn('PASS ' + realm + ' ' + scenario, result.stdout)


if __name__ == '__main__':
    unittest.main()
