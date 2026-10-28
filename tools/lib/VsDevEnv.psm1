# Finds the MSVC x64 toolchain and imports its environment into the current PowerShell process.

function Find-VsInstallation {
    <# Returns the folder of a Visual Studio / Build Tools install that has the x64 C++ tools, or $null. #>
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -prerelease -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
            Select-Object -First 1
        if ($path -and (Test-Path (Join-Path $path 'VC\Auxiliary\Build\vcvars64.bat'))) { return $path }
    }
    # vswhere does not list every Build Tools install (it lists none on the main dev machine),
    # so also probe the standard install folders.
    foreach ($base in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        foreach ($version in '18', '2022') {
            foreach ($edition in 'Enterprise', 'Professional', 'Community', 'BuildTools') {
                $path = Join-Path $base "Microsoft Visual Studio\$version\$edition"
                if (Test-Path (Join-Path $path 'VC\Auxiliary\Build\vcvars64.bat')) { return $path }
            }
        }
    }
    return $null
}

function Enter-VsDevEnv {
    <# Imports the vcvars64 environment (cl, link, Windows SDK, bundled CMake and Ninja). Safe to call twice. #>
    [CmdletBinding()]
    param()
    if ($env:VSCMD_ARG_TGT_ARCH -eq 'x64' -and (Get-Command cl.exe -ErrorAction SilentlyContinue)) { return }

    $vs = Find-VsInstallation
    if (-not $vs) { throw 'No Visual Studio or Build Tools install with the x64 C++ tools was found.' }
    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    $lines = & cmd.exe /d /s /c "`"$vcvars`" >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) { throw "vcvars64.bat failed: $vcvars" }
    foreach ($line in $lines) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0, $i), $line.Substring($i + 1), 'Process') }
    }

    # vcvars normally puts the bundled CMake and Ninja on PATH; add them if this install did not.
    foreach ($tool in 'CMake\CMake\bin', 'CMake\Ninja') {
        $dir = Join-Path $vs "Common7\IDE\CommonExtensions\Microsoft\$tool"
        if ((Test-Path $dir) -and -not (($env:PATH -split ';') -contains $dir)) { $env:PATH = "$dir;$env:PATH" }
    }
    Write-Verbose "MSVC environment from $vcvars"
}

Export-ModuleMember -Function Find-VsInstallation, Enter-VsDevEnv
