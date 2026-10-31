# remix-map-pbr (draft skill)

A Claude Code skill that teaches an agent to remaster a Garry's Mod map for RTX Remix the way this user's
sessions remastered gm_poolrooms, the two Backrooms Complex maps and modern_house: AI-upscaled PBR
materials in a Remix mod keyed by texture hashes, and a map-only Lua addon for lights, sky, mirrors, water,
fixes and visibility, checked with tours, stock-vs-remaster pairs and frame-time tables.

Drafted on 2026-10-31 from the fork's docs and scripts, this repository's decisions and notes, and the
session transcripts. Nothing was run to write it, and the user has not reviewed it. Installing it (for
example as `%USERPROFILE%\.claude\skills\remix-map-pbr`) is the user's call.

| File | What |
| --- | --- |
| `SKILL.md` | when to use it, the user's ground rules, setup check, the workflow, accepted standards, commands, troubleshooting, done criteria |
| `references/pipeline.md` | every stage and script of the three implementations, folders, recipe and light numbers, how the maps differ, a new-map checklist |
| `references/remix-hashes-and-layers.md` | texture hashes (predicted, live, drift), the mod's USD, what the runtime accepts, mod priority and names, reloads, tag textures |
| `references/testing.md` | cameras, tours, before/after, A/B with noise floors, frame times, visibility checks, load time, evidence |
| `references/lessons.md` | pitfalls with symptom, cause, fix, map and date, R3-016 first |

## Where the real tools live

All in the user's fork `H:\BACKUP_20260815\Modding\garrys-mod-rtx-remixed` (GPL-2.0). The skill describes
them and holds none of their code, because it is meant for this MIT repository.

| Map | Branch, tip | Worktree | Pipeline, doc |
| --- | --- | --- | --- |
| gm_poolrooms (Workshop 2849511871) | `sheepylord/rtx-water-poolrooms`; on `origin` up to `f28bd5a`, local tip `fc478c0` | the main checkout | `source/gm_poolrooms_rtx/tools`, `docs/GM_POOLROOMS_RTX.md`; water by `rtx_water` (`docs/RTX_WATER.md`) |
| gm_br_complex, gm_br_pitfalls (Workshop 2821179466) | `claude/rtx-remix-map-enhancement-bda9ac`, `e4d548d`, local only | `.claude\worktrees\rtx-remix-map-enhancement-bda9ac` | `source/gm_br_rtx/tools`, `docs/GM_BR_RTX.md`; loading and visibility fixes in RTXFixesBinary (`source/culling_patches.cpp`, `HardwareSkinningHooks.cpp`, `modelload_fixes.cpp`) and gmRTX Lua |
| modern_house (Workshop 3495468649) | `claude/modern-house-rtx`, `e96ad7f`, local only, never to be pushed | `.claude\worktrees\modern-house-rtx` | `source/modern_house_rtx/tools`, `docs/MODERN_HOUSE_RTX.md` |

Each map has its addon in `garrysmod/garrysmod/addons/<addon>` and its mod in
`garrysmod/rtx-remix/mods/<mod>`; the extracted map (`map_extract/`) and intermediates (`work/`) sit beside
each pipeline, git-ignored. The AI stage uses the rpai venv, the PBRify weights and rpai's `ModelRunner`
from the `mmd-remix-pbr` skill; DDS encoding uses the Remix Toolkit's `nvtt_export.exe`. This
repository's `tools\package_content.py` and `tools\poc_session.py` package and test a remaster with the
native loader.

## Status of the three maps

| Map | Done | Where it is |
| --- | --- | --- |
| gm_poolrooms | 2026-10-26; calm water by RTX Water | Committed and pushed on the fork branch (the remaster's commit `b5c194e` is on `origin`, textures included: 18 mod files, 149.6 MB). It ships in the RTX package's `packages/fixes` part (imported from `fc478c0`), so in the project's distribution item 3829070317 |
| gm_br_complex, gm_br_pitfalls | 2026-10-27; PAS visibility 2026-10-28 | Local branch only; no Workshop item. Deployed in October into `GarrysMod_RTX_c` as real folders with 14 GB of hard-linked textures; that install was replaced by the user on 2026-10-30, so whether it is still there is unverified |
| modern_house | 2026-10-27; culling fix 2026-10-27; R3-016 fix 2026-10-29 | Hidden Workshop test item 3829275998 (`modern-house-rtx`, `0.0.0-dev.202610300425+d7efd636`, 500 files, 3.32 GB), built with `package_content.py`. Its textures derive from another author's map: the branch stays local and the item hidden (the user, 2026-10-29) |

## Limits

- **Numbers from one machine:** RTX 5090, Ryzen 9 9950X3D, 4K with DLSS, a game with about 250 add-ons,
  sessions of 2026-10-26 to 2026-10-29.
- **Not measured:** the material recipes, kelvins and grades were tuned by eye from tours (the user approved
  the results), not with the A/B noise-floor method used for characters.
- **The fork scripts target the classic install:** their `*_GAME` defaults point at `GarrysMod_RTX_c` (now
  off-limits) and `restart.py` uses that install's `_debug_tools` launcher. Using them on the PoC with the
  native loader is described but unverified.
- **Open questions for the user:** the Backrooms addon still forces `r_forcehwlight 1` (R3-016); poolrooms'
  derived textures (the upscaled plaster, the ladder atlas) are pushed to the fork's GitHub remote and ship
  in the RTX package, while Modern House's stay local (whether the fork is public was not checked: no
  network); hash replacements of base-game textures change those textures on every map.
- **Sources:** the fork's `docs/GM_POOLROOMS_RTX.md`, `docs/GM_BR_RTX.md`, `docs/MODERN_HOUSE_RTX.md`,
  `docs/PBR_GMA_LOADER.md` and the three `tools/` folders; this repository's ADRs 0023, 0027, 0031, 0035,
  `tools/package_content.py.md`, `tools/poc_session.py.md`, `tools/compare_frames.py.md`,
  `docs/handover/R3-triage.md`, `docs/RESEARCH.md` sections 12, 20, 21 and 32; the `mmd-remix-pbr` skill; the
  transcripts `3d2eda0e` (Backrooms), `74c5d7d0` (Modern House), `3f948dbb` (gm_poolrooms), `ff87a857`
  (Modern House follow-up: GPU use, save loading) and `94200df9` (Blood Overhaul, general Remix lessons
  only); the memory notes those sessions wrote.
