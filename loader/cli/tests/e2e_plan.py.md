# e2e_plan.py

CTest (`nlctl_e2e_plan`) for the whole M2 chain, on archives built by the real packer
[`tools/gmapack/gmapack.py`](../../../tools/gmapack/gmapack.py.md) rather than C++ fixtures.

It builds, in `--scratch`:

- a fake Steam library (`lib\steamapps\common\GarrysMod`) whose `garrysmod\cfg\addonnomount.txt`
  disables Workshop item 2002;
- packages with real SHA-256 values in their manifests: runtime `runtime-a` as Workshop item 1001
  and again, newer, as a development folder; a second runtime `runtime-b` as a local archive; a
  `root-files` package wrapped like a legacy upload (LZMA plus GMod's `0xBEEFCACE` footer, item
  1003); a `lua-binary-module` package (1004); a manifest without a version (1005); an ordinary
  addon without a manifest (1006); and the disabled item 2002;
- `native-loader\config.json` allowlisting all of them plus an item that is not installed (3003).

Then it requires:

- `nlctl manifest` to accept every package and refuse the broken and ordinary ones;
- `nlctl plan --json` to make exactly these decisions: the dev folder's `runtime-a` active, with its
  runtime to be loaded; `runtime-b` skipped (only one runtime); Workshop `runtime-a` shadowed by the
  dev folder; 1003 and 1004 active; 1005, 1006, 2002 and 3003 skipped with their reasons;
- a config with a typo to stop `plan` with exit code 2.

Usage (CTest passes these): `python -I -B e2e_plan.py --nlctl <nlctl.exe> --gmapack <gmapack.py> --scratch <folder>`.
Writes only below `--scratch` (inside the build tree) and deletes it on success. Exit code 0 on
success; any mismatch exits non-zero with a message.
