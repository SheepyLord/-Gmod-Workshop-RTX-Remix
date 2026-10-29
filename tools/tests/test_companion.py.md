# test_companion.py

Runs the Lua companion, [`companion/nativeloader/lua/autorun/client/nativeloader.lua`](../../companion/nativeloader/lua/autorun/client/nativeloader.lua.md),
under LuaJIT with the GMod functions it calls mocked (`MsgN`, `file.Exists/Read`,
`util.JSONToTable`, `steamworks.FileInfo`, `notification.AddLegacy`, `timer`, `concommand`), from a
harness written to a scratch folder under `out\tmp`.

- A Workshop package whose item Steam reports as updated after the deployed `time_updated` prints
  the "newer Workshop version" line and raises exactly one notification (M6's restart notice); the
  session-variable line from `status.json` is printed.
- The deployed version, and a local package, print and raise nothing about updates.
- The status says "Remix API: ready (RemixLight, RemixConfig)" when the RTX fixes' tables exist,
  and "not available" when they do not (`hook`, `istable`, `isfunction` mocked too).
- Every Lua file of the companion compiles under LuaJIT (`loadfile`, nothing runs): the guard, the
  defaults, the menu, the guide and the generated table.

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Skipped when LuaJIT is not installed (on `PATH` or in
`%LOCALAPPDATA%\Programs\LuaJIT\bin`). Exit 0 when the tests pass or are skipped.
