# test_steam_manifest.py

Unit tests for [`steam_manifest.py`](../steam_manifest.py.md), using manifests built by
[`_fixtures.py`](_fixtures.py.md):

- Parsing: depot and manifest ids, directory and user-config flags, SHA-1 values, `\` to `/` paths,
  all-zero hashes read as "no hash", the encrypted-filenames flag, and rejection of non-manifest files.
- `safe_relpath`: accepts normal relative paths; refuses `..`, drive letters, absolute paths and empty paths.
- `locate_install`: finds the cached manifests through a fake `appmanifest_4000.acf`, names any
  manifest that is not cached, and refuses a folder outside `steamapps\common`.

Run from `tools\steam\`: `python -m unittest discover -s tests` (or `tools\test.ps1`).
