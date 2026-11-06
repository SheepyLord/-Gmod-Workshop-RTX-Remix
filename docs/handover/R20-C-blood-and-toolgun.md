# R20-C: Dynamic Toolgun Screen and Blood Overhaul RTX in the RTX package, realistic blood impacts (item 48)

Worktree `out/worktrees/r20-blood`, branch `r20-blood`, from `r20-int`. Implementer: Codex
(gpt-6.1-sol). Read first: [R20-plan.md](R20-plan.md) (the user's words and the rules for every task),
[AGENTS.md](../../AGENTS.md) (rules 4, 6 and 7 especially), [packages/README.md](../../packages/README.md),
[docs/PACKAGE_FORMAT.md](../PACKAGE_FORMAT.md), `tools/workshop.json`, `tools/package_content.py.md`,
`tools/inputs.py.md`, `companion/nativeloader/lua/autorun/client/nativeloader_menu.lua.md`,
`companion/nativeloader/lua/autorun/client/nativeloader_toolgun.lua.md`,
[ADR 0016](../decisions/0016-one-workshop-item-kept-current.md),
[ADR 0023](../decisions/0023-content-packages-and-modern-house-item.md).

## The user's item

> 48. Also package H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\dynamic_toolgun_screen
> and H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\Blood Overhaul, to the workshop addon.
> (with PBR we made), move its setting to the RTX tab. Enhance it to make it also replace and enhance
> the blood splatter particle effect (when bullet hit NPC / ragdoll) in realistic style (design and make
> this effect, if image generation needs to be used, use ChatGPT on this computer)

"The workshop addon" is the RTX package, Workshop item 3829070317, built from `packages/` and the
companion.

## Facts

- **Dynamic Toolgun Screen** (field `addons/dynamic_toolgun_screen`, read only) is the user's own
  add-on (author SheepyLord, v1.3.1, 13 languages of its own; `addon.json` leaves out `*.md`, `*.py`
  and `tools/`). Its settings are in Spawn Menu > Tools > Render > Dynamic Toolgun Screen and in
  Utilities > Dynamic Toolgun Screen > Settings. The companion's `nativeloader_toolgun.lua` already
  works with it (it redraws the screen after upscaling) and has a "Toolgun screen" panel in the RTX tab.
- **Blood Overhaul** in the field is **Blood Overhaul RTX**, this user's project
  `H:\BACKUP_20260815\Modding\ipg\PBR_map\blood_overhaul_rtx` (read its `README.md` first: pipeline,
  Remix traps, colour schemes, the decal mixer). Its outputs: `dist/addon_companion` (the add-on without
  the base add-on's files, 199 files, 72 MB), `dist/remix_mod` (the PBR Remix mod, 179 files, 164 MB;
  the field copy is `rtx-remix/mods/blood_overhaul_rtx`), and `dist/addon` (with them). It overhauls
  **Crunchy's 2022 Blood Overhaul (Workshop 2683396098)**. We have no permission to redistribute
  Crunchy's files or anything derived from them (the project's README says so; the repository is
  public now, so `packages/` is public too).
- The field's legacy folders `addons/dynamic_toolgun_screen` and `addons/Blood Overhaul` will stay
  there beside the package until the user removes them; the user's own add-on
  `H:\BACKUP_20260815\Modding\ipg\rainbow_Blood` hides HL2's blood mist particles and wraps
  `util.DecalEx`, a precedent for replacing stock blood effects.
- Task R20-D (parallel) makes Lua particles and decals display correctly under Remix in general,
  without per-add-on registration. Your effect should use the engine's normal paths
  (`ParticleEmitter`, `util.Decal`/`util.DecalEx`) so that work covers it; report anything that still
  needs RTX-specific handling.

## What to build

1. **Two new parts** (names of your choice, such as `toolgun-screen` and `blood-overhaul-rtx`), named
   in `tools/workshop.json`, imported with `tools\inputs.py import` (one import per binary, at the end),
   each with its provenance and licence beside it. Ship only what this project made: Dynamic Toolgun
   Screen as the add-on ships; from Blood Overhaul RTX the new patterns, the Lua, the colour schemes,
   the droplets and the PBR mod entries made from those, **none of Crunchy's files and nothing derived
   from them** (sort the files by their source with the project's README, `tools/` and `backup/`; list
   what you left out and why). The package must work with Crunchy's add-on subscribed and without it.
   Credit Crunchy's add-on as the base the patterns' style comes from, and disclose that the patterns
   were made with an AI image model. Keep the LFS volume as small as the content allows and report the
   compressed size you add.
2. **Settings in the RTX tab.** Both add-ons' settings move into the RTX Remix spawn-menu tab (sensible
   categories, beside the existing toolgun panel for the screen) and no longer appear in their old
   places when they come from the package; the companion's panel titles are translated in its six
   catalogs (Dynamic Toolgun Screen keeps its own 13 languages). With the field's standalone copies
   also installed, nothing breaks, nothing runs twice, and each panel appears once.
3. **Realistic blood impacts.** Replace the stock blood impact effect for bullet hits on NPCs,
   ragdolls and players (red, yellow and the other stock blood colours, and Blood Overhaul RTX's colour
   schemes) with a realistic one. Design it from how real bullet impacts look (back spatter toward the
   shooter, forward spatter and exit spray, a fine short-lived mist, droplets of several sizes on
   ballistic paths that leave small stains where they land; how all of that scales with damage and
   distance), make the textures it needs, and write the effect. Find how the stock effect is produced
   (engine effect names, particle systems such as `blood_impact_red_01`, decals) and the cleanest way to
   replace it so it shows for every shooter in single player and multiplayer, without networking if the
   client can do it alone. Image generation: if you need generated images, use your image generation
   (it runs on the user's ChatGPT account on this computer, which is what the user asked for; the
   project's `tools/codex_gen.py` shows how it was driven before) and keep the prompts and sources with
   the part's provenance. Requirements: it looks right with RTX on (path traced) and off; caps on
   particles and stains per second and in all; settings in the RTX tab (on/off, amount); off gives the
   stock effect back exactly.
4. **Docs.** ADR 0118 (the two parts, what is shipped and what is not, settings in the RTX tab, living
   beside standalone copies) and ADR 0119 (the impact effect: design, the replacement mechanism,
   budgets). `packages/README.md` (the parts table), the `.md` beside every script, CHANGELOG
   `### R20`, COMPONENTS, TESTING; the player-facing guide page if one fits (`guide_pages.lua` is
   R20-B's for the sky text only: add your own lines, translated).

## Tests and evidence

- `tools\inputs.py verify`, the package build (`python tools\build_package.py`, compare with
  `out\workshop\published.json`) and tests for any Lua logic (the effect's budgets and choices, the
  settings move, the duplicate guard).
- PoC (under the lock; a local package, no Workshop mounting): NPCs (citizens, combine, antlions or
  zombies) and ragdolls shot with a pistol, a shotgun and a rifle, RTX on and off, before and after;
  Crunchy's add-on present and absent; the standalone copies present and absent; the RTX tab showing
  both panels. Screenshots or short frame sequences under `out\r20c\`, frame time with many hits.

## Your paths

`packages/<your two parts>/`, `tools/workshop.json`, packagers and their tests if a part needs a change
there, new companion files for the settings or the effect, `nativeloader_menu.lua` only where you add
the panels, `companion/i18n/`, `tools/tests/` for your tests, the docs named above. Never write the
field install or the Blood Overhaul RTX project folder (copy what you need under your `out\`).
