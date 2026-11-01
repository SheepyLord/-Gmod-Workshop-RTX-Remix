# test_mmd_alpha.py

Runs LuaJIT scenarios against the real companion script: registration, missing/late APIs and
resources, fallback exclusion, invalid/duplicate hashes, late assets, removal, revision and
fallback refresh, refused writes, tracking compatibility, generated-name filtering and the
16-lookup frame budget with 4,096 parts.

Usage: `python -m unittest discover -s companion/tests -v` from the repository root. Inputs are
the companion and harness sources and an installed LuaJIT (PATH or the standard local install).
Output is a unittest result. No game, network, files or persistent settings are touched.
Exit 0 means the suite passed; nonzero means failure. A missing LuaJIT explicitly skips tests.
