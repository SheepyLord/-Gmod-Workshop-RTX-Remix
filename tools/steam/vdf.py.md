# vdf.py

Minimal reader for Valve's text KeyValues format, used by Steam's `.acf` and `.vdf` files
(`appmanifest_4000.acf`, `libraryfolders.vdf`, `appworkshop_4000.acf`, ...).

- `loads(text)` / `load(path)` return nested `dict`s of `str -> str | dict`.
- Handles quoted and unquoted tokens, `\"` `\\` `\n` `\t` escapes and `//` comments.
- A later duplicate key replaces an earlier one; platform conditionals such as `[$WIN32]` are skipped.
- Raises `ValueError` on unbalanced braces.

Command line (prints JSON): `python tools\steam\vdf.py <file.vdf> [...]`

Used by [`steam_manifest.py`](steam_manifest.py.md). Tests: [`tests/test_vdf.py`](tests/test_vdf.py.md).
