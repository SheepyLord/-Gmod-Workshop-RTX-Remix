<#
.SYNOPSIS
Compares baseline, enabled and disabled PoC launches and two console tools; restores loader state.
#>
[CmdletBinding()]
param(
    [string] $GameRoot = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC',
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Release',
    [ValidateRange(15, 600)] [int] $TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$resolvedRoot = (Resolve-Path -LiteralPath $GameRoot).ProviderPath.TrimEnd('\', '/')
$gameExe = Join-Path $resolvedRoot 'bin\win64\gmod.exe'
$consolePath = Join-Path $resolvedRoot 'garrysmod\console.log'
$loaderLog = Join-Path $resolvedRoot 'native-loader\logs\loader.log'
$disablePath = Join-Path $resolvedRoot 'native-loader\disable'
$install = Join-Path $PSScriptRoot 'install-loader.ps1'
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Steam must be running and logged in before the PoC smoke test.' }
if (Get-Process gmod -ErrorAction SilentlyContinue) { throw 'Close existing GMod processes before running the smoke test.' }
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw "Missing x64 GMod executable: $gameExe" }
# Both preflights perform every installer check, with no writes. Do not enter a
# restoring finally block after a refusal involving somebody else's DLL/install.
& $install -GameRoot $resolvedRoot -Config $Config -WhatIf
& $install -GameRoot $resolvedRoot -Config $Config -Uninstall -WhatIf
if (Test-Path -LiteralPath $disablePath -PathType Container) { throw 'The disable flag must be a regular file for a smoke test.' }

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$evidence = Join-Path $repo "out\smoke\$stamp"
$before = Join-Path $evidence 'before'
New-Item -ItemType Directory -Path $before -Force | Out-Null
$hadState = Test-Path -LiteralPath (Join-Path $resolvedRoot 'native-loader')
$hadData = Test-Path -LiteralPath (Join-Path $resolvedRoot 'garrysmod\data')
$paths = @('bin\win64\winmm.dll', 'bin\win64\winmm.pdb', 'native-loader\bootstrap-install.json',
    'native-loader\logs', 'native-loader\disable', 'garrysmod\data\native-loader', 'garrysmod\console.log')
$saved = @{}
$process = $null
$results = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{success=$false; game_root=$resolvedRoot; config=$Config; results=$results; error=$null; restored=$false}

function Assert-LocalPath([string] $Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped game root: $full" }
    if ((Test-Path -LiteralPath $full) -and ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing a reparse point: $full"
    }
}
function Read-SharedText([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Normalise-Console([string] $Text) {
    $lines = foreach ($line in ($Text -split '\r?\n')) {
        $trimmed = $line.TrimEnd()
        if ($trimmed -match '^Thumbs: \d+ => \d+$') { 'Thumbs: <variable allocation counts>' }
        elseif ($trimmed.Length) { $trimmed }
    }
    return $lines -join "`n"
}
function Stop-TestGame {
    if ($null -ne $script:process) {
        if (-not $script:process.HasExited) {
            $killer = [Diagnostics.ProcessStartInfo]::new('taskkill.exe', "/PID $($script:process.Id) /T /F")
            $killer.UseShellExecute = $false
            $killer.CreateNoWindow = $true
            $killer.RedirectStandardOutput = $true
            $killer.RedirectStandardError = $true
            $kill = [Diagnostics.Process]::Start($killer)
            $kill.WaitForExit(10000) | Out-Null
            $kill.Dispose()
            if (-not $script:process.WaitForExit(10000)) { throw 'The test game did not stop; state restoration would be unsafe.' }
        }
        $script:process.Dispose()
        $script:process = $null
    }
}
function Invoke-GameRun([string] $Name, [string] $Extra = '', [bool] $EnvironmentOff = $false, [bool] $ExpectLog = $false) {
    if (Test-Path -LiteralPath $consolePath) { Remove-Item -LiteralPath $consolePath -Force }
    if (Test-Path -LiteralPath $loaderLog) { Remove-Item -LiteralPath $loaderLog -Force }
    $arguments = '-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons +map gm_construct'
    if ($Extra) { $arguments += ' ' + $Extra }
    $start = [Diagnostics.ProcessStartInfo]::new($gameExe, $arguments)
    $start.WorkingDirectory = $resolvedRoot
    $start.UseShellExecute = $false
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables.Remove('NATIVE_LOADER_DISABLE')
    if ($EnvironmentOff) { $start.EnvironmentVariables['NATIVE_LOADER_DISABLE'] = '1' }
    Write-Host "Smoke: $Name (waiting for gm_construct client Lua startup)"
    $script:process = [Diagnostics.Process]::Start($start)
    $launchedProcessId = $script:process.Id
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $loaded = $false
    try {
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $text = Read-SharedText $consolePath
            if ($text -match '(?m)^Map: gm_construct\s*$' -and $text -match '(?m)^Clientside Lua startup!\s*$') {
                $loaded = $true
                # Allow the deterministic post-map joystick/lightmap messages to flush.
                Start-Sleep -Seconds 3
                break
            }
            if ($script:process.HasExited) { throw "Game exited before map load ($Name), exit $($script:process.ExitCode)." }
            Start-Sleep -Milliseconds 500
        }
        if (-not $loaded) { throw "Timed out waiting for gm_construct ($Name, ${TimeoutSeconds}s)." }
    } finally {
        Stop-TestGame
        if (Test-Path -LiteralPath $consolePath) { Copy-Item -LiteralPath $consolePath -Destination (Join-Path $evidence "$Name.console.log") }
        if (Test-Path -LiteralPath $loaderLog) { Copy-Item -LiteralPath $loaderLog -Destination (Join-Path $evidence "$Name.loader.log") }
    }
    $hasLog = Test-Path -LiteralPath $loaderLog
    if ($hasLog -ne $ExpectLog) { throw "Unexpected loader log presence for $Name (expected $ExpectLog; found $hasLog)." }
    if ($ExpectLog) {
        $log = Read-SharedText $loaderLog
        if ($log -notmatch '(?m)^process_id=(\d+)\r?$' -or [int]$Matches[1] -ne $launchedProcessId) {
            throw "The enabled loader log does not belong to the launched game process ($launchedProcessId)."
        }
        foreach ($proof in @('phase=exe_entry_point', 'entry_point_restored=1', 'module.engine.dll=0', 'module.shaderapidx9.dll=0', 'module.d3d9.dll=0', 'startup.complete=1')) {
            if (($log -split '\r?\n') -cnotcontains $proof) { throw "Missing loader proof: $proof" }
        }
        if ($log -notmatch '(?m)^exports.resolved=(\d+)\r?$') { throw 'No forwarding count in loader log.' }
        $resolvedCount = $Matches[1]
        if ($log -notmatch '(?m)^exports.total=(\d+)\r?$' -or $resolvedCount -ne $Matches[1]) { throw 'Not all winmm exports resolved.' }
    }
    $normal = Normalise-Console (Read-SharedText $consolePath)
    [IO.File]::WriteAllText((Join-Path $evidence "$Name.normalised.log"), $normal, [Text.UTF8Encoding]::new($false))
    $results.Add([ordered]@{name=$Name; process_id=$launchedProcessId; map_loaded=$loaded; loader_log=$hasLog; seconds=[Math]::Round($timer.Elapsed.TotalSeconds, 2)})
    return $normal
}
function Compare-Console([string] $Baseline, [string] $Actual, [string] $Name) {
    if ($Baseline -cne $Actual) {
        Compare-Object ($Baseline -split "`n") ($Actual -split "`n") -SyncWindow 0 |
            Out-String -Width 4096 | Set-Content -LiteralPath (Join-Path $evidence "$Name.diff.txt")
        throw "Unexplained console differences for $Name. Inspect $evidence; do not expand normalisation without investigating."
    }
}
function Invoke-ConsoleTool([string] $Name, [string] $Phase) {
    $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $resolvedRoot "bin\win64\$Name"))
    $start.WorkingDirectory = $resolvedRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables.Remove('NATIVE_LOADER_DISABLE')
    $tool = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $tool.StandardOutput.ReadToEndAsync()
        $stderr = $tool.StandardError.ReadToEndAsync()
        if (-not $tool.WaitForExit(15000)) { $tool.Kill(); $tool.WaitForExit(); throw "$Name did not exit by itself." }
        $result = [ordered]@{name=$Name; exit_code=$tool.ExitCode; stdout=$stdout.GetAwaiter().GetResult(); stderr=$stderr.GetAwaiter().GetResult()}
        $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence "$Phase.$Name.json")
        return ($result | ConvertTo-Json -Compress)
    } finally { $tool.Dispose() }
}

# Preflight the whole snapshot before changing any game-side files.
foreach ($relative in $paths) {
    $path = Join-Path $resolvedRoot $relative
    Assert-LocalPath $path
    if (Test-Path -LiteralPath $path -PathType Container) {
        foreach ($entry in Get-ChildItem -LiteralPath $path -Recurse -Force) { Assert-LocalPath $entry.FullName }
    }
    $saved[$relative] = Test-Path -LiteralPath $path
    if ($saved[$relative]) {
        $destination = Join-Path $before $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $path -Destination $destination -Recurse -Force
    }
}
try {
    & $install -GameRoot $resolvedRoot -Config $Config -Uninstall
    if (Test-Path -LiteralPath $disablePath) { Remove-Item -LiteralPath $disablePath -Force }
    $toolBaselines = @{}
    foreach ($name in @('vpk.exe', 'bspzip.exe')) { $toolBaselines[$name] = Invoke-ConsoleTool $name 'baseline' }
    $baseline = Invoke-GameRun 'baseline'
    & $install -GameRoot $resolvedRoot -Config $Config
    $enabled = Invoke-GameRun 'enabled' -ExpectLog $true
    Compare-Console $baseline $enabled 'enabled'
    Remove-Item -LiteralPath $loaderLog -Force
    foreach ($name in @('vpk.exe', 'bspzip.exe')) {
        $actual = Invoke-ConsoleTool $name 'enabled'
        if ($actual -cne $toolBaselines[$name]) { throw "Console tool changed with bootstrap: $name" }
        if (Test-Path -LiteralPath $loaderLog) { throw "Console tool activated the loader: $name" }
        $results.Add([ordered]@{name=$name; identical=$true; loader_log=$false})
    }
    Compare-Console $baseline (Invoke-GameRun 'off-command' -Extra '-nonativeloader') 'off-command'
    Compare-Console $baseline (Invoke-GameRun 'off-environment' -EnvironmentOff $true) 'off-environment'
    [IO.File]::WriteAllText($disablePath, '')
    Compare-Console $baseline (Invoke-GameRun 'off-file') 'off-file'
    $summary.success = $true
} catch {
    $summary.error = $_.Exception.Message
    throw
} finally {
    try {
        Stop-TestGame
        # Validate every absolute restoration/deletion target before removing it.
        foreach ($relative in $paths) {
            $path = Join-Path $resolvedRoot $relative
            Assert-LocalPath $path
            if (Test-Path -LiteralPath $path -PathType Container) {
                foreach ($entry in Get-ChildItem -LiteralPath $path -Recurse -Force) { Assert-LocalPath $entry.FullName }
            }
        }
        foreach ($relative in $paths) {
            $path = Join-Path $resolvedRoot $relative
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
            if ($saved[$relative]) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $before $relative) -Destination $path -Recurse -Force
            }
        }
        $statePath = Join-Path $resolvedRoot 'native-loader'
        if (-not $hadState -and (Test-Path -LiteralPath $statePath) -and -not (Get-ChildItem -LiteralPath $statePath -Force)) {
            Remove-Item -LiteralPath $statePath
        }
        $dataPath = Join-Path $resolvedRoot 'garrysmod\data'
        Assert-LocalPath $dataPath
        if (-not $hadData -and (Test-Path -LiteralPath $dataPath) -and -not (Get-ChildItem -LiteralPath $dataPath -Force)) {
            Remove-Item -LiteralPath $dataPath
        }
        $summary.restored = $true
    } finally {
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json')
        Write-Host "Smoke evidence: $evidence"
    }
}
Write-Host 'Smoke OK: five map loads; matching normalised console logs; all off switches; two identical, inert tools; original loader state restored.'
