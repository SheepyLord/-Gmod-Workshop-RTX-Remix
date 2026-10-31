# render_policy.h

Pure client-rendering configuration boundary. Local renderer changes require the module's client
realm, the game thread, an open module and Remix API availability. Only syntactically valid rtx.*
keys are accepted without the existing full single-player developer mutation gate. No cvar,
server, Lua execution, memory or detour authority is granted. `IsRenderingConVar` is the short
allowlist of convar name prefixes (`rtx`, `r_`, `mat_`, `cl_draw`) that `Engine.GetConVar` may read
outside local single-player; every other convar name is refused there. Tested by
render_policy_test.cpp.
