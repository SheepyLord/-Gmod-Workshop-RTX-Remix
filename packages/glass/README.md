# packages/glass

The glass system's part of the RTX package (G1, [ADR 0070](../../docs/decisions/0070-glass-overhaul.md)).
Only the native module is stored here: `bin/gmcl_nlglass_win64.dll`, built by `tools\build.ps1 -Config Release`
from [`glass/native`](../../glass/native/README.md) (this repository's code, MIT, with Jolt Physics from
[`third_party/jolt`](../../third_party/jolt/README.md), MIT, linked in) and imported with:

```powershell
python tools\inputs.py import glass --file "out/build/win64-release/glass/native/gmcl_nlglass_win64.dll=bin/gmcl_nlglass_win64.dll"
```

The add-on itself is read from [`glass/addon`](../../glass/README.md) in this repository, as the companion
is, and deployed as `garrysmod/addons/nlglass` with the module in `garrysmod/lua/bin`
(`tools/workshop.json`, part `glass`). The add-on carries its MIT licence and Jolt's licence
(`nlglass/LICENSE`, `nlglass/licenses/jolt/LICENSE`). Rebuild and import the module whenever
`glass/native` or `third_party/jolt` changes.
