# loader_update_harness.lua

LuaJIT executable harness for the actual companion `nativeloader.lua` autorun. Run with its source
path as the only argument, normally through `test_presentation_ui.py`. Mocks GMod files, JSON, hashes,
hooks, timers and Derma. Covers trusted physical record ownership, content aliases, unchanged bytes,
bounded reads, release/prerelease precedence, older-loader gating, buttons, map/start lifetime,
version-specific ignore and 900/2160-height scaling. No game, disk writes or network. Prints PASS and
exits 0; an assertion or Lua error exits nonzero.
