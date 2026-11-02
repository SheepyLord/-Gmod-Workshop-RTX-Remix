# test_mmd_morphs.py

R10 regression tests for the shipped morph table/CP932 codec, conservative group
synonyms, offset similarity, exact PMX binding and complete bilateral semantic
fallback, virtual overflow playback, preserved manual overrides and imported VMD
identities, and NPC registration after map precache reset.

Run `python -m unittest discover -s tests -p test_mmd_morphs.py -v` from `tools`,
or `tools/test.ps1 -Config Release`. Uses only Python's standard library and
LuaJIT when installed; Lua tests explicitly skip without LuaJIT. Corpus fixtures
are aggregate counts and named relations in `mmd_morph_statistics.json`, never
model data. Generated PMX/Lua fixtures and scratch stay under `out/tmp`.

Inputs: the packaged Lua/static data and the aggregate fixture. Outputs: test
results; temporary generated fixtures are removed. Exit 0 when all pass,
nonzero on failure. No game, Steam, network or publishing side effects.
