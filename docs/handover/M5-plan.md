# M5 plan: the RTX fixes on a vanilla install

- Author and implementer: Claude, 2026-10-28, under the user's instruction to plan, build and test
  M5-M7 without further approvals (rule 5 items still excluded: no push, no Workshop publishing, no
  Steam settings or launch options).
- Branch: `m5-rtx-fixes`, in the main checkout, from `main` at `c49f946` (M4 merged).
- Facts this plan rests on: [RESEARCH.md](../RESEARCH.md) sections 11 and 12.

## Goal

A vanilla install with only `bin\win64\winmm.dll` and two allowlisted local packages, the runtime
and the fixes, renders like `GarrysMod_RTX_c`, and with RTX off is still vanilla, including the
console variables the next RTX-off session starts with.

Acceptance, on the PoC:

1. gm_construct is path-traced (moved from M4): a screenshot at a fixed camera, compared with the same
   view in `GarrysMod_RTX_c`.
2. The user's test save `gm_csgosafehouse 2026-10-25 04-08-30.gms` at their reference camera, compared
   with `GarrysMod_RTX_c` by their block-difference measure (mean absolute difference of 32x32 block
   means; about 1 is noise, up to 3.6 counts as close). The PoC gets the content the save needs as
   test content (map, CS:GO mount, the user's Remix mods for it); the MMD character and its add-ons
   are the user's separate tools (M7 covers coexistence), so their region is reported, not fixed.
3. RTX off after an RTX session: System32 `d3d9.dll`, no patches, no shader override, and the console
   variables the RTX session changed are back to the user's values.
4. Uninstall leaves 2,877 depot files OK.

## What the classic install does, and how the loader does it instead

| Classic install (RTXLauncher + fixes) | Loader | Where |
|---|---|---|
| Runtime and `rtx.conf`/`dxvk.conf` in the copy's folders | M4: runtime package, config layers | done |
| Seven `patches64` byte patches written into `engine`, `shaderapidx9`, `materialsystem`, `datacache` on disk | **patch sets**: the same bytes written in memory when each DLL is mapped, before its code runs; each pattern must match exactly once, else that patch is skipped and reported | new, ADR 0010 |
| `bin\win64\stdshader_dx6.dll` replaced on disk | **module override**: `filesystem_stdio.dll`'s `LoadLibraryExA` of `<root>\bin\win64\stdshader_dx6.dll` loads the package's copy instead (import-table hook installed when each game DLL is mapped) | new, ADR 0010 |
| `autoexec.cfg` with the RTX console variables, archived into that install's own `config.cfg` | **session console variables**: a generated `cfg\nativeloader_session.cfg`, executed through `+exec` for RTX sessions only; the user's archived values recorded first and restored at the next RTX-off start | new, ADR 0010 |
| `gmcl_*` modules in `garrysmod\lua\bin` | root files, kind `lua-binary-module` | M3 |
| Lua add-ons in `garrysmod\addons\<name>\` | root files in a new area, kind `lua-addon`: GMod x64 mounts addon **folders** but not loose `.gma` files there (tested) | new, ADR 0011 |
| `rtx-remix\mods\*` | root files, kind `root-files` | M3 |
| Five Steam files overwritten (menu, camera SWEP, images) | left out: rule 2 | - |

Patch sets, the module override and the session variables belong to RTX sessions only: they are
applied only when a runtime activates, so RTX off stays vanilla.

## Manifest additions (schema 1, additive)

```json
"kinds": ["lua-binary-module", "lua-addon", "root-files", "patch-set", "module-override"],
"patch_sets": [
  { "module": "engine.dll", "patches": [
    { "name": "mod_loadlighting_hdr", "find": "ff90????????85c0742b", "offset": 0, "replace": "b80200000090" } ] } ],
"module_overrides": [ { "module": "stdshader_dx6.dll", "file": "native/payload/shaders/stdshader_dx6.dll" } ],
"session_cvars": { "r_3dsky": "0", "mat_softwareskin": "1" }
```

- `patch_sets`: `module` a DLL base name (`[a-z0-9_]+\.dll`); `find` hex byte pairs or `??`, 1-256 bytes;
  `replace` hex, written at `offset`, entirely inside the matched bytes; names unique.
- `module_overrides`: `module` a DLL base name that the game loads from `bin\win64`; `file` a payload
  path listed in `files`.
- `session_cvars`: names `[A-Za-z0-9_]{1,64}`, values `[A-Za-z0-9_.+-]{0,32}`: assignments only, no
  commands, quotes or separators, so the generated file cannot run anything else.
- `lua-addon` root files live in `garrysmod/addons/<addon>/...` (`<addon>`: `[a-z0-9_.-]{1,64}`, plus
  the fixes' existing mixed-case names), policy `replace-owned`.

## Loader changes

- `nl_core`: manifest parsing and validation; journal records the three new fields per package (so
  start-up needs no archive); `nl::patch` (pattern parsing, a single-match search over a module's
  executable sections, writing the replacement); `nl::session` (reading `config.cfg` values, the
  restore record `native-loader\session_cvars.json`, generating the two `.cfg` files).
- `nl::activate::plan`: collects the RTX-session extras from every package of the committed
  generation when the runtime activates; adds `+exec nativeloader_session.cfg`; on an RTX-off start
  with a restore record, adds `+exec nativeloader_restore.cfg` and clears the record.
- Bootstrap: registers an `LdrRegisterDllNotification` callback (from `ntdll` by `GetProcAddress`, so
  `winmm.dll` still imports only KERNEL32) when patch sets or overrides are active; at each mapped
  game DLL it applies that DLL's patch sets and hooks its `LoadLibraryA/W` and `LoadLibraryExA/W`
  imports. Results go to `garrysmod\data\native-loader\session.json` and `loader.log`.
- Patch sets need `-insecure` unless `config.json` says `patch_sets.require_insecure: false`;
  `package_runtime.py --insecure` adds `-insecure` to the runtime's launch arguments (allowed from
  schema 1 on) as the classic launch line does.

## Packaging and companion

- `tools/package_fixes.py`: builds the fixes package from the fixes repo (`garrysmod/` tree: add-ons,
  mods, `stdshader_dx6.dll`, the RTX block of `autoexec.cfg` as `session_cvars`), the built modules
  (`--modules-from`, default the repo's `x86_64\Release`) and the seven patch sets; leaves out the
  Steam files the fixes overwrite. Folder and/or `.gma`, like `package_runtime.py`.
- Lua companion (`nativeloader` add-on in the fixes package): prints the start-up and session status
  to the console at start and on `nativeloader_status`; M6 adds the restart notice.

## Tests

- Unit: manifest and journal for the new fields; pattern parsing and matching (exactly-once,
  wildcards, offsets); patch application on a buffer; the import hook on a test DLL; `config.cfg`
  parsing; restore record lifecycle; plan extras.
- Synthetic game (M4's harness): a test "engine" DLL with a known byte pattern loaded after start-up
  gets patched before its code runs; a test module that loads `bin\win64\<name>.dll` with
  `LoadLibraryExA` gets the package's copy; session cfg and `+exec` present with RTX on, restore with
  RTX off; nothing applied with RTX off; `winmm.dll` still imports only KERNEL32.
- Real: `poc_session.py` runs for the acceptance above, plus `tools/compare_frames.py` (the user's
  measure).
