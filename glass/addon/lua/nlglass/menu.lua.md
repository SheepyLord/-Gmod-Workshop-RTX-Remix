# menu.lua

R7-C adds a local interaction checkbox and explanatory help in all seven languages. Reset to
Defaults restores `rtx_glass_debris_interact=1`, independently of administrator permissions.

Player break speed reads/resets to the shared 250-unit/s default. A translated help line explains
that walking stays below that default threshold; its six catalogs and generated Lua are updated.

The debris budget slider caps at 8,192, matching the debris manager's convar/native limit.

Translated glass settings page and glass_open_panel command.

Client-only bootstrap include after I18n. Retains Utilities > Glass Rewrite Remixed / GlassSettings, so the companion relocates it to RTX Remix > Water and glass, and registers a standalone scrollable window. Reads replicated convars, debounces admin setting requests and binds G1-B client debris settings. Reset applies player defaults and asks the server to reset gameplay defaults for admins. No native/private debris access or direct disk writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
