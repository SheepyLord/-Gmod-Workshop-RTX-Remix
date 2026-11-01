# Glass translations (MIT)

These original catalogs belong to the new MIT glass add-on. They contain no imported GPL catalog
data. English is in `glass.pot`, extracted from `L("text")` and `N("text")` in the add-on. The six
`.po` files cover zh-CN, zh-TW, ja, ko, fr and ru. They are agent-written and await human review.

Edit `msgstr` in UTF-8; retain printf conversions, paths and setting names. The runtime follows
`nativeloader_language` when set, otherwise `gmod_language`, with `zh`/`zh-tw` aliases. English is
the fallback. The namespace is separate from the companion's GPL bundled interface data.

```powershell
python tools/glass_i18n.py update # preserve translations, extract new phrases
python tools/glass_i18n.py check  # reject missing/blank/fuzzy/unreviewed-English translations
python tools/glass_i18n.py build  # regenerate addon/lua/nlglass/i18n_data.lua
```

The builder reuses the companion's gettext reader, completeness checks and Lua escaping. Commit
the generated Lua with the catalogs. The package assembler can build again before importing G1.
No game process or network access is used. The repository's [MIT license](../../LICENSE) applies.
