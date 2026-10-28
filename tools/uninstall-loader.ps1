<#
.SYNOPSIS
Removes the native loader from an x64 GMod install: everything it deployed (nlctl uninstall), then the
bootstrap (install-loader.ps1 -Uninstall). Defaults to the PoC install.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $GameRoot = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC',
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Release',
    [switch] $RemoveConfig,
    [switch] $AllowSteamManaged
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$resolvedRoot = (Resolve-Path -LiteralPath $GameRoot).ProviderPath.TrimEnd('\', '/')
$nlctl = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\cli\nlctl.exe"
if (-not (Test-Path -LiteralPath $nlctl -PathType Leaf)) { throw "Build nlctl first: tools\build.ps1 -Config $Config" }
$installer = Join-Path $PSScriptRoot 'install-loader.ps1'
$installerArgs = @{ GameRoot = $resolvedRoot; Config = $Config; AllowSteamManaged = $AllowSteamManaged; Uninstall = $true; RemoveState = $RemoveConfig }

# The installer's checks first (an x64 install, the Steam-managed guard, the bootstrap is ours and
# unedited), so nothing is removed from an install the bootstrap step would then refuse.
& $installer @installerArgs -WhatIf

if (-not $PSCmdlet.ShouldProcess($resolvedRoot, 'Remove everything the native loader deployed, then its bootstrap')) {
    & $nlctl uninstall $resolvedRoot --dry-run
    return
}
& $nlctl uninstall $resolvedRoot
if ($LASTEXITCODE -ne 0) { throw "nlctl uninstall exited $LASTEXITCODE; the bootstrap was left in place" }
& $installer @installerArgs
Write-Host "Native loader removed from $resolvedRoot (config.json $(if ($RemoveConfig) { 'removed' } else { 'kept' }))"
