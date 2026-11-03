# companion_stability_harness.lua

Arguments: paths to the actual companion menu, guide, i18n module and generated catalog, followed by
scenario and language, optionally a generated status JSON path and the Python decoder script.
Invoked by [`test_companion_stability.py`](test_companion_stability.py.md).
Mocks DATA status reads, ConVars, spawn-menu registration and VGUI controls; real gettext lookup,
formatting, panel construction and guide commands execute. Any configuration, file or Remix option
write fails. Checks valid/invalid I2 reports, real T1 empty-adapter/non-NVIDIA/no-layer cases,
panel reopening and direct/default guide navigation. Guide text must wrap/stretch and show only
the advice supported by the loader. Old/missing/bad reports must show update/manual-copy advice,
with no new config keys, loader CSV or automatic-session promise. R6 instructions must include
the marker path and a complete config example (printed for Python JSON/allowlist validation).
Russian tier adjectives must agree with Уровень, and guide navigation must match the tab label.

R14-H: the guide is a window with a contents list (no property sheet); the harness reads the open
page from `NATIVELOADER_GUIDE.shown` (its `id`, translated `title` and drawn `texts`). The stability
link must open `memory`, titled Performance and memory; its Start here button is **Performance and
memory guide**. The guide includes `nativeloader/guide_pages.lua`, read from beside `i18n.lua`.

The integration scenarios read a complete schema-1 JSON report from `out/tmp`. Their JSONToTable
replacement invokes `python <decoder> --decode-status <path>` to actually parse the report into
Lua data, including nested objects, arrays, booleans, null and escaped Windows paths. It checks
that both menu and guide parse it. Other scenarios keep their status data in memory. Reads only
test/source/catalog inputs, no game, GPU or network. Prints `PASS <scenario> <language>` and exits
0, or fails with an assertion and nonzero exit code. Python may create its usual bytecode cache.
