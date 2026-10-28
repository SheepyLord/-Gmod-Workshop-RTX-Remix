# test_package_loader.py

Unit tests for [`package_loader.py`](../package_loader.py.md). They bundle a fake `winmm.dll` and PDB
under `out\tmp`. Nothing else is touched.

```powershell
cd tools; python -m unittest tests.test_package_loader
```

| Test | Checks |
|---|---|
| the bundle holds the loader, the default config and the README | the zip's three members; the DLL's bytes; `config.json` equals `dist/native-loader/config.json` and allows item 3829070317; the symbols zip holds `winmm.pdb` |
| two bundles of the same files are the same bytes | fixed member times |
| no loader or no image is refused | a missing DLL, and a file that is not a Windows image |
| a config the loader would refuse is refused | the wrong schema, an unknown key, invalid JSON |
| the version comes from CMake | |
| the shipped config is accepted by the loader | runs only when `nlctl.exe` is built: `nlctl plan` of a synthetic game folder holding the shipped `config.json` succeeds and plans for item 3829070317 |

Exit 0 when every test passes.
