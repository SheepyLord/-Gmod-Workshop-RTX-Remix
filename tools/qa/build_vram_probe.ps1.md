# build_vram_probe.ps1

`tools/qa/build_vram_probe.ps1` compiles `vram_probe.cpp` with the repo's MSVC environment and
vendored Garry's Mod Lua interface. Output and compiler scratch: `out/r12-vram/probe/`.
Requires Windows x64, VS Build Tools, Windows SDK. Exit 0 on success, nonzero on a compiler error.
Restores the caller's environment; installs nothing and changes no package/native allowlist.

The DLL is an **explicit local QA instrument**, never a package payload. Under the PoC lock, back
up any same-named file before installing it as `garrysmod/lua/bin/gmcl_nlvramprobe_win64.dll`.
Run an insecure PoC session and `require("nlvramprobe")`, then `NLVramProbe.Begin()`. After two
rendered frames `NLVramProbe.Read()` returns Source's already loaded texture debug records, with
their engine-provided names, format, dimensions, group, binds and size fields. Call
`NLVramProbe.End()` afterwards; restore/remove the QA DLL at the end of the lock hold.

It reads `shaderapidx9.dll`'s `DebugTextureInfo001` and the Win64 Source KeyValues ABI, resolving
symbols through `vstdlib.dll!KeyValuesSystem`. Missing interfaces or a different shader build
return unavailable, before enabling collection. If Remix's
render path does not build the public list, it can read the shader's existing host texture registry
on **only** the stock shader DLL with SHA-256
`7534cd56738f3f729dab0b88fce7f5fa224898fc15c28021762f3352643f8ca9` and all six matching debug
vtable RVAs. Private field offsets and pooled-name/format getters were checked against that shipped
artifact. The fallback uses `ReadProcessMemory` on its own process, detects cycles/read failures,
bounds traversal, and rejects a changed head/frame. It does not find a texture or load one. Output
records identify `SnapshotMode=pinned_shader_registry`; the public list's three extra back/depth
surface records are absent in that mode. This is an approximate settled-frame host observation,
not a GPU fence or a measurement of physical residency. Unsupported engine builds never use
the private fallback. `Info()` returns method RVAs and pin status for evidence.

An engine ABI change requires revalidation before use. Collection temporarily enables the engine's debug
texture list/all-texture mode and disables both on End/module close. Do not use it while another
texture-debugging tool is collecting. It does not find/load a material or texture, change rendering,
write a file, free an engine object or call the GPU. Source `Size` fields are byte estimates, distinct from
DXVK's device-local allocations. It is not used in the user's field process or install.
