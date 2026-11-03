<# Build the R13-B VRAM pressure tool; see build_vram_pressure.ps1.md. #>
[CmdletBinding()]
param([string] $Out)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target = if ($Out) { $Out } else { Join-Path $repo 'out/r13-b/gpu-probe' }
New-Item -ItemType Directory -Force $target | Out-Null
Import-Module (Join-Path $repo 'tools/lib/VsDevEnv.psm1') -Force
$saved = @{}
foreach ($item in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) { $saved[$item.Key] = $item.Value }
Push-Location $target
try {
    Enter-VsDevEnv
    $env:TEMP = $target
    $env:TMP = $target
    & cl.exe /nologo /std:c++20 /EHsc /MD /O2 /W4 /WX /DWIN32_LEAN_AND_MEAN /D_WIN32_WINNT=0x0A00 `
        (Join-Path $PSScriptRoot 'vram_pressure.cpp') /Fe:vram_pressure.exe /link d3d11.lib dxgi.lib
    if ($LASTEXITCODE) { throw "VRAM pressure tool build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
    foreach ($item in @([Environment]::GetEnvironmentVariables('Process').GetEnumerator())) {
        if (-not $saved.ContainsKey($item.Key)) { [Environment]::SetEnvironmentVariable($item.Key, $null, 'Process') }
    }
    foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key, $item.Value, 'Process') }
}
