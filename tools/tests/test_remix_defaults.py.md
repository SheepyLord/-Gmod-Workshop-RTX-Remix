# test_remix_defaults.py

Unit tests for [`remix_defaults.py`](../remix_defaults.py.md), run by `tools\test.ps1` (unittest
discovery in `tools\tests`). They use small config files in a temporary folder (under `out\tmp` when
it exists) and delete it.

- An ordinary option takes the stronger file's value, in first-seen key order.
- Texture-hash sets combine like Remix layers: a stronger file's `-0x..` removes, its `0x..` adds back,
  and net removals stay as `-` tokens.
- A non-hash value replaces a set.
- Captured player/body texture lists are omitted from the shipped defaults; unrelated world lists remain.
- Frame generation stays off and path bounces are 1 to 12 whatever the inputs say (ADR 0037, ADR 0051),
  also when no input names them.
- The packaged layer, `packages\runtime\layers\classic_remix_defaults.conf`, regenerated from itself
  comes out byte for byte the same, and holds every pinned value: nothing in it is typed by hand
  where the generator would write another value (the 12/1 bounces once were).
- `main` writes the layer with its header, and returns 1 for a missing input.

No game, network or install is touched. Exit codes are unittest's.
