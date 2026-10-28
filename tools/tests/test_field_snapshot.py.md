# test_field_snapshot.py

Unit tests for [`field_snapshot.py`](../field_snapshot.py.md). Each test builds a small fake game
install in a temporary folder under `out\tmp` (the user's DXVK `d3d9.dll`, a `vulkan-1.dll`, configs,
a log, a database, data and settings files, an add-on, a module, a crash dump, and a file hard-linked
from outside the install) and a throwaway registry key `HKCU\Software\NativeLoaderTest_<random>`.
The field install, the PoC and GMod's own registry key are never touched.

```powershell
cd tools; python -m unittest tests.test_field_snapshot -v    # or tools\test.ps1
```

Covers:

- A whole round: snapshot; a simulated session (the real bootstrap installed with
  [`install-loader.ps1`](../install-loader.ps1.md) when a Debug or Release build exists; configs and
  the log changed, kept files overwritten and deleted, a hard-linked file written in place, the
  loader's folders, package add-on, module, generated cfg, seed data, Remix's `imgui.ini`, a crash
  dump, and new files and folders below existing data and settings folders created; registry values
  changed and added, a new subkey); rollback. Then every kept file is back byte for byte, the hard
  link still holds and the linked copy elsewhere is back too, every new entry is gone from the install
  and is in the snapshot's debris folder, a changed file below a watched folder is reported, the
  registry key equals the export (changed value back, added value and subkeys gone), the bootstrap was
  uninstalled (exit 0), and a second rollback has nothing left to do.
- A registry key that did not exist at the snapshot is deleted again.
- Refusals: a second snapshot into the same folder, a snapshot folder inside the install (nothing is
  created), and a snapshot written by the older version of the script.
- A difference rollback cannot repair (a folder of the install deleted) fails it with the listing
  difference named.

Side effects: the temporary folder and the registry key, both removed afterwards. Exit code:
unittest's (0 when all pass).
