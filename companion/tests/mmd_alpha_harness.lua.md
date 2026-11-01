# mmd_alpha_harness.lua

LuaJIT harness for the actual MMD alpha companion. Usage:
`luajit companion/tests/mmd_alpha_harness.lua <companion script> <scenario>`.

Inputs are the script path and a scenario selected by `test_mmd_alpha.py`. Hooks are kept per event
(`Think` and `PostRender` run each frame); the soft-only scenarios add `CreateMaterial`, `render`, `cam`
and `surface` stubs whose wrapper hash appears only after it was tracked and drawn. Stubs cover asset
metadata, material/texture readiness, Remix hashes and revisions, tracking and option writes.
Output is `PASS <scenario>` or an assertion error. It writes no files and launches no game.
Exit 0 means success; an assertion or Lua error exits nonzero.
