# package_content.py

Builds a **content package** ([docs/PACKAGE_FORMAT.md](../docs/PACKAGE_FORMAT.md)): Lua add-on
folders and Remix mod folders, no native code. It is for content that GMod cannot mount from the
Workshop by itself, because Remix mods (`.usda`, `.dds`) are outside GMod's file whitelist and GMod
refuses an archive that holds them ([ADR 0015](../docs/decisions/0015-workshop-route-for-native-packages.md)).
The loader deploys the package instead, so its Lua arrives as an add-on folder and its mods in
`rtx-remix\mods`. The first such package is the Modern House remaster (`modern-house-rtx`).

```powershell
# Modern House RTX: the add-on and its Remix mod, hidden without RTX, as one archive for the Workshop:
$mh = 'H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\.claude\worktrees\modern-house-rtx'
python tools\package_content.py --id modern-house-rtx --name "Modern House RTX" --requires-remix `
  --addon "$mh\garrysmod\garrysmod\addons\modern_house_rtx" --mod "$mh\garrysmod\rtx-remix\mods\modern_house_rtx" `
  --title "Modern House RTX (native loader package)" --type map --tag scenic --tag realism `
  --gma out\packages\modern-house-rtx.gma

# A Remix mod alone, as a package folder (a development-folder source):
python tools\package_content.py --id emissives --mod <mods>\Emissives --out out\packages\emissives
```

## What goes in

| Package path | From | Manifest |
|---|---|---|
| `native/root/garrysmod/addons/<name>/**` | every file of each `--addon` folder, `<name>` being the folder's name | one `root_files` entry `garrysmod/addons/<name>`, kind `lua-addon`, `replace-owned` |
| `native/root/rtx-remix/mods/<name>/**` | every file of each `--mod` folder | one entry `rtx-remix/mods/<name>`, kind `root-files`, `replace-owned` |
| `native/manifest.json` | written last: schema 1, `requires_loader` `>=0.2.0`, `requires_remix` from `--requires-remix`, `kinds` exactly those used | |
| `addon.json` (archive root) | the Workshop metadata: `--title`, `--type`, `--tag`, `--description` | none: [`gmapack`](gmapack/gmapack.py.md) writes it into the archive header, where `gmpublish` reads the type and tags |

Junk is left out as [package_fixes.py](package_fixes.py.md) leaves it out (`.git`, `Thumbs.db`,
`desktop.ini`, `*.bak`, map compile logs, ...). Private or machine-specific files (Remix's
`user.conf`, logs, dumps, `.env`) are refused unless `--allow-private` names them, by the rules of
[package_runtime.py](package_runtime.py.md).

## Options

- `--addon FOLDER`, `--mod FOLDER` (repeatable, at least one in all). The folder's name is the
  deployed name: 1-64 characters of `A-Z a-z 0-9 _ . -`.
- `--id` (required), `--name` (default: the id), `--version` (default
  `0.0.0-dev.<UTC time of the newest input, yyyymmddhhmm>+<first 8 digits of the files' digest>`: the
  SHA-256 over every package path and file hash, so the same inputs give the same version and a
  changed file a new one).
- `--requires-remix`: the add-ons are hidden in starts without an active Remix runtime
  ([ADR 0013](../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)). Use it for RTX-only Lua.
- `--title` (default: the name), `--description`, `--type` (a GMod add-on type, default `tool`),
  `--tag` (a GMod tag, at most two): the Workshop metadata.
- `--out FOLDER`, `--gma FILE`: what to write, at least one; `--force` replaces an earlier one.
- `--allow-private PATH` (repeatable), `--no-validate` (skip the `nlctl manifest` check), `--json`.

## Outputs and side effects

- The package is built in `<output>.partial-<pid>` beside the output. A folder output is renamed into
  place, so a loader never reads half a package. An archive is packed from the work folder, which is
  then deleted.
- **Hard links for archives.** When only `--gma` is given, the work folder holds hard links to the
  sources instead of copies, so several GB of textures are not written twice. Each file is still
  hashed from the work folder. Across volumes it copies. A folder output (`--out`) always holds
  copies, so it never changes with its sources.
- **Checked by `nlctl`.** The package is checked with `nlctl manifest` when a loader is built
  (`out\build\win64-*\loader\cli\nlctl.exe`); the summary names the checker. `nlctl` refuses a folder
  with hard-linked files (a package may not alias other files), so a linked build is checked as the
  packed archive: staged as `<gma>.unchecked-<pid>` and moved into place only when it passes.
- **Inventory.** `<output>.inventory.txt` beside each output lists every file: size, SHA-256, package
  path, source and note, `native/manifest.json` last.
- **Reads only the inputs.** It writes only the outputs and their inventories, never a game install.
- **Refusals** (exit 1): a folder that is missing, linked, badly named or empty; two inputs with the
  same deployed name; a package path the loader's path rules reject, or two that differ only in case;
  an output inside an input (or the reverse); `--gma` inside `--out`; a non-empty `--out` without
  `--force`, or one that is not a package folder.

## Exit codes

0 success; 1 refused or failed (the reason on stderr); 2 bad command line (argparse).

Tests: [tests/test_package_content.py](tests/test_package_content.py.md).
