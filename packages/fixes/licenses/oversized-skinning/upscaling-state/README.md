# Live upscaling readback (R20-E)

Validated build: **5,515,264 bytes**, SHA-256
`53da14f9269f042869510fe8be56b8b055263acd7c80a54d3e6178dbbfa94e73`, source tree
`68b5778182983e59c2d5491699cd7f0996bcd0d1`. Built with the unchanged pinned module script using
a temporary drive alias into this worktree's `out` to avoid premake's `!` path bug. Live RTX 5090
edits and older-runtime nil fallback passed, then the module was imported once with `tools/inputs.py`.
The [R20-E report](../../../../../docs/handover/R20-E-report.md) records exact PoC restoration.

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[upscaling-state.patch](upscaling-state.patch) is the sixth native patch after the public base and
the five patches recorded in [pins.json](../../../../../tools/ci/pins.json). It adds
`RemixConfig.GetUpscalingState()` without changing the existing disk-only `GetConfigVariable`.

The complete changed files are [config_lua_bindings.cpp](source/remixapi/config_lua_bindings.cpp)
and [upscaling_state.h](source/remixapi/upscaling_state.h). The latter validates the versioned,
atomic `rtx.runtime.upscalingState` value through the loaded runtime's existing
`remixapi_GetGameValue` export. A missing export/key, API failure, wrong length, missing terminator,
unknown version or invalid field returns Lua `nil`. A valid result creates a new table with `ready`,
`upscaler`, `frame_generation`, `dlss_supported`, `dlss_frame_generation_supported` and
`fsr_frame_generation_supported` in the types R20-B requires. No settings are saved or written.

Build with [build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md) `-Only fixes` using the
pinned dependencies. `fixes.patched_tree` checks every native input after this patch. The module
continues to work with the currently packaged older runtime and returns `nil` there; runtime patch
0040 supplies the readback once the integration build imports it. See
[ADR 0123](../../../../../docs/decisions/0123-live-upscaling-readback.md).

[upscaling_state_test.cpp](tests/upscaling_state_test.cpp) compiles against the production header
without a game SDK; [the aggregate test](../../../../../tools/tests/test_upscaling_readback.py.md)
runs it in the Release gate. Build identity and PoC evidence are recorded in the R20-E handover.
