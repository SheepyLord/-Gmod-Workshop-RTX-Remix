# poc_parity.py

Gives the PoC the reference install's **user content** for a like-for-like comparison (M5's
acceptance), then takes it away again. The loader's packages bring the runtime and the RTX fixes;
the rest of what makes a frame in `GarrysMod_RTX_c` is the user's own, and this script copies it:

| Copied from the reference install | Why |
|---|---|
| `user.conf` | Remix's top settings layer (opened from the working directory) |
| `garrysmod\cfg\client.vdf`, `server.vdf` | the fixes' saved Lua settings (water, ToPBR, ...) |
| `garrysmod\cfg\mountdepots.txt` | mounted games (the CS:GO content the safehouse map uses) |
| `rtx-remix\mods\*` except the fixes' four mods | the user's Remix mods; the fixes package deploys its own |
| `garrysmod\data\remix_map_configs\` | the fixes' per-map settings |
| `--save <name>`: `garrysmod\saves\<name>.gms` and `.jpg` | the test save |
| `--map <id>:<map>`: `maps\<map>.bsp` out of Workshop item `<id>` | the save's map, for a PoC launched with `-noworkshop` |
| `--addons`: every folder in `garrysmod\addons\` the PoC does not have | the user's local add-ons (the save's props and characters); folders a package deployed stay the package's |
| `--native <rel>` (repeatable): that one file, when the PoC has none | native modules those add-ons need, e.g. the MMD Hot Loader's `garrysmod\lua\bin\gmcl_mmdhl_win64.dll` |
| `--data <name>` (repeatable): the folder `garrysmod\data\<name>\`, when the PoC has none | an add-on's saved state, e.g. the Advanced Material Editor's rules and RTX profiles (`advmat`) |

```powershell
python tools\poc_parity.py --evidence out\m5\acceptance prepare --save "gm_csgosafehouse 2026-10-25 04-08-30" --map 944959992:gm_csgosafehouse
python tools\poc_parity.py --evidence out\m5\acceptance restore
```

Options: `--reference` (default `GarrysMod_RTX_c`), `--root` (default the PoC), `--no-mods`,
`--exclude-mod <name>` (repeatable), `--no-files` (leave the four files above alone),
`--copy-linked-addons` (with `--addons`: an add-on folder that is a link to the user's working copy
elsewhere is copied from what it points to, without `.git`, and listed in `followed_links`),
`--copy-linked-mods` (a linked mod folder is copied from what it points to, file by file in Python,
never following or copying a link inside it: one of the user's mods holds a `deps` link back to the
whole `rtx-remix` folder; the links left out are listed). Mods the PoC already has (an earlier
layer's, or a package's) are left alone and listed in `skipped_mods`.

A second layer on top of a prepared PoC uses its own evidence folder and is restored first:

```powershell
python tools\poc_parity.py --evidence out\m5\acceptance\addons prepare --no-files --no-mods --addons --native garrysmod/lua/bin/gmcl_mmdhl_win64.dll
python tools\poc_parity.py --evidence out\m5\acceptance\addons restore
```

## Side effects

- Writes only to the PoC. Everything is **copied** (robocopy), never linked, so nothing the PoC's
  game does can change a file of the reference install, which is only read.
- Files it replaces are backed up to `<evidence>\parity-backup\` first; `<evidence>\parity.json`
  lists every file and folder it created and every file it replaced. `restore` deletes exactly the
  created ones and puts the replaced ones back (or deletes them when the PoC had none), then renames
  the record to `parity-restored.json`.
- Refuses to run while a PoC `gmod.exe` runs, never overwrites a mod or add-on folder the PoC already
  has (left out and listed), refuses a `--native` file or `--data` folder the PoC already has, and
  refuses a second `prepare` into the same evidence folder before `restore`.
  Linked mod and add-on folders are left out and listed in `skipped_links`; add-on folders the PoC
  already has in `skipped_addons`.
- The map comes out of a plain `.gma` or an LZMA-wrapped `*_legacy.bin` ([RESEARCH.md](../docs/RESEARCH.md)
  section 5) through [`gmapack`](gmapack/gmapack.py.md); scratch under `out\tmp`.

Exit 0 on success, 1 when refused (the reason on stderr).
