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
Review cases cover damaged empty/garbage/duplicate/excess-row registries, exact backup bytes and
fresh reload/record/restore; malformed decimal headers recover, while other well-formed versions and
oversized files stay read-only and byte-identical. A Windows sharing violation at replacement verifies
staging cleanup and preservation of the prior registry.
