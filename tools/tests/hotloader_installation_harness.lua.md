# hotloader_installation_harness.lua

Executes the complete packaged `overrides/installation.lua` and `installation_ui.lua` with game,
filesystem, timer, network and native-module fixtures. Used by
[test_hotloader_installation.py](test_hotloader_installation.py.md).

```text
luajit tools/tests/hotloader_installation_harness.lua packages/model-hotloader client findings
```

Inputs: part folder, `client` or `server`, scenario (`findings`, `matched`, `failed`, `throws`,
`unchecked`, `pending`, `pending-timeout`, `fallback`, `identity`, `missing`, `outdated`, `policy`).
Uses real initialization, refresh, retry, Recheck and UI summary/notice code. Fixtures describe
unverified libraries and arbitrary future native findings, and independently exercise every other
installation warning relevant to R21-B. The pending timeout retains the existing `game_not_ready`
warning. Prints `PASS <realm> <scenario>`; assertions fail on a regression. Writes no files and loads
no native binaries. Exit 0 on success, nonzero on failure.
