# The Advanced Material Editor's RTX bridge: source for the GitHub build

`gmcl_advmat_rtx_bridge_win64.dll` (this part's `bin/`) is built from this folder on GitHub by the
RTX package's workflow (R16, ADR 0106), so the package does not carry a binary made on a local machine.

## Source identity

- Origin: https://github.com/SheepyLord/-advanced_material_editor.git (a private repository),
  `native/rtx_bridge` at `8ece14155d771f0465dfac32ff6dd6a0e1f8aa96` ("Skip re-reading unchanged texture
  sources on every apply"). The folder is unchanged up to the origin's `main` of 2026-11-04 (`05435bd`),
  the commit the packaged add-on comes from.
- `rtx_bridge/` holds the folder's 12 files as they are; `provenance.json` lists each one's size and
  SHA-256. A workflow in this repository cannot read the private origin without a token, so the source
  is copied here.
- The binary that shipped before R16 (316,416 bytes, SHA-256 `aeb5de42...`) is byte-identical to a local
  build of that commit.
- The origin has no licence file; this copy asserts or grants none. It is the same author's code as the
  add-on this part already ships.

## Build

```powershell
cmake -S rtx_bridge -B build -G "Visual Studio 17 2022" -A x64 -DADVMAT_RTX_BUILD_GMOD_MODULE=ON `
  -DGARRYSMOD_COMMON_INCLUDE_DIR=<garrysmod_common at a854f237>/include
cmake --build build --config Release        # -> build/Release/gmcl_advmat_rtx_bridge_win64.dll
ctest --test-dir build -C Release           # the writer's tests
```

Needs only garrysmod_common's public headers (https://github.com/danielga/garrysmod_common,
`a854f237b79087826aa9a98a05de5e0d2b4502b6`, `include/`). `/W4 /WX /permissive- /EHsc`, C++17, links
`windowscodecs` and `ole32`. See `tools/ci/build_modules.ps1`.
