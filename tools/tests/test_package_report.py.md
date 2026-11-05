# test_package_report.py

`python -m unittest discover -s tools/tests -p test_package_report.py -v` tests
[`package_report.py`](../package_report.py.md) on a small GMAD v3 archive the test writes under
`out\tmp`: the archive's SHA-256 and every file's path, size and SHA-256 in archive order; a provenance
files keyed by SHA-256 marking a compiled and a fetched binary, the JSON, Markdown and sha256sum outputs
(the `.gma` hash, the run and commit, each binary's origin and source), a binary no record names reported
as taken from `packages/`; and exit 2 for an unreadable archive. No network, no game, no
writes outside its scratch folder, which it removes. Exit 0 when all pass, 1 otherwise.
