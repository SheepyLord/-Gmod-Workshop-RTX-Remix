<#
.SYNOPSIS
Configures, builds and tests the C++ loader with MSVC x64, CMake presets and Ninja.

.EXAMPLE
tools\build.ps1                          # Debug build, then CTest
tools\build.ps1 -Config Release -NoTests
tools\build.ps1 -Clean                   # delete out\build\<preset> first
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Debug',
    [switch] $Clean,
    [switch] $NoTests
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$preset = "win64-$($Config.ToLowerInvariant())"

Import-Module (Join-Path $PSScriptRoot 'lib\VsDevEnv.psm1') -Force
Enter-VsDevEnv

function Invoke-Tool([string] $Description, [string] $Exe, [string[]] $Arguments) {
    # Native tools report failure through the exit code; their stderr is not an error by itself.
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description failed (exit code $LASTEXITCODE)" }
}

if ($Clean) {
    $buildDir = Join-Path $repo "out\build\$preset"
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
}

Push-Location $repo
try {
    Invoke-Tool 'CMake configure' cmake @('--preset', $preset)
    Invoke-Tool 'Build' cmake @('--build', '--preset', $preset)
    if (-not $NoTests) {
        Invoke-Tool 'Tests' ctest @('--preset', $preset)
    }
} finally {
    Pop-Location
}
Write-Host "Build $preset OK: $(Join-Path $repo "out\build\$preset")"
