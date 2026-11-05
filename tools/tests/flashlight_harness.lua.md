# flashlight_harness.lua

Loads the RTX fixes' flashlight Lua (GPL, `packages/fixes`) under a fake GMod API and checks the R19
fixes ([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)):

- `server <sv_remix_flashlight.lua>`: a burst of toggle messages costs one broadcast and the next
  one after the 0.3 s cooldown counts (F-04); a dead player, a spectator and a player whose
  `CanUseFlashlight()` is false cannot switch on, by message or by the flashlight key, while
  switching off is never refused (the review's miss); colour messages are coalesced: the first is
  broadcast at once, the newest when the 0.1 s interval ends, none while the flashlight is off.
- `client <cl_remix_flashlight.lua>`: a repeated "on" for one player (the join-time sync after a
  broadcast) replaces the Remix light instead of leaking it (F-03); "off" and `rtx_flashlight_reload`
  keep the count right.

Usage: `luajit tools/tests/flashlight_harness.lua server|client <file>`. Reads only the given file;
no game, network or file writes. Exit 0 and a `PASS` line on success, nonzero on a failed assertion.
Run by [test_flashlight.py](test_flashlight.py.md).
