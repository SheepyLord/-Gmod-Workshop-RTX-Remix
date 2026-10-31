# package_fixes.py

Builds the RTX fixes package ([docs/PACKAGE_FORMAT.md](../docs/PACKAGE_FORMAT.md), with the M5
additions of the [M5 plan](../docs/handover/M5-plan.md): kinds `lua-addon`, `patch-set`,
`module-override`, and `session_cvars`) from the user's fork of the RTX fixes,
`garrys-mod-rtx-remixed`, which it only reads. The output is a package folder (allowlist it under
`dev_folders` in `native-loader\config.json`), a `.gma` (allowlist it under `local`), or both. Every
file is hashed while it is copied, so the manifest's sizes and SHA-256s describe exactly the bytes in
the package. The runtime is a separate package: [package_runtime.py](package_runtime.py.md).

```powershell
# The fixes as a package folder and an archive:
python tools\package_fixes.py --out out\packages\rtx-fixes --gma out\packages\rtx-fixes.gma

# Modules from another build, without the test-hook add-on, replacing the earlier folder:
python tools\package_fixes.py --modules-from <build folder> --exclude-addon rtx_agent --out out\packages\rtx-fixes --force
```

## What goes in

Sources are relative to the fixes repo's `garrysmod\` folder (its distributable tree) unless stated.

| Package path | From | Manifest |
|---|---|---|
| `native/root/garrysmod/addons/<name>/**` | every folder in `garrysmod\addons\` except `--exclude-addon` ones | one `root_files` entry `garrysmod/addons/<name>` per add-on, kind `lua-addon`, `replace-owned` |
| `native/root/garrysmod/addons/nativeloader/**` | this repo's [Lua companion](../companion/README.md) `companion\nativeloader\`, its `.md` files left out | the same, `garrysmod/addons/nativeloader` |
| `native/root/garrysmod/addons/nativeloader/lua/nativeloader/i18n_data.lua` | built from [`companion\i18n\*.po`](../companion/i18n/README.md) by [`companion_i18n.py`](companion_i18n.py.md) `build` into a scratch file under `out\tmp` (removed afterwards), with the newest `.po` file's time; the inventory names `companion\i18n` as its source. A `.po` that does not check stops the build | the same |
| `native/root/rtx-remix/mods/<mod>/**` | every folder in `rtx-remix\mods\` that holds files | one entry `rtx-remix/mods/<mod>` per mod, kind `root-files`, `replace-owned`; `~gmod_topbr` `create-only`, because the fixes' ToPBR converter rewrites it at run time (a reinstall would otherwise find its files "not placed by the loader" and refuse the package) |
| `native/root/garrysmod/data/<folder>/**` | every folder in `garrysmod\data\` that holds files, except `native-loader` (the loader's own reports): the fixes' seed data, today `remix_map_configs\default.txt` | one entry `garrysmod/data/<folder>` per folder, kind `root-files`, `create-only`, so what the fixes write there later at run time stays the user's ([M5 report](../docs/handover/M5-report.md), deviations) |
| `native/root/garrysmod/lua/bin/<module>` | `gmcl_RTXFixesBinary_win64.dll`, `gmcl_rtxwater_win64.dll`, and with `--with-debug-module` `gmcl_rtxdebug_win64.dll`, from `--modules-from` | one entry per file, kind `lua-binary-module`, `replace-owned` |
| `native/payload/shaders/stdshader_dx6.dll` | `bin\win64\stdshader_dx6.dll` | `module_overrides: [{"module": "stdshader_dx6.dll", "file": "native/payload/shaders/stdshader_dx6.dll"}]`, kind `module-override` |
| none (manifest data) | the seven `patches64` patches, as data in the script | `patch_sets`, kind `patch-set` |
| none (manifest data) | the RTX section of `garrysmod\cfg\autoexec.cfg` (below) | `session_cvars` |
| `native/manifest.json` | written last: schema 1, `requires_loader` `>=0.2.0`, `requires_remix` (the add-ons are hidden from sessions without a runtime, [ADR 0013](../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)), `kinds` exactly those used | |

**Patch sets.** The seven patches of `patches64` from `sambow23/SourceRTXTweaks`, which RTXLauncher
writes into the DLLs on disk, tabled with their purpose in [RESEARCH.md](../docs/RESEARCH.md) section
12: `engine.dll` 2 (`mod_loadlighting_hdr`, `mod_loadworldlights_hdr`), `shaderapidx9.dll` 3
(`zero_size_buffer_returns_4`, `shader_constants_return_0`, `skip_invalid_vertex_format_error`),
`materialsystem.dll` 1 (`zero_size_buffer_guard`), `datacache.dll` 1 (`dx80_vtx_to_dx90_vtx`). `find`
is lowercase hex with `??` wildcards, `replace` lowercase hex written at `offset` inside the match.
The script checks the loader's rules on them (unique snake_case names, 1-256 bytes, replacement inside
the match), and the tests check them against the RESEARCH.md table. Each pattern matches exactly once
in the PoC's build. The `datacache.dll` pattern (the string `dx80.vtx`) lies in `.rdata`, not in an
executable section.

**Session console variables.** The fixes' `autoexec.cfg` holds two blocks, each under a banner: a
rule line (`//` and ten or more `=`), comment lines, another rule line. The first, titled `RTX stack
required settings (from fixes package nightly-6d2e2b9)`, holds the RTX settings; the second,
`Personal settings ...`, the user's own (`r_forcehwlight 1`, `sv_gravity 515`, ...) and an
`exec astra_importer_compat`. The script takes only the lines below a banner whose title (its first
non-empty comment line) contains the word `RTX`, up to the next banner; a file with no such banner is
taken whole (the summary's `section` is then `null`). Of those lines it takes every plain `name value`
assignment, the value unquoted or in double quotes, a trailing `// comment` allowed, and skips:
comments; lines with `;`; commands (`exec`, `bind`, `alias`, `echo` and a few others that take an
argument, such as `map`, `connect`, `toggle`, `lua_run`); a name alone (a command or a query); more
than one value; names that are not `[A-Za-z0-9_]{1,64}` and values that are not
`[A-Za-z0-9_.+-]{0,32}`. Names compare without case and a later assignment wins. Every skipped line
is reported with its reason (`session_cvars.skipped`), including the lines outside the RTX section.
From the fixes as of 2026-10-28 that gives 34 variables (`sv_cheats 1`, `mat_disable_d3d9ex 1`,
`r_3dsky 0`, ..., `r_novis 1`) and 17 lines skipped as outside the RTX section.

## Left out

- Adjacent `*.lua.md` source documentation remains in the repository and indexed inputs. It is
  excluded from deployment: GMod tries to include even non-Lua loose files in `lua/entities`.
  Ordinary addon READMEs and license documents remain included.
- The Steam files the fixes overwrite: `garrysmod\lua\menu\**`, `garrysmod\gamemodes\**`,
  `garrysmod\html\**` ([AGENTS.md](../AGENTS.md) rule 2).
- The root `rtx.conf` and `dxvk.conf`: they are runtime configuration, layers of the runtime package:
  `package_runtime.py --rtx-conf <fixes>\garrysmod\rtx.conf --dxvk-conf <fixes>\garrysmod\dxvk.conf`.
- Everything else in the tree: the rest of `garrysmod\cfg\` (its `autoexec.cfg` becomes
  `session_cvars`), loose files directly in `garrysmod\data\` and its `native-loader\` folder,
  `stdshader_dx6.pdb` and its readme, loose files in the add-ons or mods folder. The summary lists
  them (`left_out`, relative to the fixes' `garrysmod\`).
- Junk anywhere: `.git` (a submodule's file, or a folder), `.gitattributes`, `.gitignore`,
  `.gitkeep`, `.gitmodules`, `Thumbs.db`, `desktop.ini`, `.DS_Store`, `*.bak` (listed as `junk`).
  `gmapack` drops the same names, so the folder and the archive hold the same files.
- Map compile logs, a `*.log` file in a `maps` folder, are also junk. The fixes keep vbsp/vvis/vrad
  logs beside their maps; the game never reads them, and they hold the mapper's own paths. Any other
  log is a private-looking file, which refuses the build unless `--allow-private` names it.
- A mod folder without files (`empty_mods`). An add-on folder without files is refused instead: it is
  usually a git submodule that was never initialised.

**Private or machine-specific files are refused**, by the rules of
[package_runtime.py](package_runtime.py.md): Remix's `user.conf`, `*.log`, `.env` and `*.env`,
`*.dmp` and `*.mdmp`, and anything inside a `logs` folder, wherever they are in what would be
packaged (add-ons, mods, seed data, the companion). The build stops and lists them all by package
path. `--allow-private <package path>` lets a reviewed one through. The fixes as of 2026-10-28 carry
two such files, tracked in the fixes repo beside their maps: `remixbinary\maps\gm_construct_rtx.log`
and `gm_construct_in_flatgrass_rtx.log`, by their names map compile logs. The build stops on them
until they are reviewed and passed with `--allow-private` (the refusal shows the two paths), or
left out of the fixes repo.

## Options

- `--repo <folder>`: the fixes repo, read only. Default: `garrys-mod-rtx-remixed` beside this repo
  (`H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed` on the main machine).
- `--modules-from <folder>`: where the built modules are (default `<repo>\x86_64\Release`).
- `--with-debug-module`: also package `gmcl_rtxdebug_win64.dll` and its add-on `rtx_debug` (one file,
  `require("rtxdebug")`), from the fixes' debug submodule `source/debug/addon`, as the classic install has them.
- `--client-bootstrap <DLL>`: package this project's menu-realm module as
  `garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll`, with a hashed module root entry and its MIT/BSD
  notices under the companion's `resource/native-client`. Requires the companion. Loader 0.9.0
  invokes it for the verified RTX bundle's multiplayer initialization. This raises requires_loader
  to >=0.10.0, so older bootstraps keep their previous shipment rather than miss early renderer protection.
  It does not change server
  settings or permit loading community scripts. This input is optional for standalone fixes builds.
- `--exclude-addon <name>` (repeatable): leave an add-on out, compared without case;
  `nativeloader` leaves out the companion. An unknown name is refused.
- `--add-to-addon <PATH> <SOURCE>` (repeatable): add SOURCE, a file or a folder (its files, junk left
  out), to an add-on as PATH (`<add-on name>/<path in it>`): a licence text the add-on folder does not
  have. Only new paths; a file the package has already is refused. The RTX package ships the fixes'
  GPL-2.0 text this way, as `garrysmod/addons/remixbinary/LICENSE` from `packages/fixes/LICENSE`
  (R3-011).
- `--no-patch-sets`: no `patch_sets` (and no kind `patch-set`).
- `--cvars-from <file>`: take the session variables from this `.cfg` instead (same rules);
  `--no-session-cvars`: none.
- `--out <folder>`, `--gma <file>`: what to write; at least one.
- `--id <id>` (default `rtx-fixes`), `--name <text>` (default `RTX fixes <version>`),
  `--version <semver>`. The default version is `0.0.0-dev.<UTC time of the newest input,
  yyyymmddhhmm>+<first 8 digits of the SHA-256 of gmcl_RTXFixesBinary_win64.dll>`, where the inputs
  are every packaged file and the session variables' `.cfg`: an edit anywhere gives a new version,
  and the same inputs always the same one.
- `--allow-private <package path>` (repeatable): package this file although it looks private or
  machine-specific, for example
  `native/root/garrysmod/addons/remixbinary/maps/gm_construct_rtx.log`; case does not matter. A path
  that names no such file of the package is refused.
- `--force`: replace an earlier package folder (only one that holds `native/manifest.json`) or archive.
- `--json`: print the summary as JSON: `id`, `version`, `files`, `bytes`, `manifest_sha256`, `kinds`,
  `addons`, `excluded_addons`, `mods`, `empty_mods`, `modules_from`, `modules` (name: SHA-256),
  `module_override` (source), `patches` (count), `session_cvars` (`source`, `section`, `count`,
  `skipped` with `line`, `text`, `reason`; `null` with `--no-session-cvars`), `junk`, `left_out`,
  `allowed_private` (package paths let through by `--allow-private`), `repo`, `folder`, `gma`,
  `inventory` (the inventory files written).

## Outputs and side effects

- The package is built in `<output>.partial-<pid>` beside the output and renamed into place, so a
  loader never reads half a package; an existing folder is swapped out and then deleted. On failure
  the partial folder is removed. The `.gma` is written by [`gmapack`](gmapack/gmapack.py.md) through
  a temporary file, with paths in their original case and the newest input's time as the archive
  timestamp: the same inputs give the same bytes.
- **Inventory.** Beside each output, `<output>.inventory.txt` lists everything that went into the
  package, in [package_runtime.py](package_runtime.py.md)'s format: one tab-separated line per file
  (`size`, `sha256`, package `path`, `source`, `note`), `native/manifest.json` last. Review it before
  publishing. It is written after the package is in place and replaced on every build.
- Refuses (exit 1): a package path the loader's path rules reject (non-ASCII, reserved names, `~` and
  a digit, ...; the rules are [package_runtime.py](package_runtime.py.md)'s); an add-on folder name
  that is not `[A-Za-z0-9_.-]{1,64}`; an add-on without files; a fixes add-on named `nativeloader`;
  links or special files; two paths that differ only in case; private or machine-specific files not
  named with `--allow-private`; a missing module, `stdshader_dx6.dll` or `.cfg`; an output inside the
  fixes repo, the modules folder or the companion (or the reverse); `--gma` inside `--out`; a
  non-empty output folder without `--force`; an inventory path held by a folder or a link.
- Reads the fixes repo, the modules and the companion; writes only the outputs and their
  inventories. Never touches a game install or the fixes repo.
- Check the result with `nlctl manifest <folder or .gma>` (a loader of version 0.2.0 or later).

## Exit codes

0 success; 1 refused or failed (the reason on stderr); 2 bad command line (argparse).

Tests: [tests/test_package_fixes.py](tests/test_package_fixes.py.md).

When the companion is included, companion/presentation startup text is copied under
garrysmod/data/nativeloader_ui with create-only policy, preserving user edits.
These are plain localized runtime input files, not executable menu modifications.

The generated companion table includes the bundled-interface catalogs in `companion/i18n/addons`.
The newest `.po` timestamp is found recursively, so an add-on translation update participates in
the generated file's version. Both namespaces must pass strict completeness checks.

`companion_catalog_sources()` adds the bundled-interface PO files, template, reviewed exceptions, README and GPL `COPYING` under `nativeloader/resource/bundled-translations/`, alongside the generated runtime table. These are editable source copies, not a second translation input.
