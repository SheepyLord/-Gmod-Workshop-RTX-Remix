<# Builds the local-only R12-C texture census module. See build_vram_probe.ps1.md. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repo 'tools/lib/VsDevEnv.psm1') -Force
$saved = @{}
foreach ($item in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) { $saved[$item.Key] = $item.Value }
$target = Join-Path $repo 'out/r12-vram/probe'
New-Item -ItemType Directory -Force $target | Out-Null
Push-Location $target
try {
    Enter-VsDevEnv
    $env:TEMP = $target
    $env:TMP = $target
    & cl.exe /nologo /std:c++20 /EHsc /MD /O2 /W4 /WX /LD /DWIN32_LEAN_AND_MEAN `
        "/I$repo/third_party/gmod/include" (Join-Path $PSScriptRoot 'vram_probe.cpp') `
        /link bcrypt.lib /OUT:gmcl_nlvramprobe_win64.dll
    if ($LASTEXITCODE) { throw "VRAM probe build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
    foreach ($item in @([Environment]::GetEnvironmentVariables('Process').GetEnumerator())) {
        if (-not $saved.ContainsKey($item.Key)) { [Environment]::SetEnvironmentVariable($item.Key, $null, 'Process') }
    }
    foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key, $item.Value, 'Process') }
}
