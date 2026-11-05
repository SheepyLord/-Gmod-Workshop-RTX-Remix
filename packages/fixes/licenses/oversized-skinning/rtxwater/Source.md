# RTX Water native core: R19 corresponding source (GPL-2.0)

The fixes [LICENSE](../../../LICENSE) applies. `gmcl_rtxwater_win64.dll` is native Version 4 of RTX
Water: `source/rtx_water` of the public fixes commit `b5c194ec8db59b714f01de197cbe7601949d2d0d`, placed
on the patched fixes base, with [rtxwater-lua-input.patch](rtxwater-lua-input.patch) applied after it.
The loader's `tools/ci/pins.json` lists the patch in `fixes.rtxwater_patches` and records the tree it
gives (`fixes.rtxwater_tree`: `source/rtx_water` `7e707d242c863224814a29a0d3e838cbe295d579`). It sits in
this folder so the package's native source bundle (`remixbinary/src/hw`) carries it.

**What it changes** (R19, the loader's
[ADR 0112](../../../../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)).
Any server's client Lua reaches `RTXWaterNative`.

- `SetSurface` skipped only polygons shorter than six floats and read coordinates in pairs, so a
  seven-float polygon read an eighth past its array (the pre-release review's F-01). A polygon is now an
  even count of at least six finite numbers.
- `SetMaterial` joined its texture paths to the game folder as they were, so `..` left it. A path with a
  root, a drive, `:`, `..`, a shortened or device segment keeps the current material.

The copies under `source/rtx_water/` are the files the patch changes, as the working tree of
`b5c194e` with it applied (CRLF): `lua_input.h` (both checks, standard C++ only), `rtxwater.cpp`,
`README.md` and `test/lua_input_test.cpp`.

**Rebuild:** the loader's `tools\ci\build_modules.ps1 -Only rtxwater` restores `source/rtx_water` from
`b5c194e`, applies the patch to the index, checks the recorded tree, then runs premake and MSBuild
Release/x64. Built 2026-11-05 on this machine: 281,088 bytes, SHA-256
`970f9dbdcb670a984cd64c798c2d31e9577af10f02502a289337684425afe5a9`.

**Tests:** `test/lua_input_test.cpp` (standard C++; the loader's `tools/tests/test_fixes_native_inputs.py`
compiles and runs it from this copy).
