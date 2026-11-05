<#
.SYNOPSIS
Builds the RTX package's native modules that come from other repositories (R16, ADR 0106): the RTX fixes'
gmcl_RTXFixesBinary, gmcl_rtxwater and gmcl_rtxdebug, and the Advanced Material Editor's RTX bridge, from
the sources and commits in tools\ci\pins.json. See build_modules.ps1.md.

.EXAMPLE
tools\ci\build_modules.ps1
tools\ci\build_modules.ps1 -FixesClone H:\...\garrys-mod-rtx-remixed -GmodCommon H:\...\garrys-mod-rtx-remixed\garrysmod_common -Premake H:\...\premake5.exe
#>
param(
    # Where the built modules go, as <part>\<path in the part> (default out\ci\built).
    [string] $Out,
    # Scratch for checkouts and builds (default out\ci\work).
    [string] $Work,
    # An existing clone of the fixes fork with the pinned commits; default: cloned from GitHub.
    [string] $FixesClone,
    # An existing garrysmod_common checkout at the pinned commit with its submodules; default: cloned.
    [string] $GmodCommon,
    # An existing premake5.exe 5.0.0-beta2; default: the pinned official archive, downloaded and checked.
    [string] $Premake,
    # The workflow run that builds them (recorded with each module).
    [string] $RunUrl,
    # Which modules (default all): fixes, rtxwater, rtxdebug, advmat.
    [string[]] $Only = @('fixes', 'rtxwater', 'rtxdebug', 'advmat'),
    # MSVC toolset and Windows SDK the recorded builds used (garrysmod_common projects).
    [string] $VCToolsVersion = '14.44.35207',
    [string] $WindowsSdk = '10.0.26100.0'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repo 'tools\lib\VsDevEnv.psm1') -Force
$pins = Get-Content (Join-Path $PSScriptRoot 'pins.json') -Raw | ConvertFrom-Json
if (-not $Out) { $Out = Join-Path $repo 'out\ci\built' }
if (-not $Work) { $Work = Join-Path $repo 'out\ci\work' }
New-Item -ItemType Directory -Force $Out, $Work, (Join-Path $Work 'tmp') | Out-Null
# Compiler and tool scratch stays inside the work folder (AGENTS.md rule 9).
$env:TEMP = $env:TMP = Join-Path $Work 'tmp'
$provenance = [ordered]@{}

function Invoke-Native([string] $What, [scriptblock] $Body) {
    # The exit code decides. What a tool writes to stderr (git's warnings) is passed on as text: Windows
    # PowerShell would otherwise stop at its first line.
    $ErrorActionPreference = 'Continue'
    & $Body 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE) { throw "$What failed (exit $LASTEXITCODE)" }
}
function Get-Native([scriptblock] $Body, [switch] $Required) {
    # A query's output lines; when it fails, nothing (or an error with -Required).
    $ErrorActionPreference = 'Continue'
    $lines = @(& $Body 2>$null | ForEach-Object { "$_".Trim() })
    if ($LASTEXITCODE) {
        if ($Required) { throw "$Body failed (exit $LASTEXITCODE)" }
        return @()
    }
    $lines
}
function Get-Sha256([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }
function Add-Built([string] $File, [string] $Part, [string] $Rel, [hashtable] $Source) {
    $target = Join-Path $Out (Join-Path $Part $Rel)
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath $File -Destination $target -Force
    $sha = Get-Sha256 $target
    $provenance[$sha] = [ordered]@{ part = $Part; path = $Rel.Replace('\', '/') } + $Source + @{ run = $RunUrl }
    "built $Part/$Rel ($((Get-Item $target).Length) bytes, SHA-256 $sha)"
}
function Find-One([string] $Root, [string] $Name) {
    $found = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter $Name -File | Sort-Object LastWriteTime -Descending)
    if (-not $found) { throw "no $Name under $Root" }
    $found[0].FullName
}

# --- premake 5.0.0-beta2 ---------------------------------------------------------------------------
if (-not $Premake) {
    $zip = Join-Path $Work 'premake.zip'
    Invoke-WebRequest -Uri $pins.premake.url -OutFile $zip -UseBasicParsing
    if ((Get-Sha256 $zip) -ne $pins.premake.archive_sha256) { throw "premake archive does not match its pin" }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $Work 'premake') -Force
    $Premake = Find-One (Join-Path $Work 'premake') 'premake5.exe'
}
$version = (& $Premake --version) -join ' '
if ($version -notmatch [regex]::Escape($pins.premake.version)) { throw "premake is '$version', not $($pins.premake.version)" }

# --- garrysmod_common at its pin, with its submodules ----------------------------------------------
if (-not $GmodCommon) {
    $GmodCommon = Join-Path $Work 'garrysmod_common'
    if (-not (Test-Path (Join-Path $GmodCommon '.git'))) {
        Invoke-Native 'clone garrysmod_common' { git clone --quiet --filter=blob:none --no-checkout $pins.garrysmod_common.repository $GmodCommon }
    }
    if (-not (Get-Native { git -C $GmodCommon cat-file -t $pins.garrysmod_common.commit })) {
        # The pinned commit is no longer on a branch (the branch moved on): GitHub serves it by its hash.
        Invoke-Native 'fetch the pinned garrysmod_common' { git -C $GmodCommon fetch --quiet --filter=blob:none origin $pins.garrysmod_common.commit }
    }
    Invoke-Native 'checkout garrysmod_common' { git -C $GmodCommon checkout --quiet --detach $pins.garrysmod_common.commit }
    Invoke-Native 'garrysmod_common submodules' { git -C $GmodCommon submodule update --init --recursive --filter=blob:none }
}
$have = Get-Native { git -C $GmodCommon rev-parse HEAD }
if ("$have" -ne $pins.garrysmod_common.commit) { throw "garrysmod_common is at '$have', not $($pins.garrysmod_common.commit)" }
foreach ($sub in $pins.garrysmod_common.submodules.PSObject.Properties) {
    $at = Get-Native { git -C (Join-Path $GmodCommon $sub.Name) rev-parse HEAD }
    if ("$at" -ne $sub.Value) { throw "garrysmod_common/$($sub.Name) is at '$at', not $($sub.Value)" }
}

Enter-VsDevEnv | Out-Null
$msbuildProps = @("/p:Platform=x64", "/p:VCToolsVersion=$VCToolsVersion", "/p:WindowsTargetPlatformVersion=$WindowsSdk")

# --- the RTX fixes: the public base with this repository's GPL patches -----------------------------
$fixes = Join-Path $Work 'fixes'
if (($Only -contains 'fixes') -or ($Only -contains 'rtxwater')) {
    Remove-Item -Recurse -Force $fixes -ErrorAction SilentlyContinue
    if ($FixesClone) {
        # Borrows the local clone's objects (git alternates): that repository is only read.
        Invoke-Native 'clone the fixes (local)' { git clone --quiet --shared --no-checkout $FixesClone $fixes }
    } else {
        # A full clone (about 300 MB): in a blob-filtered one, git restore --source does not fetch the
        # blobs RTX Water's pinned commit needs ("unable to read sha1 file", R16's first run).
        Invoke-Native 'clone the fixes' { git clone --quiet --no-checkout $pins.fixes.repository $fixes }
    }
    foreach ($commit in $pins.fixes.base, $pins.fixes.rtxwater_commit) {
        if (-not (Get-Native { git -C $fixes cat-file -t $commit })) {
            Invoke-Native "fetch $commit" { git -C $fixes fetch --quiet origin $commit }
        }
    }
    # Only the native sources are checked out (the fork also holds the game files, about 300 MB).
    Invoke-Native 'sparse checkout' { git -C $fixes sparse-checkout set --no-cone /.gitattributes /premake5.lua /public/ /source/ }
    Invoke-Native 'checkout the fixes base' { git -C $fixes checkout --quiet --detach $pins.fixes.base }
    # The patches apply to the index (the repository's own bytes), then the files are written from it,
    # so line-ending settings cannot make them fail.
    $include = @($pins.fixes.patch_paths | ForEach-Object { "--include=$_" })
    foreach ($patch in $pins.fixes.patches) {
        Invoke-Native "apply $patch" { git -C $fixes apply --cached @include (Join-Path $repo $patch) }
    }
    Invoke-Native 'write the patched files' { git -C $fixes checkout -- . }
    if ("$(Get-Native { git -C $fixes cat-file -t $pins.fixes.patched_commit })" -eq 'commit') {
        # The patched native tree must be the recorded one (verifiable where that commit exists).
        $diff = Get-Native -Required { git -C $fixes diff --cached --stat $pins.fixes.patched_commit -- source premake5.lua public }
        if ($diff) { throw "the patched fixes differ from $($pins.fixes.patched_commit):`n$diff" }
        "fixes: the patched native tree equals $($pins.fixes.patched_commit)"
    }
}
$fixesSource = @{ repository = $pins.fixes.repository; commit = $pins.fixes.base
                  patches = ($pins.fixes.patches -join ', '); patched_native_tree = $pins.fixes.patched_commit }
if ($Only -contains 'fixes') {
    Push-Location $fixes
    try {
        Invoke-Native 'premake (fixes)' { & $Premake --os=windows "--gmcommon=$GmodCommon" vs2022 }
        $project = Find-One $fixes 'gmcl_RTXFixesBinary.vcxproj'
        Invoke-Native 'msbuild gmcl_RTXFixesBinary' { msbuild $project /nologo /m:2 /v:minimal /p:Configuration=ReleaseWithSymbols @msbuildProps }
        $dll = Find-One $fixes 'gmcl_RTXFixesBinary_win64.dll'
        Add-Built $dll 'fixes' 'modules\gmcl_RTXFixesBinary_win64.dll' ($fixesSource + @{ how = "compiled: premake $($pins.premake.version) + MSBuild ReleaseWithSymbols x64 (as recorded in packages/fixes/licenses/oversized-skinning/build-pins.json)" })
    } finally { Pop-Location }
}
if ($Only -contains 'rtxwater') {
    Push-Location $fixes
    try {
        # Version 4 of the native RTX Water, as shipped: that commit's source/rtx_water on the patched base.
        Invoke-Native 'rtx_water at its pin' { git -C $fixes restore "--source=$($pins.fixes.rtxwater_commit)" --staged --worktree -- source/rtx_water }
        Invoke-Native 'premake (rtx_water)' { & $Premake --os=windows "--gmcommon=$GmodCommon" vs2022 }
        $project = Find-One $fixes 'gmcl_rtxwater.vcxproj'
        Invoke-Native 'msbuild gmcl_rtxwater' { msbuild $project /nologo /m:2 /v:minimal /p:Configuration=Release @msbuildProps }
        $dll = Find-One $fixes 'gmcl_rtxwater_win64.dll'
        Add-Built $dll 'fixes' 'modules\gmcl_rtxwater_win64.dll' @{ repository = $pins.fixes.repository; commit = $pins.fixes.rtxwater_commit
            how = "compiled: source/rtx_water of that commit (Version 4) on the patched fixes base, premake + MSBuild Release x64" }
    } finally { Pop-Location }
}

# --- the RTX debug module, from this repository's complete copy of its source -----------------------
if ($Only -contains 'rtxdebug') {
    $debug = Join-Path $Work 'rtxdebug'
    Remove-Item -Recurse -Force $debug -ErrorAction SilentlyContinue
    Copy-Item -Recurse (Join-Path $repo $pins.rtxdebug.source) $debug
    $remix = Join-Path $fixes 'public\include'
    if (-not (Test-Path $remix)) { throw "the Remix headers ($remix) come from the fixes checkout: build 'fixes' or 'rtxwater' first" }
    Push-Location $debug
    try {
        Invoke-Native 'premake (rtxdebug)' { & $Premake --os=windows "--gmcommon=$GmodCommon" "--remixinclude=$remix" vs2022 }
        $solution = Find-One $debug 'RTXDebugModule.sln'
        if ($debug.Contains('!')) {
            # Under a path with "!" (this machine's repository path) the pinned generator writes a wrong
            # absolute IntDir (packages/fixes/licenses/rtxdebug/Source.md): the helper libraries first,
            # then the module itself with a relative IntDir.
            $project = Find-One $debug 'gmcl_rtxdebug.vcxproj'
            $references = @(([xml](Get-Content -LiteralPath $project -Raw)).Project.ItemGroup.ProjectReference.Include | Where-Object { $_ })
            foreach ($reference in $references) {
                $path = Join-Path (Split-Path $project) $reference
                Invoke-Native "msbuild $reference" { msbuild $path /nologo /m:2 /v:minimal /p:Configuration=Release @msbuildProps }
            }
            Invoke-Native 'msbuild gmcl_rtxdebug' { msbuild $project /nologo /m:2 /v:minimal /p:Configuration=Release /p:BuildProjectReferences=false '/p:IntDir=obj\Release\' @msbuildProps }
        } else {
            Invoke-Native 'msbuild gmcl_rtxdebug' { msbuild $solution /nologo /m:2 /v:minimal -t:gmcl_rtxdebug /p:Configuration=Release @msbuildProps }
        }
        $dll = Find-One $debug 'gmcl_rtxdebug_win64.dll'
        Add-Built $dll 'fixes' 'modules\gmcl_rtxdebug_win64.dll' @{ repository = $pins.rtxdebug.repository; commit = $pins.rtxdebug.commit
            how = "compiled: this repository's complete copy of that source ($($pins.rtxdebug.source)), premake + MSBuild Release x64" }
    } finally { Pop-Location }
}

# --- the Advanced Material Editor's RTX bridge, from this repository's copy of its source -----------
if ($Only -contains 'advmat') {
    $build = Join-Path $Work 'advmat'
    Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue
    $source = Join-Path $repo $pins.advmat_bridge.source
    Invoke-Native 'cmake configure (advmat)' { cmake -S $source -B $build -G 'Visual Studio 17 2022' -A x64 -DADVMAT_RTX_BUILD_GMOD_MODULE=ON -DADVMAT_RTX_BUILD_TESTS=ON "-DGARRYSMOD_COMMON_INCLUDE_DIR=$GmodCommon/include" }
    Invoke-Native 'cmake build (advmat)' { cmake --build $build --config Release }
    # Its writer test builds a game root under %TEMP% and fails once that folder's path is longer than
    # about 75 characters (a material with every texture role passes MAX_PATH; RESEARCH.md, R16): the
    # runner's own temporary folder, or the shortest folder this repository's out\ offers, is short enough.
    $testTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { Join-Path $repo 'out\t' }
    New-Item -ItemType Directory -Force $testTemp | Out-Null
    $env:TEMP = $env:TMP = $testTemp
    try { Invoke-Native 'ctest (advmat)' { ctest --test-dir $build -C Release --output-on-failure } }
    finally { $env:TEMP = $env:TMP = Join-Path $Work 'tmp' }
    $dll = Find-One $build 'gmcl_advmat_rtx_bridge_win64.dll'
    Add-Built $dll 'advanced-material-editor' 'bin\gmcl_advmat_rtx_bridge_win64.dll' @{ repository = $pins.advmat_bridge.repository; commit = $pins.advmat_bridge.commit
        how = "compiled: this repository's copy of native/rtx_bridge ($($pins.advmat_bridge.source)), CMake Visual Studio 17 2022 x64 Release, its tests run" }
}

$record = [ordered]@{ binaries = $provenance; premake = $version; garrysmod_common = $pins.garrysmod_common.commit }
$path = Join-Path $Out 'provenance-modules.json'
[IO.File]::WriteAllText($path, ($record | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
"modules: $($provenance.Count) built; $path"
