# test_imported_parts.py

`python -m unittest discover -s tools/tests -p test_imported_parts.py -v` runs the 11 scenarios of
[imported_parts_harness.lua](imported_parts_harness.lua.md) (R15): the painted-shadow rules over real
field-library parts, the solid-hair rules and VTF sampling, the client controller's lifecycle and bounds,
and the Model Hotloader's visibility hook. Finds LuaJIT on PATH or the machine's normal user install;
skips when it is unavailable.

Inputs: Lua sources and the harness. No game, network or disk writes. Output: unittest results. Exit 0
when all scenarios pass, 1 on a failed assertion.
