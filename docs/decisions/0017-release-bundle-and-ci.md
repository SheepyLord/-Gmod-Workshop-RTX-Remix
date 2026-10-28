# 0017: GitHub builds the loader; the release bundle carries a default config that allows the project's item

- Status: Accepted 2026-10-28
- Decided by: the user ("Setup GitHub action to build the winmm.dll. Setup the native-loader\config.json
  for me."), Claude doing the setup the same day. The default allowlist entry is the user's choice, so
  AGENTS.md rule 4 (no loosening without the user's agreement) is met.
- Builds on: [0003](0003-native-trust-allowlist.md) (the allowlist), [0016](0016-one-workshop-item-kept-current.md)
  (item 3829070317)

## Context

[ADR 0016](0016-one-workshop-item-kept-current.md) left a subscriber with three things to do:
install `bin\win64\winmm.dll`, write a `native-loader\config.json` that allowlists the item, and
subscribe. Building `winmm.dll` needed this repository and the MSVC Build Tools, and the config had to
be typed by hand. The loader runs nothing a config does not list, and the user asked for both steps to
be done for them.

## Decision

1. **A GitHub workflow builds the loader:**
   [`.github/workflows/build.yml`](../../.github/workflows/build.yml), on every push of `main`, every
   pull request, and on demand.
   - It runs `tools\test.ps1 -Config Release` on `windows-2022`: conventions, the Release build, CTest
     and the Python tests.
   - It builds the end-user bundle with [`tools/package_loader.py`](../../tools/package_loader.py.md)
     and keeps the zips as a run artifact.
   - On a `v*` tag it also creates a GitHub release with the bundle.
2. **The bundle is extracted into the Garry's Mod folder.** It holds:
   - `bin/win64/winmm.dll`;
   - `native-loader/config.json`, which allows exactly one source: Workshop item 3829070317;
   - `README-native-loader.txt`.

   So a player's whole setup is: extract, subscribe, start the game. The symbols (`winmm.pdb`) ship in
   a separate zip.
3. **The default config lives in [`dist/native-loader/config.json`](../../dist/native-loader/config.json).**
   - The bundle ships it.
   - `install-loader.ps1 -DefaultConfig` writes it for a developer install, never over an existing
     `config.json`.
   - The loader itself is unchanged. A missing `config.json` still allows nothing, and the allowlist
     is still the only way anything is deployed or loaded.
4. **The Workshop item is still updated from the developer's machine** (ADR 0016), not by the
   workflow, because uploading needs Steam.

## Consequences

- **A player never types JSON.** Turning RTX off or the loader off is one documented key in the same
  file.
- **The trust decision now comes with the download.** Extracting the bundle means trusting the
  project's item, as ADR 0003 intends: the decision is the player's, made by installing this bundle.
  The README says what the config allows.
- **Updating means replacing only `winmm.dll`.** Extracting a newer bundle over an install would
  replace the player's own `config.json` (Windows asks first), so the README says to replace only
  the DLL.
- **CI runs every test on a clean Windows Server 2022** on each push, which local development never
  did.
  - A machine-specific failure there is a finding, not noise.
  - The likeliest one is `generate_exports.py --check`: the committed export set must cover the
    runner's `winmm.dll`.

## Alternatives considered

- **The loader writes a default config when none exists.** Rejected: it would allow the item for
  anyone who drops in `winmm.dll` for another reason, without any decision of theirs. That loosens
  ADR 0003 for a convenience the bundle gives anyway.
- **A separate installer program.** It would add code that writes into the game folder, for one copy
  step that extracting a zip already does.
- **Publishing releases on every push.** Too many releases. Every push gets an artifact, and tags make
  releases.
