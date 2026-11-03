"""Compile and run the packaged GPL production game-map registry regression."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'packages/fixes/licenses/oversized-skinning/autopbr'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'


class GameRegistryTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_production_registry(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='game-registry-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text('''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 (Join-Path $Source 'tests/game_registry_test.cpp') /Fegame_registry_test.exe /Fogame_registry_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_registry_test.exe') (Join-Path $Scratch 'fixture')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 (Join-Path $Source 'tests/game_matching_test.cpp') /Fegame_matching_test.exe /Fogame_matching_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_matching_test.exe') (Join-Path $Scratch 'matching')
exit $LASTEXITCODE
''', encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(SOURCE), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS game registry:', result.stdout)
            self.assertIn('PASS R12 matching:', result.stdout)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_compact_game_maps(self):
        """R13-M: BC4/BC5 maps, refusal lines, recipe keys, legacy transcoding and a version bump."""
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='game-dds-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text('''param([string]$Repo, [string]$Source, [string]$Scratch, [string]$Python)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
$test = Join-Path $Source 'tests/game_dds_test.cpp'
& cl.exe /nologo /EHsc /std:c++17 /O1 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $test /Fegame_dds_test.exe /Fogame_dds_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& cl.exe /nologo /EHsc /std:c++17 /O1 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 /DTOPBR_GAME_GENERATOR_VERSION=999 $test /Fegame_dds_bumped.exe /Fogame_dds_bumped.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach ($name in @('fixture', 'bump')) {
    & $Python (Join-Path $Source 'tests/make_game_pbr_fixtures.py') (Join-Path $Scratch $name)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& (Join-Path $Scratch 'game_dds_test.exe') (Join-Path $Scratch 'fixture')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_dds_test.exe') (Join-Path $Scratch 'bump') bump-prepare
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'game_dds_bumped.exe') (Join-Path $Scratch 'bump') bump-check
exit $LASTEXITCODE
''', encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(SOURCE), '-Scratch', str(root), '-Python', sys.executable],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for line in ('PASS codec:', 'PASS publication:', 'PASS conversion:', 'PASS migration without source:',
                         'PASS bump-prepare:', 'PASS bump-check: generator 999 reused every map'):
                self.assertIn(line, result.stdout)
