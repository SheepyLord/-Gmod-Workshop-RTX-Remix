# R10-E: steady eye whites for imported characters, with a brightness setting (brief)

Read [AGENTS.md](../../AGENTS.md), [R10-plan.md](R10-plan.md), [C16-plan.md](C16-plan.md),
[C16-report.md](C16-report.md), ADRs [0067](../decisions/0067-scene-adaptive-emission.md),
[0068](../decisions/0068-adaptive-eye-emission-publishing.md) and [0069](../decisions/0069-tuned-adaptive-eye-emission.md),
[R7-A-report.md](R7-A-report.md) with [ADR 0081](../decisions/0081-mmd-alpha-texture-category.md) (the MMD alpha rule: the companion finds
Model Hotloader materials by name and hands their texture hashes to the runtime), [runtime/README.md](../../runtime/README.md)
and [build_runtime.ps1.md](../../runtime/build_runtime.ps1.md). Patterns to reuse:
`companion/nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua` and `nativeloader_model_layers.lua`
(bounded per-frame lookups, `RemixMaterial.GetAllTextureHashes`, owned NoSave runtime options written with
`RemixConfig.SetConfigVariable` and retried), `nativeloader_menu.lua` (the RTX menu), the companion's
translation catalog, and the PBR tool's material classes (`skills/mmd-remix-pbr/tool/rpai/classify.py`,
the `sclera` rule).

Work on branch `r10-eyes` in `out/worktrees/r10-eyes`. **Owns:** `runtime/**` (a new patch `0019-...`
and its unit tests), `companion/**` (the eye-white logic, the menu settings and their translations),
`tools/qa/*eye*`, `tools/tests/*eye*` and `tools/tests/*adaptive*`, ADR 0088, and additive edits to
CHANGELOG (a `### R10` section under Unreleased), ROADMAP, RESEARCH, TESTING and COMPONENTS. If a hook in
the Model Hotloader is unavoidable, only `packages/model-hotloader/mmd_hotloader/lua/mmdhl/native_render.lua`
and `materials.lua`, staged under `out/` and brought in with `tools\inputs.py import model-hotloader --file`;
the other R10 task owns the rest of that part. **Does not touch:** `loader/**`, `glass/**`,
`packages/character-motion-importer`, any other part of `packages/`, the field install, the Workshop,
`origin`.

## The user's request (2026-11-02)

> Auto apply eye white correction adaptive texture to eligible hot loader models. The eye white part
> usually has an identificable name, something like "眼白". Check our model catalogue. There should be
> some option for user to adjust the brightness.

C-16 fixed eye whites that turn grey by day and glow at night only for characters with a PBR pack: their
eye material carries an emissive map and `emissive_adaptive_intensity`. A character imported with the
Model Hotloader and no pack still has plain eye whites, shaded grey by the lids in every light. The user
wants the same correction applied automatically to every imported character whose eye white can be
recognized, with a brightness setting.

## What Claude found (starting points: verify them)

1. **The catalogue.** `out/r10/corpus_scan.py` read the user's 1,225 PMX models under `E:\G\Upload` into
   `out/r10/corpus.jsonl` (one JSON line per model: materials with name, English name, texture, face
   count and the other materials sharing that texture; morphs). Eye-white material names, by count:
   `白目` 239, `眼白` 142, `Face_Eyewhite` 20, `目白` 9 (and 54 more models where `目白` is the only one),
   `EyeWhite` 7, `眼白1` 7, `眼白2` 5, `eyewhiteL`/`eyewhiteR`, `白目2`, `eyewhite`, `Eye_White`,
   `00_EyeWhite` and expression variants (`00_EyeWhite_はぅ`...), `Face008_GP_EyeWhite (Instance)`,
   `eyeball`, `眼睛眼白`, `Eye Whites`, `眼白左`/`眼白右`, `顔（白目）`. Not eye whites: `目影` (eye shadow),
   `目HL`/`目光`/`目ハイライト` (highlights), `瞳`/`目`/`眼睛` (iris), `眼罩` (blindfold); check `目白底`,
   `目白框`, `eye_back`, `眼角膜`. The installed libraries are a second catalogue: the PoC's five
   characters and the field install's 144 (`garrysmod/data/mmd_hotloader/assets/<id>/manifest.json`,
   read only). The PBR tool's `sclera` rule (`白目`, `白眼`, `眼白`; `sclera`, `eyewhite(s)`, `shirome`) misses
   `目白`.
2. **Shared textures.** In 411 of the 434 models with a named eye white, that material shares its texture
   with the face: Guinaifen's `白目` is on `颜.png` with `颜`, `口`, `舌齿`, `眼线内`, `目`, `目光` and `眉目`; Robin's
   on `颜.png`; March 7th's `眼白` on `脸.png`; Linlong's `白目` on `face.png` (Linlong is in the PoC library and
   has no pack: the natural test subject). Remix keys a material by its albedo texture's hash, so a
   material for that hash would make the whole face emit. The correction must stay on the eye-white
   surface.
3. **How imported characters reach Remix.** The hotloader's Lua passes one IMaterial per PMX material to
   its native renderer (`native.SetInstanceMaterials`, `native.DrawInstance` in `native_render.lua`), which
   draws each material separately. Materials and textures come from per-asset archives mounted from
   `data/mmd_hotloader/assets/<id>/materials-v5.gma` (textures cached as `data/mmd_hotloader/textures/<sha256>.vtf`);
   the asset's `manifest.json` lists its materials (name, base texture, index range). The eye-white draw
   and the face draw differ only in geometry and in Source-side state.
4. **The runtime** (`H:\BACKUP_20260815\Modding\dxvk-remix-gmod`, base `c6b48ed1` plus `runtime/patches`):
   `AssetReplacer::getReplacementMaterial(hash)` looks only in mods; Remix API materials
   (`remixapi_CreateMaterial`) serve API meshes only; a legacy (unreplaced) material has no emission;
   the disk loader reads only DDS. Opaque materials already have `emissive_adaptive_intensity` (patch
   0016) and `emissiveAlphaMask` (emission = the emissive texture's RGB times its alpha). The fork's
   worktree `.claude/worktrees/remix-i18n` (`claude/sky-night`, `f9937026`) holds an older build folder; the
   tree that built the shipped DLL (base + 0001-0018) was under this repository's `out/worktrees` and is
   gone, so the next build starts from `build_runtime.ps1` (a new worktree needs the network for
   submodules and two clones) or from that old tree brought exactly to `base.json` plus the patches.

## What to build

1. **Recognize eye whites** on Model Hotloader characters by material name: the list above, with the
   exclusions, matched on both the material's name and its English name. Run the matcher over the corpus
   and both libraries and report hits, misses and false positives.
2. **Give them C-16's look:** emission taken from the eye white's own albedo (keeping its painted shading),
   scene-adaptive through the `emissive_adaptive_intensity` path, at the level C-16's packs give (Robin's
   pack is the reference, ADR 0069's `R = 25`: measure, do not assume), **and on no other surface**,
   including the rest of a shared atlas. Pick the mechanism with evidence and record it in ADR 0088.
   Candidates:
   - give the eye-white draw a texture identity of its own (for example a byte-different copy of the atlas
     mounted for that one material), which the runtime treats as the atlas for replacement lookups and,
     where the atlas has no replacement, gives the albedo emission;
   - a UV mask the runtime applies to the atlas (from the eye-white triangles' UVs, which the companion
     can read through the hotloader);
   - a per-draw marker the runtime can see.
   Weigh: no glow outside the eye white (mind bilinear filtering and mip levels at island edges),
   per-frame and memory cost, how characters with packs behave, older runtimes and packages,
   multiplayer (other players' characters), and robustness to hotloader updates.
3. **Characters with a pack keep it.** Where a mod has a material for the atlas (Robin, Evernight,
   March 7th, Guinaifen), the pack's eye material applies exactly as before; no second emission.
4. **Settings** in the RTX menu beside the character options (the Model outlines checkbox): a checkbox
   "Steady eye whites for imported characters" (default on) and an "Eye-white brightness" slider (0-200 %,
   default 100 % = C-16's tuned look). The slider scales every character's eye whites, the automatic ones
   and the packs' (for example through `rtx.adaptiveEmission.scale`, or an option of the patch: decide and
   document). Archived per player, applied live, translated into the companion's seven languages. Only
   under RTX.
5. **Runtime patch 0019** with unit tests in the runtime's suite, built with
   `runtime\build_runtime.ps1 -NoImport` (the old build folder or a new worktree, as above). Do not commit
   a runtime import: Claude imports the reviewed DLL once, to keep Git LFS storage down (a pushed object is
   never freed). Test with a local package that carries your DLL; leave `packages/runtime` and
   `runtime/base.json` unchanged in your commits. Report the DLL's path, size and SHA-256.
6. **Tests and docs:** the runtime's unit tests; Lua harness tests for the matcher and the option writes;
   Python tests where you add scripts; a `.md` beside every new script; ADR 0088; CHANGELOG `### R10`; the
   facts you dug for in RESEARCH.
7. **PoC QA** (`tools/qa/eye_white_probe.lua`, `tools/qa/eye_white_patches.py`; C-16's protocol: the player
   placed by a `--console` line, noon, golden hour, dusk, night and the lamp-lit room): Linlong with the
   feature on and off (eye white over cheek per condition; a face patch outside the eye whites must not
   change), the slider at 0, 100 and 200 %, Robin's pack unchanged with the feature on and off, and the
   frame time with a few characters on screen.

## Acceptance

- Linlong's eye whites land where Robin's pack lands (C-16's numbers) in every condition; with the
  feature off they are as before; no other surface of any test character emits.
- Robin (a pack) is the same with the feature on and off.
- The slider changes every character's eye whites live; 0 turns the automatic ones off.
- `tools\test.ps1 -Config Release` passes on the branch; the runtime's unit tests pass.

## Rules for this run

- The PoC is shared with R10-H. Before you deploy to it or start a session there, create
  `out\r10\poc.lock` in the main checkout (`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock`)
  exclusively, with your task name and the time; if it exists, wait and retry every minute (a lock older
  than 90 minutes with no PoC game running may be taken over). Delete it when your session has ended and
  the PoC is back on its Workshop-only config.
- The user allowed closing any running game for this run (prefer a console `quit`; say which you closed).
  Never write the field install, Steam's files or a Remix `user.conf`. `-multirun` for every session.
- No questions to the user: decide, and record the decision. Commit on `r10-eyes` with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`; never push, merge or publish.
- Write `docs/handover/R10-E-report.md`: what you built and why, the measurements, the DLL, what is left.
