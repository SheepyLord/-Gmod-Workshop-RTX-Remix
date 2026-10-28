<# .SYNOPSIS Tests tools\uninstall-loader.ps1 end to end in synthetic game folders. #>
[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Repo,
    [ValidateSet('Debug', 'Release')] [string] $Config,
    [Parameter(Mandatory)] [string] $Python,
    [Parameter(Mandatory)] [string] $Scratch)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $Repo 'tools\install-loader.ps1'
$uninstaller = Join-Path $Repo 'tools\uninstall-loader.ps1'
$nlctl = Join-Path $Repo "out\build\win64-$($Config.ToLowerInvariant())\loader\cli\nlctl.exe"
$gmapack = Join-Path $Repo 'tools\gmapack\gmapack.py'
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
function Write-Utf8([string] $Path, [string] $Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
# Every file (path, size, time) and folder below a game folder.
function Get-Tree([string] $Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length + 1)
        if ($_.PSIsContainer) { "D $rel" } else { "F $rel $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    } | Sort-Object
}
function New-Game([string] $Path) {
    Write-Utf8 (Join-Path $Path 'bin\win64\gmod.exe') 'synthetic root; never executed'
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'garrysmod\cfg') | Out-Null
    return $Path
}
# Bootstrap, an allowlisted package with a payload and a root file, and its deployment.
function Install-All([string] $Game, [string] $Gma, [switch] $AllowSteamManaged) {
    & $installer -GameRoot $Game -Config $Config -AllowSteamManaged:$AllowSteamManaged
    Write-Utf8 (Join-Path $Game 'native-loader\config.json') ('{"schema": 1, "allow": {"local": ["' + $Gma.Replace('\', '/') + '"]}}')
    $report = (& $nlctl apply $Game --json --steam-dir (Join-Path $Scratch 'no-steam')) -join "`n" | ConvertFrom-Json
    Check ($report.outcome -eq 'deployed') "apply: $($report.outcome) $($report.error)"
}

if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
try {
    $package = Join-Path $Scratch 'package'
    $files = [ordered]@{ 'native/payload/config/u.conf' = "u = 1`n"; 'native/root/rtx-remix/mods/u/mod.usda' = "#usda 1.0`n" }
    $listed = @()
    foreach ($rel in $files.Keys) {
        $path = Join-Path $package $rel
        Write-Utf8 $path $files[$rel]
        $listed += '"' + $rel + '": {"size": ' + (Get-Item -LiteralPath $path).Length + ', "sha256": "' + (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() + '"}'
    }
    Write-Utf8 (Join-Path $package 'native\manifest.json') ('{"schema": 1, "id": "u", "version": "1.0.0", "kinds": ["root-files"], "files": {' + ($listed -join ', ') + '}, "root_files": [{"path": "rtx-remix/mods/u"}]}')
    Write-Utf8 (Join-Path $package 'addon.json') '{"title": "u", "type": "servercontent", "tags": []}'
    $gma = Join-Path $Scratch 'u.gma'
    & $Python -I -B $gmapack create --folder $package --out $gma --quiet
    Check ($LASTEXITCODE -eq 0) 'gmapack failed'

    $game = New-Game (Join-Path $Scratch 'game')
    $original = Get-Tree $game
    $dll = Join-Path $game 'bin\win64\winmm.dll'
    $mod = Join-Path $game 'rtx-remix\mods\u\mod.usda'
    $state = Join-Path $game 'native-loader'
    Install-All $game $gma
    Check (Test-Path -LiteralPath $mod) 'apply did not place mod.usda'

    # -WhatIf: checks and a dry run only.
    & $uninstaller -GameRoot $game -Config $Config -WhatIf | Out-Null
    Check ((Test-Path -LiteralPath $mod) -and (Test-Path -LiteralPath $dll)) 'WhatIf removed something'

    # An edited bootstrap stops the uninstall before any deployed file is removed.
    $bytes = [IO.File]::ReadAllBytes($dll)
    [IO.File]::WriteAllBytes($dll, [byte[]]($bytes + [byte[]]@(0)))
    Refuses { & $uninstaller -GameRoot $game -Config $Config } 'changed or untracked'
    Check ((Test-Path -LiteralPath $mod) -and (Test-Path -LiteralPath (Join-Path $state 'state.json'))) 'deployed files were removed before the refusal'
    [IO.File]::WriteAllBytes($dll, $bytes)

    # Default: everything the loader deployed and the bootstrap go; config.json stays.
    & $uninstaller -GameRoot $game -Config $Config
    Check (-not (Test-Path -LiteralPath $mod) -and -not (Test-Path -LiteralPath (Join-Path $game 'rtx-remix'))) 'deployed files left'
    Check (-not (Test-Path -LiteralPath $dll)) 'bootstrap left'
    Check (-not (Test-Path -LiteralPath (Join-Path $state 'state.json')) -and -not (Test-Path -LiteralPath (Join-Path $state 'lock'))) 'journal or lock left'
    Check (Test-Path -LiteralPath (Join-Path $state 'config.json')) 'config.json was removed without -RemoveConfig'

    # -RemoveConfig: the game folder is exactly as it was.
    Install-All $game $gma
    & $uninstaller -GameRoot $game -Config $Config -RemoveConfig
    $diff = @(Compare-Object -ReferenceObject $original -DifferenceObject (Get-Tree $game))
    Check ($diff.Count -eq 0) "-RemoveConfig left differences: $(($diff | ForEach-Object { $_.SideIndicator + ' ' + $_.InputObject }) -join '; ')"

    # A folder Steam manages needs -AllowSteamManaged, and nothing is removed without it.
    $managed = New-Game (Join-Path $Scratch 'steamapps\common\Managed')
    Write-Utf8 (Join-Path $Scratch 'steamapps\appmanifest_4000.acf') '"AppState" { "installdir" "Managed" }'
    Install-All $managed $gma -AllowSteamManaged
    Refuses { & $uninstaller -GameRoot $managed -Config $Config } 'Steam manages'
    Check (Test-Path -LiteralPath (Join-Path $managed 'rtx-remix\mods\u\mod.usda')) 'removed files from a Steam-managed folder without -AllowSteamManaged'
    & $uninstaller -GameRoot $managed -Config $Config -AllowSteamManaged -RemoveConfig
    Check (-not (Test-Path -LiteralPath (Join-Path $managed 'native-loader')) -and -not (Test-Path -LiteralPath (Join-Path $managed 'rtx-remix'))) 'managed uninstall left files'
    Write-Host "uninstall-loader OK: $script:checks checks (synthetic roots only)."
} finally {
    if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
}
