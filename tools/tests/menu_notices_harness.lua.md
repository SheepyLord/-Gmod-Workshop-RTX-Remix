# menu_notices_harness.lua

LuaJIT fixture execution of the real embedded menu reader:

```powershell
luajit tools/tests/menu_notices_harness.lua loader/proxy/ui/read_notices.lua
```

Tests quoted process tokens, current/other-process status and commit records, the menu realm's
once-per-start warning state, read bounds, malformed/scalar JSON and a missing menu. File/JSON/UI
APIs are fixtures; no game, disk writes, settings, clipboard or network actions. Reads only the
supplied script, outputs a pass line, and exits 0 on success or nonzero on assertion/Lua errors.
`test_presentation_ui.py` runs it when the already-installed LuaJIT is available.
