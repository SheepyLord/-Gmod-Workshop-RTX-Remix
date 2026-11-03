# R14 report: noclip and glass, and the guide

Status: **done**

The user's items (2026-11-03), verbatim:

> 41. No-cliping and fly through glass make fractures on the glass, which is not an expected behaviour.
>
> 5: Redesign and greatly enhance and Refine the help document and the wording in the help section to make
> it natural, logical and detailed. More labeled, guided screenshots (like arrows in the screenshot) are
> needed to navigate user around the setting and functions of RTX-Remix. Only assign translation and text
> validation tasks to Codex for this session.

A scheduled session (task `r14-after-r13`, after R13's report said done) made a first pass, merged as
`1cd57a7`. Then the user asked: "Please proceed to R14 here, launch sub agent if needed." The main session
continued on `r14-int` ([plan](R14-plan.md#continued-in-the-main-session-2026-11-03)). There were three
parts:
- R14-G, the glass: by Claude.
- R14-H, the guide and the help wording: by a Claude subagent ([brief](R14-H-guide.md),
  [report](R14-H-report.md)).
- R14-T, the text check and the translations: by Codex, and nothing else, as the user said.

## Item 41: noclip and glass (R14-G)

**First pass.**
- `glass/addon/lua/nlglass/server.lua` gained `S.Ghost(body)`, which is true for a player in noclip.
- `S.Body` and the `SetupMove` sweep return early for it. So no contact path (touch, physics contact,
  sweep) fractures a pane.

**Continued:**
- `S.Ghost` also covers spectators (`MOVETYPE_OBSERVER`).
- The broken glass's scene (`debris_scene.lua`) no longer counts a flying or spectating player as a body.
  So broken pieces on the floor do not move for them either.
- The engine harness's `bodies` scenario gained a spectator case and a runner control.
- The interaction harness puts flying and spectating players into its scene.

**Proven in a PoC game.**
- The never-shipped QA add-on (`tools/qa/nlglass_qa`, `nlglass_qa noclip` through
  `tools/qa/nlglass_noclip_start.lua`) moves the player through a 64x96 pane under its own controls.
- It holds forward and sprint for 1.6 s.

| Step | Speed (units/s) | Passed the pane | Impacts | Glass left | Move type |
|---|---:|---|---:|---:|---|
| Noclip | 1,500 | yes | 0 | 100 % | 8 (noclip) |
| Spectating | 1,500 | yes | 0 | 100 % | 10 (observer) |
| Running into it (control) | 400 | no | 1 | 3 % | walk |

Evidence: `out/worktrees/r14-int/out/r14/glass/noclip/` (console log, screenshots). Afterwards the PoC
was back on the Workshop item, the QA add-on was removed, and the lock was released.

## Item 5: the guide

### The redesign (R14-H)

**The window and the pages.**
- A window with a contents list on the left (every page and every section) replaces the six tabs.
- There are six task-ordered pages: Welcome, The RTX Remix tab, The Remix menu (Alt+X), Characters,
  Performance and memory, and Troubleshooting.
- `nativeloader_guide <page> [section]` opens a part directly.

**The pictures.** There are 17 labeled pictures of every place a player goes:
- the tab and its panels;
- both forms of the Alt+X menu and its Save buttons;
- External Models, Imported game PBR and the eye-white chooser with a character.

They are real 1920x1080 PoC captures, cropped and never scaled. Numbered badges and arrows sit in the
margins, and the legend under each picture is translated.

**The help lines.** The help lines of the companion's panels were reworded in the same terms.

The [R14-H report](R14-H-report.md) has the details, the regeneration steps and its in-game check in
English and French.

### The main session's review

**The pictures.** I viewed all 17 pictures:
- They are sharp.
- Each badge's arrow lands on the control its legend names.
- No badge covers what it points at.

The in-game window was checked from the subagent's captures: the contents list, the pictures drawn at
their own size, and the legends below them.

**The facts.** I checked the guide's facts against the code:
- the memory profiles' thresholds and budgets (`memory_profile.cpp`);
- the idle-texture release: 60 presented seconds, at a quarter of VRAM (ADR 0100);
- which Save button writes which file (RESEARCH, the save targets);
- the default of Disable Remix API Lights: the RTX fixes create it as 0, and the classic settings tick it.

**Fixes made in the review:**
- The supported hardware, in the user's R13 words: 8 GB VRAM and 16 GB RAM are the minimum, 16 GB and
  32 GB are recommended, and nothing lower is supported.
- The memory-profile lines, and the Player models line.
- The page's new name in `README.md`, `dist/README-native-loader.txt` and `docs/TESTING.md`.

**Remix's own Alt+X menu is translated** by the runtime fork (patches 0002-0014). So the guide's translated
names for its buttons must be the runtime's.
- The fork's translated worktree has only patches 0002-0004. The i18n hunks of 0005-0028 were applied to a
  scratch copy (`out/r14/remix-i18n`) and its labels read from there.
- Term files were collected under `out/r14` for every place the guide names:
  - `terms.json`: the companion;
  - `addon-terms.json`: the RTX add-ons;
  - `glass-terms.json`: the glass panel;
  - `other-terms.json`: the Model Hotloader's `.properties` and the Imported game PBR panel's own phrase
    table;
  - `remix-terms.json`: the Alt+X menu.

### The text check (R14-T, Codex)

**The check.** Codex checked the 292 new and reworded messages read-only, against the code and the
pictures' specs. It made 26 proposals, and found that all 17 legends match their badges.

**What was applied.** Claude checked each proposal in the code and applied 27 edits, most of them shorter
than proposed. The corrected facts:
- **Characters in advance.** The memory profiles load up to five (recommended) or ten (high) recently used
  characters in advance when a map starts, within a memory budget. The old text said a fixed number stayed
  ready (ADR 0099).
- **DLSS Preset.** DLSS has its own preset beside Graphics Preset. Keeping single settings needs Custom in
  both: Start here, the save steps and the restart symptom now say so.
- **The VRAM CSVs** are kept across starts; they rotate only when full.
- **Game layout.** Single game maps (Use individual maps) need Game layout set to the character's game
  (`cl_rtx_topbr_conversion.lua`).
- **The tier line** shows how the tier was chosen: automatically, by config.json, or as a fallback.
- **Player break speed:** walking stays below it only at the default of 250.
- **DLSS Mode:** "faster" and "sharper", because Ultra Performance and DLAA exist too.

The wording fixes:
- the exact labels of the flashlight's controls (Cone Angle, Cone Softness, Volumetric Scale, Position
  Offset) and of Steady eye whites for imported characters;
- the classic settings: applied once, except where you had already changed a setting;
- the sky interval's unit;
- the eye glow that follows the scene's light;
- Turning RTX off by `"enabled": false`;
- the memory_profile line as concrete JSON;
- "texture maps" where "maps" could mean levels.

One proposal was taken in part. "Everything runs smoothly" on a recommended computer became "should run
smoothly": it is the user's goal for that computer, not a promise.

### The translations (R14-T, Codex)

**The jobs.** Six Codex jobs translated the 292 messages, one language each. Codex ran them one after
another. Each job had the term files, the runtime's glossary, and the old translations of the reworded
lines.

**Two writes through PowerShell lost letters:**
- Russian lost every Cyrillic letter. Its own review caught it, and it rewrote the file.
- 14 French lines lost their accents. Claude's byte check found them, and they were translated again.

**The ambiguous step.** Every translator found "the same folder" in the crash step ambiguous; it came from
Claude's review edit. The step now names the folder.

**The repair and validation pass.** One Codex pass over all six catalogs:
- translated the emptied and reworded entries;
- fixed the Imported game PBR checkbox's name in its picture's legend: the panel's own label, not Model
  outlines' one;
- fixed the Korean crash link's wording, to match its heading;
- fixed the idle-texture sentence in ja, fr and ru (the quarter of VRAM is the textures' total).

It also turned the games' local names in zh-CN, zh-TW, ja and ko (鸣潮/鳴潮, 终末地, 白银之城, 명조,
엔드필드, 실버 팰리스, ...) into English. Claude undid that: the published translations use the local
names.

**Allowed to equal the English:** DLSS, PBR, VRAM and Remix API, and French "Path tracing"
(`tools/companion_i18n.py`'s `UNCHANGED`).

**The result.**
- `companion_i18n.py check` passes in its complete mode: 450 of 450 in each language.
- Every on-screen name of two words or more in the new text matches the label the player sees
  (`out/r14/check_labels.py`; the misses it lists are words inside longer labels).

**Five pictures captured again.** The review's rewording changed help lines that five pictures show:
`spawnmenu_tab`, `start_here`, `sky_weather`, `model_outlines` and `eye_whites`. The R14-H subagent captured
them again from `r14-int`'s text. Its badges follow the controls that moved down, and the legends are
unchanged (`38819b3`). Claude viewed the new pictures.

**The R6 convention.** The stability test asks for Task Manager's Committed reading and Remix's "User
Settings (user.conf): Save" to keep their English name in parentheses after the translation, as the R6
translations did. The new translations had dropped it. Claude put it back in the two entries per
language, so a player with an English Windows or an English Remix menu still finds them.

### The translated guide in a game

**The sessions.**
- Package 0.0.0-dev.20261103221325+c9aed748 was built from `r14-int` and checked with `nlctl`.
- PoC, 1920x1080, gm_construct, with the RTX add-ons loaded. `tools/qa/guide_shots.lua`'s `guide_lang`
  set opened every page and section, in zh-CN and then in ru: 38 captures each, no Lua error.

**What they show.**
- The window title, the contents list, the headings, the steps, the legends and the code render in both
  scripts.
- Long Russian entries wrap in the contents list.
- The translated names match the tab's own labels (С чего начать, 从这里开始).

**The first attempt.** It ran without `--addons`, so `-noaddons` kept the package's Lua add-ons out, and
it showed nothing; it was run again.

**Afterwards** the PoC config was put back byte for byte, and the lock released. Every session ended with
the field game's settings.

Evidence: `out/worktrees/r14-int/out/r14/guide-lang/lang-zh-CN/` and `lang-ru/`; the script is
`out/r14/guide_lang_session.py`.

### The guide's size

**Found in the field check.** The field game draws its interface text about 2.2 times larger than a
plain game:
- Its console says "GUI SCALER INITIALIZED", from one of the user's Workshop add-ons.
- A Start here line is about 1,100 pixels wide there, against about 490 in the PoC.

The guide created its fonts at fixed pixel sizes. On the user's 3840x2160 screen it was therefore less
than half as large as the panels around it.

**The first fix** (published as `0d3b2c60`):
- At every opening the guide compared `DermaDefault`'s height with a Tahoma 13 font of its own, and
  scaled its fonts, margins and window by the ratio.
- Its pictures grew by whole steps (2 from 1.75), point-sampled, so they stay sharp.
- `nativeloader_guide_scale` overrides the measurement: 0 measures, 1 to 4 sets it.
- The previous and next buttons now use the guide's font.

In a 3840x2160 PoC game with the setting at 2.2, the field's scale, the window was 2728x2068 with
pictures at 2 and readable text (`out/worktrees/r14-int/out/r14/guide-scale/scale/`). But the field
measured 1.

**Why the field measured 1.** The scaler is Workshop item 3495129511, whose file is named
`gmpublisher.gma`:
- Its factor is the screen's height over 1080, times `guiscaler_scale_multiplier`.
- With `guiscaler_only_spawnmenu 1`, its default, it gives only the spawn menu its own enlarged fonts.
- `DermaDefault` stays as it is, and no other window grows.

**The fix.** The guide's scale is now the larger of the screen's height over 1080 and the `DermaDefault`
ratio. That is 2 on the field's 3840x2160 and 1.33 at 1440 lines, and 1920x1080 games keep the plain
sizes. The harness's `scale` mode checks the ratio, the setting, a plain game, 2160 lines and 1440 lines.

## Tests

`tools\test.ps1 -Config Release` on `r14-int` passed (`out/r14/tests/final2.log`):
- repository conventions;
- the C++ build and all 26 CTests;
- the gmapack and steam tests (28 and 25);
- the tools' 544 Python tests, among them the new `test_companion_guide`, the stability, UI and catalog
  tests in all six languages, and the package build with complete catalogs.

The first full run on the merged branch failed only on the untranslated text. It also hit a disk-space
guard: `test_poc_parity` keeps 20 GiB spare, and H: had 19.8 GiB free.

**Later runs.**
- Each later commit passed again: 545 Python tests with the scale test.
- The last run was on the merged `main` `5be211a`, which also holds R13-F's runtime patch 0030
  (`out/r14/tests/main-5be211a.log` in the main checkout).

## Publication and the field check

**Three publications.** Workshop item 3829070317 was published three times. Each time the push's second
hook run found the inputs unchanged.

| Merge on `main` | Version | What it carried |
|---|---|---|
| `c66ab5c` | 0.0.0-dev.20261103223347+be2ba4fd | R14 |
| `5f4956d` | 0.0.0-dev.20261103231759+0d3b2c60 | The first size fix |
| `5be211a` | 0.0.0-dev.20261103233057+1d6fd9f5 | The size fix by the screen's height, with R13-F's patch 0030 |

**Before the first field start.**
- `tools\steam\verify_install.py` found the field install intact. Only the user's `autoexec.cfg`
  differs.
- `garrysmod\cl.db`, which holds the spawn menu's group cookies, was saved to `out\r14\field\backup` in
  the main checkout.

The sessions ran through `poc_session.py --root <field> --allow-steam-managed`, with Workshop and local
add-ons, no `-windowed` and no `+map` before the subscriptions. Evidence: `out\r14\field\` in the main
checkout.

| Start | Package | Result |
|---|---|---|
| 01-download | (be2ba4fd downloaded) | The game ended with code 1, 45 s after the map, no crash dump: R13-F's PoC lab ends any running game before its runs, and its next run started 3 s later |
| 02-r14 | be2ba4fd deployed | The same: ended by R13-F's next run, before the probe |
| 03-r14-guide | be2ba4fd | Passed: Start here unfolded, every page and picture shown; the guide at its 1080p size on the 3840x2160 screen |
| 04-download, 05-r14-scale | 0d3b2c60 | Normal quits; the measurement gave 1 (above) |
| 06-download, 07-r14-screen | 1d6fd9f5 | Normal quits; scale 2, a 2480x1880 window, pictures at 2, on every page opened |

**R13-F's lab.** R13-F apologized: its lab came from R13-P and ended any running game before a PoC
launch. It now waits until no field game runs, and it messages before any PoC session. The loader
recorded starts 01 and 02 as crashes in `native-loader\logs\sessions` (exit code 1, `abnormal`). They
were not crashes.

**The unfolded group.** The probe toggled only the Start here group (the cookie the first pass had
folded), and it stayed open in the later starts. Sky and weather is folded in the field, and was left
as the user has it.

Every session quit with the field's own settings. The field game's language is English.

## Open items

- **Not pictured.**
  - The simple Alt+X menu's Graphics tab, where Graphics Preset is. Remix's menu ignores posted mouse
    input while the real cursor is elsewhere, and the user's mouse was not moved. The page names the tab
    in words.
  - The small panels: Player models, Toolgun screen, ToPBR, Auto-Categorization, Map, the light wrappers
    and Entity Light HUD. The pages describe them in words.
- **The glass picture's speed.** It shows a Player break speed of 80. PoC sessions run with the field
  game's own `config.cfg`, so that is the user's setting. The panel beside it says "Default: 250", and the
  legend now states the default.
- **The same setting under two names** in the game itself:
  - Imported game PBR: Model outlines' checkbox and the Imported game PBR panel translate it differently
    in some languages. The panel's text is in `packages/fixes`, GPL.
  - Base Options' Pseudoplayer Enabled and Player models' Local player shadow are the same setting.
- **`packages/fixes` text left alone (GPL):** the Fix Skybox Leaking help misspells `light_environment`
  as "light_enviornment".
- **Disk.** H: was down to 19.8 GiB free during this round. `tools\test.ps1` needs 20 GiB spare (the
  poc_parity test). Claude deleted 5 GiB of its own superseded packages, and R13-F 9 GB of its own.
