# R12 plan: the user's report after R11-B (items 36-40)

Claude is the project manager; Codex (gpt-6.1-sol) does the four tasks below, each in its own worktree.
Standing rules: [AGENTS.md](../../AGENTS.md). Earlier rounds: [R11-report.md](R11-report.md),
[R11-B-report.md](R11-B-report.md), [R10-report.md](R10-report.md).

## The user's items (2026-11-02, verbatim)

> 36: If a model is removed and imported again Ragdoll could be spawned, but not NPC: Model id: endminf
> (in active session)
> `[mmd_hotloader] [Model Hotloader restore] Cached model carrier is missing or outdated. Reapply/import the model.`
> 1. report - addons/mmd_hotloader/lua/mmdhl/persistence.lua:211
> 2. oldSetModel - addons/mmd_hotloader/lua/mmdhl/persistence.lua:240
> 3. SetModel - lua/compositeentities/override/sh_entity.lua:455
> 4. SpawnNative - addons/mmd_hotloader/lua/mmdhl/actors.lua:356
> 5. unknown - addons/mmd_hotloader/lua/mmdhl/server.lua:108
>
> 37. PBR import from model hot loader is not robust enought, eg:
> E:\G\Upload\Alf\1_PMX\白银之城—阿芙2.0_by_神帝宇_fe972123c0e320e139d391cf37bad8d5\白银之城—阿芙2.0, can not import
> PBR. A better way is to match texture's feature, with support by name. Like "衣服.png" is to
> "T_AlfDefault_Body01_A_N.png", a human can easily match them together.
>
> 38. In some way, allow manual assignment of a material on character to be eye-white.
>
> 39. Allow manual override of imported PBR resources from hotloader, make it apply to textures with the
> same hash (not limited to the character with the same name only).
>
> 40: (Important) Garry's Mod currently uses so much VRAM in the active session. Please investigate and
> optimize the VRAM use.

## What Claude found before the round

- **36.** NPC spawns go `SpawnActorNative` → `ent:SetModel(rig.model)` → the persistence wrapper of
  `Entity:SetModel` (`persistence.lua:236-245`) → `mmdhl.EnsureModel(path)`, which fails with the carrier
  message after the asset was deleted from the library and imported again in the same session; ragdolls
  take another path. Related design: [ADR 0090](../decisions/0090-ready-carriers-before-actor-publication.md)
  (R10 item 33). The field asset is endminf `a9c7045d3863...` (Arknights: Endfield, source
  `E:\G\Upload\the_endministrator\1_PMX\【明日方舟：终末地】女管理员_by_茶叶味香皂_...\女管理员.pmx`).
- **37.** R11-A's `GamePBR::Discover` (fixes `source/material_pipeline/to_pbr/game_pbr.h:184`) pairs maps
  only through a `<stem>_D` base and `<stem>_N/_MRA/_E/_P/_HN` (with `_ID/_HM` as Wuthering Waves evidence)
  anywhere under the PMX folder. The 阿芙2.0 build renamed all 13 bases (`衣服.png`, `衣服2.png`, `衣饰.png`,
  `皮肤.png`, `丝袜.png`, `头发.png`, `头饰.png`, `熔岩.png`, `脸.png`, `眼睛*.png`, `眉毛.png`, `表情1.png`) and
  keeps the maps in `法贴\` under the game's names: `T_AlfDefault_{Body01_A, Body01_B, Hair01_A, Hat01_A,
  Skin01_A, Socks01_A, Reactor01_D, Glass01_A, Pupil01_A, Face01_A, Special01_A}_{N, MRA, E, ...}`. The
  field's other game characters pair by name (four Endfield, 穗穗 twice, Alf `合体7`, 初雪), each with a few
  renamed bases. Field facts: [R11-B-report.md](R11-B-report.md) (field check sections).
- **38.** R10-E recognizes eye whites by material name ([ADR 0088](../decisions/0088-imported-character-eye-whites.md):
  白目, 白眼, 眼白, 目白 and explicit names) in `companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua`,
  with a proxy texture per eye-white material and runtime patch 0019's `rtx.gmod.eyeWhiteAliases`.
- **39.** Claude's reading: a manual override of the automatic imported (game) PBR of a character material
  (choose its maps, or none), stored by the live texture identity/hash, so it applies to every character
  and material that shows that texture, as R11-B's registry already keys automatic records
  ([ADR 0093](../decisions/0093-cached-imported-game-materials.md)). The Advanced Material Editor already
  scopes its RTX edits by captured hash; this is about the automatic imported PBR.
- **40.** Claude's field sessions (gm_construct, the user's add-ons, 3840x2160, cleanup log): DXVK allocated
  about 20 GB of 31.4 GB; **D3D9 app textures 12.9-13.9 GB** with nothing or one character spawned, on the
  R11 and R11-B packages alike (so not R11-B); replacement textures 3.9 GB; render targets 1.35 GB; OMM
  0.5 GB; retained 0.5-1.3 GB. The PoC (9 library assets, no Workshop add-ons, 1280x720): D3D9 app textures
  1.8 GB, 6.4 GB in all. The field library has 175 `materials-v*.gma` files (64.5 GiB) for about 45 assets;
  the hotloader's base textures are uncompressed VTFs. Unknown: how the 13 GB splits between the user's
  Workshop add-ons, the hotloader library, eye-white proxies and anything else. One suspect from R11-B:
  its `QueueGameMaterial` calls `FindMaterial` before checking that the material was drawn, for every
  material of every asset the Lua loop visits, which may load unspawned characters' textures.

## Tasks

| Task | Items | Worktree / branch | Brief | ADR |
|---|---|---|---|---|
| R12-A | 36 | `out/worktrees/r12-hotloader` / `r12-hotloader` | [R12-A](R12-A-hotloader-npc.md) | 0094 |
| R12-B | 37, 39 | `out/worktrees/r12-pbr` / `r12-pbr`; fixes `out/worktrees/r12-fixes` / `codex/r12-pbr` | [R12-B](R12-B-game-pbr-matching.md) | 0095 |
| R12-C | 40 | `out/worktrees/r12-vram` / `r12-vram` | [R12-C](R12-C-vram.md) | 0096 |
| R12-D | 38 | `out/worktrees/r12-eyes` / `r12-eyes` | [R12-D](R12-D-eye-white-assignment.md) | 0097 |

All four run at once. Each touches only the paths its brief gives it; shared docs (CHANGELOG under a new
`### R12` heading, ROADMAP, RESEARCH, TESTING, `docs/decisions/README.md`, `docs/handover/README.md`) get
additive edits only. Each task ends with `docs/handover/R12-<X>-report.md`.

## Rules for every task

- **The PoC is shared.** Lock: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock`, created
  exclusively; if it exists, another task holds the PoC: wait (retry every two minutes) and never remove
  a lock you did not create. Snapshot what you change, restore it exactly, then release the lock. Keep each
  hold short: prepare everything first.
- **The field game is a test session** (the user, 2026-11-02: "you can always consider the field as a
  test session and terminate it when needed"; this replaces the activity gate first written here). When
  a game launch needs the GPU or the PoC, end a running field `gmod.exe` instead of waiting, and say in
  your report which one you ended. Never write the field install, Steam's files or a Remix `user.conf`.
  `-multirun` always. R12-C may run read-only field sessions (no spawn, no setting written).
- The user's models under `E:\G\Upload` are read only: copy what you test under your worktree's `out\`.
- Never read the user's own GMod console logs: only the part of `console.log` your session wrote.
- No questions to the user: decide, record why, carry on. Commit with
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`; never push, merge or publish. A binary in
  `packages/` changes only through `tools\inputs.py import` (one import per binary at the end: Git LFS
  storage is never freed). `tools\test.ps1 -Config Release` passes before your last commit.
