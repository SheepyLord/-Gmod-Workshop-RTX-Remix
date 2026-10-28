# poc_deploy_check.ps1

M3's acceptance check on the PoC install, without starting the game. It runs the whole deployer
life cycle on a real install and proves the install is exactly as it was afterwards:

1. Refuses unless the PoC is clean: no `native-loader` folder, no `bin\win64\winmm.dll`, the game not
   running. Records every file (path, size, last write time) and folder.
2. Builds a test package with [`gmapack`](gmapack/gmapack.py.md) under the evidence folder: a payload
   file and root files in three areas (`rtx-remix/mods`, `garrysmod/lua/bin`, and a create-only
   seed file in `garrysmod/data/nl_poc_test`), and validates it with `nlctl manifest`.
   `garrysmod/cfg` is no longer a package area ([ADR 0014](../docs/decisions/0014-r1-hardening.md)).
3. Installs the bootstrap ([`install-loader.ps1`](install-loader.ps1.md)) and writes a
   `native-loader\config.json` that allowlists only that package (by absolute path).
4. `nlctl apply`: must deploy, with every byte where it belongs. A second `apply` must change
   nothing (0 file-system changes). `nlctl status --verify` must be clean.
5. [`uninstall-loader.ps1`](uninstall-loader.ps1.md) `-RemoveConfig` (always, even if a step failed).
6. The file and folder list must equal the one from step 1, sizes and times included, and
   [`verify_install.py`](steam/verify_install.py.md) `--manifests-from` the field install must
   report every depot file unchanged.

```powershell
tools\build.ps1 -Config Release
tools\poc_deploy_check.ps1
tools\poc_deploy_check.ps1 -GameRoot <another copy> -ManifestsFrom <its Steam install> -Config Debug
```

## Inputs and outputs

- `-GameRoot` (default the PoC), `-ManifestsFrom` (default the field install, read only),
  `-Config` (default Release: which `nlctl.exe` and bootstrap build to use).
- Evidence in `out\poc-deploy\<UTC timestamp>\`: the package and its `.gma`, every `nlctl` report
  (`apply-1.json`, `apply-2.json`, `status.json`), `tree-before.txt` / `tree-after.txt`,
  `verify.json` / `verify.txt`, and `summary.json` with each check.
- Writes to the PoC only through `install-loader.ps1`, `nlctl apply` and `uninstall-loader.ps1`, and
  leaves it as it found it. Never starts the game, never writes the field install or Steam's files.
- Exit 0 when every check passes, 1 when one fails, a terminating error when a precondition fails.
- Hashing the depot files takes about a minute.
