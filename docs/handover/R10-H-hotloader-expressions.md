# R10-H: imported NPCs after a map change; VMD expressions that drive the right morphs (brief)

Read [AGENTS.md](../../AGENTS.md), [R10-plan.md](R10-plan.md), [packages/README.md](../../packages/README.md)
(a part changes only by `tools\inputs.py import`), and the code below. Work on branch `r10-hotloader` in
`out/worktrees/r10-hotloader`. **Owns:** `packages/model-hotloader` (its Lua and data, except
`native_render.lua` and `materials.lua`, which R10-E may touch) and `packages/character-motion-importer`,
both changed only by importing reviewed copies staged under `out/`; new analysis or QA scripts in `tools/`
(each with its `.md`) and their tests; ADR 0089 (and 0090 if item 33 needs a decision of its own); additive
edits to CHANGELOG (a `### R10` section under Unreleased), ROADMAP, RESEARCH, TESTING and COMPONENTS.
**Does not touch:** `runtime/**`, `companion/**`, `loader/**`, `glass/**`, other parts of `packages/`, the
hotloader's native binaries, the field install, the Workshop, `origin`.

## The user's requests (2026-11-02)

**33.** "When user enter map #1, spawn a mmd model, then switch to another map, spawning that model again
as NPC will produce error as model not found."

**34.** "The imported mmd model's expression naming scheme when passed through the importer, is a bit off
from the actual expected. For example: refer to: https://github.com/Sinsax/mmd-facial-expression (note
this repo might have some misinformation for left and right), context is: [MMD VMD] Built animation:
mmd_vmd_npc/built/motion_35e2c448ff_c541b3669b_mmd_94ac7b53f627cfeb_gui_nai_fen_3335225749_tw0_ht0_eye0_sp0.json,
"笑い" is incorrectly assigned to eye_blink_happy_left. There are a lot of assignment mistakes, also
observable in Robin model. Since both the original model (E:\G\Upload\1_fin\Guinevere\1_PMX\星穹铁道-桂乃芬)
and mmd (nanoem) https://github.com/hkrn/nanoem is available, please figure out a better facial
expression mapping for mmd importer models, you can sample models on E:\G\Upload."

The user's screenshot: the motion importer's manual flex mapping lists MMD morph `笑い`, assigned flex
`eye_blink_happy`, "Drives: eye_blink_happy_left #17", target `eye_blink_happy_left #17`, marked "Wrong!".
`笑い` closes both eyes in a smile; `eye_blink_happy_left` is the model's `ウィンク`, a one-eyed wink.

## What Claude found (starting points: verify them)

**33.** Not reproduced yet. The motion importer spawns no NPCs; the Model Hotloader does:
`packages/model-hotloader/mmd_hotloader/lua/mmdhl/actors.lua` registers each actor rig as a spawn-menu
NPC (`list.Set('NPC', 'mmd_'..key, {Model = rig.model, ...})`) and player model, spawns through
`mmdhl.SpawnNPC`, attaches menu NPCs in the `PlayerSpawnedNPC` hook `MMDHL.AttachMenuNPC`, and falls back
to Kleiner where `util.IsValidModel` fails (line 199). See also `persistence.lua`, `library.lua`,
`carrier.lua`, `client.lua`, `server.lua`, `workshop.lua`. Reproduce on the PoC (gm_construct and
gm_flatgrass are installed; `tools/poc_session.py --change-map`): spawn a library character on the first
map, change map, spawn it as an NPC from the spawn menu's NPC tab and from the hotloader's own spawn UI;
also a fresh start straight on the second map. Capture the exact error and where it comes from.

**34.**
- **The hotloader names flexes natively.** Each PMX morph becomes a flex named by SCMI's exact-name table
  (473 names) or `englishMorph`'s composition (a trailing `左`/`右` becomes `_left`/`_right`, digits a
  `_n` suffix): source `H:\BACKUP_20260815\Modding\ipg\!GMHLVK\Gmod-Model-Hotloader-with-Vulkan\native\mmd_names.hpp`,
  `native\scmi_data.hpp` (decoded in `out\r10\scmi_flexnames.json`) and `native\rig.cpp` around line 405.
  The packaged natives are release 2.3.1, build `ecd7c426c0b5` (that repository's `ecd7c42`). Examples:
  `笑い`→`eyes_blink_smile`, `まばたき`→`blink`, `ウィンク`→`eye_blink_happy_left`, `ウィンク右`→`eye_blink_happy_right`,
  `ウィンク２`→`eye_blink_left`, `ウィンク２右`→`eye_blink_right` (the half-width `ｳｨﾝｸ２右` has no entry),
  `はぅ`→`eyes_sqeeze`, `なごみ`→`eyes_peaceful`, `じと目`→`eyes_stare`. Each morph keeps its PMX name: the rig's
  morph records are `{mmd, name, original, displayName, namingSource, native}` (Lua: `mmdhl.GetMorphs(ent)`,
  `faceposer.lua`). Only 96 morphs get a native flex controller (`native >= 0`); the rest are overflow.
- **The importer maps VMD names to its own canonical names**, then to the model's flexes:
  `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_import_data.lua` (around lines
  600-938: `笑い`→`eye_blink_happy`, `ウィンク`→`eye_blink_happy_left`, `ウィンク右`→`eye_blink_happy_right`,
  `ウィンク２`→`eye_blink_left`...), the alias groups in `data_static/mmd_vmd_npc/flex_mapping_table.json`, and a
  side split in `sv_cache.lua` (around line 399: `eye_blink_happy` → `eye_blink_happy_left` +
  `eye_blink_happy_right`). The two tables disagree: the model's `笑い` is `eyes_blink_smile`, in no alias
  group of `eye_blink_happy`, so a VMD's `笑い` falls to the split and drives the wink. The manual mapping UI
  is in `cl_menu.lua`. The importer's own repository is
  `H:\BACKUP_20260815\Modding\ipg\Gmod-Mmd-Motion-Importer` (with `flex_mapping.py`); `packages/` holds
  R4's local changes on top and is the source of truth now.
- **What MMD does.** MMD binds a VMD morph keyframe to the model's morph of the same name. VMD names are
  15-byte Shift-JIS fields, so long names arrive truncated. Confirm the exact rule (encoding, truncation,
  width) in nanoem's source (https://github.com/hkrn/nanoem; a nanoem build is in
  `H:\BACKUP_20260815\Modding\nanoem-v34.10.0-win64`, and the hotloader links nanoem's model library).
- **The corpus.** `out/r10/corpus.jsonl` (from `out/r10/corpus_scan.py`, all 1,225 PMX under `E:\G\Upload`)
  holds every model's morphs with panel (1 brow, 2 eye, 3 mouth, 4 other), type, group children, and for
  vertex and group morphs the offset-weighted share of moved vertices at +X (`left`) and their mean X and Y.
  In PMX, +X is the character's left (`左目` sits there). `out/r10/morph_stats.tsv` tabulates names (NFKC):
  - `笑い`: both eyes in 999 of 1,009 models. `まばたき`: both.
  - `ウィンク`: the character's left eye in 971, right in 22; `ウィンク右`: right 955, left 22; `ウィンク2`: left 945,
    right 34; `ウィンク2右`: right 920, left 34.
  - miHoYo-style names (`EL_*`, `EB_*`, `TD_*`, `TDS_*`, `jawOpen_*`, `look_*`, `biyan*`, about 360 models, with
    or instead of the Japanese ones) do not follow one side convention: `EL_Happy_l_CLO` closes the
    character's right eye in all 345 models and `EL_Happy_r_CLO` the left, while `biyan_L`/`biyan_R` follow
    the character.
  So a name does not reliably tell the side, and Sinsax's table can be wrong about it; geometry does.
- **Test material.** The user's own example motion's built caches are in the field install's
  `garrysmod/data/mmd_vmd_npc/built/` (`motion_35e2c448ff_...`, for Robin and others) and its imported motions
  in `.../mmd_vmd_npc/motions/` (read only; copy what you need under `out/`). The PoC library holds Guinaifen
  (`1c2ed2fc...`), Robin (`f9c3e4b4...`), Evernight, March 7th and Linlong. Guinaifen's PMX is
  `E:\G\Upload\1_fin\Guinevere\1_PMX\星穹铁道-桂乃芬\桂乃芬.pmx`; Robin's is under `E:\G\Upload\robin\1_PMX\`.

## What to build

**33.** Fix the cause so an imported character spawns as an NPC (spawn menu and the hotloader's UI) on any
map, after any number of map changes and after a fresh start, single player and on a listen server; a
regression test; the PoC steps above passing.

**34.** VMD expressions on imported characters drive the morph MMD would drive:

1. **Exact name first.** A VMD morph whose name is one of the model's PMX morph names (`original`,
   compared as MMD and nanoem compare, truncation and width included) drives that morph, whatever the
   hotloader named it. Overflow morphs too if the hotloader can drive them; if not, say so.
2. **Meaning only where the model lacks the name.** A corrected table of the standard MMD morphs (both
   eyes or one side, and which side) checked against the corpus; synonyms for models without the
   standard names, mined from the corpus (models whose standard-named group morphs wrap other morphs;
   offset similarity between morphs within a model); sides from geometry, never from a name's suffix.
   Make the importer's canonical names and the hotloader's names agree (for example `eyes_blink_smile` is
   `笑い`).
3. **A morph for both eyes never drives one side.** A split controller drives both sides or nothing.
4. **The mapping UI tells the truth**: each target with its PMX name; existing manual overrides are kept;
   caches built with the old mapping are rebuilt (bump their version or key).
5. **Other models keep working:** Source models with flexes use the semantic path as today.
6. **Evidence:** before and after mappings for Guinaifen and Robin with the user's motion (or another
   motion using `笑い`, `ウィンク` and `まばたき`); corpus-wide coverage (the share of a typical VMD's morphs that
   resolve by name, by meaning, or not at all); the hotloader names that misstate a meaning or a side, as a
   recommendation (renaming the native flexes is out of scope: saved face presets and caches use them).
7. **PoC QA:** play an expression motion on Guinaifen and Robin; record the driven morph weights per frame
   (a probe) and screenshots: `笑い` closes both eyes, `ウィンク` the character's left eye, `まばたき` both.

ADR 0089 records the mapping rules. Tests for the matcher and the tables (the corpus statistics as
fixtures, not the models). CHANGELOG `### R10` lines in the user's terms.

## Rules for this run

- The PoC is shared with R10-E. Before you deploy to it or start a session there, create
  `out\r10\poc.lock` in the main checkout (`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock`)
  exclusively, with your task name and the time; if it exists, wait and retry every minute (a lock older
  than 90 minutes with no PoC game running may be taken over). Delete it when your session has ended and
  the PoC is back on its Workshop-only config.
- The user allowed closing any running game for this run (prefer a console `quit`; say which you closed).
  Never write the field install, Steam's files or a Remix `user.conf`. `-multirun` for every session.
- No questions to the user: decide, and record the decision. Commit on `r10-hotloader` with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`; never push, merge or publish.
- `tools\test.ps1 -Config Release` passes on the branch.
- Write `docs/handover/R10-H-report.md`: the causes, what you built and why, the evidence, what is left.
