# R12 report: the user's report after R11-B (items 36-40)

[Plan](R12-plan.md), with the user's items verbatim. Claude was the project manager. Codex
(gpt-6.1-sol) did four tasks in parallel, then one follow-up after Claude's review. Claude
integrated them on `r12-int` and merged that into `main`.

| Item | Task | Result |
|---|---|---|
| 36: NPC fails after a character is removed and imported again | [R12-A](R12-A-report.md) | Fixed: the carrier's metadata is restored before every spawn kind |
| 37: game PBR for renamed textures (阿芙2.0) | [R12-B, R12-B2](R12-B-report.md) | Matched by UV features with name support; 阿芙2.0's clothes, accessories, hair, headwear and stockings now pair |
| 38: mark a material as eye white by hand | [R12-D](R12-D-report.md) | A chooser per spawned character, saved per character |
| 39: manual override of imported PBR, by texture | [R12-B](R12-B-report.md) | An Imported game PBR panel; a choice applies to every character showing that texture |
| 40: VRAM in an active session | [R12-C](R12-C-report.md) | Found: about 12.4 GB of unused character textures; runtime patch 0022 gives a texture GPU memory only on first use |

## Item 36: NPCs after a re-import (R12-A)

A deleted character's carrier archive can stay mounted while its `rig.json` and name records are
removed. A re-import then reused the archive, but the server's model check ran before the returned
manifest was cached. NPC spawns took that path and failed with "Cached model carrier is missing or
outdated"; ragdolls took another path. Now every spawn kind, attachment and readiness gate restores a
missing `rig.json` from the manifest native returns, using a staged, verified write. Deletion forgets
the asset's reusable rigs and converted NPC variants in both realms; live entities keep their bound
carrier. The PoC ran two delete/re-import cycles of a copy of the user's endminf with NPC, ragdoll and
player spawns ([ADR 0094](../decisions/0094-reimported-carrier-metadata-and-state.md)).

## Items 37 and 39: imported game PBR (R12-B, R12-B2)

**Matching (item 37).** Exact game names still pair first. A renamed base (衣服.png) is compared with
each game map family by the edges of its UV atlas at the same positions; the name only adds 0.08
after the layout agrees. It is accepted only with clear evidence (correlation at least 0.28,
score 0.36, margin 0.12) and otherwise abstains. Measured on the user's 121 PMX sources with names
hidden, against the 259 pairs whose game names prove the answer: **146 agree, 0 wrong, 113 abstain**.

Claude's review of R12-B found two problems, fixed in the follow-up
[R12-B2](R12-B2-decode-and-masks.md):

- **WIC's Fant scaler premultiplies alpha when it shrinks an image.** Body01_B's packed map (alpha 0
  on 97.7 % of its pixels) shrank to a mean colour of 3.1 instead of 166, so 衣饰 could not match it.
  The same loss affected R11-A's conversion whenever a map was shrunk. Maps now decode at their own
  size and are area-averaged per channel; converted maps get a new version so old outputs rebuild.
- **Hair matches only the family's mask maps.** 头发.png does not line up with Hair01_A's normal map
  at all, but does with its anisotropy mask. Mask maps (LBMask, AnisoMask, PromMask, ...) now count,
  but only when the base's name and the family's name agree, so the gun's lava texture does not
  pair with an eye map.

阿芙2.0 (13 character bases): 衣服 to Body01_A, 衣饰 to Body01_B, 头发 to Hair01_A, 头饰 to Hat01_A,
丝袜 to Socks01_A; 眼睛 and 眼睛2 to Pupil01_A (eyes stay protected). Skin, face, eyebrows,
expressions and the other eye texture abstain, which is what a conservative match should do with
their weak evidence. The panel below can assign any of them by hand.

**Manual choices (item 39).** The RTX menu's **Imported game PBR** panel (or `rtx_topbr_game_editor`)
lists the looked-at character's materials. For each it offers a discovered map family, individual
files from the source folder with their game layout, **no game maps**, or **automatic**. A choice is
stored by the live texture identity (`mmd/t/<hash>`), not the character's name, so it applies to
every character and material showing the same texture, and it keeps working when the source folder
is gone. The PoC proved it on two different characters sharing one texture. Claude read item 39 as
this override of the automatic imported maps; the user can redirect if they meant something else.
See [ADR 0095](../decisions/0095-texture-features-and-imported-pbr-overrides.md).

## Item 38: eye whites by hand (R12-D)

**Choose eye-white materials**, beside the eye-white brightness slider (or
`nativeloader_eye_white_materials`), lists a spawned character's materials with thumbnails, their
automatic or manual state and a checkbox. Marks and exclusions apply at once to every copy of that
character, survive map changes, restarts and re-imports of the same asset, and **Use automatic
detection** clears them. Eye-white work now covers spawned characters only
([ADR 0097](../decisions/0097-manual-eye-white-materials.md)).

## Item 40: VRAM (R12-C)

The field session's D3D9 app textures held about 13.4 GB of the 21.3 GB DXVK used. R12-C measured
where it went on a read-only copy of the field library (50 characters) on the PoC at 4K:

| Cold copied field library, no character spawned | D3D9 app textures |
|---|---:|
| With the saved actor registrations (as shipped) | 13.51 GB |
| Registrations removed (an experimental control only) | 1.07 GB |
| With registrations and runtime patch 0022 | **0.91 GB** |

The hotloader registers saved characters as NPC/player models and precaches them, which made Source
create, and DXVK back, every library character's textures, 12.4 GB of them never drawn. Runtime
patch 0022 keeps a static managed texture's data in CPU memory and creates its GPU image on first
sampling, upload or `PreLoad`; dimensions, mips and texture hashes stay the same, and
`d3d9.deferManagedTextures` turns it off. Three helpers also loaded unspawned characters: the MMD
alpha classifier and R11-B's game-PBR queue (each about 1.95 GB on a nine-character library,
overlapping) now wait for a real draw, and the eye-white helper is limited to spawned characters (R12-D)
([ADR 0096](../decisions/0096-demand-loaded-character-classification-and-memory-census.md)).

Not done here, proposed for later: avoiding the hotloader's CPU and RAM work for unspawned
characters (without breaking NPC readiness), releasing a used character's textures after it is
removed, and bounding replacement texture residency (an explicit cleanup freed about 2.4 GB of
replacement textures in one workload). Details: [R12-C report](R12-C-report.md#proposals-outside-this-change).

## Integration (Claude)

- `r12-int` from `main` (`48a659d`): R12-A, R12-D, R12-B, R12-C, then R12-B2. Shared docs were merged
  by keeping both sides.
- Reviews: each task's diff, its built-binary hashes against the imported inputs (fixes DLL
  `ce41b8b0…`, runtime `e8deaccb…`), its evidence, and the corpus's 14 new pairings by eye.
- **The field game is a test session** (the user, 2026-11-02). R12-C's input-activity gate
  (`tools/game_activity.py`) was not kept, because it never clears while the user talks to an agent.
  R12-A's QA tool now ends a running field game instead of waiting. One field game was ended for a
  test: PID 52192 (gm_flatgrass, started 03:57:38 UTC), closed normally at 04:10:42 UTC so R12-B2's
  PoC run had the GPU.
- Tests: `tools\test.ps1 -Config Release` on the final `r12-int` (`b9d3422`) passes 26 CTests and
  530/28/25 Python tests (two existing skips), `All checks passed.`
- No separate integrated PoC run: each task passed its own PoC check, and the field game, a test
  session by the user's rule, was the integrated check after publication (below).

## Publication and field check (Claude)

`main` at `7c2c8f4` was pushed and published: Workshop item 3829070317, version
`0.0.0-dev.20261103042843+84d5e7b4`, digest `10823c3e…`, 1,793,132,608-byte GMA. The field install
verified vanilla first (only the user's `autoexec.cfg` differs). Field game PID 2788 was ended at
04:30 UTC (forced after 60 s); it was an automated validation session (`gm_flatgrass`,
`-additional_validation_session 3a50c478…`), not the user's game.

- Start 1 (04:31-04:33 UTC) downloaded the new GMA and quit normally on the old package.
- Start 2 (04:33-04:39 UTC) deployed generation 49 (248 changes), ran the new runtime, and quit
  normally with exit 0 and zero Lua errors. Settings: gm_construct, 3840x2160, the user's add-ons and
  767 Workshop subscriptions.

VRAM against the field's own telemetry before R12 (R11-B package, an active session at 01:40 UTC,
from the [R12-C report](R12-C-report.md#active-field-read-only-category-attribution)):

| GB | Before R12 | R12, nothing spawned | R12, two characters spawned |
|---|---:|---:|---:|
| D3D9 app textures | 14.38 | **0.99** | 1.35 |
| Replacement textures | 5.86 | 4.13 | 4.60 |
| Render targets | 1.42 | 1.42 | 1.42 |
| DXVK used | 22.86 | **7.02** | 8.39 |
| DXVK allocated | 24.04 | 8.46 | 9.80 |
| Driver allocated (budget 32.95) | 25.94 | **10.63** | 11.69 |

The sessions differ (an active session against a fresh one), but the drop matches R12-C's
controlled replay.

- **Item 36:** endminf spawned as an NPC (`npc_citizen`, `models/mmd/cdc60d5c735e867d/endminf.mdl`),
  with no carrier error. Deleting and re-importing in the field was not done, because it would delete
  the user's library entry; R12-A proved that on a PoC copy.
- **Item 37:** the user's own 阿芙2.0 import (`f68499a5…`) pairs and converts 衣服, 衣饰, 头发, 头饰
  and 丝袜 with the same scores as the corpus. 眼睛 pairs but stays protected; the rest abstain.
  endminf's exact-name families still pair first. Its face and iris bases, named after families that
  ship no maps, abstain ("conflicting exported family").
- **Screenshot:** `out/r12/field/02-check/shot-01-alf2.png`, with endminf standing behind 阿芙2.0.
  Both render normally.
