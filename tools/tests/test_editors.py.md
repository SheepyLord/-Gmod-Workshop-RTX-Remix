# test_editors.py

Checks the R19-E fixes in the three editors the RTX package carries, without starting Garry's Mod: the
Advanced Material Editor, the Advanced Bodygroup Tool and Procedural Bodygroup Destruction, as stored in
`packages/`. Each LuaJIT test runs one scenario of [editors_harness.lua](editors_harness.lua.md), which
loads the shipped files with small stand-ins for the game's libraries.

```powershell
python -m unittest discover -s tools/tests -p test_editors.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_no_getbool_or_fallback_idiom` | No Lua file of the three add-ons uses `:GetBool() or <fallback>` (only `or false` / `or nil`), the idiom that turned a setting of 0 into the fallback (BBS-01). Needs no LuaJIT |
| `test_material_snapshot_encoded_once_and_queue_bounded` | ADV-01: requests for one state of the store encode the snapshot once; a revision or a removed entity's rules make a new one; requests coalesce, so draining the queue sends the snapshot in flight and one waiting snapshot; each player gets exactly one snapshot per `AdvMat.SyncBegin` |
| `test_rtx_hello_never_resets_the_limit` | ADV-02: alternating HELLO 0 and 3 (or a mismatched protocol) inside the 2 s window sends no snapshot; one capable HELLO in it is answered once at its end, not after a withdrawal; profile messages are encoded once per revision, for every player |
| `test_crafted_bodygroup_dupe_raises_nothing` | ABT-01: dupes with strings, numbers and wrong shapes in every field paste without a Lua error and keep only what checks out; a crafted stored modifier does not break the next action; a huge crafted table stops at the entry budget |
| `test_bodygroup_actions_budget_and_player_targets` | ABT-03: a flood of actions is cut to the burst and the budget refills; every vertex-cut request is answered. ABT-04: another player's model only for an admin, one's own and props as before (CanTool still decides); the tool does not select another player for a non-admin and drops such a selection |
| `test_region_analysis_cache_is_bounded` | ABT-02: the client's region analyses stay within the count and triangle budgets, least recently used first, never evicting the analysis in use |
| `test_refused_destruction_settings_are_logged_sparingly` | BBS-02: a flood of refused settings packets logs one line per player per 10 s, with the count in between; an admin still changes the setting |
| `test_getbool_returns_the_setting` | BBS-01: the GetBool helpers of four destruction files and the material editor's `ConVarBool` return a setting of 0 as false and use the fallback only for a missing setting |

LuaJIT is optional: without it the LuaJIT tests are skipped (CI). Writes nothing. Exit code 0 on success.
