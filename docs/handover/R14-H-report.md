# R14-H report: the guide and the help wording, redesigned, with labeled screenshots

Status: **done** on `r14-guide` (from `r14-int` `186fe5c`), for review and integration. Not merged, not
pushed. The new text is untranslated: its translation and text check are R14-T's (Codex).

[Brief](R14-H-guide.md), with the user's item verbatim. Claude subagent; no Codex.

## What changed

**The guide** (`companion/nativeloader/lua/autorun/client/nativeloader_guide.lua`, pages in the new
`companion/nativeloader/lua/nativeloader/guide_pages.lua`):

- A window with a **contents list** on the left (every page, and under it every section) and the page on
  the right, instead of six tabs. A click opens a page, or the page scrolled to the section; each page
  ends with Previous and Next. Entries wrap, so long translated titles stay readable. The window is
  resizable (at most 1240 x 940).
- **Six task-ordered pages:** Welcome; The RTX Remix tab (one section per group: Start here, Remix
  settings, Sky and weather, Rendering, Lights, Water and glass); The Remix menu (Alt+X); Characters;
  Performance and memory (was Memory and stability); Troubleshooting.
- **Wording:** short task-first steps ("To keep a change: 1. 2. 3."), UI names exactly as shown, what a
  setting does and when to change it, symptoms with what to do, no internal jargon (no ADRs, journal,
  replace-owned, patches, "companion"), and a "Words used in this guide" list (path tracing, DLSS,
  frame generation, graphics preset, PBR, Remix mod, Remix API, VRAM).
- **Item kinds:** headings, paragraphs, numbered steps, lists, pictures with legends (a green badge per
  number, the text translated), explained words, symptoms, tips and cautions, code, buttons that run a
  console command (the eye-white chooser, `nativeloader_status`) and links to another section.
- **Pictures** are drawn at their own size (never enlarged; made smaller only on a page narrower than
  them, which does not happen at 1280x720 or more: they are at most 900 wide).
- **Commands:** `nativeloader_guide [page] [section]` (completes page names), `nativeloader_stability_guide`
  (Performance and memory), the first-session opening unchanged. `NATIVELOADER_GUIDE.shown` records what
  the open page drew, for tests and checks.
- **Loader-dependent advice** keeps R6's rule and adds R13's: items marked `r6`/`legacy` (performance
  tier) and `r13`/`pre13` (memory profile) show only what the installed `winmm.dll` supports, so an older
  loader is never told to write a key it would reject.
- The Remix menu page now describes the real menus, read from captures and the fork's source: the simple
  menu's four tabs and its Save Settings (user.conf), and the developer menu's Settings Management with its
  two Save buttons, View Changes and the Migrate button (below). The status button runs
  `nativeloader_status` only: `showconsole`, tried first, is blocked by GMod from Lua.

**The help wording** of the companion's own panels, in the guide's terms, meaning and behaviour kept:
Start here (opening line, classic settings, the guard's help moved under its checkbox, the Alt+X note;
the stability button is now **Performance and memory guide**, and an unapplied tier line points to that
page), Common Remix settings (session/Save note, startup replay, numeric overrides), Player models,
Toolgun screen, Model outlines (outlines, Imported game PBR, steady eye whites, brightness), the Sky and
weather panel (four help lines) and the eye-white chooser (help, empty state, selection note, "Texture not
available", the save-failure message). Labels, controls and ConVars are unchanged.

**Other:** `nativeloader_i18n.lua` also sends `guide_pages.lua` to clients; the render guard's exact table of
bundled Lua paths (ADR 0086) lists it (one line; 345 paths; the two test docs that state the count were
corrected). Two first-pass pictures nothing would show are gone (`remix_menu_marked.jpg`,
`guide_window.jpg`); `rtx_on.jpg` and `remix_menu.jpg` stay for the repository README.

## The pictures

Real 1920x1080 PoC captures (loader 0.13.0, the branch's package), cropped and never scaled, JPEG quality
85 without chroma subsampling. Numbered green badges with dark rims and arrows point at the exact control,
mostly a measured box drawn just outside it; badges sit in margins outside the UI (the game scene beside a
panel, or a plain margin), so none covers anything a badge points at (`guide_annotate.py` checks it). 17
pictures for the guide, 1.50 MB (19 files, 1.61 MB, with the README's two); the largest is 148 KB.

| Picture | Page | What it shows (badges) |
|---|---|---|
| `spawnmenu_tab.jpg` 750x548 | Welcome | The spawn menu's right half: the RTX Remix tab beside Tools/Options/Utilities, the groups, the open panel (3) |
| `tab_overview.jpg` 200x490 | The RTX Remix tab | The sidebar with every group open: Quick Filter and the six groups (7) |
| `start_here.jpg` 560x475 | Start here | The tier and memory profile lines, the guide and stability buttons, the status button, classic settings, the guard, the language (7) |
| `remix_settings.jpg` 560x635 | Remix settings | Reapply at launch, a choice, a number with its Set ... here box, Fog, Clear (5) |
| `sky_weather.jpg` 560x777 | Sky and weather | Sky, Follow the map's sun, time and its buttons, sun direction, time passes, season/moon/eclipse, night sky, weather, reset (9) |
| `base_options.jpg` 560x425 | Rendering | Pseudoplayer, Pseudoweapon, Hardware Skinning, Fix Skybox Leaking, Disable Remix API Lights, Map Fixes (6) |
| `performance.jpg` 560x280 | Rendering | Performance Mode, Culling and 3D Sky, Advanced: Engine Patches (3) |
| `flashlight.jpg` 560x713 | Lights | Brightness and radius, cone, volumetric scale, color, position offset, reset (6) |
| `glass_settings.jpg` 560x977 | Water and glass | Glass kinds, strength, cracks, player break speed, debris lifetime and budget, Clear broken glass (6) |
| `rtx_water.jpg` 560x570 | Water and glass | Enable, water type and waves, wave sliders, interaction waves, splashes (5) |
| `remix_simple.jpg` 700x695 | The Remix menu | User Graphics Settings (General tab): the tabs, DLSS Preset, DLSS Mode, Frame Generation, Developer Settings Menu, Save Settings, Delete All User Settings (7) |
| `remix_developer.jpg` 535x306 | The Remix menu | The developer menu's top: Graphics Settings Menu, Default Menu, the tabs, video memory, a blue changed-setting dot (5) |
| `remix_save.jpg` 535x260 | The Remix menu | Settings Management: View Changes, User Settings (user.conf) Save, the yellow Migrate button (do not press), Remix Config (rtx.conf) Save (4) |
| `hotloader.jpg` 890x810 | Characters | External Models (window, 800 wide): Import Character Models, the library, the selected character with its preview, the spawn buttons (4) |
| `imported_pbr.jpg` 560x740 | Characters | Imported game PBR with Karin (an Endfield character): the checkbox, the character, its materials and states (the chosen `发 automatic` in view), map family, single maps, the buttons (6) |
| `model_outlines.jpg` 560x335 | Characters | Hide outline meshes, Imported game PBR, steady eye whites, brightness, Choose eye-white materials (5) |
| `eye_whites.jpg` 880x690 | Characters | The eye-white chooser with Karin: the character, `目白`'s texture (Automatic: eye white), its Eye white box and Use automatic detection, Next materials (4) |

The Welcome page also shows `rtx_on.jpg` (a view of the game, no badges).

**Regenerating them** (all inside this worktree's `out\`; the PoC lock first):

1. Build the package from the branch: the build requires complete catalogs, so for a local test build fill
   the untranslated entries with the English (`out\r14-guide\placeholders.py` writes English plus a
   space), run `python tools\build_package.py --out <dir>`, then `git checkout -- companion/i18n/*.po`.
   Allow it: `poc_session.py config --allow-local <gma>`.
2. Captures: `poc_session.py run --addons --extra=-insecure --width 1920 --height 1080 --lua <set file>
   --lua tools\qa\guide_shots.lua --lua-shots 600`, with `NL_GUIDE_SET` = `panels` (the tab's panels and
   the characters) and `remix` (Alt+X; run `tools\qa\guide_input.py` beside it). Each view's controls are
   printed as `NL_RECT` lines (exact screen rectangles) for the spec.
3. `python tools\guide_annotate.py --shots <evidence root>` reads `tools\guide_pictures.json` (capture,
   crop, optional margin, and per badge the box or point and the badge's place) and writes the JPEGs;
   `--grid` makes a gridded copy of a capture for reading coordinates.

**How the hard ones were captured:**
- Panels open through `spawnmenu.ActivateTool(<item>)`; the RTX Remix tab's panel is found by its place in
  `spawnmenu.GetTools()` (the tool menu keys panels by place, not name), every group is unfolded, and the
  tool half is widened to 640 pixels (re-applied after the menu's first layout). The tip on the page says
  players can drag that divider too.
- Remix's menu: `rtx.showUI` opens the simple (1) or developer (2) menu. Posted mouse input does not reach
  it while the real cursor is elsewhere, so the tabs could not be clicked; posted keyboard input does, and
  Page Down paged the developer menu to its Settings Management section. Keys also reach the game's binds:
  an End press quit the game (the field's `config.cfg`, which `poc_session.py` uses, binds End to `quit`).
  The user's own mouse was never moved.
- Characters: 鳴潮_白蓮 and Karin from the PoC's own library, spawned as frozen citizens; the External Models
  window and the eye-white chooser were narrowed so their badges fit beside them in 900 pixels.

## Translations

`python tools\companion_i18n.py update` merged the new text into the six catalogs, untranslated.
**`out\r14-guide\new-msgids.json`** (this worktree) lists **292 message IDs** to translate (each with
where it is used); 25 are reworded help lines and name the message each replaces (its translations were
dropped); the rest is new guide text. 450 messages are in the catalog; the other 158 keep their
translations, and 90 translated messages that are no longer used were dropped (listed under `dropped`).

## The in-game check

PoC, the final package (`dist2`, 0.0.0-dev.20261103194421+c5d2de84) with the branch's companion, 1920x1080,
gm_construct, `NL_GUIDE_SET = "check"`: every page and every section opened by `nativeloader_guide <page>
<section>`, in English and then in French (`nativeloader_language fr`). 75 captures, no Lua errors:
- The guide opens, every page and section shows, and the pictures load at their own size: a crop of the
  game's capture of the Start here section is as crisp as the panel (`out\r14-guide\check-zoom-start.png`);
  the widest (the 880-pixel eye-white chooser) is drawn 880 wide.
- In French the window title, page names, group names and the earlier headings are translated, and the new
  lines show in English until R14-T translates them.
- The RTX Water picture was added after this run, so the final package (`dist3`,
  0.0.0-dev.20261103200132+a83df2e2, checked with `nlctl`) was checked again on the RTX Remix tab page: every
  section, then the page scrolled to its end, where RTX Water's picture and legend show at their own size
  and the page lists all nine of its pictures as loaded (`out\r14-guide\s8\water\`,
  `out\r14-guide\s8\water-bottom\shot-01-water_bottom.png`). Both sessions quit normally.
- Evidence (this worktree): `out\r14-guide\s7\check\shot-01-guide_welcome.png` to
  `shot-75-guide_fr_troubleshooting.window.png`, `out\r14-guide\s7\session.json`.
- That session's game shut down normally (it wrote its `config.cfg`, Remix closed its log) but its process
  stayed past the quit timeout, so `poc_session.py` ended it (exit 1). No crash dump; the settings had been
  put back before the quit. The other sessions quit normally, except `s3`, which the End key's bind ended
  (exit 0, no crash; that session changed no setting). GMod's shared video settings
  (`HKCU\Software\Valve\Source\garrysmod\Settings`) still hold the field's 3840x2160 borderless window.

Captures behind the pictures: `out\r14-guide\s5\panels` (the tab's panels, External Models),
`out\r14-guide\s6\character` (Imported game PBR, the eye-white chooser), `out\r14-guide\s2\pictures` (the
two Alt+X menus), `out\r14-guide\s4\remix` (Settings Management). `s1` was the first survey, `s3` the
keyboard trial that ended with the End bind.

## Tests

`tools\test.ps1 -Config Release` on the final commit (`out\r14-guide\test-final.log`): repository conventions
pass, the C++ build and all 26 CTests pass, the gmapack and steam Python tests pass; the tools' Python
tests run 536 with 3 errors and 18 failures, **all from the untranslated IDs**: `test_companion_i18n`
(shipping catalogs complete), `test_companion_ui_i18n` and `test_companion_stability` (both build complete
catalogs), and 18 `test_package_fixes` cases (the package build refuses incomplete catalogs). With the
untranslated entries filled with English (`out\r14-guide\test-placeholders.log`), every one of them passes
except `test_companion_stability`'s Russian guide case, which needs the Russian of "Start here"
(С чего начать) in the translated memory page.

New: `tools\tests\test_companion_guide.py` with `companion_guide_harness.lua` (pages, sections, links,
every page and section in every language for an old, an 0.11 and an 0.13 loader, the pictures against
their specs, the size budget and the 900-pixel width). It builds its catalog with `complete=False`, so it
passes before the translations exist. The stability harness follows the new window.

## The PoC

The lock `out\r10\poc.lock` (main checkout) was taken exclusively, each time after the other tasks
released it: 18:57-19:53 UTC (after R13-P) for sessions s1-s7, and 20:31-20:34 UTC (after R13-F and R13-D)
for the final check s8, with a fresh snapshot (`out\r14-guide\s8\poc-before`; 6 changed files put back).
Before the first session the PoC's
`native-loader\config.json`, `cl.db`, `garrysmod\data` (the big asset and texture folders by listing),
spawn icons, saves and the ToPBR cache were saved (`out\r14-guide\poc_state.py`); afterwards 12 changed
files were put back and 25 the sessions added (the two characters' rigs and names, the use history, the
converted game maps of Karin and 鳴潮_白蓮) were moved into `out\r14-guide\s1\poc-before\added`. The config is
byte-identical to before (the Workshop item, `remix.enabled` true, `require_insecure` true). Every session
ended with the field game's own settings (`settings_back: restored`). The field install was not touched.

## For the main session

- **Text in `packages/fixes` (GPL), left alone:** Base Options' Fix Skybox Leaking help misspells the entity
  (`light_enviornment` for `light_environment`); its Pseudoplayer help is one run-on sentence; Base
  Options' **Pseudoplayer Enabled** and the companion's **Local player shadow** (Player models) are the same
  setting (`rtx_pseudoplayer`) under two names.
- `dist/README-native-loader.txt` (not this task's path) still calls the guide's page "Memory and
  stability"; it is now "Performance and memory".
- The first pass ran its captures on the field install and its label clicks folded the RTX Remix tab's
  Start here group there (a Derma cookie); one click on the group's header unfolds it.

## Open items

- R14-T: the translations of the 292 IDs, and a text check of the English.
- Not pictured: the simple menu's Graphics tab (where Graphics Preset is; its tabs cannot be selected
  without real mouse input, so the page names the tab in words), and the small panels (Player models,
  Toolgun screen, ToPBR, Auto-Categorization, Map, the light wrappers, Entity Light HUD), which the pages
  describe in words.
