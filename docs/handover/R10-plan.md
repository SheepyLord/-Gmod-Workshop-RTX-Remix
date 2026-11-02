# R10: the user's character report of 2026-11-02 (plan)

The user's requests, after R9 (numbered as the user numbered them):

- **31.** "Auto apply eye white correction adaptive texture to eligible hot loader models. The eye white
  part usually has an identificable name, something like "眼白". Check our model catalogue. There should
  be some option for user to adjust the brightness."
- **33.** "When user enter map #1, spawn a mmd model, then switch to another map, spawning that model
  again as NPC will produce error as model not found."
- **34.** "The imported mmd model's expression naming scheme when passed through the importer, is a bit
  off from the actual expected. For example: refer to: https://github.com/Sinsax/mmd-facial-expression
  (note this repo might have some misinformation for left and right), context is: [MMD VMD] Built
  animation: mmd_vmd_npc/built/motion_35e2c448ff_c541b3669b_mmd_94ac7b53f627cfeb_gui_nai_fen_3335225749_tw0_ht0_eye0_sp0.json,
  "笑い" is incorrectly assigned to eye_blink_happy_left. There are a lot of assignment mistakes, also
  observable in Robin model. Since both the original model (E:\G\Upload\1_fin\Guinevere\1_PMX\星穹铁道-桂乃芬)
  and mmd (nanoem) https://github.com/hkrn/nanoem is available, please figure out a better facial
  expression mapping for mmd importer models, you can sample models on E:\G\Upload." A screenshot of
  the motion importer's manual flex mapping showed MMD morph `笑い`, assigned flex `eye_blink_happy`,
  target `eye_blink_happy_left #17`, marked "Wrong!".

Standing permissions for this run: no questions to the user; assign the work to Codex (75,000 credits
left); close any running game; push `main` and update the Workshop when done.

## Findings before the briefs (Claude)

- **Corpus.** `out/r10/corpus_scan.py` read all 1,225 PMX files under `E:\G\Upload` into
  `out/r10/corpus.jsonl` (materials with their textures; morphs with panel, type and the side of the
  face they move). `out/r10/morph_stats.tsv` tabulates the morph names.
- **31.** 434 models name an eye-white material (`白目` 239, `眼白` 142, `Face_Eyewhite` 20, `目白`,
  `EyeWhite`...); `目白` alone marks it in 54 more, and the PBR tool's sclera rule misses `目白`. In 411
  of the 434 the eye white shares its texture with the face (Guinaifen, Robin, March 7th and Linlong
  among them), and Remix keys materials by texture, so the correction has to be limited to the
  eye-white surface. The runtime has no emission for legacy materials and gives Remix API materials to
  API meshes only, so it needs a patch.
- **33.** The motion importer spawns no NPCs; the hotloader does (`actors.lua`: the spawn menu's NPC
  entries, `SpawnNPC`, the `PlayerSpawnedNPC` hook). Not reproduced yet.
- **34.** Two naming tables disagree. The hotloader names a model's `笑い` `eyes_blink_smile` (SCMI table),
  while the importer maps a VMD's `笑い` to `eye_blink_happy`, finds no such flex and splits it into
  sides: it drives the model's `ウィンク` (`eye_blink_happy_left`), a wink. The hotloader keeps each
  morph's PMX name (`rig.morphs[].original`), so the importer can match names as MMD does. In the
  corpus `笑い` moves both eyes in 999 of 1,009 models; `ウィンク` closes the character's left eye in 971
  of 993; miHoYo-style `EL_Happy_l_CLO` closes the character's right eye in all 345: names alone do
  not give the side.

## Tasks

| Task | Brief | Items | Branch / worktree |
|---|---|---|---|
| R10-E | [R10-E-eye-whites.md](R10-E-eye-whites.md) | 31 | `r10-eyes` in `out/worktrees/r10-eyes` |
| R10-H | [R10-H-hotloader-expressions.md](R10-H-hotloader-expressions.md) | 33, 34 | `r10-hotloader` in `out/worktrees/r10-hotloader` |

Both run in parallel as Codex (`gpt-6.1-sol`, effort max) with full access. The PoC is shared: a task
takes `out/r10/poc.lock` before it deploys to the PoC or starts a session there. Claude reviews, runs
the PoC QA, imports the runtime once, merges, publishes and checks the field.
