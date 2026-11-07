# packages/glass

The glass system's part of the RTX package (G1, [ADR 0070](../../docs/decisions/0070-glass-overhaul.md)).
Only the native module is stored here: `bin/gmcl_nlglass_win64.dll`, built by `tools\build.ps1 -Config Release`
from [`glass/native`](../../glass/native/README.md) (this repository's code, MIT, with Jolt Physics from
[`third_party/jolt`](../../third_party/jolt/README.md), MIT, linked in) and imported, with the record of
what it was built from ([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)), by:

```powershell
python tools\ci\repo_builds.py refresh glass/bin/gmcl_nlglass_win64.dll
```

`tools\check_repo.py` fails while its sources in `tools/ci/pins.json` `repository_builds` (`glass/native`,
Jolt, LZMA, the GMod headers, the root CMake files) differ from that record. The stored module is R19-G's
build (SHA-256 `10cefd57...`); a build of commit `a5a3ff1` in a folder of the same path length is the same
image, so the first record (after R20) kept it.

The add-on itself is read from [`glass/addon`](../../glass/README.md) in this repository, as the companion
is, and deployed as `garrysmod/addons/nlglass` with the module in `garrysmod/lua/bin`
(`tools/workshop.json`, part `glass`). The add-on carries its MIT licence and Jolt's licence
(`nlglass/LICENSE`, `nlglass/licenses/jolt/LICENSE`). Refresh the module whenever one of its sources
changes; the check says when.
