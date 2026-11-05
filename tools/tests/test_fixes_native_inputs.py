"""Compile and run the RTX fixes' R19 input checks (ADR 0112) from their GPL source copies in
packages/fixes/licenses: the path rules the module's Lua functions use (lua_path_policy.h) and what
RTX Water's native core takes from Lua (lua_input.h). Both are standard C++, compiled with MSVC."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LICENSES = REPO / 'packages/fixes/licenses/oversized-skinning'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
TESTS = {
    'lua_path_policy': (LICENSES / 'autopbr/tests/lua_path_policy_test.cpp', 'PASS lua path policy:'),
    'rtxwater_lua_input': (LICENSES / 'rtxwater/source/rtx_water/test/lua_input_test.cpp', 'PASS rtxwater lua input:'),
}
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Name, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /utf-8 $Source "/Fe$Name.exe" "/Fo$Name.obj"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch "$Name.exe")
exit $LASTEXITCODE
'''


class FixesNativeInputTests(unittest.TestCase):
    def compile_and_run(self, name: str) -> None:
        source, expected = TESTS[name]
        self.assertTrue(source.is_file(), source)
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=f'{name}-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(source), '-Name', name, '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(expected, result.stdout)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_lua_path_policy(self):
        self.compile_and_run('lua_path_policy')

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_rtxwater_lua_input(self):
        self.compile_and_run('rtxwater_lua_input')

    def test_the_copies_match_the_patches(self):
        # Each new file of a patch is also in the copy beside it, byte for byte once line endings agree.
        for patch, root in ((LICENSES / 'autopbr/lua-paths.patch', LICENSES / 'autopbr'),
                            (LICENSES / 'rtxwater/rtxwater-lua-input.patch', LICENSES / 'rtxwater')):
            text = patch.read_text(encoding='utf-8')
            for block in text.split('diff --git a/')[1:]:
                path = block.split(' ', 1)[0]
                if '\nnew file mode' not in block.split('@@', 1)[0]:
                    continue
                added = [line[1:] for line in block.split('@@', 2)[2].splitlines()[1:] if line.startswith('+')]
                copy = (root / path).read_text(encoding='utf-8').replace('\r\n', '\n').rstrip('\n').split('\n')
                self.assertEqual(added, copy, f'{patch.name}: {path}')


if __name__ == '__main__':
    unittest.main()
