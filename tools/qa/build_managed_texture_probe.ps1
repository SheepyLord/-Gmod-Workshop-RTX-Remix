<# Build the isolated R12-C GPU regression host; see build_managed_texture_probe.ps1.md. #>
[CmdletBinding()]
param([string] $RuntimeSource)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $RuntimeSource) { $RuntimeSource = Join-Path $repo 'out/runtime-src' }
$RuntimeSource = (Resolve-Path -LiteralPath $RuntimeSource).Path
$target = Join-Path $repo 'out/r12-vram/gpu-probe'
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
        "/external:I$RuntimeSource/public/include" /external:W0 `
        (Join-Path $PSScriptRoot 'managed_texture_probe.cpp') /Fe:managed_texture_probe.exe /link user32.lib
    if ($LASTEXITCODE) { throw "Managed texture probe build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
    foreach ($item in @([Environment]::GetEnvironmentVariables('Process').GetEnumerator())) {
        if (-not $saved.ContainsKey($item.Key)) { [Environment]::SetEnvironmentVariable($item.Key, $null, 'Process') }
    }
    foreach ($item in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($item.Key, $item.Value, 'Process') }
}
