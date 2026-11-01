# Backrooms native regression harnesses

Run in an MSVC x64 developer shell:

```powershell
python tests/test_backrooms_native.py --out <aggregate-worktree>/out/r8-backrooms/tests
```

`--source` optionally selects the fixes checkout (default: this script's parent repository).
Keep TEMP/TMP and all outputs under the aggregate repository's ignored `out/`.
The script extracts the actual production model resolver, checksum reader, lazy transform
resolver and studio hook, and visibility adapter. It includes the production PAS policy header.
MSVC C++17 `/W4 /WX /UNDEBUG` builds three executables with fake filesystem/engine interfaces
and real Windows memory protection and SEH. No game, GPU, network or installed game file is used.

Checks cover missing versus malformed/zero-checksum VTX files, path aliases, separate GAME/all-path
miss scopes (a GAME miss cannot hide a file in another path ID), alternate/specific
mounts, 8,000 concurrent cache hits, the cache bound and reset; lazy successful/failed reads,
nested pending/resolved transforms, all nine draw arguments and exception restoration; PAS
bounds and maximum clusters, 1,000 reversible toggles, ownership loss, reused/freed allocations,
map identity, signature rejection, default-off zero reads, protected memory and module unload.
The signature scanner and engine interfaces are stubs; the tests do not prove an installed
engine's signature matches or that map geometry/lights render correctly.

Outputs: generated C++ harnesses, objects and executables in `--out`. Exit zero means all
compiles and assertions passed; a failed assertion/compiler/subprocess exits nonzero.
Run the existing oversized-skinning and memory-limit tests separately as well.
