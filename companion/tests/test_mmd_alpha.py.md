# test_mmd_alpha.py

Runs LuaJIT scenarios against the real companion script: registration, missing/late APIs and
resources, fallback exclusion, invalid/duplicate hashes, late assets, removal, revision and
fallback refresh, refused writes, tracking compatibility, generated-name filtering and the
16-lookup frame budget with 4,096 parts; `soft_only` (a part drawn only through its soft copy is tagged by the copy's name; fails on R7-A's
code), `soft_late` (a soft copy created later joins at the next sweep; fails on R7-A's code),
`soft_budget` (1,024 soft copies stay within the 16-lookup budget) and `soft_namespace` (only
hotloader soft-copy names are tracked).

R12-C adds a cold 4,096-material library: no material/VMT/tracking loads until an actual draw hash
exists, followed by successful classification of the one newly drawn material.

Usage: `python -m unittest discover -s companion/tests -v` from the repository root. Inputs are
the companion and harness sources and an installed LuaJIT (PATH or the standard local install).
Output is a unittest result. No game, network, files or persistent settings are touched.
Exit 0 means the suite passed; nonzero means failure. A missing LuaJIT explicitly skips tests.
