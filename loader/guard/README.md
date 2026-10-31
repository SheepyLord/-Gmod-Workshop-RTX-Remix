# loader/guard

`early.h` / `early.cpp` prepare an exact read redirect for the supported stock client Lua
initializer. The original Steam file is never changed. Only the enabled, allowlisted RTX owner's
SHA-verified companion guard is appended, before third-party autorun code can cache native APIs.
The client-only call is protected against recoverable Lua initialization errors. Server/menu realms,
RTX-off sessions, unknown stock hashes and incompatible guard versions do not receive that code.

A listen host serves its initializer view to remote clients too, so the generated block installs
the guard early only where its own cache file exists on the machine running it
(`file.Exists(<cache file>, "BASE_PATH")`); the guard itself also requires this machine's active RTX
start. The cache file is therefore named from its inputs (generator format, stock initializer and
guard hashes) rather than from its own bytes, which name it.

Any preparation failure (unverified catalog, changed stock initializer after a GMod update, a link)
throws, and start-up records a note and keeps RTX: the companion's guard then installs from its
ordinary autorun, later ([ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md)).
Foreign selected runtimes and disabled policy perform no reads; an unverified file cannot request
this view.

`CMakeLists.txt` builds `nl_render_guard` separately from the proxy. `tests/` contains generated-file
policy tests described in its README. Cache files live under the game's protected native-loader
folder and refuse links. A changed cache file (or a folder in its place) is moved to
`native-loader/backup/render-guard/<name>.<n>`, never deleted, and the view is written again.
