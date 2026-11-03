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
`guide_lang`):

| Set | Labels | What is opened |
|---|---|---|
| `tab` | `spawnmenu_tab`, `remix_settings`, `sky_weather`, `base_options`, `performance`, `model_outlines`, `player_models`, `toolgun`, `topbr`, `autocat`, `flashlight`, `map_lights`, `glass_settings`, `rtx_water` | The spawn menu on the RTX Remix tab with every group of its sidebar open, and each panel in turn through `spawnmenu.ActivateTool(<item>)`, as a click on the item does (the first pass clicked labels: a group's header has the same text as its item, so a click folded the group and left the old panel showing) |
| `remix` | `remix_simple`, `remix_developer` | Remix's menu through `RemixConfig.SetConfigVariable("rtx.showUI", "1")` (the simple Graphics Settings menu) and `"2"` (the developer menu); `"0"` closes it. The option is not saved |
| `character` | `hotloader_tab`, `hotloader_window`, `character_spawned`, `imported_pbr`, `imported_pbr_window`, `model_outlines_character`, `eye_whites` | External Models (the tab and `mmdhl.Open()`'s window), then one imported character spawned as a frozen citizen in front of the player (a Wuthering Waves one, `鳴潮`, when the library has one, for its game maps), the player looking at it; Rendering > Imported game PBR, `rtx_topbr_game_editor`, Model outlines and the eye-white chooser (`nativeloader_eye_white_materials`) |
| `guide` | `guide_<page>`, `guide_<page>.<section>` | `nativeloader_guide <page> [section]` for every page and every section of the guide |
| `guide_lang` | `guide_<language>_<page>...` | The same in `NL_GUIDE_LANGUAGE` (default `fr`), set through `nativeloader_language` |

`NL_GUIDE_TOOL_WIDTH` (default 640) is the width the spawn menu's tool half is given, so panels are
captured with room for their help lines. Diagnostics are printed as `NL_GUIDE <text>` (the steps, a
panel that did not open, the spawn's progress).

## Side effects

Opens and closes windows and the spawn menu, spawns one character, and sets `rtx.showUI` (not saved).
At the end it puts back the spawn menu's divider, the open state of the RTX Remix groups (both are
Derma cookies) and `nativeloader_language`, then prints `NL_SHOT_DONE`. It writes no file itself; the
game keeps its cookies and the hotloader its use history as usual.
