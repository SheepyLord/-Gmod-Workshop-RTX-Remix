# build_managed_texture_probe.ps1

Build-only wrapper for `managed_texture_probe.cpp`, an isolated Windows x64 GPU API regression.

`tools/qa/build_managed_texture_probe.ps1 -RuntimeSource out/runtime-src [-Out <folder>]` uses MSVC
and the recorded runtime source's `public/include/remix/remix_c.h` (API 0.1000.1). All
output/compiler scratch goes to `-Out` (default `out/r12-vram/gpu-probe`); the caller's environment
is restored. No game or GPU is launched by the build. Requires VS Build Tools/Windows SDK and a
prepared runtime source tree. Exit 0 success, nonzero compile failure.

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
End a running field game before either GPU run (the field game is a test session: the user,
2026-11-02). This host does not use a game install,
PoC files, Steam or an interactive window. No native payload or trust setting is changed.

## R13 sequence (`r13` as the third argument)

R13-B ([ADR 0100](../../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)): one copy
of each managed texture and idle image release, on the game's standard device path. Four
4096-square managed A8R8G8B8 textures (full mip chains, a different per-texel pattern each, so a hash or
a read-back notices any lost byte) are filled, drawn once (upload and hash), then left idle while the
host presents once a second, which runs the runtime's managed texture passes. The host then checks,
with exact equality:

- the hash of every texture while it was idle (its CPU copy and/or image released);
- every texel of mips 0 and 3 and of another texture through read-only locks (the read-back);
- the pixels and hash after the next draw (the re-upload);
- a rewrite of the center of mip 0 after the copies went: the drawn pixel and a refreshed hash, and
  every texel of the rewritten mip;
- release again, a device `Reset` while released, then pixels, hashes and an untouched mip.

It prints one JSON line: the hashes, the pixels and sampled texel, and memory deltas: the process's
private bytes, its committed read-write and write-combined private address space, and the runtime's
app-texture bytes, after the first use, while idle and after the re-use.

Run it against the original runtime and the new one with each option, through the environment:
`DXVK_RELEASE_MANAGED_HOST_COPIES` and `DXVK_MANAGED_TEXTURE_BUDGET_MIB` (for example 1 MiB, so the
images go), with `DXVK_MANAGED_TEXTURE_IDLE_SECONDS=0` and `DXVK_MANAGED_HOST_COPY_IDLE_SECONDS=0`, besides
the settings above. Hashes, pixels and the sampled texel must be identical in every run; the memory
deltas show what each option released. `R13_PROBE_CENSUS=1` (with `RTX_PROFILER_MEMORY_ENABLE=1`) also
writes the runtime's host memory census of the idle state to its log
([host_memory_census.py](host_memory_census.py.md)).
