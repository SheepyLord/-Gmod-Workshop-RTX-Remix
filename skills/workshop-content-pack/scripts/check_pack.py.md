# check_pack.py

Checks a staged Workshop content pack before it is uploaded. **Read only**: it writes nothing (it runs
`nlctl manifest` and `nlctl verify`, which only read).

It turns the mistakes of the earlier packs into checks, so the next pack is right the first time:

| Area | Checks |
|---|---|
| Names | `mmdhl_<n>` and `pbr_<n>` with the same `<n>`, package id `<n>-rtx`; `r18` in a folder name or the package id is an error (the user, Robin), in a title or display name a warning |
| Model Hotloader package | one `data_static\mmdhl\packages\<32 hex>.json`; the rules `workshop.lua` `ValidatePackage` applies on install (format, version, id, install mode, items, file entries, per-kind size limits, packet bounds, the 256x expansion bound, 16 GB in all); every listed `.dat` present with its packed size; unlisted `.dat` files; per model: a plain ASCII display name (an error otherwise, a placeholder too: the Evernight and March 7th pack shipped 長夜月 and 三月七, R5; a warning for a model given to `--keep-name`), R18 in it, the default bodygroup preset (presets as an array, no valid default, a default named `1`), a terms-of-use record (an error without one: March 7th went out without, R5), terms that mention restrictions (Evernight: 禁止二配). `--deep` unpacks every packet (Windows `cabinet.dll`) and compares its SHA-256 |
| Remix mod | `mod.usda` and its sub-layers present; every `../` reference of every layer present and inside the mod; other references only `.mdl` shaders; every file Remix data and an ASCII path (what a content package may deploy); files no layer references. `--hashes-json` (repeatable): each live hash rpai recorded has a material in the mod; a sheet with maps but no material for its hash is an error; predicted-only parts and sheets without maps (left to Remix, or covered by another character's layer on this machine only) are warnings |
| Archive | the GMAD header (type one of GMod's, at most two tags, R18 in the title); `native/manifest.json` content only (kinds `lua-addon` and `root-files`, no payload or native settings, root files under `rtx-remix/mods` and `garrysmod/addons`), the staged folders among its root files, over 4 GB; then `nlctl manifest` and `nlctl verify` |
| Icon | a 512x512 baseline JPEG (what worked for gmpublish); over 1 MB |
| Description | names the RTX package 3829070317 (an error otherwise) and the loader; says GMod itself cannot mount the item; no straight double quotes (PowerShell 5.1 drops them when it passes the text as an argument); at most 8000 bytes |

```powershell
$B = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\packages\robin'
python -I scripts\check_pack.py $B --hashes-json "$env:USERPROFILE\.rpai\work\robin_r18_f9c3e4b4\hashes.json" --deep
python -I scripts\check_pack.py --addon "$B\mmdhl_robin" --mod "$B\pbr_robin"     # before the archive exists
python -I scripts\check_pack.py "$B\..\guinaifen" --deep --keep-name 1c2ed2fc     # an update that keeps her published name
```

## Options

| Option | Meaning |
|---|---|
| `build` | a build folder (`out\packages\<n>`): one `mmdhl_*` folder (or one with `data_static\mmdhl`), one folder with `mod.usda`, one `.gma`, `icon.jpg`, `description.txt` |
| `--addon`, `--mod`, `--gma`, `--icon`, `--description` | a part given explicitly (wins over the found one) |
| `--hashes-json FILE` | rpai's `work\<key>\hashes.json` of a packed model (repeatable) |
| `--nlctl FILE` | `nlctl.exe`; default: `out\build\win64-release` (or `win64-debug`) `\loader\cli\nlctl.exe` in a folder above the archive, which finds the main checkout's build from `out\packages\<n>` and from a worktree's `out` |
| `--deep` | unpack every Model Hotloader packet and compare its SHA-256 (Windows) |
| `--keep-name ASSET` | a model (8 to 64 hex digits of its asset id, as the `model <id8>` lines print it) whose published display name the user keeps: its non-ASCII or placeholder name is a warning, not an error (repeatable). For an update of an item named before the rule: Guinaifen, `1c2ed2fc` (the user kept `Guinaifen (桂乃芬)`, 2026-11-01). Players who installed the model keep its library name anyway; new installs get the kept name |

An add-on folder without `data_static\mmdhl` (a map remaster's Lua) is checked as a plain add-on: no
Hotloader checks and no `mmdhl_`/`pbr_` naming rule.

## Output and exit codes

`ok`, `WARN` and `ERROR` lines grouped by area, then `<e> errors, <w> warnings`. Exit 0 with no errors
(warnings allowed: read them, several must go into the report to the user); 1 with errors; 2 bad
command line. Standard library only; runs with `python -I`.

## Verified (2026-10-31) on the three published packs

| Pack | Result |
|---|---|
| Robin (`out\packages\robin`, `--deep`) | names, Hotloader package, mod, archive, nlctl and icon pass; warnings: six parts with predicted hashes only, and sheets with no material of their own; error: the description does not name 3829070317 (written before this rule) |
| Robin's first build (`out\packages\robin-r18`) | 3 errors (`mmdhl_robin_r18`, `pbr_robin_r18`, `robin-r18-rtx`), warnings for the R18 title and name, the English name `Robin R18`, presets as an array with default `1`: everything the user had changed |
| Guinaifen | passes apart from the description; warns that English readers see `New MMD Model` for `Guinaifen (桂乃芬)`, the PMX's English name |
| Evernight and March 7th (`--deep`) | passes apart from the description; warns about Evernight's terms (禁止二配), the non-ASCII 三月七, seven predicted-only parts, and two sheets (bq.png, inmon.png) with no material of their own; `--deep` also unpacked every packet Model Hotloader's own exporter wrote |
| Guinaifen's C-16 update (2026-11-02, `--deep --keep-name 1c2ed2fc`) | 0 errors, 4 warnings: the kept name, two predicted-only parts (颜赤.png, baisiwa.png), Body.png left to Remix. Without `--keep-name` the name is its one error; a value that is not hex exits 2 |

## Provenance

New in this skill (2026-10-31), written by Claude for this user from the failures of the Guinaifen,
Robin and Evernight sessions. Not third-party code.
