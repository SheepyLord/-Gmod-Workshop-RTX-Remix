# test_package_reshade.py

Unit tests for [`package_reshade.py`](../package_reshade.py.md). No ReShade download is needed: each
test makes a stand-in setup (bytes, then a ZIP holding a `ReShade64.dll`) and a stand-in licence,
and pins their hashes as version `9.9.9` for the test's duration. Scratch goes in a temporary folder
under `out\tmp`.

```powershell
cd tools; python -m unittest tests.test_package_reshade -v    # or tools\test.ps1
```

Covers:

- **The part.** `--out` and `--gma` together: the manifest (id `reshade`, kind `reshade`,
  `requires_loader >=0.5.0`, `"reshade": {"layer": ...}`), the DLL byte-identical to the one in the
  setup, the licence copied, the notice, and the layer manifest named `VK_LAYER_nativeloader_reshade`
  with `.\ReShade64.dll` and no `disable_environment`. Every listed size and SHA-256 matches its file,
  the archive holds the DLL, and no work folder is left behind.
- **Refusals.** A setup with another hash, a version that is not pinned, a licence with another hash,
  and a setup whose ZIP has no `ReShade64.dll`: exit 1 or `PackageError`, and nothing is written.
- **`--force`.** An existing folder is refused without it and replaced with it.

Side effects: the temporary folders, removed afterwards. Exit code: unittest's (0 when all pass).
