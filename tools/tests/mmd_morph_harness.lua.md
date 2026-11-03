# mmd_morph_harness.lua

LuaJIT regression harness invoked by [test_mmd_morphs.py](test_mmd_morphs.py.md).
Runs the packaged production Lua, with generated tables/PMX and mocked GMod APIs.

Arguments: `matcher|actor|mount|geometry`, importer Lua directory, hotloader Lua
directory, generated Lua fixture, optional generated PMX. Tests exact identity,
case/width/truncation, duplicate names, overflow playback and reset interfaces,
geometry-selected opposite sides, missing halves, saved manual overrides,
ordinary Source flexes, preserved custom VMD tracks, malformed PMX rejection,
and registration after the server's map precache table is reset. Group vector
cancellation/partial geometry cannot supply a false bilateral side. Mount
memoization is checked after visibility disappears and when the requested
model is missing. It also refuses publication when a mount fails. No game or
user data is touched.

The actor-only fixture stubs R12-A's manifest persistence boundary; its disk/deletion behavior
is exercised separately by [mmd_reimport_harness.lua](mmd_reimport_harness.lua.md).

Reads the named files, writes stdout only. Exit 0 and `PASS <mode>` on success;
an assertion/Lua error is nonzero. Scratch files are generated under `out/tmp`.
