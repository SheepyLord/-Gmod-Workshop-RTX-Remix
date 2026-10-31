# test_classic_defaults.py

Unit tests for [`classic_defaults.py`](../classic_defaults.py.md), run by `tools\test.ps1`. They write
a small synthetic `garrysmod\cfg\client.vdf` and `server.vdf` in a temporary folder (under `out\tmp`
when it exists) and delete it.

- Only RTX settings are taken (`rtx_`, `mhrtx_`, `brrtx_`, the skinning variables, AMAP's
  `mmd_vmd_npc_flashlight_`). Debug switches, key bindings (`_key`) and other add-ons' or the game's
  variables are left out. The version is written.
- `main` writes the table, `--check` passes on an up-to-date table and fails on a changed one, and a
  missing reference gives exit 1.
- There is no default reference: without `--reference` it exits 1 and writes nothing (it used to read
  `GarrysMod_RTX_c`, which is no longer a classic install).

No game, network or install is touched. Exit codes are unittest's.
