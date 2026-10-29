# test_companion_i18n.py

Unit tests for [`companion_i18n.py`](../companion_i18n.py.md), on a small companion written to a
scratch folder under `out\tmp` (the real `companion/i18n` is never touched).

```powershell
cd tools; python -m unittest tests.test_companion_i18n -v    # or tools\test.ps1
```

Covers:

- **Extraction.** `L("...")`, `L"..."` and `N("...")` are found, a text used twice is listed once with
  both lines, Lua escapes (`\\`, `\"`) are read, and comment lines and unmarked strings are left out.
- **Merging.** A second `update` keeps translations of unchanged text (with backslashes and quotes),
  adds changed text untranslated, drops the old text and says no translation was lost; the template
  marks text with `%s` as `c-format`.
- **Checks.** A translation without the English `%s` is refused with the file and line; with it, it is
  used. A `%` in other text is accepted. A `msgid` the companion does not have, and a PO escape that does
  not exist (`\q`), are refused. Empty and fuzzy entries show the English.
- **PO strings** round-trip through quoting and unquoting (quotes, backslashes, line breaks, tabs, CJK).
- **The add-on.** The built table is read by the real `companion/nativeloader/lua/nativeloader/i18n.lua`
  under LuaJIT, with the GMod functions it calls mocked: the text comes in `gmod_language`'s language,
  `nativeloader_language` overrides it, a language without the text and English show the English, `N`
  returns its text, and the module lists the seven languages and watches `nativeloader_language`.
  Skipped when LuaJIT is not installed (on `PATH` or in `%LOCALAPPDATA%\Programs\LuaJIT\bin`).

Side effects: the scratch folder, removed afterwards. Exit code: unittest's (0 when all pass).
