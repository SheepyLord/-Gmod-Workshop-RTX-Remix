# test_gmapack.py

The vendored GMA File Packer's own unit tests for [`gmapack.py`](../gmapack.py.md), on small
synthetic addons only (no game content). They cover:

- create / verify / extract round trips, deterministic builds with a fixed timestamp, `--nocrc`;
- strict whitelist mode, refusing symlinked sources and Git pointer files, and not packing an
  existing output inside the addon;
- verify and extract rejecting CRC mismatches, truncated payloads, trailing data, unsupported
  versions, duplicate paths, parent traversal and Windows device names;
- reading the LZMA-wrapped Workshop form, including truncation and trailing-data checks;
- CLI edge cases: `--force` rules, missing input, Unicode output paths, control characters in listings.

Run from `tools\gmapack\`: `python -m unittest discover -s tests` (or `tools\test.ps1`).
