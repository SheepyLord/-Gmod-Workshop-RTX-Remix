# guide_shots.lua

Client Lua for the RTX Remix guide's pictures and its in-game check. It runs in a PoC session through
[`tools/poc_session.py`](../poc_session.py.md) `run --addons --lua <set file> --lua tools\qa\guide_shots.lua
--lua-shots <seconds>`, with the companion deployed (the package built from the branch, allowed with
`poc_session.py config --allow-local <gma>`). It opens one view at a time and prints `NL_SHOT <label>`
when the view is ready; the driver saves `shot-<nn>-<label>.png` and answers `nl_shot_taken <nn>`, and
the next view opens. [`tools/guide_annotate.py`](../guide_annotate.py.md) then crops the captures and
draws the badges.

```powershell
# out\r14-guide\set-tab.lua holds one line: NL_GUIDE_SET = "tab"
python tools\poc_session.py --evidence out\r14-guide\shots run --name tab --addons --width 1920 --height 1080 `
    --settle 15 --screenshots 0 --lua out\r14-guide\set-tab.lua --lua tools\qa\guide_shots.lua --lua-shots 300
```

## The views

Set the global `NL_GUIDE_SET` in a Lua file run before this one (default `all`: every set but
`guide_lang`; `pictures`: `tab`, `remix` and `character`, what the guide's pictures are made from;
`panels`: `tab` and `character`; `check`: `guide` and `guide_lang`, the in-game check of the guide):

| Set | Labels | What is opened |
|---|---|---|
| `tab` | `spawnmenu_tab`, `remix_settings`, `sky_weather`, `base_options`, `performance`, `model_outlines`, `player_models`, `toolgun`, `topbr`, `autocat`, `flashlight`, `map_lights`, `glass_settings`, `rtx_water` | The spawn menu on the RTX Remix tab with every group of its sidebar open, and each panel in turn through `spawnmenu.ActivateTool(<item>)`, as a click on the item does (the first pass clicked labels: a group's header has the same text as its item, so a click folded the group and left the old panel showing) |
| `remix` | `remix_simple`, `remix_simple_graphics`, `remix_simple_general`, `remix_developer`, `remix_developer_about`, `remix_developer_bottom`, `remix_developer_top` | Remix's menu through `RemixConfig.SetConfigVariable("rtx.showUI", "1")` (the simple User Graphics Settings menu) and `"2"` (the developer menu); `"0"` closes it. The option is not saved. Its tabs (the simple menu's Graphics and General, the developer menu's About and Rendering) and the developer menu's scroll to its Settings Management section are clicked and scrolled by [`guide_input.py`](guide_input.py.md), which must run beside the session: the script prints `NL_INPUT <n> click <x> <y>` or `NL_INPUT <n> wheel <x> <y> <notches>` (points of the menu at 1920x1080). `showconsole` cannot be used: GMod blocks it from Lua |
| `character` | `character_spawned`, `hotloader_window`, `hotloader_tab`, `imported_pbr`, `imported_pbr_window`, `model_outlines_character`, `eye_whites` | Two imported characters spawned as frozen citizens in front of the player: a Wuthering Waves one (`鳴潮`, for its game maps) and Karin (whose `目白` the eye-white rules detect), when the library has them. Then External Models: `mmdhl.Open()`'s window made 800 x 1000 (the library lays itself out again) and the spawn menu's tab, each with the first character selected; Rendering > Imported game PBR and `rtx_topbr_game_editor`, each with the first material whose state is automatic or cached selected; Model outlines; and the eye-white chooser (`nativeloader_eye_white_materials`) for the second character, scrolled to its first material detected as an eye white |
| `guide` | `guide_<page>`, `guide_<page>.<section>` | `nativeloader_guide <page> [section]` for every page and every section of the guide |
| `guide_lang` | `language_<language>`, `guide_<language>_<page>...` | The same in `NL_GUIDE_LANGUAGE` (default `fr`), after a step that sets `nativeloader_language` (the spawn menu is rebuilt in that language) |

`NL_GUIDE_PAGE` (a page id) limits the guide sets to that page and its sections.
`NL_GUIDE_TOOL_WIDTH` (default 640) is the width the spawn menu's tool half is given, so panels are
captured with room for their help lines. Diagnostics are printed as `NL_GUIDE <text>` (the steps, a
panel that did not open, the spawn's progress).

Just before each `NL_SHOT`, it prints where every control of the view is on screen, one line each:
`NL_RECT <label> <class> <x> <y> <w> <h> <text>` (tab-separated; screen pixels, which are capture
pixels): the RTX Remix tab's panel, sidebar, Quick Filter and the spawn menu's tabs, the External
Models library, and every open window. The picture specs in `tools/guide_pictures.json` point at these
measured rectangles. Remix's own menu is not Derma, so its coordinates are read from the capture.

## Side effects

Opens and closes windows and the spawn menu, spawns one character, and sets `rtx.showUI` (not saved).
At the end it puts back the spawn menu's divider, the open state of the RTX Remix groups (both are
Derma cookies) and `nativeloader_language`, then prints `NL_SHOT_DONE`. It writes no file itself; the
game keeps its cookies and the hotloader its use history as usual.
