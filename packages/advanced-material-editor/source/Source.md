# The Advanced Material Editor's RTX bridge: source for the GitHub build

`gmcl_advmat_rtx_bridge_win64.dll` (this part's `bin/`) is built from this folder on GitHub by the
RTX package's workflow (R16, ADR 0106), so the package does not carry a binary made on a local machine.

## Source identity

- Origin: https://github.com/SheepyLord/-advanced_material_editor.git (a private repository),
  `native/rtx_bridge` at `8ece14155d771f0465dfac32ff6dd6a0e1f8aa96` ("Skip re-reading unchanged texture
  sources on every apply"). The folder is unchanged up to the origin's `main` of 2026-11-04 (`05435bd`),
  the commit the packaged add-on comes from.
- `rtx_bridge/` holds the folder's 12 files with this repository's R19 changes, and one new test file;
  `provenance.json` lists each file's size and SHA-256 and, under `r19_changes`, what changed. A workflow
  in this repository cannot read the private origin without a token, so the source is copied here.
- **R19-E changes** (the pre-release review's BR-02 and BR-03; the origin does not have them):
  - `src/lua_bindings.cpp`, `src/standalone_module.cpp`: a request string is refused by its length
    before it is copied (a hash 18 bytes, a path 2048, a name 64, anything else 4096, no NUL), and no
    C++ exception leaves an exported function or the module's entry point: it becomes `false` and a
    reason.
  - `src/texture_ingest.cpp`: a DDS is checked against its file size (a known format, a mip count of at
    most 16 and no more than the dimensions allow, sane faces and array layers, every byte the header
    describes present), and a cached copy gets the same check before it is reused.
  - `tests/writer_tests.cpp`, the new `tests/lua_binding_tests.cpp` and `CMakeLists.txt`: tests of both.
- The binary that shipped before R16 (316,416 bytes, SHA-256 `aeb5de42...`) is byte-identical to a local
  build of that commit. `provenance.json` `shipped_binary` records the R19 build that replaced it.
- The origin has no licence file; this copy asserts or grants none. It is the same author's code as the
  add-on this part already ships.

## Build

```powershell
cmake -S rtx_bridge -B build -G "Visual Studio 17 2022" -A x64 -DADVMAT_RTX_BUILD_GMOD_MODULE=ON `
  -DGARRYSMOD_COMMON_INCLUDE_DIR=<garrysmod_common at a854f237>/include
cmake --build build --config Release        # -> build/Release/gmcl_advmat_rtx_bridge_win64.dll
ctest --test-dir build -C Release           # the writer's tests and the Lua boundary's
```

Needs only garrysmod_common's public headers (https://github.com/danielga/garrysmod_common,
`a854f237b79087826aa9a98a05de5e0d2b4502b6`, `include/`). `/W4 /WX /permissive- /EHsc`, C++17, links
`windowscodecs` and `ole32`. See `tools/ci/build_modules.ps1`.
