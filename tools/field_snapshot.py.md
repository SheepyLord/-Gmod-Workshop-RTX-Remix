# field_snapshot.py

M7's safety net for putting the loader into a real install (default: the field install
`...\common\GarrysMod`): a **snapshot** before, and a **one-command rollback** after.

```powershell
python tools\field_snapshot.py --snapshot out\m7\snapshot snapshot            # before anything else
python tools\field_snapshot.py --snapshot out\m7\snapshot rollback            # undo everything
```

Snapshot options: `--root` (default the field install), `--registry-key` (default
`HKCU\Software\Valve\Source\garrysmod`), `--manifests-from <install>` (the Steam install whose depot
manifests describe this one, for a copy such as the PoC). Rollback option: `--config Debug|Release`
(the build whose uninstaller identity to use, default Release).

## What the snapshot records (`<snapshot>\snapshot.json`, schema 2)

| Kind | Where | How |
|---|---|---|
| Kept files | every file directly inside the root, `garrysmod`, `garrysmod\cfg`, `bin\win64` and `garrysmod\lua\bin` that no Steam depot lists (the user's DXVK `d3d9.dll` and `vulkan-1.dll`, the MMD Hot Loader and Jolt files, `console.log`, `cl.db`, logs, configs), plus `config.cfg`, `client.vdf`, `server.vdf`, `autoexec.cfg`, `mountdepots.txt`, `addonnomount.txt`, `user.conf`, `rtx.conf`, `dxvk.conf`, `imgui.ini` even when a depot lists them or they are absent | copied to `<snapshot>\files\` with their SHA-256 (files over 2 GiB: hash only) |
| Listings | those five folders, `garrysmod\addons`, `garrysmod\data`, `crashes` | entry names |
| Watched trees | everything below `garrysmod\data` and `garrysmod\settings` | size and time of each file, each folder and link (too many to copy: the field install's data folder is 61 GB) |
| The loader's paths | `bin\win64\winmm.dll`, `native-loader\`, `rtx-remix\`, `garrysmod\data\native-loader\` | present or not |
| GMod's shared settings | the registry key | `reg export` to `<snapshot>\registry.reg`, or recorded as absent |

Without depot manifests (not a Steam install, no `--manifests-from`), every file in the five folders
is kept and the depot check is skipped.

## What rollback does (`<snapshot>\rollback.json`)

1. When the bootstrap is installed and was not before: [`uninstall-loader.ps1`](uninstall-loader.ps1.md)
   `-RemoveConfig -AllowSteamManaged` (everything the journal lists, then the bootstrap and
   `native-loader\`).
2. Moves every entry of the listed folders that was not there before (deepest folders first), and
   every new file or folder below the watched trees, into `<snapshot>\debris\<time>\` at its install
   path. A rename: links move as links and are never followed, and nothing is lost (Remix's logs, a
   crash dump). Only when the snapshot is on another volume are they deleted instead (`rmdir /s`,
   which does not follow links either); `deleted` lists them.
3. Writes back every kept file that changed or went missing. In place, so a file hard-linked from
   elsewhere stays linked (and the other copy is back too).
4. Imports the registry export, then deletes every value and subkey the export does not have, so the
   key equals the export; a key that was absent is deleted.
5. Checks: the listings match, every kept file has its hash, the registry export after equals the one
   before, no new file is left below the watched trees, and
   [`steam\verify_install.py`](steam/verify_install.py.md) reports every depot file OK.
   Files below the watched trees that a session **changed** or removed cannot be put back; they are
   listed under `watched` and do not fail the rollback.

Exit 0 only when every check holds (`clean: true`); 1 when refused or when something remains (read
`rollback.json`). Running rollback again is safe and finds nothing left to do.

## Side effects and limits

- Refuses while a `gmod.exe` from the install runs, refuses a second snapshot into the same folder,
  a snapshot folder inside the install, and a snapshot written by the older version of this script.
- Writes only the snapshot folder and, on rollback, the install's paths described above and the
  registry key.
- Not covered: caches the game rewrites every session (`garrysmod\cache`, `ChromiumCache`,
  `GPUCache`: only their names are compared, as root entries) and the content of files below the
  watched trees.
