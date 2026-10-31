# glass_debris_probe.lua

Client Lua for `poc_session.py run --map modern_house --console "sv_cheats 1" --lua
tools\qa\glass_debris_probe.lua --lua-shots 180` (on the PoC: `--mount-workshop 3495468649
--change-map modern_house`): checks the loose broken glass of
[ADR 0061](../../docs/decisions/0061-loose-glass-breaks-again-and-expires.md) in the game (R5).

Finds the nearest `func_breakable` with a glass material, stands 110 units in front of it
(`setpos`/`setang`, which need `sv_cheats 1` for the session), breaks it with one 357 shot, then fires
four shots into the pile below the window, then sets `rtx_glass_debris_lifetime` to 6 s and waits 9 s,
putting the player's value back afterwards. Prints `NL_GLASS` lines and takes a screenshot per step:

| Line | Holds |
|---|---|
| `NL_GLASS broken shards <n> groups <group>x<count>,...` | the visible pieces after the break and their collision groups (11 `COLLISION_GROUP_WEAPON`, 1 `COLLISION_GROUP_DEBRIS`, 20 `COLLISION_GROUP_WORLD`, the old group) |
| `NL_GLASS shot_pile shards <n> moved <m> broke_or_gone <k>` | after the shots into the pile: pieces that moved more than 2 units, pieces that broke (their fragments take their place) or turned to dust |
| `NL_GLASS after_lifetime shards <n>` | the visible pieces left once the lifetime has passed (0 expected) |

Pass: group 11 (or 1 with `rtx_glass_expensive_shards 0`), `moved` or `broke_or_gone` above 0, and no
piece left after the lifetime. Side effects: the map state of that session; `rtx_glass_debris_lifetime`
(archived) is set back to the value it had. Exit codes: none (client Lua).
