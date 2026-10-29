# package_content.py

Builds an **add-on package** ([docs/PACKAGE_FORMAT.md](../docs/PACKAGE_FORMAT.md)): Lua add-on
folders, Remix mod folders and binary Lua modules. It is for what GMod cannot mount from the Workshop
by itself: Remix mods (`.usda`, `.dds`) and binary modules are outside GMod's file whitelist, and GMod
refuses an archive that holds them ([ADR 0015](../docs/decisions/0015-workshop-route-for-native-packages.md)).
The loader deploys the package instead: its Lua arrives as add-on folders, its mods in
`rtx-remix\mods` and its modules in `garrysmod\lua\bin`.

It builds:
- the Modern House remaster (`modern-house-rtx`, [ADR 0023](../docs/decisions/0023-content-packages-and-modern-house-item.md));
- these parts of the RTX package, through [`publish_workshop.py`](publish_workshop.py.md) as the
  builder `"build": "package_content"` in [`workshop.json`](workshop.json):
  - `Remove_halo`;
  - the user's five add-ons, among them Model Hotloader with its natives
    ([ADR 0024](../docs/decisions/0024-bundled-addons-and-module-dependencies.md)).

```powershell
# Modern House RTX: the add-on and its Remix mod, hidden without RTX, as one archive for the Workshop:
$mh = 'H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed\.claude\worktrees\modern-house-rtx'
python tools\package_content.py --id modern-house-rtx --name "Modern House RTX" --requires-remix `
  --addon "$mh\garrysmod\garrysmod\addons\modern_house_rtx" --mod "$mh\garrysmod\rtx-remix\mods\modern_house_rtx" `
  --title "Modern House RTX (native loader package)" --type effects --tag scenic --tag realism `
  --gma out\packages\modern-house-rtx.gma --link

# Model Hotloader: its add-on, its natives, and its runtime loaded before both modules:
$bin = 'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\garrysmod\lua\bin'
python tools\package_content.py --id model-hotloader --requires-remix `
  --addon H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\garrysmod\addons\mmd_hotloader `
  --lua-bin "$bin\gmcl_mmdhl_win64.dll" --lua-bin "$bin\gmsv_mmdhl_win64.dll" --lua-bin "$bin\mmdhl_runtime_win64.dll" `
  --load-first gmcl_mmdhl_win64.dll=mmdhl_runtime_win64.dll --load-first gmsv_mmdhl_win64.dll=mmdhl_runtime_win64.dll `
  --out out\packages\model-hotloader
```

## What goes in

| Package path | From | Manifest |
|---|---|---|
| `native/root/garrysmod/addons/<name>/**` | each `--addon` folder (`<name>` its folder name) or `--addon-as NAME FOLDER`: the files gmad would publish (below) | one `root_files` entry `garrysmod/addons/<name>`, kind `lua-addon`, `replace-owned` |
| `native/root/rtx-remix/mods/<name>/**` | every file of each `--mod` folder | one entry `rtx-remix/mods/<name>`, kind `root-files`, `replace-owned` |
| `native/root/garrysmod/lua/bin/<file>` | each `--lua-bin` file | one entry per file, kind `lua-binary-module`, `replace-owned` |
| `native/manifest.json` | written last: schema 1, `requires_loader` `>=0.2.0` (`>=0.3.0` with `--load-first`), `requires_remix` from `--requires-remix`, `kinds` exactly those used, `module_dependencies` from `--load-first` | |
| `addon.json` (archive root) | the Workshop metadata: `--title`, `--type`, `--tag`, `--description` | none: [`gmapack`](gmapack/gmapack.py.md) writes it into the archive header, where `gmpublish` reads the type and tags |

**Add-ons as gmad publishes them.** An add-on folder keeps only the files GMod's whitelist allows (the
table `gmad.exe` uses, from [`gmapack`](gmapack/gmapack.py.md)), minus those its own `addon.json`
"ignore" list or `--ignore` matches; `addon.json` itself is kept. So a working copy's development files
(`.codex*` staging folders, tests, docs, sources, crash dumps) stay out; the summary lists them as
`filtered`. `--no-addon-filter` packages every file.

Junk is left out as [package_fixes.py](package_fixes.py.md) leaves it out (`.git`, `Thumbs.db`,
`desktop.ini`, `*.bak`, map compile logs, ...). Private or machine-specific files (Remix's
`user.conf`, logs, dumps, `.env`) are refused unless `--allow-private` names them, by the rules of
[package_runtime.py](package_runtime.py.md); in an add-on, the filter leaves most of them out first.

## Options

- **Inputs** (at least one in all):
  - `--addon FOLDER`, `--addon-as NAME FOLDER`, `--mod FOLDER`, all repeatable. A deployed folder name
    is 1-64 characters of `A-Z a-z 0-9 _ . -`, optionally after GMod's `!`, which sorts an add-on
    first.
  - `--lua-bin FILE` (repeatable): a binary module or a file beside it (its runtime, worker, version
    file). File names 1-64 characters of `A-Z a-z 0-9 _ . -`.
  - `--load-first MODULE=FILE` (repeatable): two `--lua-bin` `.dll` names; the loader loads FILE before
    the game loads MODULE, in every session (loader 0.3.0, `module_dependencies`).
- **Add-on filter:** `--ignore PATTERN` (repeatable, gmad wildcards) and `--no-addon-filter`.
- **`--addon-file PATH FILE`** (repeatable): the add-on file PATH (`<add-on folder name>/<path in it>`,
  such as `mmd_hotloader/lua/mmdhl/installation.lua`; case folded) comes from FILE instead. Only a file
  the add-on has, after the filter, can be replaced, so a misspelled path is refused rather than added.
  FILE is a separate argument, so [publish_workshop.py](publish_workshop.py.md) counts it among the
  inputs that start a new upload. The summary lists it as `replaced`
  ([ADR 0026](../docs/decisions/0026-addon-file-from-its-repository.md)).
- **Identity:** `--id` (required), `--name` (default: the id), `--version`. The default version is
  `0.0.0-dev.<UTC time of the newest input, yyyymmddhhmm>+<first 8 digits of the files' digest>`. The
  digest is the SHA-256 over every package path and file hash, so the same inputs give the same
  version and a changed file a new one.
- **`--requires-remix`:** the add-ons are hidden in starts without an active Remix runtime
  ([ADR 0013](../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)).
- **Workshop metadata:** `--title` (default: the name), `--description`, `--type` (a GMod add-on type,
  default `tool`), `--tag` (a GMod tag, at most two).
- **Outputs:** `--out FOLDER` and/or `--gma FILE`, at least one; `--force` replaces an earlier one;
  `--link` (below).
- `--allow-private PATH` (repeatable), `--no-validate` (skip the `nlctl manifest` check), `--json`.

## Outputs and side effects

- The package is built in `<output>.partial-<pid>` beside the output. A folder output is renamed into
  place, so a loader never reads half a package. An archive is packed from the work folder, which is
  then deleted.
- **Hard links with `--link`.** With `--gma` alone and `--link`, the work folder holds hard links to the
  sources instead of copies, so several GB of textures are not written twice. Across volumes it copies.
  It is not the default: a link changes the source file's record (its link count), and some sources
  (the classic install) are only read. A folder output (`--out`) always holds copies.
- **Checked by `nlctl`.** The package is checked with `nlctl manifest` when a loader is built
  (`out\build\win64-*\loader\cli\nlctl.exe`); the summary names the checker. `nlctl` refuses a folder
  with hard-linked files (a package may not alias other files), so a linked build is checked as the
  packed archive: staged as `<gma>.unchecked-<pid>` and moved into place only when it passes.
- **Inventory.** `<output>.inventory.txt` beside each output lists every file: size, SHA-256, package
  path, source and note, `native/manifest.json` last.
- **Reads only the inputs.** It writes only the outputs and their inventories, never a game install.
- **Refusals** (exit 1):
  - inputs: a folder or file that is missing, linked, badly named or empty (an add-on with nothing gmad
    would publish); two inputs with the same deployed name;
  - `--load-first` that is malformed, names a file not given with `--lua-bin` or not a `.dll`, names the
    module itself, or is given twice;
  - `--addon-file` without a path in the add-on, for an add-on not given or a file it does not have,
    with a missing FILE, or given twice;
  - paths: one the loader's path rules reject, or two that differ only in case;
  - outputs: one inside an input (or the reverse); `--gma` inside `--out`; a non-empty `--out` without
    `--force`, or one that is not a package folder.

## Exit codes

0 success; 1 refused or failed (the reason on stderr); 2 bad command line (argparse).

Tests: [tests/test_package_content.py](tests/test_package_content.py.md).
