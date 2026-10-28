# workflow.ps1

Runs the CI build workflow ([`.github/workflows/build.yml`](../.github/workflows/build.yml)) on this
machine, so a build can be tested without waiting for GitHub. The steps are the workflow's build job:

1. [`test.ps1 -Config Release`](test.ps1.md): conventions, the Release build, CTest and the Python
   tests. `-SkipTests` runs [`build.ps1 -Config Release -NoTests`](build.ps1.md) instead.
2. [`package_loader.py --config Release --out out\dist`](package_loader.py.md): the end-user bundle
   and its symbols zip, the same files the workflow keeps as its artifact.
3. With `-Install <game root>` only: [`install-loader.ps1`](install-loader.ps1.md) `-Config Release
   -DefaultConfig` puts the build into that game.

```powershell
tools\workflow.ps1                    # what CI runs; the bundle lands in out\dist
tools\workflow.ps1 -SkipTests         # build and bundle only, for a quick loop
tools\workflow.ps1 -SkipTests -Install H:\SteamLibrary\steamapps\common\GarrysMod_PoC
tools\workflow.ps1 -Install H:\SteamLibrary\steamapps\common\GarrysMod -AllowSteamManaged -ReplaceUntracked
```

## Inputs

- The repository: the CMake tree, the tests, [`dist/`](../dist/native-loader/config.json).
- `-Install`: a game folder with `bin\win64\gmod.exe`. `-AllowSteamManaged` is needed for a folder Steam
  manages, such as the field install. `-ReplaceUntracked` replaces a loader that was put there by hand,
  for example by extracting a bundle; `install-loader.ps1` keeps a copy of it first.

## Outputs and side effects

- `out\build\win64-release\` (the build) and `out\dist\gmod-native-loader-<version>+<commit>.zip` with
  its `-symbols.zip`. The paths are printed at the end.
- With `-Install`: the game's `bin\win64\winmm.dll` and `winmm.pdb`, the install receipt, and a
  `native-loader\config.json` that allows Workshop item 3829070317, only when the game has no config yet.
  Every refusal of `install-loader.ps1` applies: a foreign or edited `winmm.dll`, and a Steam-managed
  install without `-AllowSteamManaged`. Agents follow AGENTS.md rule 1 before installing into the
  field install.
- Nothing is pushed or uploaded. The Workshop item is updated by the git hooks
  ([`publish_workshop.py`](publish_workshop.py.md)), not by this script.

## Exit codes

0 when every step succeeded. A failed step stops the script with a terminating error that names it
(non-zero when run as `powershell -File`): no bundle is made after failed checks, and nothing is
installed after a failed bundle.
