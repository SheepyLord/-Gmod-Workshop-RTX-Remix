# R13 report: less RAM and VRAM, with budgets that scale with the computer

Status: **in progress** (the integration is done; publication and the field check follow)

[Plan](R13-plan.md), with the user's words verbatim. Claude was the project manager and did R13-C
itself. Three Claude subagents did R13-M, R13-A and R13-B in parallel; Codex was not used, as the user
asked. Claude reviewed each part, had the runtime patches reviewed independently, integrated
everything on `r13-int`, measured it on the PoC and merged it into `main`.

| Part | Task | Result |
|---|---|---|
| Budgets that scale with the computer | [R13-C](#r13-c-memory-profiles-claude) | Loader 0.13.0 picks a memory profile (below minimum, minimum, recommended, high) from the VRAM and RAM and passes its budgets to the hotloader and the runtime ([ADR 0101](../decisions/0101-memory-profiles.md)) |
| The lag report; load a character on first use | [R13-A](R13-A-report.md) | The trigger was the first Combine soldier of a session. Saved characters now load when first used; the most recently used stay ready ([ADR 0099](../decisions/0099-saved-characters-load-on-first-use.md)) |
| The runtime's texture memory | [R13-B](R13-B-report.md) | One copy of each game texture on small computers, idle game textures leave the GPU over a quarter of the VRAM, Remix's own textures give way under real VRAM pressure ([ADR 0100](../decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| Smaller maps, reuse across versions | [R13-M](R13-M-report.md) | Imported game maps take about a sixth of the VRAM and disk, and a release that changes no conversion reuses every map ([ADR 0098](../decisions/0098-compact-imported-game-maps-and-recipe-keys.md)) |

## The lag report, explained

`out/r12/lag/lag-report.md` (main checkout, git-ignored): in the field game at 09:41 UTC on
2026-11-03, 14.35 GB of game textures became GPU-resident within 30 seconds, the driver went 2.5 GB
over its budget and the game stuttered until it was restarted.

- **The trigger** (R13-A) is the first precache of HL2's AR2 alt-fire ammo item in a session, which
  every Combine soldier makes (the NPC tab's, or a character spawned in that role). Source then draws
  once with every texture it has loaded (R13-B's counters: 1,128 images, all from draws), so every
  loaded texture gets its GPU image at once. On a copy of the field library that was 0.29 to 17.07 GB
  of game textures and 16 GB more private bytes. The manhack the user remembered does not do it; the
  field's file writes just before the jump match a character spawned as a Combine soldier.
- **Why it was so large:** every map loaded every saved character (98 NPC and player rigs of 57
  characters), so "every loaded texture" was the whole library.
- **The replacement textures** (10.3 GB in the report) were Remix mods that preload their textures at
  start: the field's mods preload 11.05 GB, 8.5 GB of it rpai's `ai_pbr` (R13-B section 4).

What R13 does about it: characters that are not used are no longer loaded (R13-A), idle game textures
leave the GPU once they hold more than a quarter of the VRAM (R13-B, patch 0024), and Remix's own
textures give way when VRAM runs short (patches 0025 and 0026). The engine step itself is unchanged.

## What a player gets, by computer (integrated, PoC)

The final package (`0.0.0-dev.20261103160058+ba38998d`, runtime `91f0696c`) with loader 0.13.0 on the
PoC: 1920x1080, gm_construct, the copied field library (98 saved NPC and player rigs of 57
characters), no Workshop add-ons. The minimum and recommended runs set `remix.memory_profile` on this
32 GB card, so they run those computers' budgets: 2 GiB and 4 GiB of game textures, copies released
on the minimum. `tools/qa/mmd_lazy_session.py --sequence integrated`: idle, four characters from the
NPC tab, their removal, a plain Combine soldier (the lag report's trigger) and 150 s after it, then two
characters again. Evidence: `out/r13/int/final-*` in this worktree.

| Profile (tier) | Ready | Idle: private / working set / VRAM | Four characters | Trigger: game textures | 150 s later | Peak: private / working set / VRAM |
|---|---:|---|---|---|---|---|
| minimum (low) | 0 | 9.2 / 3.5 / 5.6 GB | 12.8 / 4.9 / 7.7 GB | 2.44 -> 2.66 GB | 2.12 GB (released under 2 GiB) | 12.8 / 5.0 / 7.7 GB |
| recommended (medium) | 5 | 11.7 / 5.7 / 5.8 GB | 15.3 / 7.2 / 7.9 GB | 2.49 -> 3.07 GB | 3.07 GB (under 4 GiB) | 15.7 / 7.2 / 8.3 GB |
| high (auto) | 10 | 15.1 / 9.1 / 5.9 GB | 18.8 / 10.6 / 8.0 GB | 2.49 -> 6.36 GB | 6.36 GB (under 8 GiB) | 22.5 / 10.7 / 11.6 GB |
| before R13 (R13-A run 12, current package) | all 98 | 27.0 / 20.9 GB | | 0.29 -> 17.07 GB (run 19) | 17.08 GB (R13-B) | 43.7 GB private after the trigger |

- VRAM is the driver's allocation for the process. On the PoC 2.5-2.7 GB of it are the PoC's Remix
  mods, which preload their textures; on a card that runs short, patches 0025 and 0026 let the
  undrawn ones give way.
- Private bytes include the driver's mapping of the game's VRAM (R13-B section 1), so the working set
  is what the game holds in RAM: 5 GB at most on the minimum profile.
- On the minimum profile the runtime released 2,770 CPU copies and 48 idle images (game textures
  2.45 -> 1.91 GB). The images came back on use (42 re-uploads), with the characters looking the same
  (`final-min-low/npc-tab-newest-again.png`).
- First spawns from the NPC tab: the largest character (阮·梅 R18, 1.2 GB of textures) took 4.0 s
  when ready and 6.0 s cold on the minimum. The others took 0.5-2.1 s. Once loaded, a character
  spawns again in about 0.05 s.
- Every session quit normally with its settings put back. One earlier recommended session crashed in
  the runtime's option system (below); its repeat and every later session ran cleanly.

## R13-C: memory profiles (Claude)

Loader 0.13.0 reads the largest hardware adapter's dedicated VRAM (any vendor) and the total RAM at
every RTX start. Each size picks a profile and the smaller wins. The limits sit a little below the
installed sizes, because Windows reports less (an 8 GB card as 8,188 MiB):

| Profile | VRAM | RAM | Characters kept ready | Game textures on the GPU before idle ones go | CPU copy of a game texture |
|---|---|---|---:|---|---|
| below minimum (unsupported) | under 7,680 MiB, or | under 14,336 MiB | 0 | VRAM / 4 | released |
| minimum (8 GB / 16 GB) | 7,680 MiB or more | 14,336 MiB or more | 0 | VRAM / 4 | released |
| recommended (16 GB / 32 GB) | 15,360 MiB or more | 28,672 MiB or more | 5 | VRAM / 4 | kept |
| high (24 GB / 64 GB) | 23,552 MiB or more | 57,344 MiB or more | 10 | VRAM / 4 | kept |

- Every budget comes from the computer's own sizes, so a 16 GB card never runs an 8 GB budget, and
  larger computers keep more: the ready characters' archives may hold RAM / 10, and the GPU budget is
  a quarter of whatever the card has.
- `status.json` reports the choice as `activation.memory`. The hotloader reads its two character
  values from there; the runtime gets its two values in the DXVK layer
  `native-loader\remix\memory.conf` (D3D9 options only, after the package's layers).
- `remix.memory_profile` (`auto`, `minimum`, `recommended`, `high`) overrides the choice. An explicit
  minimum or recommended profile sizes its budgets for that profile's nominal computer, which is how
  the PoC ran the minimum's budgets on a 32 GB card.
- The RTX tab's Start here page shows the profile, its sizes and the characters kept ready, in all
  six languages. `nlctl activation` prints it.
- Without loader 0.13.0 the runtime works out the same two runtime values itself, and the hotloader
  keeps no character ready, so every character loads when first used. The bootstrap reaches players
  only when they install it.
- Also: [`tools/qa/memory_report.py`](../../tools/qa/memory_report.py.md) summarizes a session's RAM
  and VRAM by phase from the loader's and the companion's telemetry, and the player README has a
  lower-end guide.

## Reviews and integration (Claude)

- **R13-M:** a clean rebuild of fixes `913bb6b` differs from the imported DLL only in its PE
  timestamp, debug directory timestamps and PDB GUID (22 bytes); code and data are identical.
- **R13-A:** the hotloader's lazy publication, the readiness from `status.json` and the routes were
  read through. ADR 0090 now says it is superseded in part by 0099.
- **R13-B:** `runtime\build_runtime.ps1 -Verify` confirms the runtime tree is the fork commit with the
  recorded patches and builds the imported `d3d9.dll`. Its option names and values match the loader's
  memory layer.
- **An independent review of the runtime patches** (a separate Claude agent, reading only) found
  three defects, which R13-B fixed in patch 0028 before anything was published:
  - the texture hash API could race the release of a game texture's image and return an empty hash or
    read a freed image (ToPBR calls it from Lua);
  - under VRAM pressure, the terrain baker's preloaded source textures could drop to their smallest
    mip for the rest of the session;
  - on the minimum profile, a write locked with `D3DLOCK_NO_DIRTY_UPDATE` could be lost when the CPU
    copy went.
  The GPU probe gained a thread reading hashes through every release and an unmarked write: the
  runtime before 0028 fails both, and 0028 matches the original runtime in every variant
  (`d3d9.dll` `91f0696c`).
- **Steam Cloud.** GMod keeps `cfg/config.cfg` in Steam Cloud, shared by every install, and writes it
  at its quit; PoC sessions had left `fps_max "60"` there for the user's next start. Every
  `tools/poc_session.py` run now executes the field game's own `config.cfg` and writes it before the
  quit, and the cloud copy matched the field's again (`0ebf6a15`).
- `tools\test.ps1 -Config Release` passes on the integrated branch: 26 CTests and 592 Python tests.

**An intermittent crash, not R13's.** One of the integrated PoC sessions (recommended profile, medium
tier) crashed about 15 s into its idle phase: a null read in `RtxOptionImpl::resolveValue`
(`rtx_option.cpp:1151`), called from `RtxOptionManager::applyPendingValues` on the render thread. No
R13 patch touches the option system; the same session ran cleanly when repeated, and no other R13
session crashed this way. R13-B's time-boxed look found a candidate: `acquireLayer` and
`releaseLayer` change every option's layer list under the layer mutex only, while
`applyPendingValues` resolves them under the update mutex only (R13-B report, section 11). It is
recorded as a follow-up, not fixed, because the dump does not prove it. Dump and tools:
`out/r13/int/rec-medium/game/crash-reports/` (this worktree) and `out/r13/verify/` (main checkout).

<!-- R13-REPORT: publication and the field check go here. -->

## Open items and follow-ups

- **Preloaded Remix mods.** rpai (`ai_pbr`), ToPBR's game maps and the material editor set
  `preload_textures`, so their maps load at every start whether drawn or not (the field: 11.05 GB).
  Patch 0026 lets the undrawn ones give way under pressure, but with free memory they stay. Streaming
  them would cut most of that from the start, and needs a visual check first.
- **The user's duplicate mods:** `pbr_robin`, `pbr_guinaifen` and `pbr_evernight_march7th` hold the
  same 2.22 GB of files as `ai_pbr`'s folders for those characters, and Remix loads them twice. That is
  the user's content.
- **The engine step** that draws every loaded texture once on the first AR2 alt-fire ammo precache
  (and during a map load) is unchanged; the runtime now releases what it makes resident.
- **`rtx_flush_textures` after removing lazily loaded characters** releases their CPU copies but not
  their GPU images until the map changes (R13-A); patch 0024's budget releases them once game
  textures exceed a quarter of the VRAM.
- **Superseded uncompressed game maps stay on disk** until a collector proves them unreferenced
  (R13-M; the field cache is 4.57 GB, 0.89 GB of it AO maps nothing reads). Emission maps stay
  uncompressed. Downgrading after the map migration is not supported.
- **The intermittent option crash** above.
- **Not tested:** a second player on another computer; Remix captures.
