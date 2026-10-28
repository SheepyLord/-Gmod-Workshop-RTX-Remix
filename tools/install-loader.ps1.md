# install-loader.ps1

Copies the built, identified bootstrap and its PDB to an x64 GMod install. Defaults to the PoC,
Release. Does not build. Uses the version resource (`OriginalFilename` and `InternalName` =
`nl_winmm.dll`, `ProductName` = `GMod Native Loader`) to reject foreign DLLs. Records SHA-256 in
`native-loader/bootstrap-install.json`; replacement/removal requires the installed files to match
that receipt, or the selected build if manually installed. User-edited files are refused.

```powershell
tools\build.ps1 -Config Release
tools\install-loader.ps1
tools\install-loader.ps1 -Config Debug -GameRoot H:\Games\MyPoC
tools\install-loader.ps1 -Uninstall
tools\install-loader.ps1 -Uninstall -RemoveState
```

Inputs: `-GameRoot`, `-Config Debug|Release`, built DLL/PDB in `out/build/win64-<config>/loader/proxy`.
`-Uninstall` removes only verified DLL/PDB; state stays by default. `-RemoveState` (requires
`-Uninstall`) deletes the loader's own control and log files in `native-loader` (`config.json`,
`bootstrap-install.json`, `disable`, `session_cvars.json`, `logs\loader.log` and its rotations),
then every folder left empty, then `native-loader` itself if empty. Any other file stays and is
listed in a warning: a payload file the user changed (`nlctl uninstall` leaves those in place), or a
journal `nlctl uninstall` had to keep. Reparse points in affected paths or the removal tree are
refused, and the absolute target must equal the game's own `native-loader` directory.

A game whose folder matches `installdir` in an `appmanifest_*.acf` in its library's `steamapps`
requires `-AllowSteamManaged` for either install or uninstall. That flag is explicit authorization
for this script; repository agents still follow AGENTS.md concerning the field install. Steam
manifests/settings are never written. A foreign `winmm.dll` is refused even with that flag.

Outputs: DLL/PDB and install receipt. Copy/receipt failures attempt restoration of their original
bytes. No game depot files are replaced. Console reports the result. Exit 0 on success; a
terminating error (nonzero when run in a separate PowerShell process) on invalid input, ownership,
hash mismatch, Steam-managed refusal or I/O failure.

Standard PowerShell `-WhatIf` performs all preflight checks and writes nothing.
