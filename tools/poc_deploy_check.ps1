<#
.SYNOPSIS
M3 acceptance on the PoC install without starting the game: installs the bootstrap, allowlists a test
package built with gmapack, deploys it with nlctl, checks it, removes everything with
uninstall-loader.ps1 -RemoveConfig, and proves the install is exactly as it was before.
#>
[CmdletBinding()]
param(
    [string] $GameRoot = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC',
    [string] $ManifestsFrom = 'H:\SteamLibrary\steamapps\common\GarrysMod',
    [ValidateSet('Debug', 'Release')] [string] $Config = 'Release'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $GameRoot).ProviderPath.TrimEnd('\', '/')
$nlctl = Join-Path $repo "out\build\win64-$($Config.ToLowerInvariant())\loader\cli\nlctl.exe"
$evidence = Join-Path $repo ("out\poc-deploy\" + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$checks = [ordered]@{}

function Test-Step([string] $Name, [bool] $Ok, [string] $Detail = '') {
    $checks[$Name] = [ordered]@{ ok = $Ok; detail = $Detail }
    Write-Host ("{0}  {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { ": $Detail" } else { '' }))
}

# Runs nlctl, keeps its output as evidence, returns the parsed JSON report and the exit code.
function Invoke-Nlctl([string] $Label, [string[]] $Arguments) {
    $ErrorActionPreference = 'Continue'
    $text = (& $nlctl @Arguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $code = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $evidence "$Label.json"), $text + "`n", [Text.UTF8Encoding]::new($false))
    $report = try { $text | ConvertFrom-Json } catch { $null }
    return @{ code = $code; report = $report }
}

# Every file below the install with its size and time, and every folder: what must come back unchanged.
function Get-Tree([string] $Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length + 1)
        if ($_.PSIsContainer) { "D $rel" } else { "F $rel $($_.Length) $($_.LastWriteTimeUtc.Ticks)" }
    } | Sort-Object
}

# A clean PoC to start from, and the builds.
if (Test-Path -LiteralPath (Join-Path $root 'native-loader')) { throw "$root already has a native-loader folder; remove the loader first (tools\uninstall-loader.ps1 -RemoveConfig)" }
if (Test-Path -LiteralPath (Join-Path $root 'bin\win64\winmm.dll')) { throw "$root already has a bin\win64\winmm.dll; remove it first" }
if (-not (Test-Path -LiteralPath $nlctl -PathType Leaf)) { throw "Build first: tools\build.ps1 -Config $Config" }
if (Get-Process -Name gmod -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) }) {
    throw "Garry's Mod is running from $root; close it first"
}
$before = Get-Tree $root
$before | Set-Content -LiteralPath (Join-Path $evidence 'tree-before.txt') -Encoding UTF8

# The test package: a payload file and root files in all three areas (one of them create-only).
$package = Join-Path $evidence 'package'
$files = [ordered]@{
    'native/payload/config/nl_poc_test.conf'                 = "rtx.nl_poc_test = True`n"
    'native/root/rtx-remix/mods/nl_poc_test/mod.usda'        = "#usda 1.0`n"
    'native/root/garrysmod/lua/bin/gmcl_nl_poc_test_win64.dll' = 'MZ-not-a-real-module'
    'native/root/garrysmod/cfg/nl_poc_test.cfg'              = "// nl_poc_test`n"
}
$listed = [ordered]@{}
foreach ($rel in $files.Keys) {
    $path = Join-Path $package $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $files[$rel], [Text.UTF8Encoding]::new($false))
    $listed[$rel] = [ordered]@{ size = (Get-Item -LiteralPath $path).Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifest = [ordered]@{ schema = 1; id = 'nl-poc-test'; version = '1.0.0'; kinds = @('root-files', 'lua-binary-module'); files = $listed
    root_files = @(@{ path = 'rtx-remix/mods/nl_poc_test' }, @{ path = 'garrysmod/lua/bin/gmcl_nl_poc_test_win64.dll' },
                   [ordered]@{ path = 'garrysmod/cfg/nl_poc_test.cfg'; policy = 'create-only' }) }
[IO.File]::WriteAllText((Join-Path $package 'native\manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $package 'addon.json'), '{"title": "nl_poc_test", "type": "servercontent", "tags": []}', [Text.UTF8Encoding]::new($false))
$gma = Join-Path $evidence 'nl_poc_test.gma'
& python -I -B (Join-Path $repo 'tools\gmapack\gmapack.py') create --folder $package --out $gma --quiet
if ($LASTEXITCODE -ne 0) { throw 'gmapack could not build the test package' }
Test-Step 'test package validates' ((Invoke-Nlctl 'manifest' @('manifest', $gma, '--json')).code -eq 0)

$installed = $false
try {
    & (Join-Path $PSScriptRoot 'install-loader.ps1') -GameRoot $root -Config $Config
    $installed = $true
    $allowlist = [ordered]@{ schema = 1; allow = [ordered]@{ local = @($gma.Replace('\', '/')) } }
    [IO.File]::WriteAllText((Join-Path $root 'native-loader\config.json'), ($allowlist | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))

    $first = Invoke-Nlctl 'apply-1' @('apply', $root, '--json')
    Test-Step 'apply deploys the package' ($first.code -eq 0 -and $first.report.outcome -eq 'deployed') "$($first.report.outcome) $($first.report.error)"
    $placed = @{
        'rtx-remix\mods\nl_poc_test\mod.usda'          = $files['native/root/rtx-remix/mods/nl_poc_test/mod.usda']
        'garrysmod\lua\bin\gmcl_nl_poc_test_win64.dll' = $files['native/root/garrysmod/lua/bin/gmcl_nl_poc_test_win64.dll']
        'garrysmod\cfg\nl_poc_test.cfg'                = $files['native/root/garrysmod/cfg/nl_poc_test.cfg']
    }
    foreach ($rel in $placed.Keys) {
        $path = Join-Path $root $rel
        Test-Step "placed $rel" ((Test-Path -LiteralPath $path) -and [IO.File]::ReadAllText($path) -ceq $placed[$rel])
    }
    $packages = Join-Path $root 'native-loader\packages\nl-poc-test'
    $payload = if (Test-Path -LiteralPath $packages) { @(Get-ChildItem -LiteralPath $packages -Directory) } else { @() }
    Test-Step 'payload folder placed' ($payload.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $payload[0].FullName 'config\nl_poc_test.conf'))) ($payload.Name -join ', ')
    $second = Invoke-Nlctl 'apply-2' @('apply', $root, '--json')
    Test-Step 'a second apply writes nothing' ($second.code -eq 0 -and $second.report.outcome -eq 'unchanged' -and $second.report.operations -eq 0) "$($second.report.outcome), $($second.report.operations) changes"
    $status = Invoke-Nlctl 'status' @('status', $root, '--json', '--verify')
    Test-Step 'status --verify is clean' ($status.code -eq 0 -and $status.report.ok)
} finally {
    if ($installed) { & (Join-Path $PSScriptRoot 'uninstall-loader.ps1') -GameRoot $root -Config $Config -RemoveConfig }
}

$after = Get-Tree $root
$after | Set-Content -LiteralPath (Join-Path $evidence 'tree-after.txt') -Encoding UTF8
$diff = @(Compare-Object -ReferenceObject $before -DifferenceObject $after)
Test-Step 'every file and folder is as before (sizes and times)' ($diff.Count -eq 0) "$($diff.Count) difference(s)$(if ($diff.Count) { ': ' + (($diff | Select-Object -First 5 | ForEach-Object { $_.SideIndicator + ' ' + $_.InputObject }) -join '; ') })"

Write-Host 'Hashing every depot file (about a minute)...'
$ErrorActionPreference = 'Continue'
& python -I -B (Join-Path $repo 'tools\steam\verify_install.py') $root --manifests-from $ManifestsFrom --quiet --report (Join-Path $evidence 'verify.json') |
    Set-Content -LiteralPath (Join-Path $evidence 'verify.txt') -Encoding UTF8
$verified = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$report = Get-Content -LiteralPath (Join-Path $evidence 'verify.json') -Raw | ConvertFrom-Json
Test-Step 'verify_install: every depot file matches' ($verified -eq 0) "$($report.ok) OK, $(@($report.missing).Count) missing, $(@($report.hash_mismatch).Count) changed"

$passed = -not ($checks.Values | Where-Object { -not $_.ok })
[IO.File]::WriteAllText((Join-Path $evidence 'summary.json'),
    ([ordered]@{ game_root = $root; config = $Config; passed = $passed; checks = $checks } | ConvertTo-Json -Depth 4) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "$(if ($passed) { 'PASSED' } else { 'FAILED' }); evidence in $evidence"
if (-not $passed) { exit 1 }
