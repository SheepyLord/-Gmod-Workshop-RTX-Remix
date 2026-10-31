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

Review R4 checks: one slot without a private copy leaves out only itself (reported once, not looked
up every frame) while the body still draws; draws reuse the pose snapshot and the material list and
register a categorized slot once; a shared material whose player tags are off is not looked up
again, and one not drawn yet is looked up less and less often until its hashes appear.
