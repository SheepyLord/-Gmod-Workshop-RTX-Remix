# test_companion_ui_i18n.py

Builds the real companion and bundled-interface catalogs, then runs their
[Lua harness](companion_ui_i18n_harness.lua.md). Checks language switching, namespace separation,
metadata phrases, control labels and localized server notices without starting a game.

Run `python -m unittest discover -s tools/tests -p test_companion_ui_i18n.py` or `tools/test.ps1`.
Requires LuaJIT; skipped when it is unavailable. The generated catalog is temporary under `out/tmp`
and removed afterwards. Exit 0 on success, nonzero on a failed test.
