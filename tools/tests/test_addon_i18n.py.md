# test_addon_i18n.py

Regression tests for [check_addon_i18n.py](../check_addon_i18n.py.md): missing languages and keys,
changed placeholders, accidental English fallback, and the shipped catalogs' real language selectors.
The real-catalog case requires LuaJIT and is skipped if it is unavailable. The validator fixture needs
only Python. Run `python -m unittest discover -s tools/tests -p test_addon_i18n.py` or `tools/test.ps1`.
Reads source catalogs; no persistent writes. Exit 0 on success, nonzero on a failed test.
