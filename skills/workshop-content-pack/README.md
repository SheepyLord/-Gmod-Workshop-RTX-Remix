# workshop-content-pack (draft skill)

A Claude Code skill that teaches an agent to pack Garry's Mod RTX content that depends on other
add-ons into one Steam Workshop item, the way the Guinaifen, Robin and Evernight and March 7th packs
were made: an MMD character imported with Model Hotloader plus its rpai PBR (a Remix mod), or a
remastered map's Remix mod and Lua. The item holds a native-loader content package; the loader
deploys it from any subscription, and it relies on the RTX package (3829070317).

The agent reads `SKILL.md`; the details are in `references/`, the tools in `scripts/`.

## Install

Copy this folder to `%USERPROFILE%\.claude\skills\workshop-content-pack\`, or keep it beside
`mmd-remix-pbr` under a `skills\` folder: SKILL.md finds that skill's `hotloader_export.py` and
`stage_pbr_mod.py` in `%USERPROFILE%\.claude\skills\mmd-remix-pbr\scripts` or `..\mmd-remix-pbr\scripts`.

## Items made with this workflow (all hidden; dates UTC)

| Item | Package | Content | History |
|---|---|---|---|
| [3829348717](https://steamcommunity.com/sharedfiles/filedetails/?id=3829348717) | `guinaifen-rtx` 0.0.0-dev.202610290741+bd360151 | Guinaifen (桂乃芬.pmx), 18 PBR materials, 44 DDS; 695,563,031 bytes | 2026-10-29: the user published the agent's build as this item; the agent updated it with two extra texture hashes |
| [3829347093](https://steamcommunity.com/sharedfiles/filedetails/?id=3829347093) | `guinaifen-rtx` (first build) | the same pack, before the hash fix | the agent's first upload; a hidden duplicate that stays (nothing is deleted until the project is done) |
| [3829892354](https://steamcommunity.com/sharedfiles/filedetails/?id=3829892354) | `robin-rtx` 0.0.0-dev.202610300504+6d1373ed | Robin (知更鸟.pmx), preset `Default`, 17 materials, 30 DDS; 452,591,324 bytes | 2026-10-30: created as `robin-r18-rtx`, renamed (`mmdhl_robin`, `pbr_robin`), then the display name `Robin`. The Workshop title was set at creation ("Robin R18 RTX (native loader package)") and `update` cannot change it |
| [3830769477](https://steamcommunity.com/sharedfiles/filedetails/?id=3830769477) | `evernight-march7th-rtx` 0.0.0-dev.202610311103+e95455ed | Evernight and March 7th, two layers; 1,222,846,295 bytes | 2026-10-31: the first pack made with `hotloader_export.py` and `stage_pbr_mod.py`; downloaded copy identical to the build |

On 2026-10-31 the field install's `nlctl plan` lists all three as `ACTIVE ... (subscribed, content
only)`, and the downloaded Guinaifen and Robin archives are byte-identical to the builds in
`out\packages\guinaifen` and `out\packages\robin`. Builds: `out\packages\guinaifen\`,
`out\packages\robin\` (and the first Robin build in `out\packages\robin-r18\`), and the Evernight
worktree's `out\packages\evernight-march7th\`.

## Contents

| File | What |
|---|---|
| `SKILL.md` | rules, what a pack holds, dependencies, the step-by-step procedure, the description template, updates, maps |
| `references/model-hotloader-package.md` | the Model Hotloader package on disk: manifest fields, limits, the MMDPACK2 packets, what an install writes and never changes, display names |
| `references/pitfalls.md` | 22 failures and traps with cause and fix; where to look when a pack does not show up |
| `scripts/mmdhl_pack.py` | the Model Hotloader package, offline (fallback for `hotloader_export.py`) |
| `scripts/pbr_mod.py` | the Remix mod with only the referenced files (fallback for `stage_pbr_mod.py`) |
| `scripts/add_hashes.py` | add texture hashes to a staged layer; check rpai's live hashes against a layer or mod |
| `scripts/gma_diff.py` | compare two archives member by member |
| `scripts/check_pack.py` | read-only preflight of a build folder |

Every script has its `.md` beside it, as the repository requires. They use only Python's standard
library, run with `python -I`, and write nothing outside the output they are given (a game install
only with `--allow-game-install`).

## What was verified for this draft (2026-10-31, offline)

- `mmdhl_pack.py` rebuilt Robin's published Hotloader package (46 packets byte-identical) and made
  the same 47 packets and manifest content as Model Hotloader's own exporter for Evernight and March 7th.
- `pbr_mod.py` rebuilt Robin's published mod byte for byte; `add_hashes.py` rebuilt Guinaifen's fixed
  layer byte for byte; `gma_diff.py` reproduced the 77-of-77 comparison of Guinaifen's two imports.
- `check_pack.py` passes the three published builds apart from the new description rule, flags every
  naming problem of Robin's first build, and finds the issues listed under Limits.

Nothing was uploaded, no game was started, and no repository, game install or skill folder was
written while drafting.

## Limits

- **Not exercised**: setting Required items on the item page; whether `gmpublish create` sets the
  page's description (its logs show no such step); a public release; the subscribe probe
  (`out\round5\steam_ugc_probe.py`, a throwaway); a map remaster through `check_pack.py`.
- **Inferred from code, not observed**: a requires-Remix character pack lets a standalone Model
  Hotloader delete and reinstall the model around starts without RTX; `ai_pbr` hides the packaged
  layer on the author's machine; English readers see Guinaifen as "New MMD Model" (her PMX's English
  name); Model Hotloader shows no Workshop page button for loader-deployed packages.
- **Open decisions for the user**: whether character packs use `--requires-remix` (Guinaifen and
  Robin did, Evernight did not); whether to rename Guinaifen to an ASCII name in a rebuild; making
  anything public (R18 content; the models' terms, Evernight's forbids redistribution).
- The agent cannot sign in to Steam's website: titles after creation, descriptions, Required items
  and visibility stay with the user.
- Windows only for packing (`cabinet.dll`'s XPRESS Huffman codec). The offline packer does not carry
  VRM licence records (none of these PMX models has one).
- The published descriptions of the three items predate the Required-items rule; `check_pack.py`
  reports that as an error for each.

## Provenance

Written by Claude for this user on 2026-10-31 from the sessions' transcripts, their scripts and
outputs, the repository's docs and tools, Model Hotloader's code, and the mmd-remix-pbr skill. The
four packers were written for the user by Claude in those sessions; `check_pack.py` is new. Moved
into the repository's `skills\` folder, it would fall under the repository's MIT licence.
