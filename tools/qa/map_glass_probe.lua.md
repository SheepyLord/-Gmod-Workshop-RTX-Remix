# map_glass_probe.lua

Client Lua for `poc_session.py run --map modern_house --console "sv_cheats 1" --lua
tools\qa\map_glass_probe.lua --lua-shots 180`: shoots a map glass pane the way a player does, then
the broken window again, then the debris on the floor (review R4: shooting a window crashed the game).

Finds the `func_breakable` entities whose brush surfaces use a glass material, picks the nearest,
stands 90 units in front of it at eye level (`setpos`/`setang`, which need `sv_cheats 1` for the
session; it is not archived), selects the 357 and fires with real `+attack`. Prints `NL_GLASS` lines
(pane count, target, shard counts after each step) and takes a screenshot per step. A crash shows in
the session record as an abnormal exit; the dump is in `rtx-remix\logs\.sentry-native\reports`.

Side effects: the map state of that session only (a broken window, debris). Exit codes: none.
