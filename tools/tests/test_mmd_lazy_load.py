"""R13-A: saved characters load at their first use; the most recently used stay ready (ADR 0099).
Runs the shipped Lua under LuaJIT with disk, mounts, precache and entities instrumented."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('server_none', 'server_budget', 'server_convar', 'server_first_use', 'server_fallback',
             'server_map_change', 'server_forget', 'client_host', 'client_remote')


def production_slices() -> str:
    """The real MountPackage (autorun), RememberRig/ForgetAssetRigs (carrier.lua) and
    GetRigForModel (materials.lua); the harness loads the rest of the files whole."""
    autorun = (LUA / 'autorun/mmdhl.lua').read_text(encoding='utf8')
    carrier = (LUA / 'mmdhl/carrier.lua').read_text(encoding='utf8')
    materials = (LUA / 'mmdhl/materials.lua').read_text(encoding='utf8')
    code = autorun[autorun.index('local mountedPackages={}'):autorun.index('function mmdhl.Decode(')]
    code += carrier[:carrier.index('-- On the client, networked strings')]
    code += materials[materials.index('function mmdhl.GetRigForModel('):materials.index('if CLIENT then\n mmdhl.editorPreviews')]
    return code


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LazyLoadTests(unittest.TestCase):
    def test_saved_characters_load_at_first_use(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mmd-lazy-', dir=scratch) as folder:
            selected = Path(folder) / 'production.lua'
            selected.write_text(production_slices(), encoding='utf8')
            for scenario in SCENARIOS:
                with self.subTest(scenario=scenario):
                    result = subprocess.run([LUAJIT, str(Path(__file__).with_name('mmd_lazy_load_harness.lua')),
                                             str(selected), str(LUA / 'mmdhl'), scenario], cwd=REPO,
                                            capture_output=True, encoding='utf8', errors='replace', timeout=20)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('PASS ' + scenario, result.stdout)

    def test_map_start_restores_through_the_ready_set(self):
        # The server's map-start restoration hands every saved entry to mmdhl.RestoreActors
        # (actors.lua), which alone decides what is mounted and precached.
        sharing = (LUA / 'mmdhl/sharing.lua').read_text(encoding='utf8')
        hook = sharing[sharing.index("hook.Add('InitPostEntity','MMDHL.RestorePublishedActors'"):]
        hook = hook[:hook.index('\n end)')]
        self.assertIn('mmdhl.RestoreActors(entries)', hook)
        self.assertLess(hook.index('mmdhl.RestoreActors(entries)'), hook.index('mmdhl.RegisterActor('))
        actors = (LUA / 'mmdhl/actors.lua').read_text(encoding='utf8')
        self.assertIn('function mmdhl.RestoreActors(entries)', actors)
        # No new bundled Lua file: the companion's render guard lists every one (ADR 0086).
        self.assertFalse((LUA / 'mmdhl/readiness.lua').exists())


if __name__ == '__main__':
    unittest.main()
