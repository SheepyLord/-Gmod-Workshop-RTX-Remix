# editors_harness.lua

LuaJIT harness invoked by [test_editors.py](test_editors.py.md), one scenario per run:

```powershell
luajit tools\tests\editors_harness.lua <scenario> <!advanced_material_editor> <!advanced_bodygroup_tool> <bullet_break_simulator folder>
```

The last three arguments are the add-on folders (for Procedural Bodygroup Destruction, its
`lua/bullet_break_simulator` folder). Scenarios: `adv_snapshot`, `adv_hello`, `abt_dupe`, `abt_actions`,
`abt_cache`, `bbs_denied`, `getbool`. Each loads the shipped files it tests (`sh_20_net.lua` and
`sv_30_store.lua`; `sv_31_rtx_store.lua`; the bodygroup tool's autorun file and stool; `cl_uv_hide.lua`;
`sv_20_hits.lua`; for `getbool`, the helpers cut out of their files) with stand-ins for the game's
libraries: hooks, timers fired on demand, a clock the scenario advances, convars, net messages recorded
and delivered, entities, players and counting `util.TableToJSON`/`util.Compress`.

It writes no files and touches no network. Prints `PASS <scenario>` and exits 0, or fails an assertion
with a message and exits 1.
