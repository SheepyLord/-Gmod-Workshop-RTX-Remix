# collect_runtime.py

Lays out the Remix runtime a workflow built as the runtime part's files (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)): from the build's install folder
(`runtime\build_runtime.ps1 -Install` writes `<tree>\_output`) it copies every file the runtime part
indexes under `files/` ([`packages/runtime/files.json`](../../packages/runtime/files.json)), except this
repository's own `files/atmosphere/`, to `<out>\runtime\files\`.

```powershell
python tools\ci\collect_runtime.py <tree>\_output [--out out\ci\built] [--run-url URL]
```

Writes `<out>\provenance-runtime.json`: `copied`, the indexed files the build did not make (`missing`),
the files it made that the part does not ship (`built_not_shipped`, without `.pdb`, `.lib`, `.exp`), and
for every `.dll`/`.exe` (by its SHA-256) its part, path, the fork's repository and commit from
[`runtime/base.json`](../../runtime/base.json), `runtime/patches`, and `how`: `compiled:` for `d3d9.dll`
and the Remix USD plugins, `fetched by the same build` for the vendor binaries packman, the submodules and
the clones bring.

**Exit:** 0 collected; 1 when a binary the part ships is missing from the build, or the folder has no
`d3d9.dll`. The package never takes a local copy in its place. Tested by
[test_ci_tools.py](../tests/test_ci_tools.py.md); checked on the fork's local `_output` (189 files, 41
binaries: 3 compiled, 38 fetched by the build, nothing missing or extra).
