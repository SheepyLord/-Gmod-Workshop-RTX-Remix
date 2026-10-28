# uninstall_tests.ps1

CTest `nlctl_uninstall_loader` (registered in [`../CMakeLists.txt`](../CMakeLists.txt)): tests
[`tools/uninstall-loader.ps1`](../../../tools/uninstall-loader.ps1.md) end to end in synthetic game
folders. It uses the bootstrap and `nlctl` built for the configuration under test, and a package
built with [`gmapack.py`](../../../tools/gmapack/gmapack.py.md) that has a payload file and a root file.

| Check | Expected |
|---|---|
| `-WhatIf` | Nothing is removed |
| The bootstrap DLL edited | The script refuses (`changed or untracked`) before any deployed file is removed |
| Default run | The deployed files, the folders the loader made, the journal, the lock and the bootstrap are gone; `config.json` stays |
| `-RemoveConfig` after a fresh deployment | The game folder is file for file (size, time) as before the first install |
| A folder Steam manages, without `-AllowSteamManaged` | Refused, nothing removed; with the flag, everything removed |

```powershell
powershell -NoProfile -File loader\cli\tests\uninstall_tests.ps1 -Repo . -Config Debug `
  -Python python -Scratch out\tmp\uninstall-tests
```

Inputs: `-Repo`, `-Config Debug|Release` (which builds to use, from `out\build\win64-<config>`),
`-Python`, and `-Scratch`, a folder it deletes and recreates. It writes only below `-Scratch` and
removes it at the end. A failed check throws, which makes the run exit non-zero. Synthetic roots
only: it never touches a game install.
