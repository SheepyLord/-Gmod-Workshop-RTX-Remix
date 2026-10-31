# The Model Hotloader Workshop package, on disk

What a pack's `mmdhl_<name>` add-on folder holds, how Model Hotloader reads it, and what that means
for names and settings. Sources, read 2026-10-31:

- the add-on the RTX package ships, `packages\model-hotloader\mmd_hotloader\lua\mmdhl\` in the native
  loader repository: `workshop.lua` (install), `workshop_export.lua` (the export dialog), `names.lua`
  (display names), `terms.lua`, `bodygroups.lua`, `first_person.lua`, `materials.lua`;
- Model Hotloader's repository `H:\BACKUP_20260815\Modding\ipg\!GMHLVK\Gmod-Model-Hotloader-with-Vulkan`
  (commit `bed4582`, 2026-10-28): `native\packages.cpp` and `.hpp` (the exporter), `native\sharing.cpp`
  and `.hpp` (the packet codec), `docs\WORKSHOP_PACKAGES.md`;
- the three packs built with it (Guinaifen, Robin, Evernight and March 7th).

Model Hotloader release in all three local installs: 2.3.1, build `ecd7c426c0b5-20261026T225907Z`.

## Layout

```
mmdhl_<name>\                              deployed by the loader to garrysmod\addons\mmdhl_<name>\
  addon.json                               title, type, tags (and "ignore"); not read by Model Hotloader
  data_static\mmdhl\packages\<id>.json     the package manifest; <id> = 32 lowercase hex digits
  data_static\mmdhl\files\<sha256>.dat     one MMDPACK2 packet per distinct cache file
```

Every member is on GMod's add-on whitelist (`data_static/*.json`, `data_static/*.dat`), so
`package_content.py`'s gmad filter keeps them all.

**How it is found.** `workshop.lua` runs `W.Scan` one second after `InitPostEntity` and two seconds
after `GameContentChanged`. It lists `data_static/mmdhl/packages/*.json` in the `GAME` search path,
which includes every mounted add-on folder. The loader deploys the folder before GMod starts, so GMod
mounts it as a legacy add-on and the scan finds it in the first map. The Workshop archive itself is
never mounted: it holds files outside the whitelist (`native/...`), GMod prints
`Couldn't mount addon file '<path>' from '<title>' (<id>)` and its add-on list shows the item red.
Even if it were mounted, its Hotloader files sit under `native/root/...`, where the scan does not look.

## The package manifest (`packages\<id>.json`)

Compact UTF-8 JSON, at most **4 MiB** (`MaxPackageBytes`; larger is refused on install). Model
Hotloader's exporter writes its keys sorted; `mmdhl_pack.py` writes them in this order. Order does
not matter.

| Key | Rule on install (`W.ValidatePackage`) | Exporter / packer |
|---|---|---|
| `format` | `"mmdhl-package"` | |
| `version` | `1` | |
| `id` | equals the file name, 32 hex | random per export (`BCryptGenRandom`), so each build has a new one |
| `title` | clipped to 128 bytes; empty shows the id's first 8 digits | required, at most 128 bytes, no control characters |
| `author` | clipped to 128 bytes | at most 128 |
| `description` | clipped to 8000 bytes, multi-line | at most 8000; tab, CR, LF allowed |
| `created` | integer 0..2^40, else 0 | Unix time |
| `install` | `"workshop"` or `"user"` | `"workshop"`: a Workshop model (labelled, removed when the package goes). `"user"`: a demo pack, adopted as the player's own |
| `folder` | clipped to 80 bytes; used for `user` installs only | omitted for `workshop` |
| `generator` | not checked | `{"release": "2.3.1", "build": "ecd7c426c0b5-..."}` |
| `items` | 1..1000 entries (below) | |
| `files` | `{<cache path>: {size, sha256, packed}}` (below) | |

### `files` entries

| Field | Rule |
|---|---|
| key | a cache path: `assets/<64 hex>/manifest.json` (at most 64 MiB), `assets/<64 hex>/model.bin` (1 GiB), `textures/<64 hex>.png` (1 GiB in 2.3.1), `static/assets/<64 hex>.gmdl` (props, 2 GiB); any other path refuses the whole package |
| `size` | integer 0..4294967295, the raw file size |
| `sha256` | 64 lowercase hex digits of the raw file |
| `packed` | integer 80..4294967295, the `.dat` file's size, at most `size + 80 + 8 * ceil(size / 1 MiB)` |
| expansion | `size` at most `max(1 MiB, packed * 256)`: a better-compressing file must be stored raw |
| total | all `size` together at most 16 GiB |

`docs\WORKSHOP_PACKAGES.md` still says 256 MiB per texture; the code (2.3.1) allows 1 GiB.

### `items` entries (characters)

| Field | Meaning and rules |
|---|---|
| `kind` | `"character"` (or `"static"` for a prop, whose only file is `static/assets/<asset>.gmdl`) |
| `asset` | the 64-hex asset id, the SHA-256 identity Model Hotloader gave the import; `rpai` keys end in its first 8 digits |
| `name` | the display name, clipped to 100 bytes; empty falls back to the id's first 12 digits. See "Display names" |
| `files` | the cache paths of this model, each in `files`. A character must list its `manifest.json` and `model.bin` and otherwise only `textures/<sha256>.png` whose name matches its hash. These are the raw import: generated archives (`materials-v5.gma`, carrier models) are never shipped; every game rebuilds them |
| `settings.spawn` | `{"scaleMultiplier": n}`, clamped to 0.1-4 on install |
| `settings.bodygroups` | `{"presets": {<name>: {"visible": [bool per PMX material]}}, "default": <name>}`. On install: at most 64 presets, names cleaned and clipped to 64 bytes, `visible` indices 1-512; `default` must be a **string** naming a preset, else it is dropped and the model spawns with its authored look |
| `terms` | the terms-of-use record: `file` (the PMX name), `embedded` (`name`, `nameEnglish`, `comment`, `commentEnglish`, `copyright` from the PMX), `readmes` (readme files matched to the model: `name`, `text` at most 32 KiB, `folder`, `matched`, `truncated`, `encoding`); at most 240 KiB in all (`T.ForPackage`) |
| `fit` | the physics fit (`fit_overrides\<asset>.json`), without `editor.savedBy` / `savedByName`; used only when `version` is 3 and `generator` 14, 15 or 18 (`W.ItemFit`) |
| `arms` | first-person arm parts, `{"<material slot>": -1, 0 or 1}` (`CleanArmsParts`: slots 0-4095, at most 1024) |

**Preset names.** `util.JSONToTable` turns numeric keys such as `"1"` into numbers, and
`util.TableToJSON` then writes a table of presets named `1`, `2`, ... as a JSON **array**
(`bodygroups.lua` comments on it). The library entry of Robin held `"presets": [ {...} ]` with
`"default": "1"`. Installed from such a package the preset is called `1`, which works but is easy to
miss; the Robin pack renamed it `Default` (`mmdhl_pack.py --default-preset-name Default`).

## The packets (`files\<sha256>.dat`, MMDPACK2)

The lossless block format of Model Hotloader's multiplayer model transfer (`packSharedBytes`):

```
offset 0   8 bytes   "MMDPACK2"
offset 8   u64 LE    raw size
offset 16  64 bytes  the raw file's SHA-256, lowercase hex ASCII
offset 80  blocks, until the raw size is reached:
           u32 LE    raw bytes in this block (1 .. 1 MiB; every block but the last is 1 MiB)
           u32 LE    stored bytes; high bit 0x80000000 set: stored raw (then equal to the raw count)
           ...       the stored bytes
```

Compressed blocks use Windows' Compression API with XPRESS Huffman
(`COMPRESS_ALGORITHM_XPRESS_HUFF` = 4, buffer mode, `cabinet.dll`). A block that does not shrink is
stored raw; a file that would inflate more than 256 times its packet (and is over 1 MiB) is packed
with every block raw; Linux builds of Model Hotloader store every block raw (every release reads
both). The installer streams the packet to `BeginSharedFile` ... `CommitSharedFile`, which checks
the size, the bounds and the SHA-256.

Measured: Robin's 46 files, 84,605,060 bytes, pack to 66,492,088; Guinaifen's 28 files, 36,840,020 to
24,359,872; a 158-byte file grows to 246 (header and block header). The same input packs to the same
bytes: `mmdhl_pack.py` reproduced Robin's published packets, and the 47 packets Model Hotloader's own
exporter wrote for Evernight and March 7th, byte for byte.

## Install, and what never changes afterwards

For each model a mounted package provides (`W.Reconcile`, client):

1. If the model is not complete in the cache (a file missing or resized), its files are queued and
   installed one at a time, a few milliseconds per frame, with a progress notice.
2. With natives after 2.3.0 the assembled model is loaded off the main thread as using it would
   (`StartAssetCheck`); only if that passes is it recorded as installed.
3. `installed()` then writes, **each only if the file does not exist yet** (`writeIfMissing`):
   - `data\mmd_hotloader\library\<asset>.json`: `name`, `spawn`, `bodygroups` (and `folder` for a
     `user` install);
   - `arms\<asset>.json` and `fit_overrides\<asset>.json`;
   - and the terms record `terms\<asset>.json` through `SaveFromPackage`, also only when the player
     has no record for the model (`origin: "workshop"`, `package: <title>`).
4. It records the install in `data\mmd_hotloader\workshop\state.json` (`installed`, `name`,
   `package`, file times).

So a later version of the package never changes an installed model's **name, presets, default,
spawn size, arm parts, fit or terms record**. That is what kept "Robin R18" in the user's library.
Files are repaired, though: every scan compares sizes, and once per session files whose time changed
are hashed again and reinstalled when they no longer match.

**Removal.** A model installed from a package that is no longer mounted (unsubscribed, add-on
disabled, or a requires-Remix add-on hidden in a start without RTX) is deleted from the cache at the
next scan, unless it is in use on the map or was adopted (`user` install). Deleting a Workshop model
in the library hides it (Deleted Workshop models) and Restore installs it again.

**Origin.** Model Hotloader traces a package to the mounted add-on whose title equals the package
title, else (native scan) to the mounted `.gma` whose index lists the package file. A loader-deployed
folder is neither a mounted Workshop archive, so the origin falls back to the package title with no
Workshop id. Inferred from `workshop.lua`, not seen in game: the library's Workshop page button is
then missing for such models.

## Display names (`names.lua`)

`N.EntryName` shows a library entry's name. For a Workshop model (and any model whose name is the
model's own) it goes through `N.Display`:

1. Nothing is changed unless translation is allowed for the model (`mmdhl_translate_names` on, and
   the model's recorded choice, or the player has seen the notice).
2. **An English reader** (the add-on's or the game's language is English) whose model name has
   non-ASCII characters, and whose terms record holds an ASCII `nameEnglish` that differs from it,
   sees `nameEnglish`.
3. An ASCII name is shown as written to English readers.
4. Otherwise the name is queued for Google Translate and shown translated once the answer is cached
   (`data\mmd_hotloader\translations`).

Consequences for a pack:

| Item name | PMX English name (terms) | An English reader sees |
|---|---|---|
| `Robin (知更鸟)` | `Robin R18` | `Robin R18` (seen by the user, 2026-10-30) |
| `Robin` | `Robin R18` | `Robin` (the fix) |
| `Guinaifen (桂乃芬)` | `New MMD Model` | `New MMD Model` (computed from the field install's library and terms records on 2026-10-31; not looked at in game) |
| `長夜月` | `Evernight` | `Evernight` |
| `三月七` | none | a machine translation, once it arrives |

So give the item a plain ASCII name, the character's (`Robin`, `Guinaifen`). The terms record keeps
the PMX's own names; that is right, do not edit it.

## The exporter (`StartPackageExport`) and the two routes

The library's **Export as Workshop package** dialog (`workshop_export.lua`, `mmdhl_export`) collects,
per model, `name` from the library entry, `settings` (`spawn`, `bodygroups`), `terms`
(`T.ForPackage`), `arms` and `fit`, asks the player to confirm each model's terms of use
(`mmdhl.terms.BeforeExport`), and calls the native `StartPackageExport`. The native exporter checks
the texts and limits, packs the files, and writes
`<game root>\garrysmod\data\mmd_hotloader\exports\<file name>.gma` (the file name is the title reduced
to safe ASCII, at most 80 characters) plus, when a character preview is open, a 512x512 `.jpg`. Its
GMA header carries the title, `{"description", "type": "model", "tags"}` and the author.

- **`hotloader_export.py`** (mmd-remix-pbr skill) runs the same collection and the same native call
  through rpai's game bridge, skips the terms dialog (so: private items only), waits for the archive
  and extracts it with `gmapack` into the add-on folder. `gmapack extract` rebuilds `addon.json` from
  the header (`description`, `tags`, `type`, `title`, tab-indented). The archive stays in the game's
  `exports` folder.
- **`mmdhl_pack.py`** (this skill) builds the same folder offline from the cache files, with the
  item name and preset name given on its command line.

Either way the folder name is the pack's (`mmdhl_<name>`), not the exporter's file name.
