# _fixtures.py

Test helpers for the Steam tools (not a test module itself).

- `entry(path, data=None, flags=0, sha=None)`: one manifest entry; `data=None` makes a directory,
  `sha` overrides the stored hash bytes (for example 20 zero bytes).
- `build_manifest(entries, depot_id, manifest_id, encrypted)`: encodes a synthetic ContentManifest
  (payload, metadata and end blocks, protobuf varints) that [`steam_manifest.py`](../steam_manifest.py.md) parses.
- `write_tree(root, {relative path: bytes})`: creates a fake install.

No real Steam files are used by any test.
