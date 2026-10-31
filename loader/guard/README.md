# loader/guard

`early.h` / `early.cpp` prepare an exact read redirect for the supported stock client Lua
initializer. The original Steam file is never changed. Only the enabled, allowlisted RTX owner's
SHA-verified companion guard is appended, before third-party autorun code can cache native APIs.
The client-only call is protected against recoverable Lua initialization errors. Server/menu realms,
RTX-off sessions, unknown stock hashes and incompatible guard versions do not receive that code.
After catalog verification identifies a V2 guard, a stock/cache preparation failure disables RTX
activation and uses the existing vanilla fallback. Foreign selected runtimes and legacy V1 guards
retain their previous behavior; an unverified file cannot request this policy.

`CMakeLists.txt` builds `nl_render_guard` separately from the proxy. `tests/` contains generated-file
policy tests described in its README. Cache files live under the game's protected native-loader
folder, refuse links and are content-addressed; a changed existing cache file is preserved/refused.
