# read_notices.lua

Local main-menu notice reader, embedded into the generated `control.Menu.js` view. The stock menu's
`lua.Run` bridge formats its two `%s` placeholders with a quoted process token and numeric PID.
Reads only `native-loader/status.json` (at most 1 MiB) and `native-loader/memory.json` (at most 4 KiB)
from `DATA`. Rejects other-process records, invalid JSON and non-table values. Returns only the
previous-session summary, latest commit observation and the menu Lua realm's once-per-start warning
state through `pnlMainMenu:Call`. Parsed values are JSON-encoded again before entering JavaScript.

No direct CLI usage, arguments, exit codes, writes, imports or networks. Missing data means absent
fields; a missing menu panel does nothing. The JavaScript consumer checks freshness and before-map
visibility and records warning consumption in menu Lua only after displaying it. The script never
changes Steam/depot files or game settings. Tested by `tools/tests/menu_notices_harness.lua`.
