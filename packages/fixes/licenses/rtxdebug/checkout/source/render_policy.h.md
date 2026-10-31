# render_policy.h

Pure client-rendering configuration boundary. Local renderer changes require the module's client
realm, the game thread, an open module and Remix API availability. Only syntactically valid rtx.*
keys are accepted without the existing full single-player developer mutation gate. No cvar,
server, Lua execution, memory or detour authority is granted. Tested by render_policy_test.cpp.
