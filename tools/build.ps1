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

# The MSVC environment and the scratch TEMP are for this build only: every process variable is put
# back as it was when the script ends, however it ends (R1-018). PowerShell hashtables compare names
# case-insensitively, as Windows does.
$savedEnvironment = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) { $savedEnvironment[$entry.Key] = $entry.Value }
function Restore-Environment {
    foreach ($entry in @([Environment]::GetEnvironmentVariables('Process').GetEnumerator())) {
        if (-not $savedEnvironment.ContainsKey($entry.Key)) { [Environment]::SetEnvironmentVariable($entry.Key, $null, 'Process') }
    }
    foreach ($entry in $savedEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}

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

# Compiler and test scratch stays inside the repo (AGENTS.md rule 9).
$scratch = Join-Path $repo 'out\tmp'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

Push-Location $repo
try {
    Enter-VsDevEnv
    $env:TEMP = $scratch
    $env:TMP = $scratch
    Invoke-Tool 'CMake configure' cmake @('--preset', $preset)
    Invoke-Tool 'Build' cmake @('--build', '--preset', $preset)
    if (-not $NoTests) {
        Invoke-Tool 'Tests' ctest @('--preset', $preset)
    }
} finally {
    Pop-Location
    Restore-Environment
}
Write-Host "Build $preset OK: $(Join-Path $repo "out\build\$preset")"
