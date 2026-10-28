# test_install_tools.py

End-to-end tests for [`verify_install.py`](../verify_install.py.md) and
[`make_vanilla_copy.py`](../make_vanilla_copy.py.md) on a fake install that has one file of each
kind: vanilla, edited in place, resized, missing, a customised user-config file, and a non-depot DLL.

- `verify` puts each file in the right category; `extras` finds the non-depot DLL; the CLI exits 1
  for the modified install and 0 for a clean one.
- A depot file reached through a junction (`garrysmod\cfg` linked to a folder elsewhere that holds
  byte-identical files) is reported as `reparse_point`, not OK, and the CLI exits 1 (R1-020). The
  same holds for a depot file that is itself a symbolic link; that case is skipped where symbolic
  links need a privilege the account lacks (Developer Mode off, not elevated). The junction is
  removed by the test, never what it points to.
- A depot entry with no hash but a size is `unverified`, and the CLI exits 1. An empty entry without
  a hash and a user-config entry without one count as OK.
- `clone` copies only verified files (keeping mtimes, creating listed empty folders, leaving no
  `.partial` files), takes rejected files from a fallback folder when one verifies, and refuses a
  non-empty destination or one inside the source.
- The fixture folder is created under the repo's `out\tmp` whatever `TEMP` says (AGENTS.md rule 9;
  R1-028). A test points `tempfile` at a folder that does not exist and checks the fixture still
  starts there.

Run from `tools\steam\`: `python -m unittest discover -s tests` (or `tools\test.ps1`). Scratch goes
to `out\tmp` either way.
