<#
.SYNOPSIS
Runs every check in the repo: documentation conventions, Python tool tests, C++ build and tests.

.DESCRIPTION
Run this before finishing any change. Each tools\**\tests folder is run from its parent
folder with "python -m unittest discover -s tests", so tests import the scripts beside them.

.EXAMPLE
tools\test.ps1
tools\test.ps1 -SkipNative         # Python and convention checks only
tools\test.ps1 -Config Release
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Debug',
    [switch] $SkipNative
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$failed = [System.Collections.Generic.List[string]]::new()

function Invoke-Step([string] $Name, [scriptblock] $Body) {
    Write-Host "==> $Name" -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'   # native tools signal failure through exit codes
    $global:LASTEXITCODE = 0
    try {
        & $Body
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    } catch {
        Write-Host "FAILED: $Name ($_)" -ForegroundColor Red
        $failed.Add($Name)
    }
}

Invoke-Step 'repo conventions (tools\check_repo.py)' { python (Join-Path $repo 'tools\check_repo.py') }

$testDirs = Get-ChildItem (Join-Path $repo 'tools') -Recurse -Directory -Filter tests |
    Where-Object { $_.FullName -notmatch '\\(__pycache__|out|build)\\' } | Sort-Object FullName
foreach ($dir in $testDirs) {
    $group = $dir.Parent.FullName
    Invoke-Step "python tests ($($group.Substring($repo.Length + 1)))" {
        Push-Location $group
        try { python -m unittest discover -s tests -q } finally { Pop-Location }
    }
}

if (-not $SkipNative) {
    Invoke-Step "C++ build and tests ($Config)" { & (Join-Path $PSScriptRoot 'build.ps1') -Config $Config }
}

if ($failed.Count) {
    Write-Host ("{0} step(s) failed: {1}" -f $failed.Count, ($failed -join '; ')) -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
