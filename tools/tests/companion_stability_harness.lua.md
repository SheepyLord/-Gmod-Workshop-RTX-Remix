# companion_stability_harness.lua

Arguments: paths to the actual companion menu, guide, i18n module and generated catalog, followed by
scenario and language. Invoked by [`test_companion_stability.py`](test_companion_stability.py.md).
Mocks DATA status reads, ConVars, spawn-menu registration and VGUI controls; real gettext lookup,
formatting, panel construction and guide commands execute. Any configuration, file or Remix option
write fails. Checks valid/invalid I2 reports, panel reopening and direct/default guide navigation.
Guide text must wrap and stretch, and the selected page must contain memory/crash guidance.

Reads its Lua/catalog inputs only. All status/settings/control data stays in memory. No game, GPU,
network or writes. Prints `PASS <scenario> <language>` and exits 0, or fails with an assertion and
nonzero exit code.
