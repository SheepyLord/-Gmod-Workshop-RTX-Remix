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
tools\install-loader.ps1 -GameRoot <install> -AllowSteamManaged -DefaultConfig   # also the default settings
tools\install-loader.ps1 -GameRoot <install> -AllowSteamManaged -ReplaceUntracked # over a bundle extracted by hand
```

Inputs: `-GameRoot`, `-Config Debug|Release`, built DLL/PDB in `out/build/win64-<config>/loader/proxy`.

`-DefaultConfig` (install only) also writes the release bundle's settings,
[`dist/native-loader/config.json`](../dist/native-loader/config.json), which allow the project's
Workshop item 3829070317 ([ADR 0017](../docs/decisions/0017-release-bundle-and-ci.md)). It writes
them only when the install has no `native-loader\config.json`; an existing one is kept as it is.

`-ReplaceUntracked` (install only) replaces a `winmm.dll` and `winmm.pdb` that no receipt records,
such as a release bundle extracted by hand, when the DLL identifies as the loader. Their bytes are
copied to `native-loader\replaced\` first. Files a receipt records are still refused when they changed,
and a foreign DLL is always refused. [`workflow.ps1`](workflow.ps1.md) `-Install` passes it on.

`-Uninstall` removes only verified DLL/PDB; state stays by default. `-RemoveState` (requires
`-Uninstall`) deletes the loader's own control and log files in `native-loader` (`config.json`,
`bootstrap-install.json`, `disable`, `session_cvars.json`, `replaced\winmm.dll` and `.pdb`,
`remix\non-nvidia.conf` (ADR 0030), `logs\loader.log` and its rotations),
then every folder left empty, then `native-loader` itself if empty. Any other file stays and is
listed in a warning: a payload file the user changed (`nlctl uninstall` leaves those in place), a
journal `nlctl uninstall` had to keep, or the RTX sessions' ReShade settings in `reshade\` (ADR 0028). Reparse points in affected paths or the removal tree are
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
