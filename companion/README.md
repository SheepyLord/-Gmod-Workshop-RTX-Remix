# companion

The Lua companion: a normal GMod add-on that shows what the native loader did. It is not loaded from
here; [`tools/package_fixes.py`](../tools/package_fixes.py.md) copies `nativeloader/` into the RTX
fixes package as the add-on folder `garrysmod/addons/nativeloader` (kind `lua-addon`), leaving out
the `.md` files.

| File | What |
|---|---|
| [`nativeloader/lua/autorun/client/nativeloader.lua`](nativeloader/lua/autorun/client/nativeloader.lua.md) | Prints the loader's start-up status (`status.json`) and RTX session results (`session.json`) to the console at client start and on `nativeloader_status` |
| [`nativeloader/lua/autorun/nativeloader_defaults.lua`](nativeloader/lua/autorun/nativeloader_defaults.lua.md) | First-run defaults: the classic RTX install's values for the RTX add-ons' settings, once, only where a setting is still at its default ([ADR 0020](../docs/decisions/0020-classic-rtx-settings-as-defaults.md)) |
| [`nativeloader/lua/nativeloader/classic_defaults.lua`](nativeloader/lua/nativeloader/classic_defaults.lua.md) | The generated table of those values ([`tools/classic_defaults.py`](../tools/classic_defaults.py.md)) |
| [`nativeloader/lua/autorun/_nativeloader_guard.lua`](nativeloader/lua/autorun/_nativeloader_guard.lua.md) | The RTX-session guard: session settings stay as set, no stock post-processing over the path-traced image ([ADR 0022](../docs/decisions/0022-companion-rtx-session-guard.md)) |
| [`nativeloader/lua/autorun/client/nativeloader_menu.lua`](nativeloader/lua/autorun/client/nativeloader_menu.lua.md) | The "RTX Remix" spawn-menu tab: the RTX add-ons' panels gathered, "Start here", "Remix settings" |
| [`nativeloader/lua/autorun/client/nativeloader_guide.lua`](nativeloader/lua/autorun/client/nativeloader_guide.lua.md) | The in-game guide (`nativeloader_guide`), with images in `nativeloader/materials/nativeloader/guide/` |

M5: the status print. M6: the restart notice for Workshop package updates that Steam downloaded
(`steamworks.FileInfo`, checked at client start and every 600 seconds).
