# R6 memory-limit compatibility change

GPL-2.0 corresponding source for the current `gmcl_RTXFixesBinary_win64.dll`, layered on the
preceding [oversized-skinning build](../Source.md). The existing [COPYING](../COPYING) applies.
[build-pins.json](build-pins.json) records the source, dependencies, toolchain and binary hashes.

- Base: `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe` (the preceding packaged binary's source).
- Change: `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`, branch `r6-no-memory-limits`.
- DLL: 4,847,616 bytes, SHA-256 `cfcbdc95617f88ec3b002e47d35838376e77e5bba77023365a81927bbd04cfe0`.
- Repository: https://github.com/SheepyLord/garrys-mod-rtx-remixed.git. This commit is local and
  unpushed; [no-memory-limits.patch](no-memory-limits.patch) preserves the complete commit.

Only four native files differ from the preceding source: [module.cpp](source/module.cpp),
[remixapi.cpp](source/remixapi/remixapi.cpp), [remixapi.h](source/remixapi/remixapi.h) and
[resource_lua_bindings.cpp](source/remixapi/resource_lua_bindings.cpp). Complete changed files
are included. Hardware-skinning source and tests retain their content (two checkout files have
CRLF line endings); no other native source or dependency revision changed.

## Behavior

Module open no longer calls `SetMemoryLimits(256, 1024)`. The deprecated Lua function
`RemixResource.SetMemoryLimits(maxCacheSize, maxVRAM)` still requires two numbers and returns
`true` for compatibility, but neither argument sets any limit. An explicit call logs once per
loaded module lifetime that Remix has no cache/VRAM limit options and no limits were changed.
There are no configuration API writes, including replacements with real budget settings that
would enter the User layer and could be persisted to `user.conf` by Remix Save.

## Rebuild and checks

Follow the [preceding rebuild instructions](../Source.md#rebuild) to reconstruct the base if the
local commit is unavailable, then apply `no-memory-limits.patch` with `git am`. Use the unchanged
generated projects in [build-projects](../build-projects), the same recorded dependency revisions
and `ReleaseWithSymbols|x64`, MSVC 14.44.35207, Windows SDK 10.0.26100.0. Build only
`gmcl_RTXFixesBinary.vcxproj`, with `OutDir` and all scratch files below the aggregate worktree's
`out/`. No software download is needed on the development machine.

The earlier restricted attempt denied writes to the original fixes repository's `.git`. The source
branch/worktree therefore lives in an offline shared clone at `out/fixes-origin.git` and
`out/fixes-source` of the R6 T5 aggregate worktree; the original checkout and refs were not changed.
Recursive dependencies were archived from already-present local git objects at their pinned
revisions. The baseline at the exact base commit and the changed DLL both built successfully.
This is source equivalence plus a controlled rebuild, not byte-for-byte binary reproducibility:
timestamps, paths and linker layout differ from the preceding build.

Run [test_memory_limits.py](tests/test_memory_limits.py.md) in an x64 developer shell, with
TEMP/TMP and `--out` inside the aggregate worktree's `out/`. It compiles the actual production
method and Lua wrapper bodies in a fake SDK harness: 8,000 concurrent calls, a disconnected
runtime, legacy Lua success and invalid-argument cases, one notice, zero configuration writes.
The unchanged oversized-skinning C++17 `/W4 /WX` test also passes, with assertions enabled.
PE checks confirm unchanged x64 imports/exports, removal of both unsupported key strings and
presence of the compatibility notice. The fake SDK test does not load the full DLL or renderer.

Only the DLL is imported, from a stage inside the committed fixes worktree so `files.json`
records the correct native source commit:

```powershell
python tools/inputs.py import fixes --file out/fixes-source/out/r6-module/gmcl_RTXFixesBinary_win64.dll=modules/gmcl_RTXFixesBinary_win64.dll
```

Game acceptance remains with R6 integration: no `rtx.resourceLimits` rejection at map load;
explicit legacy Lua calls keep their result and log the explanatory notice once per module load.
