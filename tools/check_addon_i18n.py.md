# check_addon_i18n.py

Checks the bundled add-ons' existing catalogs, including their actual language selectors under
LuaJIT. It starts no game and reads no game logs.

```powershell
python tools\check_addon_i18n.py
python tools\check_addon_i18n.py --out out\translation-audit\native-audit.json
```

Requires LuaJIT on PATH or in `%LOCALAPPDATA%\Programs\LuaJIT\bin`. The
[Lua harness](tests/addon_i18n_harness.lua.md) loads only catalog code with mocked game functions.
Model Hotloader's `.properties` files are read directly. Checks required languages, every English
key, blank values, named placeholders, motion's printf conversions, duplicate property keys, and
unexpected English fallback. Existing Arabic and Spanish motion catalogs are checked too. All six parts
(bodygroup, destruction, material, material_help, motion, hotloader) must be found.

Model Hotloader looks every phrase up as `mmdhl.<key>` (`lua/mmdhl/i18n.lua`, `render()`), so two
more checks hold its catalogs to what the add-on actually asks for (review R4: two keys added without
the prefix showed as `mmdhl.ui.character.rtx_normals` on the External Models tab): every catalog key
carries the prefix, and every literal `L'key'` / `L("key")` in its Lua has `mmdhl.<key>` in the English
catalog. A literal that ends in `.` is a prefix completed at run time and is skipped.

[`addon_i18n_unchanged.json`](addon_i18n_unchanged.json) records reviewed exceptions by key **and exact
English text**: language autonyms, product/engine names, paths, units, pure interpolation templates,
and words also used in French. A changed source sentence does not inherit an old exception.

Inputs: indexed Lua and localization files under `packages/`; the exception record. Output: counts
and problems, optionally the full audited catalogs and results in `--out`. Only the requested report
is written. Exit 0 means all checks passed; 1 means an invalid catalog or a failed language-selection
assertion. Missing LuaJIT is an error for this command; its unittest is skipped on CI without LuaJIT.

Tests: [test_addon_i18n.py](tests/test_addon_i18n.py.md).
