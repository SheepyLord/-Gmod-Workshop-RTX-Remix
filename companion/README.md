# companion

Editable startup text is in [presentation/](presentation/README.md), outside the Lua add-on. The
fixes packager deploys it as create-only runtime input. Main-menu diagnostics live in loader 0.8.1;
edit loader/proxy/ui/mainmenu.js and its labels.json for that panel's layout and labels.

The Lua companion: a normal GMod add-on that shows what the native loader did. It is not loaded from
here; [`tools/package_fixes.py`](../tools/package_fixes.py.md) copies `nativeloader/` into the RTX
fixes package as the add-on folder `garrysmod/addons/nativeloader` (kind `lua-addon`), leaving out
the `.md` files, and adds the translations built from `i18n/`.

| File | What |
|---|---|
| [`nativeloader/lua/autorun/client/nativeloader.lua`](nativeloader/lua/autorun/client/nativeloader.lua.md) | Prints the loader's start-up status (`status.json`) and RTX session results (`session.json`) to the console at client start and on `nativeloader_status` |
| [`nativeloader/lua/autorun/client/nativeloader_vram.lua`](nativeloader/lua/autorun/client/nativeloader_vram.lua.md) | Samples Remix VRAM totals/categories every 30 seconds when the fixes expose the API; keeps two bounded local CSV segments, controlled by `nativeloader_vram_telemetry` |
| [`nativeloader/lua/autorun/nativeloader_defaults.lua`](nativeloader/lua/autorun/nativeloader_defaults.lua.md) | First-run defaults: the classic RTX install's values for the RTX add-ons' settings, once, only where a setting is still at its default ([ADR 0020](../docs/decisions/0020-classic-rtx-settings-as-defaults.md)) |
| [`nativeloader/lua/nativeloader/classic_defaults.lua`](nativeloader/lua/nativeloader/classic_defaults.lua.md) | The generated table of those values ([`tools/classic_defaults.py`](../tools/classic_defaults.py.md)) |
| [`nativeloader/lua/autorun/_nativeloader_guard.lua`](nativeloader/lua/autorun/_nativeloader_guard.lua.md) | The RTX-session guard: session settings stay as set, no stock post-processing over the path-traced image ([ADR 0022](../docs/decisions/0022-companion-rtx-session-guard.md)) |
| [`nativeloader/lua/autorun/client/nativeloader_menu.lua`](nativeloader/lua/autorun/client/nativeloader_menu.lua.md) | The "RTX Remix" spawn-menu tab: the RTX add-ons' panels gathered, "Start here", "Remix settings" |
| [`nativeloader/lua/autorun/client/nativeloader_guide.lua`](nativeloader/lua/autorun/client/nativeloader_guide.lua.md) | The in-game guide (`nativeloader_guide`), with images in `nativeloader/materials/nativeloader/guide/` |
| [`nativeloader/lua/autorun/nativeloader_sky.lua`](nativeloader/lua/autorun/nativeloader_sky.lua.md) | The sky in RTX sessions: the runtime's physical sky with the sun, moon and stars for a time of day (by default the map's own sun), a clock, the moon's phases and lunar and solar eclipses, the night sky image or the procedural stars, and the runtime's twelve weather presets blended into each other; the "Sky and weather" panel ([ADR 0031](../docs/decisions/0031-physical-sky-time-and-weather.md), [ADR 0032](../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md)) |
| [`nativeloader/lua/nativeloader/sky_model.lua`](nativeloader/lua/nativeloader/sky_model.lua.md) | The sky's arithmetic: solar and lunar positions, the moon off the ecliptic and the stages of an eclipse, the stars' turn, the map's sun from its entities, the weather blend |
| [`nativeloader/lua/nativeloader/weather_presets.lua`](nativeloader/lua/nativeloader/weather_presets.lua.md) | The generated table of the runtime's weather presets ([`tools/weather_presets.py`](../tools/weather_presets.py.md)) |
| [`nativeloader/lua/nativeloader/i18n.lua`](nativeloader/lua/nativeloader/i18n.lua.md) | The translations of the tab, the guide and the update notice: `L` and `N`, the language (`gmod_language`, or `nativeloader_language`) ([ADR 0029](../docs/decisions/0029-companion-translations.md)) |
| [`nativeloader/lua/autorun/nativeloader_i18n.lua`](nativeloader/lua/autorun/nativeloader_i18n.lua.md) | Sends the translations to clients |
| [`i18n/`](i18n/README.md) | The translations as gettext files for people to review and edit: `nativeloader.pot` and one `.po` per language. Not part of the add-on: the RTX package's build writes them into it as `lua/nativeloader/i18n_data.lua` |
| [`nativeloader/lua/autorun/client/nativeloader_toolgun.lua`](nativeloader/lua/autorun/client/nativeloader_toolgun.lua.md) | Redraws the live toolgun screen after upscaling with a separate depth mask for the gun and hands |
| [`nativeloader/lua/autorun/client/nativeloader_model_layers.lua`](nativeloader/lua/autorun/client/nativeloader_model_layers.lua.md) | Suppresses the outline materials of loaded models through transient options while protecting shared ordinary textures; the runtime's front-cull shell rule is a separate opt-in |
| [`nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua`](nativeloader/lua/autorun/client/nativeloader_mmd_alpha.lua.md) | Tags loaded Model Hotloader character textures for matching MMD cutouts and blend opacity in every ray type, through a transient category joined with saved tags |
| [`nativeloader/lua/autorun/client/nativeloader_motion_tab.lua`](nativeloader/lua/autorun/client/nativeloader_motion_tab.lua.md) | The "Motion importer" spawn-menu tab: the bundled motion importer's in-game importer and Motion Manager, built into the tab by the add-on's own builders ([ADR 0060](../docs/decisions/0060-motion-tab-hosts-the-importer.md)) |

M5: the status print. M6: the restart notice for Workshop package updates that Steam downloaded
(`steamworks.FileInfo`, checked at client start and every 600 seconds).
