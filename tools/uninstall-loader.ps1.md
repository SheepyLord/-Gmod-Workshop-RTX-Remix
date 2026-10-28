# uninstall-loader.ps1

Removes the native loader from an x64 GMod install, defaulting to the PoC, in two steps:

1. `nlctl uninstall <game root>`: every file and folder the loader deployed, as its journal
   (`native-loader\state.json`) lists them, then the journal and `native-loader\lock`. Files changed
   since the loader placed them, and files that were there before it (adopted), stay and are
   reported. See [loader/cli/README.md](../loader/cli/README.md).
2. [`install-loader.ps1`](install-loader.ps1.md) `-Uninstall`: the bootstrap's `winmm.dll` and PDB,
   only if they are ours and unedited.

```powershell
tools\uninstall-loader.ps1                                # the PoC; keeps native-loader\config.json
tools\uninstall-loader.ps1 -RemoveConfig                  # also deletes the whole native-loader folder
tools\uninstall-loader.ps1 -GameRoot <install> -WhatIf    # checks and nlctl's dry run, changes nothing
```

## Inputs

- `-GameRoot`: the install (default `H:\SteamLibrary\steamapps\common\GarrysMod_PoC`).
- `-Config Debug|Release` (default Release): which build of `nlctl.exe` to use, from
  `out\build\win64-<config>\loader\cli`. Build it first with `tools\build.ps1 -Config Release`.
- `-RemoveConfig`: after the deployed files are gone, delete the whole `native-loader` folder
  (`config.json`, the bootstrap's logs and install receipt) through `install-loader.ps1 -RemoveState`.
  Without it, `config.json` (the user's allowlist) is kept.
- `-AllowSteamManaged`: needed for an install Steam manages, exactly as for `install-loader.ps1`.
  Repository agents still follow AGENTS.md rule 1 for the field install.

## Side effects and exit

- Before anything is removed, `install-loader.ps1 -Uninstall -WhatIf` runs every check of the
  bootstrap step (an x64 install, the Steam-managed guard, a foreign or edited `winmm.dll`); if one
  fails, nothing is removed.
- `-WhatIf` runs those checks and `nlctl uninstall --dry-run` (what would be deleted) and changes nothing.
- `nlctl uninstall` refuses (exit 1) while this install's `gmod.exe` runs or another deployment holds
  the lock, and stops with exit 2 if the journal is invalid. The bootstrap is then left in place and
  the script fails.
- Exit: 0 on success; a terminating error (non-zero when run as a separate PowerShell process) otherwise.
- Never touches Steam's depot files: the deployer never writes them, and the installer only removes
  its own verified files.
