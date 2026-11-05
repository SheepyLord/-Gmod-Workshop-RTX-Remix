<#
.SYNOPSIS
Builds the Model Hotloader's four native files (gmcl_mmdhl_win64.dll, gmsv_mmdhl_win64.dll,
mmdhl_runtime_win64.dll, mmdhl_worker.exe) from the source this repository keeps in
packages/model-hotloader/source, and regenerates the add-on's hash records for them (native_policy.lua,
mmdhl-native-release.json) with the add-on's own scripts/native_manifest.py (R16, ADR 0107).
See build_hotloader.ps1.md.

.EXAMPLE
tools\ci\build_hotloader.ps1 -RunUrl <run>
tools\ci\build_hotloader.ps1 -Source out\r16\hotloader-stage\mmdhl -Vendor H:\...\wt-full-textures-props\vendor
#>
param(
    # Where the built files go, as <part>\<path in the part> (default out\ci\built).
    [string] $Out,
    # Scratch for the source copy and its build (default out\ci\work-hotloader).
    [string] $Work,
    # A source tree to build instead of packages/model-hotloader/source/mmdhl (a test of a staged copy).
    [string] $Source,
    # The add-on's bootstrapped dependencies (its vendor folder, each with .mmdhl-revision): copied in
    # instead of downloaded, for a build without network.
    [string] $Vendor,
    # The workflow run that builds them (recorded with each file).
    [string] $RunUrl,
    [ValidateRange(1, 64)] [int] $Jobs = 2
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repo 'tools\lib\VsDevEnv.psm1') -Force
$pins = (Get-Content (Join-Path $PSScriptRoot 'pins.json') -Raw | ConvertFrom-Json).hotloader
if (-not $Out) { $Out = Join-Path $repo 'out\ci\built' }
if (-not $Work) { $Work = Join-Path $repo 'out\ci\work-hotloader' }
$src = Join-Path $Work 'src'
New-Item -ItemType Directory -Force $Out, $Work, (Join-Path $Work 'tmp') | Out-Null
# Compiler and tool scratch stays inside the work folder (AGENTS.md rule 9).
$env:TEMP = $env:TMP = Join-Path $Work 'tmp'

function Invoke-Native([string] $What, [scriptblock] $Body) {
    # The exit code decides; a tool's stderr is passed on as text (Windows PowerShell would stop at it).
    $ErrorActionPreference = 'Continue'
    & $Body 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE) { throw "$What failed (exit $LASTEXITCODE)" }
}
function Get-Sha256([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }

# --- the source: this repository's copy, or a given tree -----------------------------------------
if (Test-Path $src) { Remove-Item -Recurse -Force $src }
if ($Source) {
    Copy-Item -Recurse -LiteralPath $Source -Destination $src
} else {
    Invoke-Native 'extract the source' { python -I (Join-Path $repo 'tools\inputs.py') extract model-hotloader --prefix $pins.source_prefix --dest $src }
}
if ($Vendor) {
    # A copy (not links) of the folder; robocopy's exit codes below 8 mean success.
    robocopy $Vendor (Join-Path $src 'vendor') /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying the dependencies from $Vendor failed (robocopy exit $LASTEXITCODE)" }
}

Push-Location $src
try {
    # The add-on's own recipe (its scripts/build.ps1): the pinned dependencies, its local patches of
    # Bullet, then CMake with Visual Studio 2022 x64, Release. Only the four shipped targets are built.
    Invoke-Native 'bootstrap (pinned dependencies)' { python -I scripts/bootstrap.py }
    Invoke-Native 'Bullet patches' { python -I scripts/patch-bullet-threading.py }
    Enter-VsDevEnv | Out-Null
    Invoke-Native 'cmake configure' { cmake -S . -B build -G 'Visual Studio 17 2022' -A x64 }
    Invoke-Native 'cmake build' { cmake --build build --config Release --parallel $Jobs --target mmdhl_client mmdhl_server mmdhl_worker }
    $bin = Join-Path $src 'build\bin\Release'
    $identity = (& (Join-Path $bin 'mmdhl_worker.exe') --version) -join "`n" | ConvertFrom-Json
    if ($identity.release -ne $pins.release) { throw "the worker reports release $($identity.release), not $($pins.release)" }
    "worker: release $($identity.release), build $($identity.build)"
    # The add-on's hash records for these files: its native_manifest.py rewrites this release's entry
    # of a copy of the shipped policy and writes native-release.json beside the binaries.
    $policy = Join-Path $Work 'native_policy.lua'
    Copy-Item -LiteralPath (Join-Path $repo $pins.policy) -Destination $policy -Force
    # Not isolated (-I): the script imports compatibility_profiles.py beside it.
    Invoke-Native 'native_manifest.py' { python -s scripts/native_manifest.py --bin $bin --output $policy }
} finally { Pop-Location }

$provenance = [ordered]@{}
$origin = @{ repository = $pins.repository; commit = $pins.base_commit
             patches = "$($pins.source) (that commit's native source with the staged changes it was shipped with)" }
foreach ($name in $pins.files) {
    $target = Join-Path $Out "model-hotloader\bin\$name"
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $bin $name) -Destination $target -Force
    $provenance[(Get-Sha256 $target)] = [ordered]@{ part = 'model-hotloader'; path = "bin/$name" } + $origin + @{
        how = "compiled: this repository's copy of the add-on's native source, its scripts/bootstrap.py (pinned dependencies) and CMake Visual Studio 17 2022 x64 Release, release $($identity.release), build $($identity.build)"; run = $RunUrl }
    "built model-hotloader/bin/$name ($((Get-Item $target).Length) bytes)"
}
$records = @(
    @{ from = (Join-Path $bin 'native-release.json'); path = 'bin/mmdhl-native-release.json' },
    @{ from = $policy; path = $pins.policy_in_part })
foreach ($record in $records) {
    $target = Join-Path $Out "model-hotloader\$($record.path)"
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath $record.from -Destination $target -Force
    $provenance[(Get-Sha256 $target)] = [ordered]@{ part = 'model-hotloader'; path = $record.path } + $origin + @{
        how = "generated: the add-on's scripts/native_manifest.py from the files built here"; run = $RunUrl }
    "wrote model-hotloader/$($record.path)"
}
$path = Join-Path $Out 'provenance-hotloader.json'
[IO.File]::WriteAllText($path, ([ordered]@{ binaries = $provenance; release = $identity.release; build = $identity.build } |
    ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
"hotloader: $($pins.files.Count) files built, release $($identity.release) build $($identity.build); $path"
