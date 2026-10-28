<#
.SYNOPSIS
M4 PoC acceptance in individually authorized stages. Only a run action with -Launch starts a game.
#>
[CmdletBinding()]
param(
    [ValidateSet('Prepare','Status','Baseline','RunA','RunOff','RunB','RollbackA','Capture','Stop','Confirm','Cleanup')]
    [string] $Action = 'Status',
    [string] $Session,
    [ValidateSet('Debug','Release')] [string] $Config = 'Release',
    [switch] $Launch,
    [switch] $Multirun,
    [ValidateSet('path-traced','vanilla','failed')] [string] $Visual,
    [string] $Note = '',
    [ValidateRange(15,600)] [int] $TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$gameRoot = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC'
$gameExe = Join-Path $gameRoot 'bin\win64\gmod.exe'
$consolePath = Join-Path $gameRoot 'garrysmod\console.log'
$launchActions = @('Baseline','RunA','RunOff','RunB','RollbackA')
if ($Launch -and $Action -notin $launchActions) { throw '-Launch is valid only for a single run action.' }
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) { throw 'The pinned PoC install is unavailable.' }

function Write-Json([string] $Path, $Value) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
}
function Get-Tree {
    @(Get-ChildItem -LiteralPath $gameRoot -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($gameRoot.Length + 1)
        if ($_.PSIsContainer) { "D $relative" } else { "F $relative $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    } | Sort-Object)
}
function Assert-NoGame {
    $running = @(Get-Process gmod -ErrorAction SilentlyContinue | Where-Object {
        try { -not $_.HasExited } catch { $true }
    })
    if ($Multirun) {
        $running = @($running | Where-Object { -not $_.Path -or $_.Path.StartsWith($gameRoot + '\',[StringComparison]::OrdinalIgnoreCase) })
    }
    if ($running.Count) { throw "GMod is already running (PID $($running.Id -join ', ')); close it and approve a new launch separately." }
}
function Read-Shared([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Copy-Shared([string] $Source, [string] $Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
    if ((Get-Item -LiteralPath $Source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing evidence through a link: $Source" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
}
function Copy-RemixLogs([string] $Destination) {
    $logs = Join-Path $gameRoot 'rtx-remix\logs'
    if (-not (Test-Path -LiteralPath $logs -PathType Container)) { return }
    if ((Get-Item -LiteralPath $logs -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Remix logs directory is a link.' }
    foreach ($file in Get-ChildItem -LiteralPath $logs -File -Recurse) {
        $relative = $file.FullName.Substring($logs.Length + 1)
        if ($relative -like '.sentry-native\*' -or $file.Extension -in '.lock','.dmp') { continue }
        Copy-Shared $file.FullName (Join-Path $Destination $relative)
    }
}
function Normalise-Console([string] $Text) {
    $lines = foreach ($line in ($Text -split '\r?\n')) {
        $value = $line.TrimEnd()
        if ($value -match '^Thumbs: \d+ => \d+$') { 'Thumbs: <variable allocation counts>' }
        elseif ($value.Length) { $value }
    }
    $lines -join "`n"
}

if ($Action -eq 'Prepare') {
    foreach ($relative in @('native-loader','bin\win64\winmm.dll','bin\win64\winmm.pdb','garrysmod\data\native-loader')) {
        if (Test-Path -LiteralPath (Join-Path $gameRoot $relative)) { throw "PoC already has $relative; preserve/review its state before acceptance." }
    }
    $nlctl = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\cli\nlctl.exe"
    $bootstrap = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\proxy\winmm.dll"
    if (-not (Test-Path -LiteralPath $nlctl) -or -not (Test-Path -LiteralPath $bootstrap)) { throw 'Build and test the selected configuration first.' }
    $runtime = 'H:\BACKUP_20260815\Modding\dxvk-remix-gmod\_output'
    $override = 'H:\BACKUP_20260815\Modding\dxvk-remix-gmod\built-A8E39D93-lockfree-options'
    if (-not (Test-Path -LiteralPath (Join-Path $override 'd3d9.dll'))) {
        $alternate = 'H:\BACKUP_20260815\Modding\dxvk-remix-gmod\_CompRelease_x64\src\d3d9'
        $expected = 'A8E39D938D96193DF27D245A7F6E72F1C44B75FB2D066A67BDC2CD974EDEA267'
        if (-not (Test-Path -LiteralPath (Join-Path $alternate 'd3d9.dll')) -or
            (Get-FileHash -LiteralPath (Join-Path $alternate 'd3d9.dll')).Hash -cne $expected) {
            throw 'The requested A8E39D93 runtime B is unavailable; supply/review its location before acceptance.'
        }
        $override = $alternate
    }
    $rtxConfig = 'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\rtx.conf'
    $dxvkConfig = 'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\dxvk.conf'
    foreach ($inputFile in @((Join-Path $runtime 'd3d9.dll'),(Join-Path $override 'd3d9.dll'),$rtxConfig,$dxvkConfig)) {
        if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { throw "Missing acceptance input: $inputFile" }
    }
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    $Session = Join-Path $repo "out\poc-activation\$stamp"
    $packageRoot = Join-Path $repo "out\packages\m4-$stamp"
    New-Item -ItemType Directory -Path $Session,$packageRoot -Force | Out-Null
    $layerPaths = @{}
    foreach ($inputFile in @($rtxConfig,$dxvkConfig)) {
        $beforeHash = (Get-FileHash -LiteralPath $inputFile).Hash
        $snapshot = Join-Path $Session ('layers\' + [IO.Path]::GetFileName($inputFile))
        Copy-Shared $inputFile $snapshot
        if ((Get-FileHash -LiteralPath $inputFile).Hash -cne $beforeHash -or (Get-FileHash -LiteralPath $snapshot).Hash -cne $beforeHash) {
            throw 'A reference config changed while it was copied; retry preparation with stable inputs.'
        }
        $layerPaths[[IO.Path]::GetFileName($inputFile)] = $snapshot
    }
    $packages = [ordered]@{}
    $savedTemp, $savedTmp = $env:TEMP, $env:TMP
    $env:TEMP = Join-Path $repo 'out\tmp'; $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    try {
        foreach ($name in @('A','B')) {
            $file = Join-Path $packageRoot "runtime-$($name.ToLowerInvariant()).gma"
            $arguments = @('-I','-B',(Join-Path $repo 'tools\package_runtime.py'),'--runtime',$runtime,
                '--gma',$file,'--rtx-conf',$layerPaths['rtx.conf'],'--dxvk-conf',$layerPaths['dxvk.conf'],'--json')
            if ($name -eq 'B') { $arguments += @('--d3d9-from',$override) }
            $text = (& python @arguments) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Package $name failed." }
            $description = $text | ConvertFrom-Json
            Write-Json (Join-Path $Session "package-$name.json") $description
            & $nlctl manifest $file --json | Set-Content -LiteralPath (Join-Path $Session "manifest-$name.json") -Encoding utf8
            if ($LASTEXITCODE -ne 0) { throw "Package $name validation failed." }
            $packages[$name] = [ordered]@{ path=$file; version=$description.version; id=$description.id;
                d3d9_sha256=$description.d3d9_sha256; bytes=$description.bytes; files=$description.files }
        }
    } finally { $env:TEMP = $savedTemp; $env:TMP = $savedTmp }
    $state = [ordered]@{ schema=1; game_root=$gameRoot; config=$Config; prepared_utc=[DateTime]::UtcNow.ToString('o');
        packages=$packages; runtime_source=$runtime; runtime_b_override=$override; config_sha256=$null; runs=@(); cleaned=$false }
    Write-Json (Join-Path $Session 'session.json') $state
    Write-Host "Prepared A=$($packages.A.version), B=$($packages.B.version). No game launched."
    Write-Host "Session: $Session"
    return
}

if (-not $Session) { throw '-Session is required after Prepare.' }
$sessionRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Session).ProviderPath).TrimEnd('\')
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repo 'out\poc-activation')).TrimEnd('\') + '\'
if (-not $sessionRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Session must be in this repo/out/poc-activation.' }
$sessionPath = Join-Path $sessionRoot 'session.json'
$state = Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
if ($state.schema -ne 1 -or $state.game_root -cne $gameRoot) { throw 'Invalid or foreign PoC session.' }
$Config = $state.config
$nlctl = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\cli\nlctl.exe"
$configPath = Join-Path $gameRoot 'native-loader\config.json'

function Save-State { Write-Json $sessionPath $state }
function Get-OwnedProcess($Run) {
    $process = Get-Process -Id $Run.process_id -ErrorAction SilentlyContinue
    if (-not $process) { return $null }
    if ($process.HasExited) { return $null }
    if (-not [string]::Equals($process.Path,$gameExe,[StringComparison]::OrdinalIgnoreCase) -or
        [Math]::Abs(($process.StartTime.ToUniversalTime() - ([DateTime]$Run.process_start_utc).ToUniversalTime()).TotalSeconds) -gt 0.01) {
        throw 'Recorded game PID now belongs to a different process; refusing to act on it.'
    }
    return $process
}
function Set-RunConfig([string] $Package, [bool] $Enabled) {
    if (Test-Path -LiteralPath $configPath) {
        if (-not $state.config_sha256 -or (Get-FileHash -LiteralPath $configPath).Hash -cne $state.config_sha256) {
            throw 'PoC config.json changed outside this acceptance session; refusing to overwrite it.'
        }
    }
    Write-Json $configPath ([ordered]@{schema=1;enabled=$true;allow=@{local=@($Package)};remix=@{enabled=$Enabled}})
    $state.config_sha256 = (Get-FileHash -LiteralPath $configPath).Hash
    Save-State
}
function Copy-RunEvidence($Run) {
    Copy-Shared $consolePath (Join-Path $Run.directory 'console.log')
    Copy-Shared (Join-Path $gameRoot 'native-loader\logs\loader.log') (Join-Path $Run.directory 'loader.log')
    Copy-Shared (Join-Path $gameRoot 'garrysmod\data\native-loader\status.json') (Join-Path $Run.directory 'status.json')
    Copy-RemixLogs (Join-Path $Run.directory 'remix-logs')
    foreach ($log in Get-ChildItem -LiteralPath $gameRoot -File -Filter '*.log') {
        Copy-Shared $log.FullName (Join-Path $Run.directory "root-logs\$($log.Name)")
    }
}
function Capture-Run($Run) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $nextModuleSnapshot = [DateTime]::MinValue
    do {
        $process = Get-OwnedProcess $Run
        if ($process -and [DateTime]::UtcNow -ge $nextModuleSnapshot) {
            try {
                $early = @($process.Modules | ForEach-Object { [ordered]@{name=$_.ModuleName;path=$_.FileName;bytes=$_.ModuleMemorySize} })
                Write-Json (Join-Path $Run.directory 'modules-during-startup.json') $early
            } catch {
                # The module list can change while it is read; the next snapshot retries.
                [IO.File]::WriteAllText((Join-Path $Run.directory 'module-snapshot-note.txt'),$_.Exception.Message)
            }
            $nextModuleSnapshot = [DateTime]::UtcNow.AddSeconds(2)
        }
        $console = Read-Shared $consolePath
        if ($console -match '(?m)^Map: gm_construct\s*$' -and $console -match '(?m)^Clientside Lua startup!\s*$') { break }
        if (-not $process) { throw 'Game exited before the map marker; inspect captured logs.' }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($console -notmatch '(?m)^Clientside Lua startup!\s*$') { throw 'Timed out waiting for gm_construct.' }
    Start-Sleep -Seconds 5
    $process = Get-OwnedProcess $Run
    if (-not $process) { throw 'Game exited before module capture.' }
    $modules = @($process.Modules | ForEach-Object { [ordered]@{name=$_.ModuleName;path=$_.FileName;bytes=$_.ModuleMemorySize} })
    Write-Json (Join-Path $Run.directory 'modules.json') $modules
    Copy-RunEvidence $Run
    $console = Read-Shared $consolePath
    $normal = Normalise-Console $console
    [IO.File]::WriteAllText((Join-Path $Run.directory 'console.normalised.log'),$normal,[Text.UTF8Encoding]::new($false))
    $Run.map_loaded = $true
    $Run.dxlevel = $null
    if ($console -match '(?im)^\s*"?mat_dxlevel"?\s*=\s*"?(\d+)') { $Run.dxlevel = [int]$Matches[1] }
    $Run.captured_utc = [DateTime]::UtcNow.ToString('o')
    $statusPath = Join-Path $Run.directory 'status.json'
    $d3d9 = @($modules | Where-Object { $_.name -ieq 'd3d9.dll' })
    if ($Run.mode -eq 'Baseline') {
        if ($Run.dxlevel -eq $null) { throw 'Baseline did not print mat_dxlevel; the persistence check needs a value.' }
        if ($d3d9.Count -ne 1 -or -not [string]::Equals($d3d9[0].path,(Join-Path $env:SystemRoot 'System32\d3d9.dll'),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Baseline is not using System32 d3d9.dll.'
        }
    } else {
        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        if ($status.process_id -ne $Run.process_id) { throw 'Loader status belongs to another process.' }
        $Run.activation = $status.activation.outcome
        $Run.deployment = $status.deployment.outcome
        $Run.deployment_ms = $status.deployment.elapsed_ms
        if ($Run.mode -eq 'RunOff') {
            if ($status.activation.outcome -ne 'inactive') { throw 'RTX-off launch activated a runtime.' }
            if ($d3d9.Count -ne 1 -or -not [string]::Equals($d3d9[0].path,(Join-Path $env:SystemRoot 'System32\d3d9.dll'),[StringComparison]::OrdinalIgnoreCase)) {
                throw 'RTX-off d3d9.dll is not System32.'
            }
            $baseline = @($state.runs | Where-Object { $_.mode -eq 'Baseline' -and $_.map_loaded })[-1]
            $Run.dxlevel_persisted = $Run.dxlevel -ne $baseline.dxlevel
            $baselineConsole = [IO.File]::ReadAllText((Join-Path $baseline.directory 'console.normalised.log'))
            $Run.console_matches_baseline = $normal -ceq $baselineConsole
            if (-not $Run.console_matches_baseline) {
                Compare-Object ($baselineConsole -split "`n") ($normal -split "`n") -SyncWindow 0 |
                    Out-String -Width 4096 | Set-Content -LiteralPath (Join-Path $Run.directory 'console.diff.txt') -Encoding utf8
            }
            if ($Run.dxlevel -eq $null -or $Run.dxlevel_persisted) { throw "STOP: mat_dxlevel differs from vanilla (baseline $($baseline.dxlevel), now $($Run.dxlevel)); user must choose a mitigation." }
            if (-not $Run.console_matches_baseline) { throw 'STOP: RTX-off console differs from baseline; investigate before another launch.' }
        } else {
            if ($status.activation.outcome -ne 'active') { throw "Runtime activation failed: $($status.activation.reason)" }
            $wanted = if ($Run.mode -eq 'RunB') { $state.packages.B } else { $state.packages.A }
            if ($status.activation.runtime.version -cne $wanted.version) { throw 'The wrong runtime version activated.' }
            if ($Run.mode -eq 'RollbackA' -and $status.deployment.outcome -ne 'held') { throw 'Rollback was not held at startup.' }
            $journal = Get-Content -LiteralPath (Join-Path $gameRoot 'native-loader\state.json') -Raw | ConvertFrom-Json
            $runtime = @($journal.current.packages | Where-Object { $_.id -eq $status.activation.runtime.id })[0]
            $runtimePrefix = $runtime.payload + '/runtime/'
            $names = @($journal.current.files | Where-Object { $_.path.StartsWith($runtimePrefix) -and $_.path -match '\.(dll|pyd)$' } |
                ForEach-Object { [IO.Path]::GetFileName($_.path) })
            $folder = [IO.Path]::GetFullPath($status.activation.runtime.folder).TrimEnd('\','/') + '\'
            $runtimeModules = @($modules | Where-Object { $_.name -in $names })
            Write-Json (Join-Path $Run.directory 'runtime-modules.json') $runtimeModules
            foreach ($module in $runtimeModules) {
                if (-not ([IO.Path]::GetFullPath($module.path)).StartsWith($folder,[StringComparison]::OrdinalIgnoreCase)) {
                    throw "Runtime module outside package: $($module.name) => $($module.path)"
                }
            }
            if ($d3d9.Count -ne 1 -or -not ([IO.Path]::GetFullPath($d3d9[0].path)).StartsWith($folder,[StringComparison]::OrdinalIgnoreCase)) { throw 'd3d9.dll is not loaded from the package.' }
            $Run.runtime_module_count = $runtimeModules.Count
        }
    }
    $Run.capture_ok = $true
    $Run.error = $null
    Save-State
    Write-Json (Join-Path $Run.directory 'run.json') $Run
    Write-Host "Captured $($Run.mode): PID $($Run.process_id), mat_dxlevel=$($Run.dxlevel). Game left running for user review."
}

if ($Action -eq 'Status') { $state | ConvertTo-Json -Depth 20; return }
if ($Action -eq 'Cleanup') {
    Assert-NoGame
    if (Test-Path -LiteralPath $configPath) {
        if ((Get-FileHash -LiteralPath $configPath).Hash -cne $state.config_sha256) { throw 'PoC config changed; refusing cleanup until reviewed.' }
    }
    & (Join-Path $PSScriptRoot 'uninstall-loader.ps1') -GameRoot $gameRoot -Config $Config -RemoveConfig
    Get-Tree | Set-Content -LiteralPath (Join-Path $sessionRoot 'tree-after.txt') -Encoding utf8
    Compare-Object (Get-Content -LiteralPath (Join-Path $sessionRoot 'tree-before.txt')) (Get-Tree) |
        Out-String -Width 4096 | Set-Content -LiteralPath (Join-Path $sessionRoot 'created-or-changed.txt') -Encoding utf8
    & python -I -B (Join-Path $PSScriptRoot 'steam\verify_install.py') $gameRoot --manifests-from 'H:\SteamLibrary\steamapps\common\GarrysMod' --report (Join-Path $sessionRoot 'verify.json')
    if ($LASTEXITCODE -ne 0) { throw 'PoC depot verification failed.' }
    $state.cleaned = $true
    Save-State
    Write-Host 'Loader removed; depot verification passed. Game/Remix logs, caches and configs were retained.'
    return
}
if ($Action -in @('Capture','Stop','Confirm')) {
    if (-not $state.runs.Count) { throw 'No run exists in this session.' }
    $run = $state.runs[-1]
    if ($Action -eq 'Confirm') {
        if (-not $Visual) { throw '-Visual is required; record only the actual user observation.' }
        $run.visual = $Visual; $run.visual_note = $Note; $run.visual_confirmed_utc = [DateTime]::UtcNow.ToString('o')
        Save-State; Write-Json (Join-Path $run.directory 'run.json') $run; return
    }
    if ($Action -eq 'Stop') {
        $process = Get-OwnedProcess $run
        if ($process) {
            if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(20000)) { throw 'Game did not close gracefully; close it manually before continuing. It was not force-killed.' }
            $run.exit_code = $process.ExitCode
            $run.graceful_stop = $true
            $process.Dispose()
        }
        $run.stopped_utc = [DateTime]::UtcNow.ToString('o')
        Copy-RunEvidence $run; Save-State; Write-Json (Join-Path $run.directory 'run.json') $run; return
    }
    try { Capture-Run $run } catch { $run.error = $_.Exception.Message; Copy-RunEvidence $run; Save-State; Write-Json (Join-Path $run.directory 'run.json') $run; throw }
    return
}

$arguments = '-game garrysmod -console -windowed -w 1280 -h 720 -condebug -noworkshop -noaddons +map gm_construct +mat_dxlevel'
if ($Multirun) { $arguments = '-multirun ' + $arguments }
if (-not $Launch) {
    [ordered]@{ action=$Action; executable=$gameExe; working_directory=$gameRoot; arguments=$arguments;
        package_a=$state.packages.A; package_b=$state.packages.B; launches_game=$false } | ConvertTo-Json -Depth 6
    Write-Host 'Prepared plan only. Run this action with -Launch only after the user approves this individual launch.'
    return
}
Assert-NoGame
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Steam must be running and logged in.' }
if ($state.cleaned) { throw 'This session was cleaned; prepare a new session.' }
if ($Action -eq 'Baseline') {
    if ($state.runs.Count) { throw 'Baseline must be the first run in a new acceptance session.' }
    if (Test-Path -LiteralPath (Join-Path $gameRoot 'bin\win64\winmm.dll')) { throw 'Baseline requires the bootstrap to be absent.' }
    Get-Tree | Set-Content -LiteralPath (Join-Path $sessionRoot 'tree-before.txt') -Encoding utf8
} else {
    if (-not @($state.runs | Where-Object { $_.mode -eq 'Baseline' -and $_.capture_ok }).Count) { throw 'Capture a vanilla baseline first.' }
    if ($Action -eq 'RunOff' -and -not @($state.runs | Where-Object { $_.mode -eq 'RunA' -and $_.capture_ok -and $_.visual -eq 'path-traced' }).Count) {
        throw 'RTX-on A needs an actual user confirmation before the off comparison.'
    }
    if ($Action -eq 'RunB' -and -not @($state.runs | Where-Object { $_.mode -eq 'RunOff' -and $_.capture_ok -and $_.console_matches_baseline -and -not $_.dxlevel_persisted }).Count) {
        throw 'Resolve the RTX-off comparison and dxlevel finding before switching versions.'
    }
    if ($Action -eq 'RollbackA' -and -not @($state.runs | Where-Object { $_.mode -eq 'RunB' -and $_.capture_ok }).Count) {
        throw 'Capture runtime B before the rollback launch.'
    }
    if ($Action -eq 'RollbackA' -and (Get-FileHash -LiteralPath $configPath).Hash -cne $state.config_sha256) {
        throw 'PoC config changed outside this session; no rollback or launch performed.'
    }
    & (Join-Path $PSScriptRoot 'install-loader.ps1') -GameRoot $gameRoot -Config $Config
    if ($Action -eq 'RunA') { Set-RunConfig $state.packages.A.path $true }
    if ($Action -eq 'RunOff') { Set-RunConfig $state.packages.A.path $false }
    if ($Action -eq 'RunB') { Set-RunConfig $state.packages.B.path $true }
    if ($Action -eq 'RollbackA') {
        & $nlctl rollback $gameRoot --json | Set-Content -LiteralPath (Join-Path $sessionRoot 'rollback.json') -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw 'Rollback failed; no game launched.' }
    }
}
$runDir = Join-Path $sessionRoot ('{0:D2}-{1}' -f ($state.runs.Count + 1),$Action)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
if (Test-Path -LiteralPath $consolePath) {
    # Preserve the previous log instead of deleting it; fresh markers cannot be mistaken for this run.
    Move-Item -LiteralPath $consolePath -Destination (Join-Path $runDir 'console-before.log')
}
Copy-RemixLogs (Join-Path $runDir 'remix-before')
$process = Start-Process -FilePath $gameExe -WorkingDirectory $gameRoot -ArgumentList $arguments -WindowStyle Normal -PassThru
$run = [pscustomobject][ordered]@{mode=$Action;directory=$runDir;process_id=$process.Id;process_start_utc=$process.StartTime.ToUniversalTime().ToString('o');
    started_utc=[DateTime]::UtcNow.ToString('o');multirun=[bool]$Multirun;map_loaded=$false;capture_ok=$false;dxlevel=$null;activation=$null;deployment=$null;deployment_ms=$null;
    runtime_module_count=0;dxlevel_persisted=$null;console_matches_baseline=$null;captured_utc=$null;visual=$null;visual_note=$null;visual_confirmed_utc=$null;
    stopped_utc=$null;exit_code=$null;graceful_stop=$false;error=$null}
$state.runs = @($state.runs) + $run
Save-State
try { Capture-Run $run } catch {
    $run.error=$_.Exception.Message
    if ($process.HasExited) { $run.exit_code=$process.ExitCode }
    Copy-RunEvidence $run; Save-State; Write-Json (Join-Path $runDir 'run.json') $run; throw
}
