# !nativeloader_blood.lua

The server explicitly sends the screen marker and independent-panel adapter. A listen/multiplayer
client may see only server-delivered Lua during startup; a marker present only on disk was enough
in single player but left the old Utilities shortcut in multiplayer.

Early shared R20-C bootstrap. Detects the two optional parts by their private Lua markers. The server
sends the blood modules; the client includes their private namespace exactly once. With the blood
part present it suppresses exactly four `bloodoverhaul/` includes from the legacy standalone
autorun. With the screen part present its thirteen initialization modules run once even if two
standalone/package autoruns reach them. Language includes remain repeatable for language changes.
Other includes, hooks and add-ons are unaffected. Restart to refresh an initialization module.

If a remote server sent the old standalone before verified local loading, retire its known
`bloodoverhaul` callbacks/menu/apply hooks. Unwrap a mixer/emitter only when its function's exact
source is the old `bloodoverhaul/cl_core.lua`; preserve other add-ons' intervening wrappers.

No files, network messages or server gameplay changes. Missing parts are a no-op. No exit code.
See ADR 0118 and the R20-C Lua harness for both precedence orders and repeated initialization.
