# test_install_tools.py

End-to-end tests for [`verify_install.py`](../verify_install.py.md) and
[`make_vanilla_copy.py`](../make_vanilla_copy.py.md) on a fake install that has one file of each
kind: vanilla, edited in place, resized, missing, a customised user-config file, and a non-depot DLL.

- `verify` puts each file in the right category; `extras` finds the non-depot DLL; the CLI exits 1
  for the modified install and 0 for a clean one.
- `clone` copies only verified files (keeping mtimes, creating listed empty folders, leaving no
  `.partial` files), takes rejected files from a fallback folder when one verifies, and refuses a
  non-empty destination or one inside the source.

Run from `tools\steam\`: `python -m unittest discover -s tests` (or `tools\test.ps1`).
