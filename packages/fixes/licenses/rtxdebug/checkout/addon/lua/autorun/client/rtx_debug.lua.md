# rtx_debug.lua

Client JSON RPC adapter for the native RTXDebug API. It restricts method names and request IDs,
enforces request/result size limits, returns structured errors and restores owned overrides on
shutdown. Optional process_id binding rejects a request for another client; replies always carry
the actual native process ID. The transport does not enable client Lua or alter server policy.
Only native API gates authorize mutations. It reads/writes data/rtx_debug requests/results and
prints completion markers. No HTTP or sockets are used. Errors do not expose arbitrary globals.
