# nlglass.lua

G1 bootstrap and six spawn-menu size/kind presets.

Loaded by GMod autorun in each realm. Includes shared, server or client modules in order, serves client files and registers inherited pane presets. Serves G1-B debris*.lua and world*.lua files when present, including supporting modules for remote clients; the client includes debris.lua, which owns its own includes. Both tasks must be assembled before shipping. No direct file writes.

This is a runtime Lua module, not a process: it has no exit code. Engine/load errors propagate to the caller. See the glass README for the full setting and frame contract.

R7-C also includes shared `debris_bullets.lua` before server/client setup. Its post-bullet observer
is server-only; clients only receive clipped rays. The existing debris-file rule serves all new
scene/expiry/bullet helpers to remote clients.

R8-G also includes debris_melee.lua after the shared hit router; its observers run only on the server.
