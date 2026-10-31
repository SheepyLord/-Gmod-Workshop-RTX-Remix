# test_glass_map.py

Runs glass_map_harness.lua under LuaJIT against the actual indexed add-on sources: geometry, the map
controller, the loose-glass lifecycle of ADR 0061 and the packet writer. The add-on's legacy files are
GLua, which LuaJIT does not read: `glua_to_lua` turns `//` and `/* */` comments into Lua comments,
spells `!`, `!=`, `&&` and `||` as `not`, `~=`, `and` and `or`, and turns `continue` into a `goto` to a
label at the end of its loop; strings and comments are left as they are, and a `continue` outside a
loop is refused. `run_harness(addon, folder)` converts `networking.lua`, `procedural_shard.lua` and
`world_functions.lua` into `folder` and runs the harness; a second test checks the conversion on a
program with nested loops.

Generated fixtures and the converted files stay under repository out/tmp and are removed afterward.
Skipped without LuaJIT; the full test runner discovers it. Exit follows unittest. No game, Workshop
operation, registry change or user configuration is involved.
