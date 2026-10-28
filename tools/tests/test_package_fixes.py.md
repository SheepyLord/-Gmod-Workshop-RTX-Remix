# test_package_fixes.py

Unit tests for [`package_fixes.py`](../package_fixes.py.md). Each test builds a small fake fixes repo
in a temporary folder under `out\tmp`: add-ons (with a submodule's `.git` file, a `.git` folder,
`Thumbs.db`, `desktop.ini`, a `.bak`, a loose file), Remix mods (one empty), the files the package
must leave out (menu, gamemode and HTML files, `cfg\`, `data\`, root configs, PDB), built modules and
an `autoexec.cfg` with an RTX section, a personal section and every kind of line the parser skips.
The real fixes repo is never read; the real Lua companion is (read only).

```powershell
cd tools; python -m unittest tests.test_package_fixes -v    # or tools\test.ps1
```

Covers: the manifest's keys, kinds, `root_files`, `module_overrides` and file list exactly; every
listed file's size and SHA-256, and no unlisted file under `native/`; what stays out (Steam files,
configs, junk, by-products, the companion's `.md` files) and the summary's `left_out` and `junk`;
`session_cvars` from the RTX section (later assignments win, every skipped line with its reason) and
from a whole file without one; the patch sets' shape and the loader's rules, and that they equal the
table in [RESEARCH.md](../../docs/RESEARCH.md) section 12; the switches (`--no-patch-sets`,
`--no-session-cvars`, `--exclude-addon` including the companion, `--id`, `--version`, `--name`,
`--with-debug-module`); the default version from the newest input and the main module's hash, and
byte-identical manifests and archives from the same inputs; `--force`; a `.gma` with the same files
in their original case; refusals that leave no partial output (non-ASCII and `~1` names, a bad add-on
folder name, an empty add-on, missing modules or shader, outputs inside the fixes repo, ...); the text
summary. When `nlctl.exe` 0.2.0 or newer is built (`out\build\win64-debug` or `win64-release`), it
must accept both the folder and the archive (`nlctl manifest`); otherwise that case is skipped.

Side effects: only the temporary folder, removed afterwards. Exit code: unittest's (0 when all pass).
