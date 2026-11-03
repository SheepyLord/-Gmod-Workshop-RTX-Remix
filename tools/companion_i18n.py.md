# companion_i18n.py

Translations of the Lua companion: the RTX Remix spawn-menu tab, the guide and the package update
notice ([ADR 0029](../docs/decisions/0029-companion-translations.md)). The translations are gettext
files in [`companion/i18n`](../companion/i18n/README.md), for people to review and edit; this tool
makes, checks and builds them.

```powershell
python tools\companion_i18n.py update                      # after the companion's text changed
python tools\companion_i18n.py check                       # after editing a .po file
python tools\companion_i18n.py build --out <i18n_data.lua> # what package_fixes.py does
```

| Command | What |
|---|---|
| `update` | Extracts the text the companion's Lua (`companion/nativeloader/lua/**/*.lua`) marks with `L("...")`, `L"..."`, `N("...")` or `N"..."` into `companion/i18n/nativeloader.pot`, each text once with every `file:line` it is at. Comment lines are skipped. Then merges it into every `<language>.po`: translations of text still used are kept, new text is added with an empty `msgstr`, text no longer used is dropped. Prints how many entries each language has translated |
| `check` | Reads every `.po`: PO syntax (`msgid`/`msgstr`, `"..."` continuation lines, the escapes `\n \t \r \\ \"`; no `msgctxt` or plural forms), every `msgid` must be text the companion has, and a translation of text with printf conversions (`%s`, `%d`, ...) must have the same ones in the same order. The command rejects missing, empty, whitespace-only, fuzzy, duplicate and unreviewed English entries; `--allow-incomplete` permits draft fallback |
| `build --out FILE` | Checks, then writes the Lua table the add-on reads (`lua/nativeloader/i18n_data.lua`): `return { ["zh-CN"] = { [english] = translation, ... }, ... }`, keys sorted; also embeds the separate `addons` namespace |

Languages: `zh-CN`, `zh-TW`, `ja`, `ko`, `fr`, `ru` (GMod's `gmod_language` codes). The Lua strings are
read with Lua's escapes (`\\`, `\"`, `\n`, `\ddd`), so a `msgid` is the text exactly as the add-on
looks it up.

[`package_fixes.py`](package_fixes.py.md) runs `build` for every RTX package it makes, into a scratch
file under `out\tmp` whose time is the newest `.po` file's (the same translations give the same
package version), and packs it as the companion's `lua/nativeloader/i18n_data.lua`. A translation that
does not check stops the package build.

Inputs: the companion's Lua and `companion/i18n/*.po`. Outputs: `update` writes `nativeloader.pot` and
the six `.po` files (LF line ends, UTF-8); `build` writes `--out`. Exit codes: 0 on success, 1 when a
`.po` file does not check or a file cannot be read or written (the message names file and line), 2 for
bad arguments.

Tests: [tests/test_companion_i18n.py](tests/test_companion_i18n.py.md).

The `update` and `check` commands also process [`companion/i18n/addons`](../companion/i18n/addons/README.md).
Those sources use `NL`, `NN` and `NP` markers under `packages/`. `build` includes both catalogs in one
Lua file. Add-on names intentionally unchanged are listed in that folder's `unchanged.json`.
`check(..., complete=False)` remains available to draft-editor callers; shipping `build` defaults
to complete catalogs. A translation may equal the English only for the texts in the script's
`UNCHANGED` table: product names, the guide's abbreviations (DLSS, PBR, VRAM, Remix API) and a few
words that are also correct French (since R14). Stray percent signs in formatted messages are rejected; literal `%%` is valid.

The generated add-on namespace identifies its GPL-2.0 source data and points to the editable catalog copies and license shipped with the package.
