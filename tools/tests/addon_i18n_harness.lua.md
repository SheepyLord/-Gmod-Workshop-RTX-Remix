# addon_i18n_harness.lua

Loads the bundled Bodygroup Tool, Material Editor, Destruction and Motion Importer catalog code
under LuaJIT with inert GMod stubs. Emits one JSON array per phrase: part, language, key, value.
Includes the Material Editor's English parameter help. Checks Traditional Chinese selection,
Korean selection in Destruction, unambiguous material-label lookup and context-bound label changes.

Run from the repository root with `luajit tools/tests/addon_i18n_harness.lua`; normally called by
[check_addon_i18n.py](../check_addon_i18n.py.md). Reads packaged source files, writes only stdout.
Exit 0 on success, nonzero on a Lua error or failed assertion. No game or network side effects.
