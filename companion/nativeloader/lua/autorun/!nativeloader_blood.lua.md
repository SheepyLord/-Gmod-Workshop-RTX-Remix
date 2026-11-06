# !nativeloader_blood.lua

Early shared R20-C bootstrap. Detects the two optional parts by their private Lua markers. The server
sends the blood modules; the client includes their private namespace exactly once. With the blood
part present it suppresses exactly four `bloodoverhaul/` includes from the legacy standalone
autorun. With the screen part present its thirteen initialization modules run once even if two
standalone/package autoruns reach them. Language includes remain repeatable for language changes.
Other includes, hooks and add-ons are unaffected. Restart to refresh an initialization module.

No files, network messages or server gameplay changes. Missing parts are a no-op. No exit code.
See ADR 0118 and the R20-C Lua harness for both precedence orders and repeated initialization.
