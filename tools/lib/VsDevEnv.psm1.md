# VsDevEnv.psm1

PowerShell module that puts the MSVC x64 toolchain into the current process, so `cl`, `link`, the
Windows SDK and the CMake and Ninja that ship with Visual Studio work from any shell.

| Function | Does |
|---|---|
| `Find-VsInstallation` | Returns a Visual Studio / Build Tools folder that has `VC\Auxiliary\Build\vcvars64.bat`. Tries `vswhere` first, then the standard folders for VS 2022 and 18 (Enterprise, Professional, Community, BuildTools). |
| `Enter-VsDevEnv` | Runs `vcvars64.bat` in `cmd`, copies the resulting environment into this process, and adds the bundled CMake and Ninja to `PATH` if needed. Does nothing when an x64 MSVC environment is already active. |

The folder probe exists because `vswhere` lists no instance on the main development machine even
though Build Tools 2022 is installed (see [docs/ENVIRONMENT.md](../../docs/ENVIRONMENT.md)).

## Usage

```powershell
Import-Module tools\lib\VsDevEnv.psm1
Enter-VsDevEnv
cl /?   # now available
```

Used by [`build.ps1`](../build.ps1.md). Changes only environment variables of the current process.
