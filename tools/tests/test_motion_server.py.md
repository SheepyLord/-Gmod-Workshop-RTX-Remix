# test_motion_server.py

Runs [motion_server_harness.lua](motion_server_harness.lua.md) under LuaJIT, once per scenario, without
starting Garry's Mod. It loads the shipped Character Motion Importer's server file
`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua` with the game's API
stubbed (R19, the pre-release review).

```powershell
python -I -m unittest discover -s tools/tests -p test_motion_server.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_only_yourself_or_an_admin_selects_and_poses_a_player` | H4/L-01: a player cannot select another player, yourself and (as an admin) another player can, NPCs still can; the menu's "select myself" message names only the sender; the debug window does not open on another player |
| `test_a_dance_or_build_on_another_player_is_refused_where_it_starts` | A stale or forged selection: the dance does not hide or lock the other player, the debug pose and the build are refused |
| `test_force_reset_and_death_leave_another_freeze_alone` | Force Reset and a death do not unfreeze or show a player an admin tool froze and hid; what the add-on hid it shows again |
| `test_stop_all_stops_your_own_dances` | L-03: "stop all" stops the requester's dances; an admin's stops everyone's |
| `test_a_leavers_dances_stop` | L-05: a disconnect stops the leaver's NPC dances, not another player's |
| `test_debug_frames_are_paced` | L-06: one debug frame now, the latest one when the 0.1 s interval ends |
| `test_cvars_come_back_after_a_map_change` | M9: the original of a suppressed cvar is recorded in data/, ShutDown restores it, the next start removes the record |
| `test_cvars_come_back_after_a_crash` | M9: without ShutDown, a dance before InitPostEntity takes the recorded original (not the 0 left behind), InitPostEntity restores what an earlier session left off, and a record naming anything else runs nothing |
| `test_a_lua_cvar_comes_back_at_shutdown` | A cvar made by Lua is set at once in ShutDown |
| `test_an_admins_cvar_change_is_kept` | L-04: a value an admin set during the dance stays; a dance ending in its first frame still restores |
| `test_built_animations_stay_within_a_byte_budget` | M8: the oldest idle built animation goes past the byte budget; a playing one is never dropped |
| `test_build_limits_per_player` | M8/L-09: the per-player built-file and queue limits, the per-build JSON budget, admins unlimited |
| `test_the_main_chunk_stays_below_luas_local_limit` | `sv_commands.lua` still loads (its main chunk is near Lua's 200-local limit) |

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
