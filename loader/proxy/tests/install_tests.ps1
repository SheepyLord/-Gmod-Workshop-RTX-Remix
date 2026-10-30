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
    # A foreign winmm.dll (another mod's DLL loader) is kept with its .pdb and put back by -Uninstall (ADR 0035).
    [IO.File]::WriteAllText($dll, 'foreign DLL')
    [IO.File]::WriteAllText($pdb, 'foreign PDB')
    Refuses { & $installer -GameRoot $game -Config $Config -Uninstall } 'foreign winmm.dll'
    Check ([IO.File]::ReadAllText($dll) -ceq 'foreign DLL') 'A refused uninstall changed the foreign DLL.'
    & $installer -GameRoot $game -Config $Config
    Check ((Get-FileHash -LiteralPath $dll).Hash -ceq (Get-FileHash -LiteralPath $sourceDll).Hash) 'Not installed over a foreign DLL.'
    Check ([IO.File]::ReadAllText((Join-Path $state 'original\winmm.dll')) -ceq 'foreign DLL') 'The foreign DLL was not kept.'
    Check ([IO.File]::ReadAllText((Join-Path $state 'original\winmm.pdb')) -ceq 'foreign PDB') 'The foreign PDB was not kept.'
    & $installer -GameRoot $game -Config $Config  # an update keeps the original and its record
    $kept = ([IO.File]::ReadAllText((Join-Path $state 'bootstrap-install.json')) | ConvertFrom-Json).original
    Check ($kept -and $kept.dll_sha256 -and $kept.pdb_sha256) 'An update dropped the record of the kept original.'
    & $installer -GameRoot $game -Config $Config -Uninstall -RemoveState
    Check ([IO.File]::ReadAllText($dll) -ceq 'foreign DLL') 'Uninstall did not put the foreign DLL back.'
    Check ([IO.File]::ReadAllText($pdb) -ceq 'foreign PDB') 'Uninstall did not put the foreign PDB back.'
    Check (-not (Test-Path -LiteralPath $state)) 'RemoveState left state after putting the original back.'
    Remove-Item -LiteralPath $dll
    Remove-Item -LiteralPath $pdb
    # Only the first one is kept: another foreign DLL in the loader's place is refused, nothing moved.
    $twice = Make-Game (Join-Path $scratch 'twice')
    $twiceDll = Join-Path $twice 'bin\win64\winmm.dll'
    [IO.File]::WriteAllText($twiceDll, 'first loader')
    & $installer -GameRoot $twice -Config $Config
    [IO.File]::WriteAllText($twiceDll, 'second loader')
    Refuses { & $installer -GameRoot $twice -Config $Config } 'already keeps'
    Check ([IO.File]::ReadAllText($twiceDll) -ceq 'second loader') 'A refused install changed the DLL.'
    Check ([IO.File]::ReadAllText((Join-Path $twice 'native-loader\original\winmm.dll')) -ceq 'first loader') 'The kept original changed.'
    # A DLL put over the installed loader is kept by the next install; the loader's own .pdb left beside
    # it is not part of it.
    $over = Make-Game (Join-Path $scratch 'over')
    $overDll = Join-Path $over 'bin\win64\winmm.dll'
    & $installer -GameRoot $over -Config $Config
    [IO.File]::WriteAllText($overDll, 'later loader')
    & $installer -GameRoot $over -Config $Config
    Check ([IO.File]::ReadAllText((Join-Path $over 'native-loader\original\winmm.dll')) -ceq 'later loader') 'A DLL put over the loader was not kept.'
    Check (-not (Test-Path -LiteralPath (Join-Path $over 'native-loader\original\winmm.pdb'))) 'The loader''s own PDB was kept as the original''s.'
    & $installer -GameRoot $over -Config $Config -Uninstall
    Check ([IO.File]::ReadAllText($overDll) -ceq 'later loader') 'Uninstall did not put the later DLL back.'
    Check (-not (Test-Path -LiteralPath (Join-Path $over 'bin\win64\winmm.pdb'))) 'Uninstall left the loader''s PDB.'
    & $installer -GameRoot $over -Config $Config  # kept again, and recorded again: the receipt kept by -Uninstall is stale
    $again = ([IO.File]::ReadAllText((Join-Path $over 'native-loader\bootstrap-install.json')) | ConvertFrom-Json).original
    Check ($again.dll_sha256 -and -not $again.pdb_sha256) 'A second install over a restored original recorded it wrongly.'
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
    # -ReplaceUntracked replaces a loader no receipt records (a bundle extracted by hand), keeping a copy.
    $byHand = Make-Game (Join-Path $scratch 'by-hand')
    $handDll = Join-Path $byHand 'bin\win64\winmm.dll'
    [IO.File]::WriteAllBytes($handDll, $changed)  # the loader's identity, not this build's bytes
    Refuses { & $installer -GameRoot $byHand -Config $Config } 'changed or untracked'
    & $installer -GameRoot $byHand -Config $Config -ReplaceUntracked
    Check ((Get-FileHash -LiteralPath $handDll).Hash -ceq (Get-FileHash -LiteralPath $sourceDll).Hash) 'ReplaceUntracked did not install the build.'
    Check ((Get-Item -LiteralPath (Join-Path $byHand 'native-loader\replaced\winmm.dll')).Length -eq $changed.Length) 'ReplaceUntracked kept no copy.'
    [IO.File]::WriteAllBytes($handDll, $changed)  # now a receipt records the build: a changed DLL stays refused
    Refuses { & $installer -GameRoot $byHand -Config $Config -ReplaceUntracked } 'changed or untracked'
    Check ((Get-Item -LiteralPath $handDll).Length -eq $changed.Length) 'ReplaceUntracked overwrote a changed tracked DLL.'
    Refuses { & $installer -GameRoot $byHand -Config $Config -Uninstall -ReplaceUntracked } 'does not go with -Uninstall'
    [IO.File]::WriteAllText($handDll, 'foreign DLL')  # foreign is foreign, whatever the switch: kept as the original
    & $installer -GameRoot $byHand -Config $Config -ReplaceUntracked
    Check ([IO.File]::ReadAllText((Join-Path $byHand 'native-loader\original\winmm.dll')) -ceq 'foreign DLL') 'ReplaceUntracked did not keep a foreign DLL.'
    Write-Host "Installer OK: $script:checks checks (synthetic roots only)."
} finally {
    $deleteTarget = [IO.Path]::GetFullPath($scratch)
    if (-not $deleteTarget.StartsWith($scratchBase + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe scratch cleanup target.' }
    if (Test-Path -LiteralPath $deleteTarget) { Remove-Item -LiteralPath $deleteTarget -Recurse -Force }
}
