# R20 plan: the user's report of 2026-11-06 (items 44-51)

Claude is the project manager and reviewer; Codex (`gpt-6.1-sol`, reasoning effort max, priority
tier, as the user asked) writes the code in four tasks, each in its own worktree. Standing rules:
[AGENTS.md](../../AGENTS.md). The latest round before this one: [R19-report.md](R19-report.md).

## The user's items (2026-11-06, verbatim)

> 44. Improve the compatibility to vanilla particle / decal related addons to make them display
> correctly, eg. Physics Blood. https://steamcommunity.com/sharedfiles/filedetails/?id=3818841829
>
> 48. Also package H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\dynamic_toolgun_screen
> and H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\Blood Overhaul, to the workshop addon.
> (with PBR we made), move its setting to the RTX tab. Enhance it to make it also replace and enhance
> the blood splatter particle effect (when bullet hit NPC / ragdoll) in realistic style (design and make
> this effect, if image generation needs to be used, use ChatGPT on this computer)
>
> 51. When saving dupe, the dupe can be saved, and used correctly, but throw an error:
>
>     Received dupe. Size: 3186
>
>     [ERROR] cam.End underflow
>       1. unknown - gamemodes/sandbox/entities/weapons/gmod_tool/stools/duplicator/icon.lua:151
>        2. xpcall - [C]:-1
>         3. protectedCall - lua/includes/init.lua:1599
>          4. unknown - lua/includes/init.lua:1625 (x32)
>
>     [ERROR] cam.End underflow
>       1. unknown - gamemodes/sandbox/entities/weapons/gmod_tool/stools/duplicator/icon.lua:213
>        2. xpcall - [C]:-1
>         3. protectedCall - lua/includes/init.lua:1599
>          4. unknown - lua/includes/init.lua:1625
>
>     Saved!
>
> 4 Minor QoL updates:
>
> 45. Add a game hint to remind user to enable frame generation / up scaling if they didn't enable it
> when the game start.
>
> 46. The workshop addon should record the most recent version of the loader dll. If user's dll is
> outdated, the main menu should show a window to remind user to re-download and update the loader.
>
> 49. For the sky and weather, default the time passes to be on, default a day is 20 minutes.
>
> 50. In multiplayer tab, when user click the play multiplayer, display a warning that server might
> forbid custom shading like Remix and Reshade, and the performance and stability is not grantee
> especially if you don't have the PBR resource for the map that the server is running installed, and
> the dev take no responsibility for any consequences of using this addon. User will have to agree to
> continue to server browser, else return to the main menu. This warning could be dismissed permanently.
>
> Test and build locally first, and publish to Workshop when ready. Since workshop build takes 1 hour,
> the Workshop publish does not need to wait to GitHub action, update Workshop when GitHub action
> finish.

The user also said the repository is now https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix (renamed
from `-Gmod-Workshop-RTX-Remix`). Claude replaced the 206 old links on `r20-int` before the tasks
branched; the runtime patch 0012's compiled-in fallback text keeps the old link (GitHub redirects it)
until the runtime is rebuilt.

## What Claude found before the round

- **51.** The companion's guard (`companion/nativeloader/lua/autorun/_nativeloader_guard.lua:1284`)
  wraps `cam.Start` with the pop `cam.End3D` and never wraps `cam.End`. The stock duplicator icon
  (`gamemodes/sandbox/entities/weapons/gmod_tool/stools/duplicator/icon.lua`, in the PoC) draws 32
  `cam.Start(view)`/`cam.End()` pairs per entity: every pair leaves a tracked entry, and at 32
  (`chainDepth(...) >= 32`, line 1191) the guard rejects the next push with a virtual scope, so the
  native `cam.Start` never runs and the stock `cam.End()` underflows (lines 151 and 213).
- **46, 50.** The main menu is GMod's HTML menu; the loader appends `loader/proxy/ui/mainmenu.js` to a
  generated copy of `control.Menu.js` (`loader/proxy/presentation.cpp`), so both items need a new loader
  (0.15.0) and a GitHub release. The manifest parser is strict (`only_keys`,
  `loader/core/src/manifest.cpp:273`): a new manifest key would make older loaders refuse the package.
  `native-loader/status.json` records `loader_version`, which the companion already reads. Loaders
  before 0.15.0 cannot show anything new in the menu, so the companion reminds their players in game.
- **45.** The RTX tab already reads `rtx.upscalerType` and `rtx.frameGenerationType`
  (`nativeloader_menu.lua:76-81`).
- **49.** `nativeloader_sky.lua`: `nativeloader_sky_time_passes` defaults to `"0"`,
  `nativeloader_sky_day_minutes` to `"30"`; both are archived client settings.
- **48.** Dynamic Toolgun Screen is the user's own add-on (v1.3.1). Blood Overhaul in the field is
  "Blood Overhaul RTX", this user's overhaul (project `H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx`,
  with its Remix PBR mod `rtx-remix/mods/blood_overhaul_rtx`) of **Crunchy's 2022 Blood Overhaul
  (Workshop 2683396098)**. Crunchy's files, and maps derived from them, may not be redistributed
  without his permission: the RTX package ships only what this project made.
- **44.** Physics Blood (Workshop 3818841829, subscribed; extracted to
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r20\physics_blood`) is 55 Lua files: flow meshes,
  droplets, pools drawn on render-target canvases and atlases, ground stains, wound effects.

## Tasks

| Task | Items | Worktree / branch | Brief | ADR numbers |
|---|---|---|---|---|
| R20-A | 46, 50 | `out/worktrees/r20-menu` / `r20-menu` | [R20-A](R20-A-loader-menu.md) | 0115, 0116 |
| R20-B | 45, 49 | `out/worktrees/r20-qol` / `r20-qol` | [R20-B](R20-B-companion-qol.md) | 0117 |
| R20-C | 48 | `out/worktrees/r20-blood` / `r20-blood` | [R20-C](R20-C-blood-and-toolgun.md) | 0118, 0119 |
| R20-D | 44, 51 | `out/worktrees/r20-render` / `r20-render` | [R20-D](R20-D-render-compat.md) | 0120-0122 |
| R20-E | 45 (native half, added after R20-B found Lua cannot read the live settings) | `out/worktrees/r20-native` / `r20-native` | [R20-E](R20-E-upscaling-readback.md) | 0123 |

All four run at once from `r20-int`. Claude reviews each branch, merges them on `r20-int`, tests the
whole in the PoC and the field, then: push `main` (the hooks publish the local build to the Workshop),
tag the loader release, and update the Workshop again from the GitHub package build when it finishes.
The user approved, on 2026-11-06 ("Yes, both"), tagging **v0.15.0** and starting the package workflow
(`package.yml`) once for it when R20 is ready; that approval covers this release only.

## Rules for every task

- **Your paths.** Touch only what your brief gives you. Shared docs (CHANGELOG under a new `### R20`
  heading at the top of `## [Unreleased]`, ROADMAP, RESEARCH, TESTING, COMPONENTS,
  `docs/decisions/README.md`, `docs/handover/README.md`) get additive edits only. Use only your ADR
  numbers. End with `docs/handover/R20-<X>-report.md`: what you built, the tests, the evidence (paths
  under your worktree's `out\`), what is open.
- **Translations.** New player-facing text of the companion goes through `tools/companion_i18n.py`
  (`update`, then translate every new entry into zh-CN, zh-TW, ja, ko, fr and ru, then `check`); the
  loader's menu text goes into `loader/proxy/ui/labels.json` in all of its languages. Write non-ASCII
  text from Python with `json.dump(..., ensure_ascii=True)` or UTF-8 files, and check every script's
  output: an earlier round lost characters as `?`.
- **The PoC is shared.** `H:\SteamLibrary\steamapps\common\GarrysMod_PoC`. Lock:
  `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock` (in the main checkout), created
  exclusively; if it exists another task holds the PoC: wait (retry every two minutes) and never remove a
  lock you did not create. Snapshot what you change in the PoC, restore it exactly, then release the
  lock. Prepare everything first; keep each hold under about 20 minutes. Launch with `-multirun`
  (`tools/poc_session.py` and the drivers under `tools/qa/`; read their `.md`). End sessions with the
  field's settings (PoC quits write GMod's cloud config). Never set
  `RTX_AUTOMATION_DISABLE_BLOCKING_DIALOG_BOXES` (the drivers decline Remix's crash prompt instead).
- **The field install** (`H:\SteamLibrary\steamapps\common\GarrysMod`) is the user's game: read it,
  never write it. Do not launch the field game. If a running field game blocks your PoC run, you may end
  it (the user allows it); say so in your report.
- Never read the user's own GMod console logs: only the part of `console.log` your session wrote.
- No questions to the user: decide, record why, carry on. Commit with your git identity and the trailer
  `Co-Authored-By: Codex (gpt-6.1-sol) <noreply@openai.com>`. Never push, merge, tag, publish, start a
  GitHub workflow or touch the Workshop.
- A binary in `packages/` changes only through `tools\inputs.py import`, once per binary at the end
  (Git LFS storage is never freed; the quota is 10 GiB). No other binaries in git.
- Run repository Python with `-I` from the worktree root. Temporary files stay under your worktree's
  `out\`.
- `tools\test.ps1 -Config Release` passes before your last commit.
