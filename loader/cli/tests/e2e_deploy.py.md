# e2e_deploy.py

CTest `nlctl_e2e_deploy` (registered in [`../CMakeLists.txt`](../CMakeLists.txt)): M3's deployment
through the `nlctl` command line, end to end, on packages built with
[`gmapack.py`](../../../tools/gmapack/gmapack.py.md) in a fake Steam library.

Sources:

- a runtime as a development folder, which shadows a local archive with the same id;
- a root-files package in a Workshop item, wrapped like a legacy upload (LZMA with GMod's footer);
- a binary Lua module as a local archive.

| Step | Check |
|---|---|
| `apply --json` | Deploys all three. Every placed byte and every journal record (`state.json`) is checked against the packages |
| `status --json --verify` | Clean |
| `apply` again | `unchanged`, 0 file-system changes; `state.json` keeps its bytes and its time |
| upgrade, `apply --dry-run` | Reports the replace, but changes nothing on disk |
| `apply` | Generation 2: replace, add and remove as expected; the previous generation's copies are in `native-loader\backup\2` |
| a deployed file changed | `status` exits 1 and names it; with the bytes put back it exits 0 |
| `rollback`, then `apply` | Version 1 back exactly; `apply` is then `held` with 0 changes |
| `rollback` again | Version 2 back; `apply` is `unchanged` |
| lock held through Win32 `CreateFileW` | `apply` exits 1 with `refused` |
| this folder's `gmod.exe` running | `apply` exits 1 with `refused`. A copy of System32's `PING.EXE` stands in for the game; the check is skipped if it cannot be copied |
| `state.json` broken | `apply`, `status` and `uninstall` exit 2 and change nothing |
| `uninstall --dry-run`, then `uninstall` | The game folder is file for file as before the first `apply`; a second `uninstall` is `unchanged`; `rollback` exits 1 |

```powershell
python -I -B loader\cli\tests\e2e_deploy.py --nlctl out\build\win64-debug\loader\cli\nlctl.exe `
  --gmapack tools\gmapack\gmapack.py --scratch out\tmp\e2e_deploy
```

- Inputs: `--nlctl`, `--gmapack`, and `--scratch`, a folder it may delete and recreate.
- Writes only below `--scratch` and removes it on success. The stand-in `gmod.exe` process is
  stopped again even if a check fails.
- Exit 0 when every check passes; otherwise it exits with a message naming the step.
