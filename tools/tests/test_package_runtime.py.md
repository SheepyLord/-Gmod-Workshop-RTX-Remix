# test_package_runtime.py

Unit tests for [`package_runtime.py`](../package_runtime.py.md). Each test builds a small fake
runtime (a few named files, a `usd\` tree, PDB/EXP/LIB/BAK by-products) in a temporary folder under
`out\tmp` and packages it; the real fork build is never read.

```powershell
cd tools; python -m unittest tests.test_package_runtime -v    # or tools\test.ps1
```

Covers: every runtime file listed with its size and SHA-256 and copied byte for byte; by-products
and PDBs left out unless asked for; `--d3d9-from`; config layers in order, `--env`, the switches,
id/version/name; the default version derived from `d3d9.dll` and a reproducible manifest; the
loader's path rules (shared cases with `nl::paths`); refusals that leave no partial output and
never touch a non-package folder; `--force`; a `.gma` with the same files in their original case,
byte-identical when rebuilt. When `nlctl.exe` is built (`out\build\win64-debug` or
`win64-release`), it must accept both the folder and the archive (`nlctl manifest`); otherwise that
case is skipped.

Side effects: only the temporary folder, removed afterwards. Exit code: unittest's (0 when all pass).
