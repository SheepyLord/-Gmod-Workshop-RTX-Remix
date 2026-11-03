# R14-H brief: the guide and the help wording, redesigned, with labeled screenshots

Task R14-H of the [R14 plan](R14-plan.md) (continued in the main session). Implementer: a Claude
subagent. Branch `r14-guide` from `main` `1cd57a7`, worktree `out/worktrees/r14-guide`. Claude (main)
reviews, integrates on `r14-int`, has Codex translate and check the text (R14-T), and publishes.

## The user's item (verbatim, 2026-11-03)

> 5: Redesign and greatly enhance and Refine the help document and the wording in the help section to
> make it natural, logical and detailed. More labeled, guided screenshots (like arrows in the screenshot)
> are needed to navigate user around the setting and functions of RTX-Remix. Only assign translation and
> text validation tasks to Codex for this session.

## What exists

- **The guide:** `companion/nativeloader/lua/autorun/client/nativeloader_guide.lua` (with its `.md`). It is
  a `DPropertySheet` of six tabs: Welcome, Remix menu, Settings, Lights, Memory and stability,
  Troubleshooting. Items are `{ "h" | "p" | "image" | "code", ... }`. It opens on the first RTX session,
  with `nativeloader_guide`, and from RTX Remix tab > Start here. `nativeloader_stability_guide` opens the
  memory page.
- **Its text is translated:** strings are marked `N("...")` / `L(...)` (`companion/nativeloader/lua/nativeloader/i18n.lua`).
  The catalogs are `companion/i18n/*.po` and `nativeloader.pot`, maintained with `tools/companion_i18n.py`
  (`update`, `check`).
- **The first pass (`1cd57a7`, the scheduled session) added:**
  - Five annotated pictures in `companion/nativeloader/materials/nativeloader/guide/` (JPEGs in git, as
    the guide's earlier `rtx_on.jpg` and `remix_menu.jpg` are).
  - `tools/guide_annotate.py` (numbered arrows on a capture) and `tools/qa/guide_shots.lua` (opens panels
    for captures).
  - A "Where to find things" section, legends, and a Glass section.
- **What the first pass left short** (its [report](R14-report.md)):
  - Its captures are low resolution and upscaled, so the text is pixelated.
  - A marker covers the label it points at.
  - Start here, Sky and weather, Base Options and Flashlight have no picture, because the sidebar's
    collapsing groups kept the previous panel showing.
  - Most of the guide is unchanged dense prose.
- **Where settings live:** the RTX Remix tab gathers every RTX panel, in groups:
  - Start here;
  - Remix settings (Common Remix settings);
  - Sky and weather;
  - Rendering (Auto-Categorization, Base Options, Imported game PBR, Model outlines, Performance, Player
    models, ToPBR, Toolgun screen);
  - Lights (Entity Light HUD, Flashlight, Map, Wrapper - Basic, Wrapper - Dynamic, Wrapper - Projected
    Texture);
  - Water and glass (Glass settings, RTX Water).

  The panels come from several add-ons (the companion, the RTX fixes in `packages/fixes`, glass, water).
  Remix's own menu is Alt+X. The Model Hotloader has its own window (`packages/model-hotloader`).

## The goal and the quality bar

A player who has never used Remix can follow the guide to find, understand and use every setting and
function the package gives them.

- **Natural, logical, detailed wording.**
  - Task first ("To keep your changes: 1. ... 2. ... 3. ..."), in short sentences.
  - UI names exactly as shown.
  - What each setting does, when to change it, and what to expect.
  - No internal jargon (ADRs, journal, replace-owned, patch numbers).
  - Explain terms on first use (path tracing, DLSS, preset, PBR).
- **Labeled, guided screenshots** for every place a player goes:
  - The overview of the tab, and every group's important panels.
  - The Alt+X menu in both its simple and developer forms, with the Save buttons.
  - The Model Hotloader window, and the Imported game PBR and eye-white choosers with a character.
  - Real in-game captures at a resolution where the text is sharp. Never upscale; crop instead.
  - Numbered badges with arrows pointing at the exact control, placed so they never cover what they point
    at, in one consistent style.
  - Under each picture, a legend in the text ("1. ... 2. ..."). The numbers are language-neutral; the
    legends are translated.
- **"The help section" too.** Review the wording of the RTX Remix tab's Start here panel and the help lines
  of the companion's own panels:
  - Make them natural and use the guide's terms.
  - Keep their meaning and behaviour.
  - Leave text that lives in `packages/fixes` (GPL) alone unless it is plainly wrong. If it is, list it in
    the report instead.

## A structure to start from (refine it, keep the task order)

1. **Welcome:** what is running, the three places (the RTX Remix tab, Alt+X, this guide), a short
   first-steps list, and a labeled picture of the spawn menu with the tab.
2. **The RTX Remix tab:** an overview picture, then one section per group with its picture: Start here,
   Remix settings, Sky and weather, Rendering, Lights, and Water and glass.
3. **The Remix menu (Alt+X):** the simple Graphics Settings menu and the developer menu, presets, how to
   keep changes (the Save buttons, pictured), and what not to press.
4. **Characters:**
   - Importing with the Model Hotloader, and spawning as an NPC, a ragdoll or a player model.
   - Characters load the first time they are used, and the most recently used stay ready: R13's memory
     profiles, [R13 report](R13-report.md).
   - Imported game PBR and manual choices, and eye whites.
5. **Performance and memory:**
   - The performance tier and the memory profile (minimum 8 GB VRAM / 16 GB RAM, recommended 16 / 32 GB),
     with tips for small computers.
   - The local readings.
   - The current memory and stability page's crash guidance, shortened to what a player does.
6. **Troubleshooting:** symptom, then what to do; the files to look at; after a crash.

## How

- **Code.** Keep `nativeloader_guide.lua` the entry point.
  - Split the page data into a helper module (for example `companion/nativeloader/lua/nativeloader/guide_pages.lua`)
    if it gets large. Every Lua file needs its `.md` (AGENTS.md documentation duties).
  - Keep `nativeloader_guide`, `nativeloader_stability_guide` and the first-session opening.
  - A page may hold sub-headings, step lists and pictures with legends. The window may get a table of
    contents or a left-side page list if that reads better than tabs.
- **Pictures.**
  - Put them in `companion/nativeloader/materials/nativeloader/guide/` as JPEG at about quality 85, each
    under about 250 KB, all together under about 4 MB (they ship in the Workshop package).
  - Make them reproducible:
    - Improve `tools/guide_annotate.py` to take a spec per picture (the capture, the crop, the badges with
      the target point and the badge position).
    - Improve `tools/qa/guide_shots.lua` so it opens each panel reliably (expand the right sidebar group,
      wait for the panel, then capture).
    - Keep both scripts' `.md` current.
- **Captures on the PoC** (`H:\SteamLibrary\steamapps\common\GarrysMod_PoC`, loader 0.13.0):
  - Take the PoC lock `out\r10\poc.lock` (create it exclusively, wait while another task holds it). Two
    other sessions use the PoC too.
  - Launch through `tools/poc_session.py`, which ends every session with the field game's own settings.
  - Use 1920x1080 or 2560x1440.
  - To see your companion changes, build the package from your branch (`tools/build_package.py`) and allow
    it with `poc_session.py config --allow-local <gma>`.
  - Afterwards put the PoC's `native-loader/config.json` back to the Workshop item (`allow.workshop`
    `["3829070317"]`, `remix.enabled` true, `patch_sets.require_insecure` true), and restore anything else
    you changed there.
  - For character pictures, R13's copied field library is in `out/worktrees/r13-int/out/r13/library`. R13-A's
    `tools/qa/mmd_lazy_session.py` shows how to swap it in and restore it.
- **Translation is not yours.** Mark every visible string for translation, and run
  `python tools/companion_i18n.py update` so the catalogs gain the new message IDs. Do **not** translate
  them: Codex does that next (R14-T, the user's rule). Write the list of new and changed message IDs to
  `out/r14-guide/new-msgids.json`. If `check` or a test fails only because the new IDs are untranslated,
  say so and leave it.
- **Check in a running PoC game** that the guide opens, every page shows, and every picture loads at a
  legible size, in English and in one other language (its untranslated new lines will show in English).
- **Tests:** `tools\test.ps1 -Config Release`, apart from failures caused only by the untranslated IDs (list
  them). Extend the companion's harness if a test covers the guide's structure.
- **Docs:** the guide's `.md`, the scripts' `.md`, a CHANGELOG line under R14, and
  `docs/handover/R14-H-report.md` (what changed, each picture and what it shows, how to regenerate the
  pictures, the in-game check, open items).
- **Paths:**
  - Yours: `companion/` (the guide, its helper modules, the companion panels' help text, the pictures),
    `tools/guide_annotate.py`, `tools/qa/guide_shots.lua` (with `.md`), guide tests in `tools/tests/`, and
    additive edits to the shared docs.
  - Not yours: `glass/`, `runtime/`, `packages/`, `skills/`.
  - Do not merge or push.
- No Codex. Claude subagents of your own are fine.

## Done means

- The `r14-guide` branch holds the redesigned guide, the improved help wording, the pictures and the
  scripts.
- The report, the msgid list, the in-game check's evidence (screenshots of the guide pages) and a passing
  test run, apart from the untranslated IDs.
