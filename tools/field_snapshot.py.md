# field_snapshot.py

M7's safety net for putting the loader into a real install (default: the field install
`...\common\GarrysMod`): a **snapshot** before, and a **one-command rollback** after. Rollback never
deletes anything, never writes through a link, never writes over Steam's files, and changes nothing
when the snapshot is damaged (the R1 review's R1-009 to R1-013).

```powershell
python tools\field_snapshot.py --snapshot out\m7\snapshot snapshot            # before anything else
python tools\field_snapshot.py --snapshot out\m7\snapshot rollback            # undo everything
```

Snapshot options: `--root` (default the field install), `--registry-key` (default
`HKCU\Software\Valve\Source\garrysmod`), `--manifests-from <install>` (the Steam install whose depot
manifests describe this one, for a copy such as the PoC), `--no-depot-check` (see
[Steam's files](#steams-files)). Rollback option: `--config Debug|Release` (the build whose
uninstaller identity to use, default Release).

## What the snapshot records (`<snapshot>\snapshot.json`, schema 3)

| Kind | Where | How |
|---|---|---|
| Kept files | every file directly inside the root, `garrysmod`, `garrysmod\cfg`, `bin\win64` and `garrysmod\lua\bin` that no Steam depot lists (the user's DXVK `d3d9.dll` and `vulkan-1.dll`, the MMD Hot Loader and Jolt files, `console.log`, `cl.db`, logs, configs), plus `config.cfg`, `client.vdf`, `server.vdf`, `autoexec.cfg`, `mountdepots.txt`, `addonnomount.txt`, `user.conf`, `rtx.conf`, `dxvk.conf`, `imgui.ini` and the user's loader allowlist `native-loader\config.json`, even when a depot lists them or they are absent | copied to `<snapshot>\files\` with size and SHA-256; the copy must hash like the file (files over 2 GiB: hash only). A kept file the depot manifests list as Steam's own, not as a user-config file, is marked `steam`. A link or folder in a kept file's place is not kept (the listings record entry kinds) |
| Listings | those five folders, `garrysmod\addons`, `garrysmod\data`, `crashes` | every entry's name and kind: `file`, `folder` or `link` |
| Watched trees | everything below `garrysmod\data` and `garrysmod\settings` | size and time of each file, each folder and link (too many to copy: the field install's data folder is 61 GB) |
| The loader's paths | `bin\win64\winmm.dll`, `native-loader\`, `rtx-remix\`, `garrysmod\data\native-loader\` | present or not |
| GMod's shared settings | the registry key | `reg export` to `<snapshot>\registry.reg` with its SHA-256 and size (the export must read back and hold the key, or the snapshot fails), or recorded as absent |
| Steam | the install's app manifest and depot manifests | `steam_managed` (the `appmanifest_*.acf`, or null), `depot_check` (whether the manifests were read), `no_depot_check` (the flag) |

### Steam's files

An install is **Steam-managed** when its library's `steamapps` folder holds an `appmanifest_*.acf`
whose `installdir` is the install's folder name. Its depot manifests, or those of
`--manifests-from`, tell Steam's files from the user's: Steam's are not copied, except the
user-config names above.

- When Steam manages the install, or `--manifests-from` is given, and the manifests cannot be read
  (not cached, damaged, encrypted names), snapshot **refuses** and says why. Let Steam finish
  updating or verifying the game so it caches them, or pass `--no-depot-check`.
- `--no-depot-check` reads no manifests: every file in the five folders is kept, and the snapshot
  records the flag. Rollback still reads the manifests if it can by then.
- Without a Steam install and without `--manifests-from` (the tests' synthetic installs), every file
  in the five folders is kept and there is no depot check.

## What rollback does (`<snapshot>\rollback.json`)

0. **Refusals, before anything changes:** a snapshot of another schema (schema 2 and older lack the
   entry kinds and hashes a safe rollback needs; roll those back with the version that took them),
   an install folder that is gone, a running `gmod.exe` from the install, a snapshot folder that is no
   longer on the install's volume, and **any saved copy it may write back that is missing or whose
   size or SHA-256 differs from `snapshot.json`** (each one is named).
1. When the bootstrap is installed and was not before: [`uninstall-loader.ps1`](uninstall-loader.ps1.md)
   `-RemoveConfig -AllowSteamManaged` (everything the journal lists, then the bootstrap and
   `native-loader\`, `config.json` included; step 3 puts back the user's).
2. Moves into `<snapshot>\debris\<time>\` (`<time>.1`, ... when that folder exists), at its install
   path:
   - every entry of the listed folders that is new, or of another kind than at the snapshot (a
     folder replaced by a link: the link moves, its target is untouched), shallowest folders first;
     a listed folder or link that was not there goes as a whole;
   - a kept file that was absent at the snapshot (a new `native-loader\config.json`, say);
   - every new file or folder below the watched trees.

   A rename: links move as links and are never followed. A name the debris folder already holds gets
   `.1`, `.2`, ... (`moved_as`). **Nothing is ever deleted:** an entry that cannot be renamed, or that
   sits inside a link, stays where it is and is listed under `left_in_place` with the reason, and the
   rollback is not clean.
3. Writes back every kept file that changed or went missing:
   - in place, so a file hard-linked from elsewhere stays linked (and the other copy is back too);
   - **never through a link:** the install root and every folder on the way must be ordinary ones (an
     entry of a listed folder that became a link moved out in step 2, so the file goes into a new
     ordinary folder; a link anywhere else above the file stops its restore, under `errors`), and the
     opened file must resolve to its own path before a byte is written, so a link that appears in the
     meantime is refused too;
   - **never over Steam's files:** a kept file the depot manifests (the snapshot's or the rollback's)
     list, other than as a user-config file, is not written back (`steam_files_not_restored`); the
     depot check verifies it instead. When neither the snapshot nor the rollback could read the
     manifests of a Steam-managed install, only the user-config names above go back; the others are
     named under `errors`, and rollback can run again once Steam has cached the manifests.
4. The registry: `registry.reg` is imported only when it has its recorded SHA-256, reads back
   (strictly: a cut-off or damaged export does not parse) and holds the key. Only when the import
   succeeded and the key's export after it reads back are the values and subkeys the export does not
   have deleted (names compared without case, as Windows does), so the key equals the export.
   Otherwise nothing is imported or pruned and `registry.error` says why. A key that was absent is
   deleted.
5. Checks: the listings match (names and kinds), every kept file has its hash, the registry export
   after equals the one before, no new file is left below the watched trees, and, when the depot
   manifests can be read, every depot file verifies (the check of
   [`steam\verify_install.py`](steam/verify_install.py.md), run in this process). Files below the
   watched trees that a session **changed** or removed cannot be put back; they are listed under
   `watched` and do not fail the rollback.

`clean: true` needs every check to hold, nothing in `left_in_place` or `errors`, no registry `error`,
and, for a Steam-managed install or one snapshot with `--manifests-from`, the depot check to have run
(`depot_check: true`).

| `rollback.json` key | Holds |
|---|---|
| `uninstall` | the uninstaller's exit code, or null when it did not run |
| `debris` | this rollback's debris folder |
| `moved`, `moved_as` | entries moved into it; those stored under a numbered name, with that name |
| `left_in_place` | `{entry: why it was not moved}` |
| `restored`, `errors` | kept files written back; what could not be done, and why |
| `steam_files_not_restored` | changed kept files that are Steam's, never written back |
| `registry` | `error` (why nothing was imported or pruned, or null), `import_exit`, `pruned`, `differences` |
| `listing_differences`, `kept_differences`, `watched` | what the checks found (`added`, `missing`, `changed` kind per listing) |
| `steam_managed`, `depot_check`, `depot_check_skipped`, `no_depot_check`, `verify` | the depot check: whether it ran, why not, and its result |
| `clean` | see above |

Schema 2's `deleted` key is gone: rollback never deletes.

Exit codes: snapshot 0 when taken, 1 when refused; rollback 0 only when `clean: true`, 1 when refused
or when something remains (read `rollback.json`); 2 for a command-line error. Running rollback again
is safe and finds nothing left to do.

## Side effects and limits

- Snapshot refuses while a `gmod.exe` from the install runs, a second snapshot into the same folder, a
  snapshot folder inside the install or on another volume (rollback renames into it, and a rename
  cannot cross volumes), a Steam-managed install whose depot manifests it cannot read (unless
  `--no-depot-check`), and a registry export it cannot read back.
- Writes only the snapshot folder and, on rollback, the install's paths described above and the
  registry key.
- Its PowerShell children (the game check, the uninstaller) start without `PSModulePath`, so Windows
  PowerShell 5.1 builds its own module path even when this runs under PowerShell 7, whose modules it
  cannot load (R1-029). A game check that cannot run refuses instead of passing.
- Not covered: caches the game rewrites every session (`garrysmod\cache`, `ChromiumCache`,
  `GPUCache`: only their names are compared, as root entries), the content of files below the
  watched trees, and, of the `native-loader` folder the uninstaller removes, anything but
  `config.json`.
- `reg import` cannot give back a `REG_SZ` value that holds a line break (`reg export` writes it over
  several lines, and the import leaves the value as it is); rollback then reports it under
  `registry.differences`.
