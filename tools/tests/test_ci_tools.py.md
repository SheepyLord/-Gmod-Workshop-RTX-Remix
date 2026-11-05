# test_ci_tools.py

`python -m unittest discover -s tools/tests -p test_ci_tools.py -v` tests the package workflow's helpers
in [`tools/ci`](../ci/README.md) (R16): a fetched file checked against its pins (written only when it
matches; the `contains` hashes recorded; another hash refused), a file taken out of a pinned archive (the
archive's hash checked first), the runtime's install folder laid out as the runtime part (every shipped
file, `d3d9.dll` recorded as compiled from `runtime/base.json`'s commit, a missing binary or a folder
without `d3d9.dll` refused), this repository's modules collected with their source, and the cache keys
(stable, different per build, line-ending independent, exit 2 for an unknown build).

**The RTX fixes' recorded trees (R19).** `pins.json`'s `fixes` section records object ids, not a
commit: `patched_tree` (`source`, `public`, `premake5.lua`) and `rtxwater_tree` (`source/rtx_water`),
40 hex digits each; every patch it lists is a file under `packages/fixes/licenses`, the water patches
touch only `source/rtx_water`, and `build_modules.ps1` uses `write-tree` and these keys, never
`patched_commit`. When this machine has a clone of the fixes with the pinned commits (`NL_FIXES_CLONE`,
or `garrys-mod-rtx-remixed` beside this checkout or beside the main checkout of a worktree), the test
replays the script's index steps in a `git clone --shared` scratch clone (the fixes clone is only
read): the base and the patches give `patched_tree`, RTX Water's commit and its patches give
`rtxwater_tree`. Otherwise that test is a reported skip.

No network: downloads are replaced or read from a local folder. Scratch under `out\tmp`, removed
afterwards. Exit 0 when all pass, 1 otherwise.
