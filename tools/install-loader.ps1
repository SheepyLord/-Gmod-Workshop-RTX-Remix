<#
.SYNOPSIS
Installs or removes the identified M1 bootstrap, defaulting to the PoC install.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $GameRoot = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC',
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Release',
    [switch] $Uninstall,
    [switch] $RemoveState,
    [switch] $AllowSteamManaged,
    [switch] $DefaultConfig,
    [switch] $ReplaceUntracked
)
$ErrorActionPreference = 'Stop'
if ($RemoveState -and -not $Uninstall) { throw '-RemoveState requires -Uninstall.' }
if ($DefaultConfig -and $Uninstall) { throw '-DefaultConfig installs; it does not go with -Uninstall.' }
if ($ReplaceUntracked -and $Uninstall) { throw '-ReplaceUntracked installs; it does not go with -Uninstall.' }
$repo = Split-Path -Parent $PSScriptRoot
$resolvedRoot = (Resolve-Path -LiteralPath $GameRoot).ProviderPath.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot 'bin\win64\gmod.exe') -PathType Leaf)) {
    throw "Not an x64 GMod install: $resolvedRoot"
}
$targetDir = Join-Path $resolvedRoot 'bin\win64'
$stateDir = Join-Path $resolvedRoot 'native-loader'
$receiptPath = Join-Path $stateDir 'bootstrap-install.json'
$replacedDir = Join-Path $stateDir 'replaced'
$dllPath = Join-Path $targetDir 'winmm.dll'
$pdbPath = Join-Path $targetDir 'winmm.pdb'
$sourceDir = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\proxy"
$sourceDll = Join-Path $sourceDir 'winmm.dll'
$sourcePdb = Join-Path $sourceDir 'winmm.pdb'

function Assert-OrdinaryPath([string] $Path) {
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing a reparse point: $Path"
    }
}
foreach ($path in @($resolvedRoot, (Join-Path $resolvedRoot 'bin'), $targetDir, $stateDir, $receiptPath, $dllPath, $pdbPath, $replacedDir,
                    (Join-Path $replacedDir 'winmm.dll'), (Join-Path $replacedDir 'winmm.pdb'))) {
    Assert-OrdinaryPath $path
}
if ((Test-Path -LiteralPath $stateDir) -and -not (Test-Path -LiteralPath $stateDir -PathType Container)) {
    throw "Loader state path is not a directory: $stateDir"
}

# Only the manifests of this library are consulted; no Steam files are changed.
$rootInfo = Get-Item -LiteralPath $resolvedRoot
if ($rootInfo.Parent.Name -ieq 'common' -and $rootInfo.Parent.Parent.Name -ieq 'steamapps') {
    foreach ($manifest in Get-ChildItem -LiteralPath $rootInfo.Parent.Parent.FullName -Filter 'appmanifest_*.acf' -File) {
        $text = [IO.File]::ReadAllText($manifest.FullName)
        if ($text -match '"installdir"\s+"([^"\r\n]+)"' -and $Matches[1] -ieq $rootInfo.Name -and -not $AllowSteamManaged) {
            throw "Steam manages '$resolvedRoot' ($($manifest.Name)); explicit -AllowSteamManaged is required."
        }
    }
}

function Test-LoaderIdentity([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    return $version.OriginalFilename -ceq 'nl_winmm.dll' -and
        $version.InternalName -ceq 'nl_winmm.dll' -and $version.ProductName -ceq 'GMod Native Loader'
}
function Get-HashOrNull([string] $Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return $null
}
$receipt = $null
if (Test-Path -LiteralPath $receiptPath) {
    $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
    if ($receipt.schema -ne 1) { throw 'Unsupported bootstrap install receipt.' }
}
if (Test-Path -LiteralPath $dllPath) {
    if (-not (Test-LoaderIdentity $dllPath)) { throw "Refusing foreign winmm.dll: $dllPath" }
}
function Assert-Unedited([string] $Path, [string] $RecordedHash, [string] $BuildPath) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $actual = Get-HashOrNull $Path
    $expected = if ($RecordedHash) { $RecordedHash } else { Get-HashOrNull $BuildPath }
    if (-not $actual -or -not $expected -or $actual -cne $expected) {
        throw "Refusing to overwrite/remove a changed or untracked file: $Path (no matching recorded/build SHA-256)."
    }
}
$knownDllHash = if ($receipt) { $receipt.dll_sha256 } else { $null }
$knownPdbHash = if ($receipt) { $receipt.pdb_sha256 } else { $null }
# -ReplaceUntracked: a loader no receipt records, such as a release bundle extracted by hand. Its DLL
# passed the identity check above; both files are copied to native-loader\replaced before the install.
$replaceUntracked = $ReplaceUntracked -and -not $receipt -and ((Test-Path -LiteralPath $dllPath) -or (Test-Path -LiteralPath $pdbPath))
if (-not $replaceUntracked) {
    Assert-Unedited $dllPath $knownDllHash $sourceDll
    Assert-Unedited $pdbPath $knownPdbHash $sourcePdb
}

if ($Uninstall) {
    # Check the complete deletion target before removing even the first file.
    if ($RemoveState -and (Test-Path -LiteralPath $stateDir)) {
        $deleteTarget = [IO.Path]::GetFullPath($stateDir)
        $expectedTarget = $resolvedRoot + [IO.Path]::DirectorySeparatorChar + 'native-loader'
        if (-not [string]::Equals($deleteTarget, $expectedTarget, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe state removal target.' }
        foreach ($entry in Get-ChildItem -LiteralPath $deleteTarget -Recurse -Force) { Assert-OrdinaryPath $entry.FullName }
    }
    if (-not $PSCmdlet.ShouldProcess($resolvedRoot, 'Uninstall verified native loader bootstrap')) { return }
    if (Test-Path -LiteralPath $dllPath) { Remove-Item -LiteralPath $dllPath -Force }
    if (Test-Path -LiteralPath $pdbPath) { Remove-Item -LiteralPath $pdbPath -Force }
    if ($RemoveState -and (Test-Path -LiteralPath $stateDir)) {
        # Only the loader's own control and log files, then the folders left empty (R1-014). Anything
        # else stays: a payload file the user changed (nlctl uninstall leaves those in place), or a
        # journal nlctl uninstall had to keep because it could not remove everything yet.
        $own = @('config.json', 'bootstrap-install.json', 'disable', 'session_cvars.json', 'logs\loader.log',
                 'replaced\winmm.dll', 'replaced\winmm.pdb') + @(1..5 | ForEach-Object { "logs\loader.log.$_" })
        foreach ($name in $own) {
            $path = Join-Path $deleteTarget $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
        Get-ChildItem -LiteralPath $deleteTarget -Recurse -Force -Directory | Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        $kept = @(Get-ChildItem -LiteralPath $deleteTarget -Recurse -Force -File)
        if ($kept.Count) {
            Write-Warning ("Kept in ${deleteTarget}: files the loader did not create, or that changed after it placed them:`n  " +
                           (($kept | ForEach-Object { $_.FullName.Substring($deleteTarget.Length + 1) }) -join "`n  "))
        } elseif (-not (Get-ChildItem -LiteralPath $deleteTarget -Force)) {
            Remove-Item -LiteralPath $deleteTarget
        }
    }
    Write-Host "Bootstrap uninstalled: $resolvedRoot (state retained: $(-not $RemoveState))"
    return
}

if (-not (Test-LoaderIdentity $sourceDll) -or -not (Test-Path -LiteralPath $sourcePdb -PathType Leaf)) {
    throw "Build the $Config bootstrap first: tools\build.ps1 -Config $Config"
}
if (-not $PSCmdlet.ShouldProcess($resolvedRoot, "Install $Config native loader bootstrap")) { return }
$oldDll = if (Test-Path -LiteralPath $dllPath) { [IO.File]::ReadAllBytes($dllPath) } else { $null }
$oldPdb = if (Test-Path -LiteralPath $pdbPath) { [IO.File]::ReadAllBytes($pdbPath) } else { $null }
$oldReceipt = if (Test-Path -LiteralPath $receiptPath) { [IO.File]::ReadAllBytes($receiptPath) } else { $null }
$hadState = Test-Path -LiteralPath $stateDir
try {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    if ($replaceUntracked) {
        New-Item -ItemType Directory -Path $replacedDir -Force | Out-Null
        foreach ($saved in @(@($dllPath, $oldDll), @($pdbPath, $oldPdb))) {
            if ($null -ne $saved[1]) { [IO.File]::WriteAllBytes((Join-Path $replacedDir (Split-Path -Leaf $saved[0])), [byte[]] $saved[1]) }
        }
        Write-Host "Kept the untracked loader files in $replacedDir"
    }
    Copy-Item -LiteralPath $sourceDll -Destination $dllPath -Force
    Copy-Item -LiteralPath $sourcePdb -Destination $pdbPath -Force
    $newReceipt = [ordered]@{schema=1; version=([Diagnostics.FileVersionInfo]::GetVersionInfo($sourceDll)).FileVersion;
        dll_sha256=(Get-HashOrNull $dllPath); pdb_sha256=(Get-HashOrNull $pdbPath); installed_utc=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($receiptPath, ($newReceipt | ConvertTo-Json) + "`n", [Text.UTF8Encoding]::new($false))
} catch {
    # Roll back only the three exact paths this invocation owns.
    foreach ($saved in @(@($dllPath, $oldDll), @($pdbPath, $oldPdb), @($receiptPath, $oldReceipt))) {
        if ($null -ne $saved[1]) { [IO.File]::WriteAllBytes($saved[0], [byte[]] $saved[1]) }
        elseif (Test-Path -LiteralPath $saved[0]) { Remove-Item -LiteralPath $saved[0] -Force }
    }
    if (-not $hadState -and (Test-Path -LiteralPath $stateDir) -and -not (Get-ChildItem -LiteralPath $stateDir -Force)) {
        Remove-Item -LiteralPath $stateDir
    }
    throw
}
Write-Host "Bootstrap installed ($Config): $dllPath"

# The release bundle's settings (ADR 0017): allow the project's Workshop item. Only when the install
# has no config.json yet; an existing one is the user's and is never replaced.
if ($DefaultConfig) {
    $configPath = Join-Path $stateDir 'config.json'
    Assert-OrdinaryPath $configPath
    if (Test-Path -LiteralPath $configPath) {
        Write-Host "Kept the existing $configPath"
    } else {
        Copy-Item -LiteralPath (Join-Path $repo 'dist\native-loader\config.json') -Destination $configPath
        Write-Host "Default settings written: $configPath (allows Workshop item 3829070317)"
    }
}
