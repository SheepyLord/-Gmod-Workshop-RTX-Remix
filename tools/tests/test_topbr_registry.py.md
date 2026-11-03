# test_topbr_registry.py

Compiles the packaged GPL `game_registry_test.cpp` against the production registry and fallback
selector with MSVC C++17, assertions, `/W4 /WX`, and no game/SDK dependencies. Runs with
`python -m unittest discover -s tools/tests -p test_topbr_registry.py` or `tools/test.ps1 -Config Release`.
Requires Windows and VS 2022 Build Tools; otherwise skips. Reads corresponding source under
`packages/fixes/licenses/oversized-skinning/autopbr`; writes compiler output and generated DDS/registry
fixtures only to an automatically removed directory under `out/tmp`. Does not start a game or use
the network. Exit 0 on success/skip; a compilation, assertion, or timeout fails the unittest.

Covers atomic write/read and failed replacement, live texture identity and hashes, source refresh,
generator retention, missing/truncated/edited DDS, unsafe/malformed/versioned/bounded records,
source-less cache retention, independent switches and authored-hash exclusion.

Also compiles the production R12 feature discovery and texture override regression with SDK type
stubs: spatial matching, ambiguity/flat/aspect abstention, path bounds, drawn-hash gating before
material loading, manual-map/none/automatic persistence, current-hash restoration without source,
changed DDS rejection, and failed atomic replacement without changing the current choice.
R12-B2 adds a generated straight-alpha PNG downsample (including exact fractional weights),
independent ambiguous/unreadable families, name-gated auxiliary data, self-vote/exported-family
rejection, and base-before-mask decode-budget priority to that same native regression.
Review cases cover damaged empty/garbage/duplicate/excess-row registries, exact backup bytes and
fresh reload/record/restore; malformed decimal headers recover, while other well-formed versions and
oversized files stay read-only and byte-identical. A Windows sharing violation at replacement verifies
staging cleanup and preservation of the prior registry.

R13-M (`test_compact_game_maps`) compiles the packaged `game_dds_test.cpp` twice, the second time with
`/DTOPBR_GAME_GENERATOR_VERSION=999`, and runs it on fixtures from the packaged
`make_game_pbr_fixtures.py` (the current Python). It checks compact imported game maps (BC5 normal,
BC4 roughness/metallic, uncompressed emission, no AO), the DX10 and uncompressed layouts and their
refusals, the per-block error bound, the disk/bounds/budget refusal lines, the recipe marker,
half-family completion, transcoding of finished v7/v6/v5 families (byte-identical to a fresh
conversion) and the cases that convert again, source-less registry and manual-choice migration with
a failed save, and that a build with another generator number converts and writes nothing. Writes
only its own directory under `out/tmp`; timeout 300 s.
