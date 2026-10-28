# companion

The Lua companion: a normal GMod add-on that shows what the native loader did. It is not loaded from
here; [`tools/package_fixes.py`](../tools/package_fixes.py.md) copies `nativeloader/` into the RTX
fixes package as the add-on folder `garrysmod/addons/nativeloader` (kind `lua-addon`), leaving out
the `.md` files.

| File | What |
|---|---|
| [`nativeloader/lua/autorun/client/nativeloader.lua`](nativeloader/lua/autorun/client/nativeloader.lua.md) | Prints the loader's start-up status (`status.json`) and RTX session results (`session.json`) to the console at client start and on `nativeloader_status` |

M5: the status print. M6: the restart notice for Workshop package updates that Steam downloaded
(`steamworks.FileInfo`, checked at client start and every 600 seconds).
