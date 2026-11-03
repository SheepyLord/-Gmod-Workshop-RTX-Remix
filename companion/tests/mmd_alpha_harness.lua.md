# mmd_alpha_harness.lua

LuaJIT harness for the actual MMD alpha companion. Usage:
`luajit companion/tests/mmd_alpha_harness.lua <companion script> <scenario>`.

Inputs are the script path and a scenario selected by `test_mmd_alpha.py`. The `soft*` scenarios give the
public material no hash and add `mmdhl.softMaterials` soft-copy names whose plain names carry it. Stubs cover asset
metadata, material/texture readiness, Remix hashes and revisions, tracking and option writes.
Output is `PASS <scenario>` or an assertion error. It writes no files and launches no game.
Exit 0 means success; an assertion or Lua error exits nonzero.

`cold_library` visits 4,096 unused material records for hundreds of frames with zero material,
VMT or tracker loads, then gives one material a draw hash and requires only that material to load.
`track_retry` also checks that an undrawn material never invokes tracking.
