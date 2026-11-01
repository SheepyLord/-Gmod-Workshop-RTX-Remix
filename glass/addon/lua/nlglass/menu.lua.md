# menu.lua

Translated glass settings page and glass_open_panel command.

Client-only bootstrap include after I18n. Retains Utilities > Glass Rewrite Remixed / GlassSettings, so the companion relocates it to RTX Remix > Water and glass, and registers a standalone scrollable window. Reads replicated convars, debounces admin setting requests and binds G1-B client debris settings. Reset applies player defaults and asks the server to reset gameplay defaults for admins. No native/private debris access or direct disk writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.
