# test_runtime_tiers.py

Checks the repository's packaged performance tiers against a pinned table of real RTX option
names, C++ types and inclusive ranges or enum values. The table cites the fully patched R6 T4
runtime snapshot, its commit, the reference-document hash, and each declaration's file and line.
Numeric bounds come from declarations, type limits, the OMM UI's nonnegative MiB range and
the sky-probe UI's six supported power-of-two extents (256 through 8192).
Refresh the table against the patched source when `runtime/base.json` changes; tests need no
runtime checkout, game, GPU or downloads.

Every `packages/runtime/layers/*.conf` is parsed. Low, medium and any newly added layer must use
the table: unknown/misspelt keys, wrong types, invalid enums and values outside the bounds fail.
Classic and compiler layers are pinned by SHA-256 instead: high stays byte-identical, including
15 obsolete classic keys ignored by this runtime, rather than declaring them real RTX options.
A baseline edit fails until explicitly reviewed. Fixtures exercise bad assignments, duplicate
keys, incorrect types, and each numeric/enum boundary.

Run `python -m unittest tests.test_runtime_tiers -v` from `tools`, or `tools\test.ps1`.
Reads only the packaged text layers, writes nothing, and uses unittest's exit code (0 on success).
