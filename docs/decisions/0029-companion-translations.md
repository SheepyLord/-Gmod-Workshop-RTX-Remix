# 0029: The companion's text is translated from gettext files built in when the package is made

- Status: Accepted 2026-10-29
- Decided by: the user ("Also translate the lua addon in the spawn menu. For the translation, the text
  should be organized into an i18n folder for human validation. I can edit the i18n and the new
  translation will be embedded when packed or built."; languages: Simplified and Traditional Chinese,
  Japanese, Korean, French and Russian), Claude choosing how
- Builds on: [0022](0022-companion-rtx-session-guard.md) (the companion's RTX Remix tab and guide)

## Context

- **What players read.** The companion's RTX Remix tab of the spawn menu (about 60 labels, choices
  and help lines), its guide (five pages, 32 headings and paragraphs) and the package update notice:
  93 texts. The other RTX add-ons' panels in the tab are theirs and are not translated here; Remix's
  own menu (Alt+X) is translated in the runtime, by a separate session, with gettext `.po` files in the
  runtime fork's `i18n` folder.
- **GMod's own mechanism.** GMod's localization is `resource/localization/<language>/*.properties`,
  `key=value` lines read through `language.GetPhrase`. Its keys cannot hold the English text (`=`, `:`
  and spaces), and a reviewer would see keys instead of the sentence to translate.
- **Languages.** GMod's `gmod_language` uses `zh-CN`, `zh-TW`, `ja`, `ko`, `fr`, `ru`. Windows draws CJK
  glyphs in GMod's Derma fonts through font fallback, as GMod's own translations show.

## Decision

1. **The files to review.** [`companion/i18n`](../../companion/i18n/README.md) holds
   `nativeloader.pot` (the English, generated) and one `<language>.po` per language, the format of the
   runtime's translations: each English `msgid` with its `msgstr`, `#:` naming the Lua line. People
   edit `msgstr` in any text or PO editor; an empty or fuzzy entry shows the English.
2. **The text in the Lua.** The companion writes shown text as `L("...")` (translate now) or `N("...")`
   (mark text in tables, translated where drawn). `nativeloader/i18n.lua` looks the English up in the
   built table for the current language, falling back to the English.
3. **The language.** Garry's Mod's own (`gmod_language`), unless the client setting
   `nativeloader_language` names another: a choice in "Start here", which rebuilds the spawn menu.
   Console output stays English, for reports.
4. **Built in at packing.** [`tools/companion_i18n.py`](../../tools/companion_i18n.py.md) `update`
   extracts and merges, `check` checks (syntax, known text, the same `%s`), and `build` writes
   `lua/nativeloader/i18n_data.lua`. [`package_fixes.py`](../../tools/package_fixes.py.md) runs `build`
   for every RTX package, so an edited `.po` reaches players with the next package (a commit on `main`
   publishes it); a `.po` that does not check stops the build. The built table is not kept in git.

## Consequences

- A translation fix is a `.po` edit and a commit; no Lua changes, no loader release.
- New or changed text in the companion needs `companion_i18n.py update`; until it is translated it
  shows in English.
- The guide quotes Remix's menu labels in the language's translation with the English in parentheses,
  since Remix's menu may be shown in either; labels of the other add-ons and console lines stay English.
- The translations were written by Claude and are for the user to review; the `.po` files are where to
  correct them.

## Alternatives considered

- **GMod `.properties` files with generated keys.** GMod reads them natively, but a reviewer would edit
  key-value lines with no English beside them, and a key derived from the English changes with it.
- **One spreadsheet-like table (CSV) for all languages.** Easy to compare side by side, but quoting
  long sentences with commas by hand breaks easily, and it would differ from the runtime's files.
- **The built table committed beside the Lua.** Simpler to run the add-on from the repository, but two
  copies of each translation could drift; the package build is the only consumer.
