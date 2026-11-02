# Translations of the companion

The RTX Remix tab of the spawn menu, the RTX Remix guide (`nativeloader_guide`) and the package
update notice can be shown in Simplified Chinese, Traditional Chinese, Japanese, Korean, French and
Russian ([ADR 0029](../../docs/decisions/0029-companion-translations.md)). The language follows
Garry's Mod's own (`gmod_language`, the game's language option). "Start here" in the RTX Remix tab has
a "Language" choice that sets another one (the client setting `nativeloader_language`: empty, `en`,
`zh-CN`, `zh-TW`, `ja`, `ko`, `fr`, `ru`).

Labels must be short: GMod gives a combo box label about 100 pixels and a slider label about 114
(Tahoma 13). A label that does not fit is cut off, so the tab keeps labels short and puts the rest on
a help line below the control.

Console output stays English: it goes into bug reports. The labels of the other RTX add-ons in the tab
are theirs and are not translated here; the labels of Remix's own menu (Alt+X) are translated in the
runtime ([the runtime's `i18n` folder](https://github.com/SheepyLord/dxvk-remix-gmod)).

## Files

| File | What |
|---|---|
| `nativeloader.pot` | The English text, taken from the companion's Lua. Generated: do not edit |
| `zh-CN.po`, `zh-TW.po`, `ja.po`, `ko.po`, `fr.po`, `ru.po` | One UTF-8 file per language: each English `msgid` with its `msgstr` |

[`tools/companion_i18n.py`](../../tools/companion_i18n.py.md) makes and checks them, and the RTX
package's build ([`package_fixes.py`](../../tools/package_fixes.py.md)) puts them into the add-on.

## Reviewing and editing a translation

Edit the language's `.po` file in any text editor (UTF-8) or a PO editor such as Poedit. An entry:

```po
#: nativeloader/lua/autorun/client/nativeloader_menu.lua:105
msgid "Use the classic RTX settings"
msgstr "使用经典 RTX 设置"
```

- `#:` is where the text is in the companion's Lua (`companion/nativeloader/lua/...`).
- Change `msgstr` only. `\"` is a quote and `\\` a backslash: file paths such as
  `native-loader\\config.json` keep their doubled backslashes.
- An empty `msgstr` shows the English. `#, fuzzy` above an entry also keeps the English until you
  remove the flag.
- `#, c-format` marks text with a `%s`: keep it, once.
- Keep console commands, file names, key names and product names (DLSS, XeSS, ReSTIR GI) as they are.

Then check the files:

```powershell
python tools\companion_i18n.py check
```

It names the file and line of any problem, for example
`error: companion\i18n\fr.po:12: printf conversions [] must match the English ['%s']`. The next RTX
package built from this repository (a commit on `main` publishes it, [AGENTS.md](../../AGENTS.md)
rule 5) carries the edited text; no Lua changes.

## When the companion's text changes

Text the companion shows is written in its Lua as `L("...")` (translated where it is shown) or
`N("...")` (marked only, translated later where it is drawn). After changing such text, run

```powershell
python tools\companion_i18n.py update
```

It rewrites `nativeloader.pot` and merges it into every `.po`: translations of unchanged text stay,
new text comes in untranslated, and text no longer used is dropped (the command says how many
translations that dropped).

## Release checks

`check` and package `build` now require complete catalogs: missing, blank, fuzzy, duplicate or
unreviewed English entries fail. Use `--allow-incomplete` only for local translation drafts.
The [bundled interface catalogs](addons/README.md) are a separate namespace and are embedded in the
same generated Lua file. Long RTX slider and combo labels receive a full-width line above the control.

## R6 T3 translation review

The R6 messages for the performance-tier line/source placeholders, the **Memory and stability**
guide page and its Start here button, including the independent-review fixes, are **agent-written
by Codex and not yet human-reviewed** in all six non-English catalogs (`zh-CN`, `zh-TW`, `ja`, `ko`,
`fr`, `ru`). The English source and POT supply the seventh language. Review the technical advice
and UI terminology as well as wording; preserve paths, configuration values, console commands and
printf conversions. `companion_i18n.py update` drops agent-written `#.` comments when regenerating
catalogs. This durable note records provenance until a human review is recorded. The fix pass also
corrected Russian Start here references to **С чего начать** and tier adjectives to masculine
**Высокий / Средний / Низкий**, agreeing with **Уровень**.

R11's Imported game PBR checkbox/help translations are agent-written and not yet human-reviewed
in all six non-English catalogs. English supplies the seventh language.
