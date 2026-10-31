# rtxdebug_client.py

Windows WM_COPYDATA transport for a loaded RTXDebug companion. Use
`python tools/rtxdebug_client.py Status --pid <client-pid>` or select `--root <game-root>`.
Multiple matches are refused. Windows handle APIs use pointer-sized signatures. Each request and
response is bound to the selected process and request ID. The updated native module and companion
are required for PID binding. Request/reply files are removed after completion or timeout.
No console logs are read. Exceptions report unavailable/ambiguous targets, mismatched replies,
timeouts or an unavailable module. The command exits zero for a successful API result, one for
an API failure; transport exceptions produce a nonzero exit. It never enables client Lua.
