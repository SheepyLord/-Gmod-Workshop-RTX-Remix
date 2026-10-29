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
- Hard links are opt-in: an archive-only build with `--link` uses them, leaves the sources as they
  were, is checked as the archive, holds the same files as a folder build (the add-on's own
  `addon.json` included), and carries the type and tags in its header.
- Add-ons keep only what gmad would publish: the whitelist (`lua`, `materials`, `shaders/fxc`,
  `data_static`, ...), minus the `addon.json` ignore list and `--ignore`; `--no-addon-filter` keeps all.
- `--addon-as` deploys under another name, a leading `!` allowed; a bad name is refused.
- `--addon-file` replaces one file of an add-on (never adds one), folding case and accepting `\`,
  leaves the source folder as it was and shows in both summaries. Refused: no path in the add-on, an
  add-on not in the package, a file the add-on does not have (or junk left out), a missing FILE, the
  same path twice.
- `--lua-bin` files go to `garrysmod/lua/bin` (kind `lua-binary-module`); `--load-first` writes
  `module_dependencies` and raises `requires_loader` to `>=0.3.0`; malformed, unknown, non-`.dll`,
  self and repeated rules, a repeated file name and a missing file are refused.
- Refusals leave nothing behind: no output, nothing to package, a bad id or version, a missing or
  empty folder, two inputs with one deployed name, a non-empty output, an output inside an input, an
  archive inside the folder output.
- A path the loader would refuse (non-ASCII); a private-looking file in an add-on is filtered out,
  and without the filter, or in a mod, refused unless `--allow-private` names it.
- An inventory beside each output; the text summary.
- With a built `nlctl.exe` (0.2.0 or newer): it accepts the folder and the archive.

Run with the other tool tests: `python -m unittest discover -s tests` from `tools\` (as
`tools\test.ps1` does). Exit 0 when the tests pass.
