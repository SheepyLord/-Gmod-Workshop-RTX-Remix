"""Compile the runtime publisher and GPL native readback tests from the committed patch/source."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
LICENSE = REPO / 'packages/fixes/licenses/oversized-skinning/upscaling-state'
PATCH = REPO / 'runtime/patches/0040-Publish-live-upscaling-state-for-startup-advice.patch'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'


def postimage(patch, path):
    """Read a complete postimage (new file or full-context diff), checking its hunk extent."""
    block = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    header, body = block.split('@@', 2)[1:]
    match = re.search(r'\+1,(\d+)', header)
    if not match:
        raise AssertionError(f'{path}: not a complete postimage')
    lines = [line[1:] for line in body.splitlines()[1:] if line.startswith((' ', '+'))]
    if len(lines) != int(match[1]):
        raise AssertionError(f'{path}: hunk length mismatch')
    return '\n'.join(lines) + '\n'


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_upscaling_state.cpp /Fepublisher.exe /Fopublisher.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./publisher.exe
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 (Join-Path $Repo 'packages/fixes/licenses/oversized-skinning/upscaling-state/tests/upscaling_state_test.cpp') /Fereadback.exe /Foreadback.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./readback.exe
exit $LASTEXITCODE
'''


class UpscalingReadbackTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_production_publisher_and_reader(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='upscaling-', dir=scratch) as directory:
            root = Path(directory)
            patch = PATCH.read_text(encoding='utf-8')
            for path in ('src/dxvk/rtx_render/rtx_fork_game_state.h', 'tests/rtx/unit/test_upscaling_state.cpp'):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS upscaling state publisher:', result.stdout)
            self.assertIn('PASS upscaling readback:', result.stdout)

    def test_gpl_header_matches_the_build_patch(self):
        patch = (LICENSE / 'upscaling-state.patch').read_text(encoding='utf-8')
        path = 'source/remixapi/upscaling_state.h'
        self.assertEqual(postimage(patch, path), (LICENSE / path).read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
