# collect_repo_build.py

Takes this repository's own native modules in the RTX package from the Release build a workflow just made
(`tools\build.ps1 -Config Release`) and lays them out as their parts' files (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)): `pins.json`'s
`repository_builds` maps `gmsv_nlrtxclient_win64.dll` (CMake target `nl_rtx_client`) to
`fixes/modules/` and `gmcl_nlglass_win64.dll` (`nl_glass_client`) to `glass/bin/`.

```powershell
python tools\ci\collect_repo_build.py [--out out\ci\built] [--run-url URL]
```

Writes `<out>\provenance-repository.json`: for each module's SHA-256 its part and path, this repository
(from `GITHUB_SERVER_URL`/`GITHUB_REPOSITORY` in a workflow, else `origin`), the commit (with "(with
uncommitted changes)" when tracked files differ), how it was built and the run; and `missing`.
**Exit:** 0 collected; 1 when a module is missing (build first). Tested by
[test_ci_tools.py](../tests/test_ci_tools.py.md).
