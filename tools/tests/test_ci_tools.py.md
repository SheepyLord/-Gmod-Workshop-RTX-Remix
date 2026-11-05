# test_ci_tools.py

`python -m unittest discover -s tools/tests -p test_ci_tools.py -v` tests the package workflow's helpers
in [`tools/ci`](../ci/README.md) (R16): a fetched file checked against its pins (written only when it
matches; the `contains` hashes recorded; another hash refused), a file taken out of a pinned archive (the
archive's hash checked first), the runtime's install folder laid out as the runtime part (every shipped
file, `d3d9.dll` recorded as compiled from `runtime/base.json`'s commit, a missing binary or a folder
without `d3d9.dll` refused), this repository's modules collected with their source, and the cache keys
(stable, different per build, line-ending independent, exit 2 for an unknown build). No network:
downloads are replaced or read from a local folder. Scratch under `out\tmp`, removed afterwards. Exit 0
when all pass, 1 otherwise.
