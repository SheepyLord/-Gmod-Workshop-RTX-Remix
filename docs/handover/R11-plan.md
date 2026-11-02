# R11: automatic PBR (plan)

The user's requests (2026-11-02, after R10):

- **32.** "Enhance auto import PBR in mmd importer: For importing model with PBR, we have a few presets
  like Wuwa, Arknight endfield, Sliver Palace, those PBR are compacted and should be detected and be
  automatically applied to the models (You can sample E:\G\Upload) in aggressive preset in RTX. With a
  setting to enable / disable this feature."
- **34.** "Validate and Improve the autopbr function to make it more robust for the PBRs in the vanilla
  source engine system and fit the RTX style."

Standing permissions from R10 still apply: no questions to the user, the work goes to Codex, any running
game may be closed, and `main` and the Workshop are updated when done.

## Findings (Claude)

- **The "autopbr" is the RTX fixes' ToPBR** (`garrys-mod-rtx-remixed`, GPL): Lua
  `remixlua/cl/cl_rtx_topbr_conversion.lua` and `cl_material_pipeline.lua` find materials; the native
  `source/material_pipeline/to_pbr/` (about 10,800 lines) reads their VTFs, derives PBR maps for vanilla
  Source materials and four community PBR shaders (`format_source`, `format_exopbr`, `format_gpbr`,
  `format_mwbpbr`, `format_bftpseudopbr`), and writes DDS and USD into `rtx-remix/mods/~gmod_topbr`. The
  package also ships 83 pre-made `~gmod_topbr` textures. It is off by default (`rtx_topbr_enabled 0` in the
  classic defaults). The shipped DLL is built from the fixes branch `codex/r8-backrooms-native` (`7094baf`);
  its Lua there equals the package's.
- **The imported characters' PBR maps sit beside the PMX, unreferenced.** In the user's models (`E:\G\Upload`):

  | Game | Folders | Base colour (in the PMX) | Shipped maps (channel contents, sampled) |
  |---|---|---|---|
  | Wuthering Waves (鸣潮) | 39 | `T_*_D` | `_N` 20 (RG normal, B a mask, not Z), `_ID` 18 (R a region mask, G an ID level), `_HM` 19 (hair: G a mask), `_HET` 15 (eye/face binary mask), `_LD`, `_VC`; often in an `AONMPB/` folder |
  | Arknights: Endfield (终末地) | 26 | `T_actor_*_D` | `_N` 25 (RG normal, B 0), `_P` 25 (R sparse metallic, G mostly 1 (AO?), B mask, A 0.3-0.5: Unity mask-map-like, A smoothness?), `_E` 24 (emission), `_HN` 24 (hair normal, B/A extra), `_M`, ramps `_RD`/`_RS`, `_SDF`; in `other tex/` |
  | Silver Palace (白银之城) | the_detective, Alf | `T_*Default_*_D` | `_MRA` (R metallic, G roughness 0.46-0.65, B AO), `_N` (full XYZ), `_E` (emission), masks |

  The hotloader keeps each asset's PMX texture paths (`assets/<id>/manifest.json`, `base`) and, for 45 of
  the field's 144 assets, the source PMX path (`data/mmd_hotloader/sources.local.json`).
- **"Aggressive preset"** is the PBR tool's style (`skills/mmd-remix-pbr/tool/presets/aggressive.json`):
  every class pushed off Remix's legacy roughness 0.7, normals well above 1, skin and face classes left
  anime-safe.

## Task

One brief, [R11-A](R11-A-autopbr.md), for Codex: both items live in ToPBR, so one owner avoids two
branches editing its 5,900-line core. Phase 1 makes ToPBR robust and RTX-looking for vanilla Source
materials (item 34); phase 2 adds the imported characters' game maps (item 32) with a setting. Branches:
`r11-autopbr` in `out/worktrees/r11-autopbr` (this repository) and `codex/r11-autopbr` in
`out/worktrees/r11-fixes` (the fixes clone). Claude reviews, runs the PoC and field checks, imports,
merges and publishes.
