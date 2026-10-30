# companion_ui_i18n_harness.lua

Runs the companion's real localization module and chat receiver against a built catalog under
LuaJIT. Arguments: generated data Lua, `nativeloader/i18n.lua`, and `autorun/nativeloader_i18n.lua`.
Game APIs are mocked. Checks all six language lookups, add-on aliases, metadata phrase registration,
switching the override and game language, readable control labels, and recipient-specific notices.

Called by [test_companion_ui_i18n.py](test_companion_ui_i18n.py.md). Inputs are those three files;
output is a success line or assertion failure. Writes no files and starts no game. Exit 0 on success.
