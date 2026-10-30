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
    # Build only; leave packages\runtime as it is.
    [switch] $NoImport
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$base = Get-Content (Join-Path $PSScriptRoot 'base.json') -Raw | ConvertFrom-Json
$patches = @(Get-ChildItem (Join-Path $PSScriptRoot 'patches') -Filter '*.patch' | Sort-Object Name)
if (-not $patches) { throw 'runtime\patches holds no patches' }
if (-not $Worktree) { $Worktree = Join-Path $Fork '.claude\worktrees\nl-runtime' }

function Invoke-Git([string] $Where) {
    $output = & git -C $Where @args 2>&1
    if ($LASTEXITCODE) { throw "git $($args -join ' '): $output" }
    $output
}

function Get-PatchSubject([string] $Path) {
    # The Subject header, unfolded (a long one continues on lines that start with a space).
    $subject = $null
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if ($line -eq '') { break }
        if ($null -ne $subject) {
            if ($line -match '^\s') { $subject += ' ' + $line.Trim(); continue }
            break
        }
        if ($line.StartsWith('Subject: ')) { $subject = $line.Substring(9) }
    }
    if ($null -eq $subject) { throw "$Path has no Subject header" }
    $subject -replace '^\[PATCH[^\]]*\]\s*', ''
}

Invoke-Git $Fork cat-file -e "$($base.commit)^{commit}" | Out-Null
$subjects = @($patches | ForEach-Object { Get-PatchSubject $_.FullName })
if (-not (Test-Path $Worktree)) {
    Invoke-Git $Fork worktree add --detach $Worktree $base.commit | Out-Null
    Invoke-Git $Worktree am --3way --keep-cr @($patches.FullName) | Out-Null
    Invoke-Git $Worktree submodule update --init --recursive | Out-Null
    Push-Location $Worktree
    try { & .\build_dxvk.ps1 -BuildFlavour $base.flavour -BuildSubDir $base.build_dir -Backend ninja -EnableTracy false }
    finally { Pop-Location }
} else {
    # An existing tree must hold exactly the base and the patches, in order, by subject.
    $have = @(Invoke-Git $Worktree log --reverse --format=%s "$($base.commit)..HEAD")
    if (($have -join "`n") -ne ($subjects -join "`n")) {
        throw "$Worktree is not $($base.commit) plus runtime\patches (it has: $($have -join '; '))"
    }
    $dirty = Invoke-Git $Worktree status --porcelain --untracked-files=no --ignore-submodules=all
    if ($dirty) { throw "$Worktree has uncommitted changes: $dirty" }
}

# Shaders rebuild only while their stamp is missing, and the C++ that embeds them notices the new
# headers only on the next run: delete the stamp, build twice (RESEARCH.md section 29).
Import-Module (Join-Path $repo 'tools\lib\VsDevEnv.psm1')
Enter-VsDevEnv | Out-Null
$build = Join-Path $Worktree $base.build_dir
Remove-Item -LiteralPath (Join-Path $build 'src\dxvk\_built_shaders.txt') -ErrorAction SilentlyContinue
foreach ($pass in 1, 2) {
    python -m mesonbuild.mesonmain compile -C $build
    if ($LASTEXITCODE) { throw "meson compile (pass $pass) failed: $LASTEXITCODE" }
}
$dll = Join-Path $build 'src\d3d9\d3d9.dll'
$sha = (Get-FileHash $dll -Algorithm SHA256).Hash.ToLower()
"d3d9.dll $((Get-Item $dll).Length) bytes, SHA-256 $sha"
if (-not $NoImport) {
    python (Join-Path $repo 'tools\inputs.py') import runtime --file "$dll=files/d3d9.dll"
    if ($LASTEXITCODE) { throw "inputs.py import failed: $LASTEXITCODE" }
}
