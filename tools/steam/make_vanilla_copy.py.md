# make_vanilla_copy.py

Builds a byte-exact vanilla copy of a Steam app from an existing install, with no download and no
Steam login. It copies exactly the files the cached depot manifests list, hashes each file while
copying, and keeps only files whose SHA-1 matches. Anything the user added (DXVK, MMD Hotloader,
addons, ...) is never copied, and modified depot files are rejected. This is how the PoC install
`H:\SteamLibrary\steamapps\common\GarrysMod_PoC` was made (see [docs/TESTING.md](../../docs/TESTING.md)).

## Usage

```powershell
python tools\steam\make_vanilla_copy.py `
  "H:\SteamLibrary\steamapps\common\GarrysMod" `
  "H:\SteamLibrary\steamapps\common\GarrysMod_PoC" --report out\poc_copy.json
```

| Option | Meaning |
|---|---|
| `--manifest FILE` | Use these manifests instead of the source's installed ones (repeatable) |
| `--fallback DIR` | Another folder to take files from when the source copy does not verify (repeatable) |
| `--steam-dir DIR` | Steam client folder, if the registry lookup fails |
| `--no-appid-file` | Do not write `steam_appid.txt` (a copy Steam does not manage needs it to launch) |
| `--report FILE` | Write the full JSON report |

## Behaviour

- Refuses a destination that exists and is not empty, or that overlaps the source or a fallback.
  Rebuilding the PoC after a GMod update therefore means deleting it first, on purpose.
- Writes through `<file>.partial` and renames only after the hash matches; keeps source mtimes.
- Creates the empty folders the manifests list; skips depot symlinks (GMod has none).
- User-config files that differ (GMod: `garrysmod\cfg\autoexec.cfg`) are skipped, not failed;
  Steam itself only installs them when missing.
- Exit `0` = every depot file copied; `1` = some files could not be verified (listed);
  `2` = setup error (destination not empty, manifests missing).

Never writes to the source or fallback folders. Tests: [`tests/test_install_tools.py`](tests/test_install_tools.py.md).
