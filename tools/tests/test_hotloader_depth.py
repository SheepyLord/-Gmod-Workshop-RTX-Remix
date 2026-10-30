"""DepthWrite must never be requested by the fixed-function Remix model renderer."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_render.lua'


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


class HotloaderDepthTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_actual_material_builders_and_draws_on_both_backends(self):
        source = SOURCE.read_text(encoding='utf-8')
        # These actual production sections use standard Lua. Exclude unrelated GLua continue loops.
        code = source[:source.index('local previewMaterials={}')]
        code += source[source.index('local function draw(ent,translucent,depth)'):source.index('local visual={')]
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='hotloader-depth-', dir=scratch) as folder:
            path = Path(folder) / 'native_render_depth.lua'
            path.write_text(code, encoding='utf-8')
            for backend in ('remix', 'source'):
                with self.subTest(backend=backend):
                    result = subprocess.run([luajit(), str(REPO / 'tools/tests/hotloader_depth_harness.lua'),
                                             str(path), backend], cwd=REPO, capture_output=True,
                                            encoding='utf-8', errors='replace', timeout=15)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('PASS: ' + backend, result.stdout)


if __name__ == '__main__':
    unittest.main()
