# R11-A: automatic PBR for vanilla Source materials and imported game characters (brief)

Read [AGENTS.md](../../AGENTS.md), [R11-plan.md](R11-plan.md), [packages/README.md](../../packages/README.md),
[packages/fixes/README.md](../../packages/fixes/README.md), [R8-B-report.md](R8-B-report.md) (how the fixes
DLL was built), [R6-T5-fixes-memlimits.md](R6-T5-fixes-memlimits.md) with
[the ToPBR texture notes](../../packages/fixes/licenses/topbr-bc7/README.md), the ToPBR sections of
[RESEARCH.md](../RESEARCH.md) (search `topbr`), [R10-report.md](R10-report.md) and
[ADR 0088](../decisions/0088-imported-character-eye-whites.md) (eye-white aliases and precedence), and the PBR
tool's style and lessons: [SKILL.md](../../skills/mmd-remix-pbr/SKILL.md),
`skills/mmd-remix-pbr/tool/presets/aggressive.json`, [tool/README.md](../../skills/mmd-remix-pbr/tool/README.md),
and for world materials [remix-map-pbr](../../skills/remix-map-pbr/SKILL.md) and its `references/`.

**Where you work.** This repository: branch `r11-autopbr` in `out/worktrees/r11-autopbr`. The RTX fixes
(GPL-2.0, `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed`): create a worktree at
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r11-fixes` on a new branch `codex/r11-autopbr`
from `codex/r8-backrooms-native` (`7094baf`, the shipped DLL's source); the main clone's prepared
dependencies (`garrysmod_common`, `remix`, `public`, generated projects) are what R8-B reused.

**Owns:** the fixes branch (ToPBR native and Lua, its build files); `packages/fixes`, changed only by
importing the rebuilt DLL and the edited files **one by one** (`tools\inputs.py import fixes --file ...`):
never a re-import of the whole part or `--prune`, because `packages/fixes` carries local translations and
fixes newer than the fixes repository, and edit Lua from the package's copy (it equals the fixes branch's
apart from line endings); `companion/**` if the setting lives in the RTX menu (with translations); new
`tools/` scripts with their `.md` and tests; ADR 0091 (and 0092 if needed); additive edits to CHANGELOG (a
`### R11` section), ROADMAP, RESEARCH, TESTING, COMPONENTS. A small hook in `packages/model-hotloader` Lua
only if reading its data files cannot work. **Does not touch:** `runtime/**`, `loader/**`, `glass/**`, other
parts, the field install, the Workshop, `origin` of either repository. GPL code stays in the fixes; this
repository's own code never copies it.

## The user's requests (2026-11-02)

**32.** "Enhance auto import PBR in mmd importer: For importing model with PBR, we have a few presets like
Wuwa, Arknight endfield, Sliver Palace, those PBR are compacted and should be detected and be
automatically applied to the models (You can sample E:\G\Upload) in aggressive preset in RTX. With a
setting to enable / disable this feature."

**34.** "Validate and Improve the autopbr function to make it more robust for the PBRs in the vanilla
source engine system and fit the RTX style."

The user's note on 34 (2026-11-02, after this brief): "actual PBR replacements, if exists, should always
overwrite the autoPBR result."

## What Claude found (starting points: verify them)

1. **ToPBR.** Lua finds materials (`cl_material_pipeline.lua`: phase 1 Lua fixers, phase 2 the C++ stages
   ShaderFixes, HashCollisionFixer, AutoCategorisation, ToPBR) and `cl_rtx_topbr_conversion.lua` drives the
   native `MaterialPipeline.ToPBR` (`source/material_pipeline/to_pbr/`: `to_pbr.cpp` 5,887 lines,
   `format_source.cpp`, `format_exopbr.cpp`, `format_gpbr.cpp`, `format_mwbpbr.cpp`,
   `format_bftpseudopbr.cpp`, `vtf.cpp`, `usda.cpp`). It writes DDS and USD into `rtx-remix/mods/~gmod_topbr`
   (Remix takes a material from the first mod that has it; `~` sorts after packs). The loader deploys that
   folder's shipped files create-only because ToPBR rewrites them at run time (CHANGELOG, RESEARCH: a
   rewritten `topbr_generation.txt` once made a reinstall refuse the fixes). Convars: `rtx_topbr_enabled`
   (classic default 0), `rtx_topbr_autodiscover` (1: companion `_normal`, `_mask`, `_spec`),
   `rtx_topbr_metallic` (0: "may cause black materials"), `rtx_topbr_parse_commented_properties` (1);
   commands `rtx_topbr_process`, `_inspect`, `_stats`, `_clear`, `_debug`. Nobody has validated it in this
   project.
2. **Imported characters.** Model Hotloader materials are `mmd/<asset 16 hex>/<part>` with `$basetexture`
   `mmd/t/<16 hex>` (VTFs in per-asset archives `data/mmd_hotloader/assets/<id>/materials-v5.gma`); each
   asset's `manifest.json` lists its materials and their PMX texture paths (`base`, relative to the PMX);
   `data/mmd_hotloader/sources.local.json` maps an asset id to its source PMX (45 of the field's 144 assets;
   read the field only, never write it). The game maps are beside the PMX's own textures, often in another
   subfolder.
3. **The conventions** in the user's models (corpus `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\corpus.jsonl`; channel
   statistics sampled on Baizhi, Camellya, Lupa, Akekuri, Arclight, Ardelia, the_detective, Alf):
   - **Wuthering Waves** (鸣潮, 39 folders, e.g. `E:\G\Upload\1_fin\Baizhi`): `T_*_D` (in the PMX; its alpha
     is a toon mask, not coverage), `_N` (R,G normal around 0.5; B a mask, not Z), `_ID` (R a binary
     region mask, G a constant ID level), `_HM` (hair: G a mask, B 1), `_HET` (eye/face binary), `_LD`,
     `_VC_UV0`; often in `AONMPB/`. A toon shader's inputs more than PBR: find what each holds.
   - **Arknights: Endfield** (终末地, 26 folders, e.g. `E:\G\Upload\akekuri`, "other tex/"): `_N` (R,G normal,
     B 0), `_P` (R sparse: metallic?; G mostly 1: AO?; B a mask; A 0.3-0.5: smoothness? Unity's HDRP mask
     map is R metallic, G AO, B detail mask, A smoothness), `_E` (emission, mostly black), `_HN` (hair
     normal; B and A carry more), `_M` masks, toon ramps `_RD`/`_RS`, `_SDF`; two models `_MRO`, `_NRO`.
   - **Silver Palace** (白银之城, `E:\G\Upload\the_detective`, `E:\G\Upload\Alf`): `_MRA` (R metallic, G
     roughness, B AO), `_N` (full XYZ), `_E` (emission), light-band, anisotropy and wet masks.
   Confirm the semantics (the games' shader documentation or community notes where they exist, the
   statistics, rendered checks) and the normal maps' green convention against Remix's.
4. **Precedence.** Any actual PBR replacement must always win over ToPBR's result (the user's note): the
   character packs from the Workshop, rpai's `ai_pbr`, map PBR mods, the fixes' own authored mods
   (`base_mod`...), any other mod that has a material for the same texture. Today that rests on mod folder
   order alone ("first mod wins", `~gmod_topbr` sorting after ASCII names); a folder name sorting after `~`
   (non-ASCII, for example) would lose to the generated material. R10's
   automatic eye whites hand the runtime `proxy=atlas` aliases, and a mod material for the atlas wins over
   the automatic emission: a generated material for a face atlas would switch the eye-white correction off.
   Faces rarely ship PBR maps; keep it that way or keep the correction.
5. **Style.** `aggressive.json`: default rough 0.45 / normal 1.8, cloth 0.55 / 2.6, stockings 0.30 / 1.4,
   leather 0.20 / 2.0, hair 0.28 / 1.2, metal 0.12 + metal 1 / 1.6, skin and face classes untouched. For
   world materials, `skills/remix-map-pbr` records what reads well under path tracing.

## What to build

**Phase 1, item 34: ToPBR you can leave on.**
1. Validate the current ToPBR on vanilla content on the PoC with RTX: gm_construct, gm_flatgrass, the
   Half-Life 2 content GMod mounts, and community PBR shader content (ExoPBR, GPBR, MWB, BFT) from
   subscribed Workshop items mounted read-only (`poc_session.py --workshop`). Record crashes, Lua errors,
   hitches and per-frame cost, wrong output (normal green convention, plastic or too-glossy surfaces,
   black metal, missing or stale textures, cache behaviour), and its writes into deployed folders
   (deploy, update and reinstall of the package after it wrote).
2. Fix what you find: bounded per-frame work and off-thread decoding, content-keyed caching, no Lua errors,
   safe failure on unknown formats and broken files, no conflict with the loader's journal, client-only.
   Tune the conversions to read well under path tracing (plausible roughness from Phong and envmap masks,
   sensible normal strength, metallic only on strong evidence).
3. Decide the default with evidence (before/after screenshots and frame times) and record it in ADR 0091.

**Phase 2, item 32: imported characters' game maps, automatically.**
1. For each Model Hotloader material, find its shipped maps: the base texture's stem and the game's
   suffixes, searched in the model's folder tree (bounded), with sanity checks on the channels. Rule sets
   for Wuthering Waves, Endfield and Silver Palace; open to others with the same layout (`_MRA`, `_N`...).
2. Unpack them into Remix maps: normal (rebuilt Z where only R,G are stored, the right green convention),
   roughness, metallic, AO where useful, emission, in the aggressive style: the maps' own values where the
   game authored them, the preset's class targets and normal strengths where a channel is missing; skin and
   face classes anime-safe. Wuthering Waves' masks are not plain PBR: use what they reliably mean, nothing
   more.
3. Apply them automatically under RTX for newly imported and already-imported characters (where the source
   folder is known), through ToPBR's output, keyed by the hotloader texture. Packs win; R10's eye whites keep
   working; a one-time conversion per asset, bounded, cached.
4. A setting to turn it on or off (default on), in the RTX menu's character options (or the hotloader's
   settings, if that reads better), translated into the seven languages; off restores the previous look.

**Both, first of all: real replacements win, always.** Where any other mod has a material for a texture,
that material is what renders, never ToPBR's, in both phases, whatever the mods' folder names, load order
or loading time (a pack installed or hot-reloaded after ToPBR wrote its material included). Make it a
guarantee, not an ordering accident: for example, do not generate (or remove) a ToPBR material for a hash
another mod replaces, and make the generated mod rank last. Test it, including a mod whose folder name sorts
after `~`.

**Both.** Tests (native where the fixes have them, Lua harnesses, Python for any tool), ADR 0091, CHANGELOG
lines in the user's terms, RESEARCH facts. Import the reviewed DLL and files into `packages/fixes` on your
branch (one DLL import at the end: Git LFS storage is never freed). Report the DLL's size and SHA-256.

## PoC QA

The PoC's hotloader library has Guinaifen, Robin, Evernight, March 7th and Linlong only: import one
character from each game into the PoC (for example `E:\G\Upload\1_fin\Baizhi`, `E:\G\Upload\akekuri`,
`E:\G\Upload\the_detective`) through the hotloader, then show each with the setting on and off (screenshots
of cloth, metal, hair and skin), and Robin (a pack) unchanged. For item 34, before/after of the same views
on gm_construct and an HL2 map, and frame times.

## Acceptance

- ToPBR runs on the content above without errors, crashes or visible hitches, and the package's deployment
  still works after it wrote its files; the chosen default is backed by evidence.
- One character from each game gets its own normal, roughness, metallic and emission in game, automatically,
  with the setting on, and looks as before with it off; packs and eye whites unaffected.
- Wherever a real PBR replacement exists (a pack, `ai_pbr`, a map mod, a test mod named to sort after `~`),
  it renders instead of ToPBR's material, with ToPBR on, in both phases.
- `tools\test.ps1 -Config Release` passes on `r11-autopbr`.

## Rules for this run

- The PoC lock is `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock` (create it exclusively with
  your task name; delete it when the PoC is back on its Workshop-only config). Close any running game if
  needed (the user allowed it; prefer a console `quit`). Never write the field install, Steam's files or a
  Remix `user.conf`. `-multirun` always.
- No questions to the user: decide and record why. Commit on `r11-autopbr` and `codex/r11-autopbr` with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`; never push, merge or publish.
- Write `docs/handover/R11-A-report.md`: what you found, built and measured, the DLL, what is left.
