# test_remix_defaults.py

Unit tests for [`remix_defaults.py`](../remix_defaults.py.md), run by `tools\test.ps1` (unittest
discovery in `tools\tests`). They use small config files in a temporary folder (under `out\tmp` when
it exists) and delete it.

- An ordinary option takes the stronger file's value, in first-seen key order.
- Texture-hash sets combine like Remix layers: a stronger file's `-0x..` removes, its `0x..` adds back,
  and net removals stay as `-` tokens.
- A non-hash value replaces a set.
- `main` writes the layer with its header, and returns 1 for a missing input.

No game, network or install is touched. Exit codes are unittest's.
