# build_managed_texture_probe.ps1

Build-only wrapper for `managed_texture_probe.cpp`, an isolated Windows x64 GPU API regression.

`tools/qa/build_managed_texture_probe.ps1 -RuntimeSource out/runtime-src` uses MSVC and the
recorded runtime source's `public/include/remix/remix_c.h` (API 0.1000.1). All output/compiler
scratch goes to `out/r12-vram/gpu-probe`; the caller's environment is restored. No game or GPU
is launched by the build. Requires VS Build Tools/Windows SDK and a prepared runtime source tree.
Exit 0 success, nonzero compile failure.

The host takes two absolute arguments: the built runtime `d3d9.dll` and its dependency directory
(for this checkout, `out/inputs/runtime/files`). It creates a never-shown 64×64 window/device and
four 1024-square managed textures. Metadata, surface access, LOD and CPU read/write operations
must allocate no GPU image with deferral enabled. Explicit `PreLoad` and first draw must allocate,
produce the same original Remix texture hash, sample the requested mip's exact RGB value and
refresh the hash after a partial CPU write. Default-pool allocation stays eager; system memory
stays unbacked. Unwritten managed images keep zero initialization; managed cubes remain eager,
and invalid managed/dynamic combinations remain invalid. The host prints exact integer byte
deltas, hashes and a sampled pixel as JSON, then explicitly shuts down its registered Remix objects.

An optional third `game` argument uses the known runtime's standard `Direct3DCreate9` and
`CreateDevice` path, including draw-call conversion, instead of the API's editor-oriented factory.
Compare eager/deferred outputs in both modes. The standard interfaces are registered only with
the loaded known runtime, whose objects implement the extended interfaces internally.

Run twice with `DXVK_DEFER_MANAGED_TEXTURES=0` / `1`, `DXVK_ENABLE_RAYTRACING=0`, and a local
`DXVK_CONFIG_FILE` containing `rtx.recomputeTextureHashOnWrite = True`. Compare both outputs'
hashes/pixels exactly. Set TEMP/TMP, DXVK_LOG_PATH and the working directory inside `out/`.
The runtime also places its own caches beside this test executable, inside `out/`.
Follow the field activity gate before either GPU run. This host does not use a game install,
PoC files, Steam or an interactive window. No native payload or trust setting is changed.
