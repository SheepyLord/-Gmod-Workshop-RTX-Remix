<# .SYNOPSIS Tests installer ownership, hashes, Steam protection and uninstall in synthetic roots. #>
[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Repo,
    [ValidateSet('Debug', 'Release')] [string] $Config)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $Repo 'tools\install-loader.ps1'
$sourceDll = Join-Path $Repo "out\build\win64-$($Config.ToLowerInvariant())\loader\proxy\winmm.dll"
$scratchBase = [IO.Path]::GetFullPath((Join-Path $Repo 'out\installer-tests'))
$scratch = Join-Path $scratchBase ([Guid]::NewGuid().ToString('N'))
$script:checks = 0
function Check([bool] $Value, [string] $Message) {
    if (-not $Value) { throw $Message }
    $script:checks++
}
function Refuses([scriptblock] $Action, [string] $Expected) {
    try { & $Action } catch {
        Check ($_.Exception.Message -like "*$Expected*") "Wrong refusal: $($_.Exception.Message)"
        return
    }
    throw "Expected refusal containing: $Expected"
}
function Make-Game([string] $Path) {
    New-Item -ItemType Directory -Path (Join-Path $Path 'bin\win64') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Path 'bin\win64\gmod.exe'), 'synthetic root; never executed')
    return $Path
}
try {
    $game = Make-Game (Join-Path $scratch 'poc')
    $dll = Join-Path $game 'bin\win64\winmm.dll'
    $pdb = Join-Path $game 'bin\win64\winmm.pdb'
    $state = Join-Path $game 'native-loader'
    & $installer -GameRoot $game -Config $Config -WhatIf
    Check (-not (Test-Path -LiteralPath $dll)) 'WhatIf wrote a DLL.'
    Check (-not (Test-Path -LiteralPath $state)) 'WhatIf wrote state.'
    & $installer -GameRoot $game -Config $Config
    Check ((Get-FileHash -LiteralPath $dll).Hash -ceq (Get-FileHash -LiteralPath $sourceDll).Hash) 'Installed bytes differ.'
    Check (Test-Path -LiteralPath $pdb) 'PDB missing.'
    Check (Test-Path -LiteralPath (Join-Path $state 'bootstrap-install.json')) 'Receipt missing.'
    & $installer -GameRoot $game -Config $Config
    [IO.File]::WriteAllText((Join-Path $state 'keep.txt'), 'user state')
    $original = [IO.File]::ReadAllBytes($dll)
    $changed = [byte[]]::new($original.Length + 1)
    [Array]::Copy($original, $changed, $original.Length)
    [IO.File]::WriteAllBytes($dll, $changed)
    Refuses { & $installer -GameRoot $game -Config $Config } 'changed or untracked'
    Refuses { & $installer -GameRoot $game -Config $Config -Uninstall } 'changed or untracked'
    Check ((Get-Item -LiteralPath $dll).Length -eq $changed.Length) 'Changed DLL was modified.'
    [IO.File]::WriteAllBytes($dll, $original)
    & $installer -GameRoot $game -Config $Config -Uninstall
    Check (-not (Test-Path -LiteralPath $dll) -and -not (Test-Path -LiteralPath $pdb)) 'Uninstall left bootstrap files.'
    Check (Test-Path -LiteralPath (Join-Path $state 'keep.txt')) 'Default uninstall deleted state.'
    # -RemoveState deletes the loader's own files only; a file it did not create stays (R1-014).
    & $installer -GameRoot $game -Config $Config -Uninstall -RemoveState 3>$null
    Check (-not (Test-Path -LiteralPath (Join-Path $state 'bootstrap-install.json'))) 'RemoveState left the receipt.'
    Check ([IO.File]::ReadAllText((Join-Path $state 'keep.txt')) -ceq 'user state') 'RemoveState deleted a file the loader did not create.'
    Remove-Item -LiteralPath (Join-Path $state 'keep.txt')
    & $installer -GameRoot $game -Config $Config -Uninstall -RemoveState
    Check (-not (Test-Path -LiteralPath $state)) 'RemoveState left an empty state folder.'
    [IO.File]::WriteAllText($dll, 'foreign DLL')
    Refuses { & $installer -GameRoot $game -Config $Config -AllowSteamManaged } 'foreign winmm.dll'
    Refuses { & $installer -GameRoot $game -Config $Config -Uninstall } 'foreign winmm.dll'
    Check ([IO.File]::ReadAllText($dll) -ceq 'foreign DLL') 'Foreign DLL changed.'
    Remove-Item -LiteralPath $dll
    [IO.File]::WriteAllText($pdb, 'foreign PDB')
    Refuses { & $installer -GameRoot $game -Config $Config } 'changed or untracked'
    Check ([IO.File]::ReadAllText($pdb) -ceq 'foreign PDB') 'Foreign PDB changed.'
    $invalidState = Make-Game (Join-Path $scratch 'invalid-state')
    [IO.File]::WriteAllText((Join-Path $invalidState 'native-loader'), 'user file')
    Refuses { & $installer -GameRoot $invalidState -Config $Config -WhatIf } 'state path is not a directory'
    Check ([IO.File]::ReadAllText((Join-Path $invalidState 'native-loader')) -ceq 'user file') 'Invalid state path changed.'
    $managed = Make-Game (Join-Path $scratch 'steamapps\common\Managed')
    [IO.File]::WriteAllText((Join-Path $scratch 'steamapps\appmanifest_4000.acf'), '"AppState" { "installdir" "mAnAgEd" }')
    Refuses { & $installer -GameRoot $managed -Config $Config } 'Steam manages'
    Refuses { & $installer -GameRoot $managed -Config $Config -Uninstall } 'Steam manages'
    & $installer -GameRoot $managed -Config $Config -AllowSteamManaged
    Check (Test-Path -LiteralPath (Join-Path $managed 'bin\win64\winmm.dll')) 'Explicit managed install failed.'
    & $installer -GameRoot $managed -Config $Config -AllowSteamManaged -Uninstall -RemoveState
    Check (-not (Test-Path -LiteralPath (Join-Path $managed 'native-loader'))) 'Managed cleanup failed.'
    Refuses { & $installer -GameRoot $game -RemoveState } 'requires -Uninstall'
    # -DefaultConfig writes the release bundle's config.json, never over an existing one (ADR 0017).
    $configured = Make-Game (Join-Path $scratch 'configured')
    & $installer -GameRoot $configured -Config $Config -DefaultConfig
    $shipped = [IO.File]::ReadAllText((Join-Path $Repo 'dist\native-loader\config.json'))
    $configFile = Join-Path $configured 'native-loader\config.json'
    Check ([IO.File]::ReadAllText($configFile) -ceq $shipped) 'DefaultConfig did not write the shipped config.json.'
    [IO.File]::WriteAllText($configFile, '{"schema": 1, "allow": {"local": ["mine.gma"]}}')
    & $installer -GameRoot $configured -Config $Config -DefaultConfig
    Check ([IO.File]::ReadAllText($configFile) -ceq '{"schema": 1, "allow": {"local": ["mine.gma"]}}') 'DefaultConfig replaced the user''s config.json.'
    Refuses { & $installer -GameRoot $configured -Config $Config -Uninstall -DefaultConfig } 'does not go with -Uninstall'
    Write-Host "Installer OK: $script:checks checks (synthetic roots only)."
} finally {
    $deleteTarget = [IO.Path]::GetFullPath($scratch)
    if (-not $deleteTarget.StartsWith($scratchBase + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe scratch cleanup target.' }
    if (Test-Path -LiteralPath $deleteTarget) { Remove-Item -LiteralPath $deleteTarget -Recurse -Force }
}
