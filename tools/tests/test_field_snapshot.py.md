# test_field_snapshot.py

Unit tests for [`field_snapshot.py`](../field_snapshot.py.md). Each test builds a small fake game
install in a temporary folder under `out\tmp`, laid out like a Steam library
(`library\steamapps\common\GarrysMod`; Steam manages it only in the tests that add its app manifest).
It holds the user's DXVK `d3d9.dll`, a `vulkan-1.dll`, configs, a log, a database, data and settings
files, an add-on, a module, a crash dump, and a file hard-linked from outside the install. Each test
also gets a throwaway registry key `HKCU\Software\NativeLoaderTest_<random>` holding every kind of
value `reg export` writes: DWORD, string, empty and default values, escaped quotes in a name, binary
data over several lines, multi-string and expandable string. The field install, the PoC and GMod's
own registry key are never touched.

Some tests run the script as a command. Others call it in this process so they can stand in for part
of the system: a rename that fails, a `reg import` that fails, a snapshot folder on another volume
(`os.stat` reports another device for it), a synthetic Steam folder whose depot manifests are built
with [`steam\tests\_fixtures.py`](../steam/tests/_fixtures.py.md), checks made blind to a link, and
`powershell` calls recorded instead of run.

```powershell
cd tools; python -m unittest tests.test_field_snapshot -v    # or tools\test.ps1
```

Set `TEMP` and `TMP` to the repo's `out\tmp` first when running it outside `tools\test.ps1`.

Covers:

- A whole round: snapshot; a simulated session (the real bootstrap installed with
  [`install-loader.ps1`](../install-loader.ps1.md) when a Debug or Release build exists; configs and
  the log changed, kept files overwritten and deleted, a hard-linked file written in place, the
  loader's folders, package add-on, module, generated cfg, seed data, Remix's `imgui.ini`, a crash
  dump, and new files and folders below existing data and settings folders created; registry values
  changed and added, a new subkey); rollback. Then every kept file is back byte for byte, the hard
  link still holds and the linked copy elsewhere is back too, every new entry is gone from the install
  and is in the snapshot's debris folder, nothing was left in place or deleted, a changed file below a
  watched folder is reported, the registry key equals the export (changed values back, added value
  and subkeys gone), the bootstrap was uninstalled (exit 0), and a second rollback has nothing left
  to do.
- A registry key that did not exist at the snapshot is deleted again.
- Refusals: a second snapshot into the same folder, a snapshot folder inside the install (nothing is
  created), and snapshots written by older versions of the script (no schema, schema 2).
- A difference rollback cannot repair (a folder of the install deleted) fails it with the listing
  difference named.
- R1-009, never delete: a new file and folder that cannot be renamed into the debris folder stay
  where they are, under `left_in_place`, and the rollback is not clean; a name the debris folder
  already holds gets `.1`, directly and through a rollback whose debris folder an earlier one in the
  same second made; snapshot and rollback both refuse a snapshot folder on another volume, and the
  refused rollback changes nothing.
- R1-010, never through a link: `garrysmod\cfg` replaced by a junction moves to the debris folder as
  a junction, its target untouched, and the kept files go back into a new ordinary folder;
  `bin\win64` (inside `bin`, which no listing covers) replaced by a junction stops the restore of
  every file below it, writes nothing into its target and fails the rollback; and with the checks
  made blind to the junction, the write itself refuses the file that opens outside the install.
- R1-011, prune only after a verified import: a `registry.reg` cut short by a whole subkey (still
  parsable, but not its recorded SHA-256), a failing `reg import`, and an export that does not hold
  the key (recorded as if the snapshot had written it) each leave every value in place, prune
  nothing, name the reason under `registry.error` and fail the rollback.
- R1-012, never over Steam's files: snapshot refuses a Steam-managed install whose depot manifests
  are not cached, naming the app manifest and `--no-depot-check`, which it then accepts and records
  (in this process and on the command line). A snapshot taken that way holds a copy of Steam's
  `gmod.exe`; after a Steam update, rollback without manifests writes back only the user-config
  `autoexec.cfg` and is not clean, and once the manifests are cached a second rollback leaves Steam's
  file, puts back the user's `d3d9.dll`, verifies the depot and is clean. A kept file the snapshot's
  manifests listed as Steam's is not written back when the rollback cannot read them.
- R1-013, copies checked first: a saved copy with the wrong size and a missing one stop the rollback
  before it uninstalls the bootstrap, moves, writes or prunes anything, and both are named.
- R1-026, the user's allowlist: an existing `native-loader\config.json` comes back byte for byte
  after a session rewrote it and the uninstaller removed `native-loader`; a new one goes to the
  debris folder while the rest of an existing `native-loader` folder stays.
- R1-029, PowerShell's module path: every `powershell` child (the game check twice, the uninstaller)
  gets an environment without `PSModulePath`, and a game check that cannot run refuses. With a build,
  a rollback started with an inherited module path whose first `Microsoft.PowerShell.Utility` is a
  Core-only module (as PowerShell 7 passes on) still uninstalls the bootstrap. That test makes the
  module in its temporary folder and skips itself if Windows PowerShell resolves `Get-FileHash`
  anyway.

The tests that install the real bootstrap need `tools\build.ps1` to have run. Without a build, the
round trip and the R1-013 and R1-026 tests take their branch without it, and the R1-029 rollback test
is skipped.

Side effects: the temporary folder and the registry key, both removed afterwards; child `python`,
`powershell` and `reg` processes. Exit code: unittest's (0 when all pass).
