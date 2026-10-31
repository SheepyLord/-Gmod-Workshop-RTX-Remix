# test_player_body.py

Regression test for the shipped first-person shadow proxy, texture category isolation and menu.
Run with `python -m unittest discover -s tools/tests -p test_player_body.py` or tools/test.ps1.
Uses LuaJIT and [player_body_harness.lua](player_body_harness.lua.md), loading production Lua files
without rewriting them. Requires no GPU or game install, writes only temporary guard-test code under out/tmp and returns unittest's
exit code. Skipped when LuaJIT is unavailable; real RTX acceptance is separate.

Set `NL_PLAYER_PROXY_SOURCE` to an alternate entity Lua file to validate a staged package input
before importing it. By default the test reads the indexed fixes-part source. The harness checks
that the bone callback uses a pose snapshot, applies repeated offsets from the original position,
and skips incompatible models, invalid/unused bones and missing matrices.

The harness also migrates a file-authored shared player tag with no native bookkeeping, preserves
unrelated decal flags, and defers procedural lookup until a real draw provides hashes.
