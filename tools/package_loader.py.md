# package_loader.py

Builds the end-user bundle of the loader
([ADR 0017](../docs/decisions/0017-release-bundle-and-ci.md)). The GitHub workflow
([`.github/workflows/build.yml`](../.github/workflows/build.yml)) runs it after the build and
publishes the zips as an artifact, and as a release on a `v*` tag. It also runs locally.

```powershell
tools\build.ps1 -Config Release
python tools\package_loader.py                 # out\dist\gmod-native-loader-<version>+<commit>.zip
python tools\package_loader.py --json
```

## Inputs

- The built `winmm.dll` and `winmm.pdb`, from `out\build\win64-<config>\loader\proxy`. Choose the
  build with `--config Debug|Release` (Release by default), or point `--build-dir` at another folder.
- [`dist/native-loader/config.json`](../dist/native-loader/config.json): the default settings, which
  allow the project's Workshop item 3829070317. They are checked before packing: strict JSON,
  schema 1, an `allow` object, and no key the loader would refuse.
- [`dist/README-native-loader.txt`](../dist/README-native-loader.txt): install, settings, updating
  and removing, for players.
- The version, from the `project(... VERSION x.y.z)` line of `CMakeLists.txt`.
- The commit: `GITHUB_SHA` in the workflow, otherwise `git rev-parse HEAD`. Its first eight digits go
  into the file names.

## Outputs (`--out`, default `out\dist`)

- **`gmod-native-loader-<version>+<commit>.zip`**, laid out to be extracted into the Garry's Mod folder:
  - `bin/win64/winmm.dll`;
  - `native-loader/config.json`;
  - `README-native-loader.txt`.

  The text files get CRLF line endings. Every member has a fixed time, so two bundles of the same
  files are the same bytes.
- **`gmod-native-loader-<version>+<commit>-symbols.zip`**: `winmm.pdb`, for crash reports. It is left
  out when there is no PDB.
- **A summary:** version, commit, the DLL's size and SHA-256, and the bundle's SHA-256.

Exit 0 on success, and 1 when the DLL is missing or not a Windows image, the config would be refused,
or the commit cannot be told.

Tests: [`tests/test_package_loader.py`](tests/test_package_loader.py.md).
