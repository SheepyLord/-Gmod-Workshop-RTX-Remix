# test_package_content.py

Tests for [`package_content.py`](../package_content.py.md), on a fake add-on and two fake Remix mods
written to a scratch folder under `out\tmp`. No game files are read.

- The manifest: schema 1, the id, name and version, kinds `lua-addon` and `root-files` in that order,
  `requires_loader >=0.2.0`, `requires_remix` from `--requires-remix`, one `replace-owned` root per
  add-on and mod, every file listed with its size and SHA-256, junk (`Thumbs.db`) left out and
  reported, and the Workshop title in `addon.json`.
- A mod alone: kind `root-files` only, `requires_remix` false.
- The default version is `0.0.0-dev.<newest input time>+<files digest>`; the same inputs give the same
  version and a byte-identical archive, a changed file a new version.
- An archive-only build uses hard links, leaves the sources as they were, holds the same files as a
  folder build (the add-on's own `addon.json` included), and carries the type and tags in its header.
- Refusals leave nothing behind: no output, nothing to package, a bad id or version, a missing or
  empty folder, two inputs with one deployed name, a non-empty output, an output inside an input, an
  archive inside the folder output.
- A path the loader would refuse (non-ASCII), and a private-looking file unless `--allow-private`
  names it.
- An inventory beside each output; the text summary.
- With a built `nlctl.exe` (0.2.0 or newer): it accepts the folder and the archive.

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Exit 0 when the tests pass.
