<#
.SYNOPSIS
Runs the CI build workflow (.github/workflows/build.yml) on this machine: the Release checks, then the
end-user bundle in out\dist. -Install also puts the fresh build into a game, for a quick field test.
#>
[CmdletBinding()]
param(
    [switch] $SkipTests,
    [string] $Install,
    [switch] $AllowSteamManaged,
    [switch] $ReplaceUntracked
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$started = Get-Date
if (($AllowSteamManaged -or $ReplaceUntracked) -and -not $Install) { throw '-AllowSteamManaged and -ReplaceUntracked go with -Install.' }

# The same steps as the workflow's build job, in its order.
$global:LASTEXITCODE = 0
if ($SkipTests) {
    Write-Host '==> Release build without tests (tools\build.ps1 -Config Release -NoTests)'
    & (Join-Path $PSScriptRoot 'build.ps1') -Config Release -NoTests
} else {
    Write-Host '==> conventions, Release build, CTest and Python tests (tools\test.ps1 -Config Release)'
    & (Join-Path $PSScriptRoot 'test.ps1') -Config Release
}
if ($LASTEXITCODE) { throw "The checks failed (exit code $LASTEXITCODE); no bundle was made." }

Write-Host '==> end-user bundle (tools\package_loader.py)'
$output = & python (Join-Path $PSScriptRoot 'package_loader.py') --config Release --out (Join-Path $repo 'out\dist') --json
if ($LASTEXITCODE) { throw "package_loader.py failed (exit code $LASTEXITCODE)." }
$summary = ($output -join "`n") | ConvertFrom-Json
Write-Host "Bundle:  $($summary.bundle)"
if ($summary.symbols) { Write-Host "Symbols: $($summary.symbols)" }

if ($Install) {
    # install-loader.ps1 copies the same build the bundle holds, records it, and keeps every refusal
    # (a foreign or edited winmm.dll, a Steam-managed install without -AllowSteamManaged).
    Write-Host "==> install into $Install (tools\install-loader.ps1 -DefaultConfig)"
    & (Join-Path $PSScriptRoot 'install-loader.ps1') -GameRoot $Install -Config Release -DefaultConfig `
        -AllowSteamManaged:$AllowSteamManaged -ReplaceUntracked:$ReplaceUntracked
}
Write-Host ('Done in {0:N0} s.' -f ((Get-Date) - $started).TotalSeconds)
