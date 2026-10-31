# rtx_debug.lua

Client companion for RTXDebug 0.2.0. Requires the matching native module and exposes the local
rtx_debug_request console command. Requests and results are JSON under DATA/rtx_debug; each
request ID and optional process_id is validated, and every reply includes the actual process ID.
The external source/tools client selects an explicit PID/root and removes its own transport files.

Read-only diagnostics and local rtx.* rendering changes work in multiplayer. Native Lua evaluation,
gameplay/engine writes, memory writes and detours retain their single-player + cheats + insecure
gate. This companion does not change sv_allowcslua or fetch/upload data. Protocol errors are
returned locally; oversized or unserializable results fail cleanly.
