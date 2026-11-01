# glass_i18n.py

Builds the new MIT glass menu/tool catalogs using the companion's gettext parser, extractor,
completeness/format validation and Lua escaping. It never imports the GPL add-on catalogs.

```powershell
python tools/glass_i18n.py update
python tools/glass_i18n.py check
python tools/glass_i18n.py build [--out out/g1-a/i18n_data.lua]
```

Inputs: `L("text")`/`N("text")` in `glass/addon/lua`, plus `glass/i18n/<language>.po` for the six
non-English languages. `update` regenerates `glass.pot` and merges `.po` entries, preserving current
translations and dropping unused phrases. `check` rejects missing/blank/fuzzy/identical-English
translations and incorrect printf conversions. `build` validates and writes the deterministic Lua
table, normally `glass/addon/lua/nlglass/i18n_data.lua`. Commit the catalogs and generated Lua.

Side effects are limited to these catalog/output files. No network, game, installed files or
native module is used. Exit 0 succeeds; 1 reports catalog or filesystem errors. All translations
are original agent-written data and await human review, as recorded in `glass/i18n/README.md`.
