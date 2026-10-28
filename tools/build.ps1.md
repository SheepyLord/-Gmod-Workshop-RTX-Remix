# build.ps1

Configures, builds and tests the C++ loader under [`loader/`](../loader/README.md). Enters the
MSVC x64 environment through [`lib/VsDevEnv.psm1`](lib/VsDevEnv.psm1.md), then runs the CMake presets
from [`CMakePresets.json`](../CMakePresets.json) (`win64-debug` or `win64-release`, Ninja generator)
and CTest.

## Usage

```powershell
tools\build.ps1                            # Debug: configure, build, run CTest
tools\build.ps1 -Config Release            # optimised build, PDBs included
tools\build.ps1 -Clean                     # delete out\build\<preset> first
tools\build.ps1 -NoTests                   # skip CTest
```

## Inputs and outputs

- Reads: the CMake tree (`CMakeLists.txt`, `loader/**`).
- Writes: `out\build\<preset>\` only (git-ignored). `-Clean` deletes that one folder.
- Exit: non-zero when configure, build or tests fail (the error names the step).

## Notes

- Static CRT (`/MT`), warnings as errors (`/W4 /WX`), debug info in objects (`/Z7`) and one PDB per
  binary; see the root `CMakeLists.txt`.
- Never touches a game install. Deploying a build into an install is a separate script (M1).
- [`test.ps1`](test.ps1.md) calls this script as its last step.
