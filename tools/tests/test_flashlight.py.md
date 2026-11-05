# test_flashlight.py

Runs [flashlight_harness.lua](flashlight_harness.lua.md) with local LuaJIT against the packaged RTX
fixes flashlight Lua in `packages/fixes` (`sv_remix_flashlight.lua`, `cl_remix_flashlight.lua`):
the R19 toggle cooldown, coalesced colours and gamemode rule on the server, and one Remix light per
player on the client ([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)).

`python -I -m pytest tools\tests\test_flashlight.py -q`. Reads only repository files; no game or
network. A missing LuaJIT is a reported skip; a failed harness assertion fails the test.
