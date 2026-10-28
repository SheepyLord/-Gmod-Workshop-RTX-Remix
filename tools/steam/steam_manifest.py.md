# steam_manifest.py

Library and small CLI for Steam depot **ContentManifest** files: the list of every file in one depot
version with its size, flags and SHA-1. Steam caches them as
`<Steam>\depotcache\<depot>_<manifest>.manifest`; for Garry's Mod the depots are 4001 (content) and
4002 (binaries).

## Library

| Name | Does |
|---|---|
| `parse_manifest(path)` | Returns a `Manifest` (depot id, manifest id, `filenames_encrypted`, `files`). Paths use `/`. Directories and all-zero hashes have `sha1 = None`. |
| `ManifestFile` | `path`, `size`, `flags`, `sha1`, plus `is_dir`, `is_userconfig` (user may edit; Steam only installs it when missing), `is_symlink`. |
| `locate_install(install, steam_dir=None)` | For `<library>\steamapps\common\<dir>`, reads the matching `appmanifest_*.acf` and returns the app id plus the cached manifests of its installed depots. Raises `FileNotFoundError` naming anything missing. |
| `steam_root()` | Steam client folder from `HKCU\Software\Valve\Steam\SteamPath`. |
| `safe_relpath(path)` | Refuses absolute paths, drive letters and `..` before any manifest path is joined to a folder. |
| `sha1_file(path)` | Streaming SHA-1. |

The format notes (magic numbers, protobuf field numbers) are in [docs/RESEARCH.md](../../docs/RESEARCH.md).
Manifests with encrypted filenames are detected; the tools refuse them rather than guess.

## Command line

```powershell
python tools\steam\steam_manifest.py locate "H:\SteamLibrary\steamapps\common\GarrysMod"
python tools\steam\steam_manifest.py info  <file.manifest> [...]
python tools\steam\steam_manifest.py files <file.manifest>
```

Read-only. Used by [`verify_install.py`](verify_install.py.md) and
[`make_vanilla_copy.py`](make_vanilla_copy.py.md). Tests:
[`tests/test_steam_manifest.py`](tests/test_steam_manifest.py.md).
