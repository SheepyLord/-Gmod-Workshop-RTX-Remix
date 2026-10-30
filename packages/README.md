# packages/

Everything the combined RTX package (Workshop item 3829070317) is built from, so that this repository
alone builds it ([ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)).
[`tools/workshop.json`](../tools/workshop.json) names the parts; each reads its folder here, unpacked
into `out\inputs\<part>\` by [`tools/inputs.py`](../tools/inputs.py.md).

```powershell
git lfs pull                                   # the binaries (a clone without LFS has pointers only)
python tools\inputs.py verify                  # packages\ against the indexes
python tools\build_package.py                  # the RTX package into out\dist (uploads nothing)
tools\workflow.ps1 -Package                    # the same after the Release checks and the loader bundle
```

## How a part is stored

- `packages\<part>\files.json` indexes every file: its path in the part, size, SHA-256, time
  (`mtime_ns`, restored on unpack so the packagers' time-based versions come out the same), how it is
  stored, and `origins`: where each folder came from (the source path, its git origin URL and commit,
  and when it was imported).
- **Text files up to 1 MB** (UTF-8, no NUL bytes) are stored as they are: Lua, `.cfg`, `.json`, `.usda`.
  `.gitattributes` keeps them byte for byte (`packages/** -text`).
- **Every other file** is stored as `<name>.xz` (LZMA, preset 6) in Git LFS
  (`packages/**/*.xz filter=lfs`). The index also records the `.xz` file's size and SHA-256, the Git
  LFS oid, so `verify` checks a checkout without the LFS content too.
- Beside the index a part may hold `README.md`, `LICENSE` (and `licenses\`, the licences of what it
  bundles). They are not part of the package.
- Nothing else belongs in a part folder: `inputs.py verify` (and the tests) report any file the index
  does not list.

## The parts

| Part | What | From (where `inputs.py import` read it) | Licence |
|---|---|---|---|
| `runtime` | The RTX Remix runtime: `files\` (the fork's `d3d9.dll`, NVIDIA's DLLs, `usd\`, the sky textures in `atmosphere\`), `layers\` (the classic install's settings as the low defaults layer, and the compiler-threads layer) | the fork's build ([runtime/](../runtime/README.md)) and the runtime-b6 tree | the fork: MIT and zlib; NVIDIA's DLLs: their SDK licences; `atmosphere\CREDITS.txt` |
| `reshade` | `ReShade_Setup_6.8.0.exe`, the official setup [`package_reshade.py`](../tools/package_reshade.py.md) takes the add-on from | reshade.me | [third_party/reshade](../third_party/reshade/LICENSE.md) |
| `fixes` | The RTX fixes as their repository lays them out: `garrysmod\garrysmod\addons\*`, `garrysmod\rtx-remix\mods\*`, `garrysmod\garrysmod\data\*`, `garrysmod\garrysmod\cfg\autoexec.cfg` (the session variables), `garrysmod\bin\win64\stdshader_dx6.dll`, `source\debug\addon`; their binary modules in `modules\` | `SheepyLord/garrys-mod-rtx-remixed`; the modules from the classic install's `garrysmod\lua\bin` | GPL-2.0 (`LICENSE`); its add-ons carry their own |
| `emissives` | `emissives.gma`, the Emissives Remix mod as packaged in round 3 | `out\packages\round3` | - |
| `remove-halo` | `Remove_halo\` | `ipg\Remove_halo` | - |
| `model-hotloader` | `mmd_hotloader\` (the add-on), `overrides\installation.lua` (its install check, from the Vulkan repository), `bin\` (its natives) | the classic install's add-on and `lua\bin`; `SheepyLord/Gmod-Model-Hotloader-with-Vulkan` | MIT (`LICENSE`), the natives' libraries in `licenses\` |
| `advanced-material-editor` | `!advanced_material_editor\` (without `materials\models\`), `bin\gmcl_advmat_rtx_bridge_win64.dll` | `SheepyLord/-advanced_material_editor`; the classic install's `lua\bin` | - |
| `advanced-bodygroup-tool` | `!advanced_bodygroup_tool\` | `ipg\!advanced_bodygroup_tool` | - |
| `procedural-bodygroup-destruction` | `!gmod_bullet_break_simulator\` | `SheepyLord/-gmod_bullet_break_simulator` | - |
| `character-motion-importer` | `mmd_vmd_npc\` | `SheepyLord/Gmod-Mmd-Motion-Importer` | MIT (`LICENSE`) |

Only the files a part's package holds are stored, plus the few its packager reads without shipping
them (`autoexec.cfg`; the file `--addon-file` replaces): the add-ons' repositories hold gigabytes of
builds and work trees that never ship.

## Updating a part

A part changes only by an import here, reviewed and committed like code. A commit on `main` publishes
whatever `packages\` holds (AGENTS.md rule 5), so import on a branch, build, and compare first.

1. Build the part once from its new source with its packager, as before, into `out\tmp\import\<part>`:
   the packager's `<out>.inventory.txt` lists every source file it used.
2. Import exactly those, each source folder mapped to its place in the part; `--prune` drops files the
   new version no longer has:

   ```powershell
   # The RTX fixes, from their repository and the modules of their build:
   python tools\package_fixes.py --repo <fixes repo> --modules-from <build>\lua\bin --with-debug-module --out out\tmp\import\fixes --force
   python tools\inputs.py import fixes --inventory out\tmp\import\fixes.inventory.txt `
       --root "<fixes repo>=" --root "<build>\lua\bin=modules" `
       --file "<fixes repo>\garrysmod\garrysmod\cfg\autoexec.cfg=garrysmod/garrysmod/cfg/autoexec.cfg" --prune
   # A content add-on (the folder keeps its name: it is the add-on's name in the game):
   python tools\package_content.py --id character-motion-importer --requires-remix --addon <repo>\mmd_vmd_npc --out out\tmp\import\cmi --force
   python tools\inputs.py import character-motion-importer --inventory out\tmp\import\cmi.inventory.txt --root "<repo>\mmd_vmd_npc=mmd_vmd_npc" --prune
   # One file, such as a newly built runtime (runtime\build_runtime.ps1 does this itself):
   python tools\inputs.py import runtime --file "<fork build>\src\d3d9\d3d9.dll=files/d3d9.dll"
   ```

   Sources inside this repository (the companion) are skipped: the build takes them from here.
3. `python tools\inputs.py verify`, `python tools\build_package.py --compare out\workshop\published.json`
   (it tells whether the content changed), then commit `packages\<part>` with what changed and why.

The one-time move into this folder (2026-10-30) imported every part this way from the sources above;
the build from here reproduced the published package byte for byte (the same content digest,
[RESEARCH.md](../docs/RESEARCH.md) section 30).

## Size and Git LFS

The parts hold 1.8 GB and are stored in 0.6 GB (the runtime 1.23 GB in 0.41 GB: LZMA takes
`d3d9.dll` to 17 %). GitHub Free and Pro include 10 GiB of LFS storage and 10 GiB of downloads a
month, and GitHub Actions' downloads count too. An LFS object stays stored once pushed, so a new
`d3d9.dll` costs about 62 MB of the storage for good; the package workflow caches the LFS objects, so a
run downloads only those it has not seen.

## Localized interfaces

[ADR 0038](../docs/decisions/0038-complete-bundled-interface-translations.md) records local translation
changes to the shipped inputs. Existing keyed catalogs stay with their add-ons; newly localized RTX
interfaces call the companion's separate bundled-interface catalog. Changes to the GPL fixes remain
in that part under its existing license. Source repositories outside this checkout are not changed.
