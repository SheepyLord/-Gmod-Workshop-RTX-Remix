<#
.SYNOPSIS
Rebuilds the RTX Remix runtime's d3d9.dll from the fork's base commit and this repository's patches,
and stores it in packages/runtime (ADR 0033). See build_runtime.ps1.md.

.EXAMPLE
runtime\build_runtime.ps1 -Fork H:\BACKUP_20260815\Modding\dxvk-remix-gmod
#>
param(
    # A clone of the runtime fork (runtime\base.json names it); only a worktree of it is changed.
    [Parameter(Mandatory)] [string] $Fork,
    # Where the patched tree is built (default: <Fork>\.claude\worktrees\nl-runtime). Created when missing.
    [string] $Worktree,
    # Build only; leave packages\runtime and runtime\base.json as they are.
    [switch] $NoImport,
    # Check the worktree against runtime\base.json and the patches, show its built d3d9.dll; build nothing.
    [switch] $Verify
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$basePath = Join-Path $PSScriptRoot 'base.json'
$base = Get-Content $basePath -Raw | ConvertFrom-Json
$patches = @(Get-ChildItem (Join-Path $PSScriptRoot 'patches') -Filter '*.patch' | Sort-Object Name)
if (-not $patches) { throw 'runtime\patches holds no patches' }
if (-not $Worktree) { $Worktree = Join-Path $Fork '.claude\worktrees\nl-runtime' }

function Get-Settings($object) {
    # base.json "submodules" or "clones": folder in the tree -> its settings.
    $table = [ordered]@{}
    if ($object) { foreach ($item in $object.PSObject.Properties) { $table[$item.Name] = $item.Value } }
    $table
}
# Submodules built at another commit than the tree records, or with a patch of their own; and the git
# clones the build reads that the fork's tree does not record at all (RESEARCH.md section 31).
$submodules = Get-Settings $base.submodules
$clones = Get-Settings $base.clones

function Invoke-Git([string] $Where) {
    # git's exit code decides; what it writes to stderr is only kept with the output (Windows
    # PowerShell would otherwise stop at the first stderr line).
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $Where @args 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE) { throw "git $($args -join ' '): $output" }
    $output
}

function Use-ScratchGit([string] $Where, [scriptblock] $Body) {
    # Runs $Body with git's index and new objects in a scratch folder that borrows the objects of
    # $Where's repository, so that repository is only read.
    $scratch = Join-Path $repo ('out\tmp\runtime-git-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force (Join-Path $scratch 'objects') | Out-Null
    $objects = Invoke-Git $Where rev-parse --path-format=absolute --git-path objects | Select-Object -Last 1
    $names = 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        $env:GIT_INDEX_FILE = Join-Path $scratch 'index'
        $env:GIT_OBJECT_DIRECTORY = Join-Path $scratch 'objects'
        $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $objects
        & $Body
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-PatchedTree([string] $Where, [string] $Commit, [string[]] $PatchFiles) {
    # The tree $Commit has with the patches applied, in order.
    Use-ScratchGit $Where {
        Invoke-Git $Where read-tree $Commit | Out-Null
        foreach ($patch in $PatchFiles) { Invoke-Git $Where apply --cached $patch | Out-Null }
        Invoke-Git $Where write-tree | Select-Object -Last 1
    }
}

function Get-WorkingTree([string] $Where) {
    # The tree of what $Where has checked out: its commit with its tracked files as they are now.
    Use-ScratchGit $Where {
        Invoke-Git $Where read-tree HEAD | Out-Null
        Invoke-Git $Where add --update | Out-Null
        Invoke-Git $Where write-tree | Select-Object -Last 1
    }
}

Invoke-Git $Fork cat-file -e "$($base.commit)^{commit}" | Out-Null
$needsSetup = $false
if (-not (Test-Path $Worktree)) {
    if ($Verify) { throw "$Worktree does not exist" }
    Invoke-Git $Fork worktree add --detach $Worktree $base.commit | Out-Null
    Invoke-Git $Worktree am --3way --keep-cr @($patches.FullName) | Out-Null
    Invoke-Git $Worktree submodule update --init --recursive | Out-Null
    foreach ($path in $submodules.Keys) {
        $at = Join-Path $Worktree $path
        if ($submodules[$path].commit) { Invoke-Git $at checkout --quiet --detach $submodules[$path].commit | Out-Null }
        if ($submodules[$path].patch) { Invoke-Git $at apply (Join-Path $PSScriptRoot $submodules[$path].patch) | Out-Null }
    }
    foreach ($path in $clones.Keys) {
        $at = Join-Path $Worktree $path
        Invoke-Git $Worktree clone --quiet $clones[$path].url $at | Out-Null
        Invoke-Git $at checkout --quiet --detach $clones[$path].commit | Out-Null
    }
    $needsSetup = $true
}

# What is checked out must be exactly what base.json and the patches describe (R3-014): the commit's
# tree is compared with the one the patches make, so a patch whose content changed under the same
# subject is noticed; nothing else may differ (uncommitted changes, an untracked folder the build
# could read, a submodule or clone off its commit or with changes of its own). The submodules inside
# submodules are left as the build has them: in a worktree some of their .git files point nowhere.
$problems = @()
$want = Get-PatchedTree $Worktree $base.commit $patches.FullName
$have = Invoke-Git $Worktree rev-parse 'HEAD^{tree}' | Select-Object -Last 1
if ($have -ne $want) { $problems += "its commit's tree is $have; base.json's commit with runtime\patches makes $want" }
foreach ($line in @(Invoke-Git $Worktree status --porcelain --ignore-submodules=all)) {
    if ($line -like '?? *') {
        $folder = $line.Substring(3).TrimEnd('/')
        if (-not $clones.Contains($folder)) { $problems += "$folder is untracked and not a clone base.json names (the build may read it)" }
    } else {
        $problems += "uncommitted change: $line"
    }
}
$links = @{}
foreach ($link in @(Invoke-Git $Worktree ls-tree -r HEAD | Where-Object { $_ -like '160000 commit *' })) {
    $null = $link -match '^160000 commit ([0-9a-f]+)\t(.+)$'
    $links[$Matches[2]] = $Matches[1]
}
foreach ($path in $submodules.Keys) { if (-not $links.ContainsKey($path)) { $problems += "base.json names the submodule $path, which the tree does not have" } }
foreach ($path in $links.Keys) {
    $setting = $submodules[$path]
    $wanted = if ($setting -and $setting.commit) { $setting.commit } else { $links[$path] }
    $at = Join-Path $Worktree $path
    if (-not (Test-Path -LiteralPath (Join-Path $at '.git'))) { $problems += "the submodule $path is not checked out"; continue }
    $head = Invoke-Git $at rev-parse HEAD | Select-Object -Last 1
    if ($head -ne $wanted) { $problems += "the submodule $path is at $head, not at $wanted"; continue }
    if ($setting -and $setting.patch) {
        $expected = Get-PatchedTree $at $wanted @(Join-Path $PSScriptRoot $setting.patch)
        if ((Get-WorkingTree $at) -ne $expected) { $problems += "the submodule $path does not hold exactly runtime\$($setting.patch)" }
    } elseif (@(Invoke-Git $at status --porcelain --untracked-files=no --ignore-submodules=all)) {
        $problems += "the submodule $path has uncommitted changes"
    }
}
foreach ($path in $clones.Keys) {
    $at = Join-Path $Worktree $path
    if (-not (Test-Path -LiteralPath (Join-Path $at '.git'))) { $problems += "$path ($($clones[$path].url)) is not cloned"; continue }
    $head = Invoke-Git $at rev-parse HEAD | Select-Object -Last 1
    if ($head -ne $clones[$path].commit) { $problems += "$path is at $head, not at $($clones[$path].commit)" }
    elseif (@(Invoke-Git $at status --porcelain --untracked-files=no)) { $problems += "$path has uncommitted changes" }
}
if ($problems) { throw "$Worktree is not what runtime\base.json builds:`n  $($problems -join "`n  ")" }

$build = Join-Path $Worktree $base.build_dir
$dll = Join-Path $build 'src\d3d9\d3d9.dll'
if ($Verify) {
    "$Worktree is what runtime\base.json builds: $($base.commit) with the $($patches.Count) patches (tree $want), " +
        "$($submodules.Count) submodule settings, $($clones.Count) clones"
    if (Test-Path -LiteralPath $dll) { "built d3d9.dll: $((Get-Item $dll).Length) bytes, SHA-256 $((Get-FileHash $dll -Algorithm SHA256).Hash.ToLower())" }
    return
}

# Shaders rebuild only while their stamp is missing, and the C++ that embeds them notices the new
# headers only on the next run: delete the stamp, build twice (RESEARCH.md section 29).
if (-not $needsSetup -and -not (Test-Path -LiteralPath (Join-Path $build 'meson-private\coredata.dat') -PathType Leaf)) {
    throw "$build is not configured (meson-private\coredata.dat is missing). Configure the Release build explicitly; refusing Meson's defaults."
}
Import-Module (Join-Path $repo 'tools\lib\VsDevEnv.psm1')
Enter-VsDevEnv | Out-Null
if ($needsSetup) {
    Push-Location $Worktree
    try {
        & .\build_dxvk.ps1 -BuildFlavour $base.flavour -BuildSubDir $base.build_dir -Backend ninja -EnableTracy false -WithShim $false -SkipApics $true -ConfigureOnly $true
        if ($LASTEXITCODE) { throw "runtime setup failed: $LASTEXITCODE" }
    } finally { Pop-Location }
}
# Never import a Debug CRT build, or allow a reconfigure to enable APIC downloads implicitly.
$buildOptionsJson = @(python -m mesonbuild.mesonmain introspect --buildoptions $build)
if ($LASTEXITCODE) { throw "meson build-option check failed: $LASTEXITCODE" }
$buildOptions = @{}
foreach ($option in (($buildOptionsJson -join "`n").TrimStart([char]0xfeff) | ConvertFrom-Json)) {
    $buildOptions[$option.name] = $option.value
}
if ($base.flavour -ne 'release' -or $buildOptions.buildtype -ne 'release' -or
    $buildOptions.backend -ne 'ninja' -or $buildOptions.optimization -ne '3' -or
    $buildOptions.b_vscrt -notin @('from_buildtype', 'md') -or
    $buildOptions.enable_tracy -ne $false -or $buildOptions.remix_with_shim -ne $false -or
    $buildOptions.download_apics -ne $false) {
    throw 'Expected a Release/Ninja build with optimization=3, the release DLL CRT, Tracy/shim off and download_apics=false. Configure those options explicitly before rebuilding.'
}
# The fork computes its version at configure time, so an existing build must notice the new commit.
if (-not $needsSetup) {
    python -m mesonbuild.mesonmain setup --reconfigure $build $Worktree
    if ($LASTEXITCODE) { throw "meson reconfigure failed: $LASTEXITCODE" }
}
Remove-Item -LiteralPath (Join-Path $build 'src\dxvk\_built_shaders.txt') -ErrorAction SilentlyContinue
foreach ($pass in 1, 2) {
    python -m mesonbuild.mesonmain compile -C $build
    if ($LASTEXITCODE) { throw "meson compile (pass $pass) failed: $LASTEXITCODE" }
}
$sha = (Get-FileHash $dll -Algorithm SHA256).Hash.ToLower()
"d3d9.dll $((Get-Item $dll).Length) bytes, SHA-256 $sha"
if (-not $NoImport) {
    python (Join-Path $repo 'tools\inputs.py') import runtime --file "$dll=files/d3d9.dll"
    if ($LASTEXITCODE) { throw "inputs.py import failed: $LASTEXITCODE" }
    # What the stored d3d9.dll was built from (base.json "packaged"): tools\check_repo.py fails while
    # runtime\ differs from it.
    $where = Invoke-Git $Worktree log -1 --format='%D %h' | Select-Object -Last 1
    $record = [ordered]@{ 'd3d9.dll' = $sha; built_from = "$where (with what the rest of this record names)"; commit = $base.commit
                          submodules = $base.submodules; clones = $base.clones; files = [ordered]@{} }
    $inputs = @($patches) + @(Get-ChildItem (Join-Path $PSScriptRoot 'submodules') -Filter '*.patch' -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($file in $inputs) {
        $record.files[$file.FullName.Substring($PSScriptRoot.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
    }
    $recordPath = Join-Path $repo 'out\tmp\runtime-packaged.json'
    New-Item -ItemType Directory -Force (Split-Path $recordPath) | Out-Null
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))
    python -I -c "import json, sys; path, new = sys.argv[1], sys.argv[2]; data = json.load(open(path, encoding='utf-8')); data['packaged'] = json.load(open(new, encoding='utf-8')); open(path, 'w', encoding='utf-8', newline='\n').write(json.dumps(data, indent=1, ensure_ascii=False) + '\n')" $basePath $recordPath
    if ($LASTEXITCODE) { throw "runtime\base.json could not be updated: $LASTEXITCODE" }
}
