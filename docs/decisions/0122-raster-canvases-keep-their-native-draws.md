# 0122: Offscreen raster canvases keep their native draws before RTX-only filtering

- Status: Accepted 2026-11-06
- Decided by: Codex under the user's autonomous R20-D brief (item 44)

## Context

Physics Blood paints pools into float scratch targets and RGBA atlas pages using ordinary
Source materials, alpha-only write masks and destination-dependent blending. The runtime
rejected draws without all RGB channels enabled before recognizing a non-primary render target.
That erased the intermediate alpha fields even though these canvases should be rasterized.
The post-injection skip could also discard later offscreen updates. The Lua guard allowed the
operations; relaxing its resource policy would not fix these runtime omissions.

## Decision

In D3D9 draw preparation, recognize an offscreen color target before both the post-injection
shortcut and the ray-tracing-only draw filters. Return PreserveDrawCallAndItsState for that
target, retaining D3D9's blend equations, color/alpha write masks and shader execution. The
runtime's explicit ray-traced render-target category keeps precedence. Reuse its existing
primary-target dimensions test and resolution-environment exception; do not introduce a new
guess about which engine target is the main scene.

## Consequences

Alpha-mask canvases can be built during world-render callbacks and after main-scene injection.
The resulting texture is sampled by the path tracer when used on scene geometry. This does not
turn the canvas itself into a ray-traced scene. Primary draws and explicitly tagged portal
targets retain their prior classification. Equal-sized offscreen and primary targets remain
ambiguous under the runtime's existing size heuristic; a future target-identity change needs
separate evidence. The Lua guard's format, MRT, depth, shader and memory limits remain intact.

## Native camera modes (supersedes part of 0120)

The PoC client.dll (SHA-256 c994603b24197396d83315eb685ebdda0a5437aa30a3ea3c5091599b4fb66e9c)
contains separate C functions for End (0x1800bc2c0) and End3D (0x1800bc200), both decrementing
counter 0x1808fb59c. End2D (0x1800bbff0) uses 0x1808fb598, End3D2D (0x1800bc0e0) uses
0x1808fb5a0, and EndOrthoView (0x1800bc380) uses 0x1808fb5a4. This is static native evidence,
supported by the live mode-mismatch errors, not an assumption from Lua function identity.
Complete REA/Ghidra evidence is exported under out/r20d/camera-native-evidence.json.

The guard therefore shares 3D scopes only between End and End3D, tracks Start2D with End2D,
and chooses generic Start's family and cleanup from its type (the native implementation tests
whether the type string starts with 2). Start3D2D is an opaque matrix-paint scope with its own
counter, not an ordinary camera alias. StartOrthoView/EndOrthoView are tracked when exported.
Wrong-mode closers return without native dispatch; the proper closer still works. Successful
ordinary aliases have no refusal. Cleanup uses the actual mode's original closer.

## Premultiplied transmission filters

The heavy Physics Blood scene also exposed a legitimate blend equation absent from the runtime:
Dst * (Src + 1 - SrcAlpha), with premultiplied transmission in Src. Treating it as unsupported
opaque rendering draws the texture's zero-color, zero-alpha background as a black rectangle.
Translate that native blend pair to a private legacy blend value (11, within the existing four
GPU bits), keeping the authored MDL/UI range 0..10 unchanged. The common opacity evaluator uses
clamp(alpha - luminance(premultipliedColor), 0, 1), so an empty background and a neutral filter
are transparent. This is the runtime's scalar-luminance approximation of colored transmission.
Authored alpha state still takes precedence; no global cutoff or material file is changed.

Changing vertex colors/alpha and render-target canvases must not reuse a static opacity mask.
The transient legacy-effect category therefore disables opacity micromaps for those draws, and
this filter mode is independently ineligible for micromaps. Primary, visibility and indirect
rays all use the same opacity evaluator. A shared CPU/GPU helper is checked against the native
destination factor at sixteen coverage/transmission combinations, plus saturation boundaries.

## Raster model preview materials

Removing the camera underflow alone leaves the saved icon's lit-model pass black under the DX7
RTX session. A live experiment found that lighting modes and depth overrides did not fix it,
while a plain UnlitGeneric material retaining the model's base texture did. Keep that fallback
inside suppressed-lighting PostRender previews, using studio overrides rather than mutating
entities. Preserve explicit caller overrides and restore original override state on normal return or
error. The fallback is a flat representative-map thumbnail; authored alpha/cull/shader fidelity is
not promised for this preview, and world materials are unchanged. Bound the material cache and number of slots. Catch late helper definitions
at startup and retain a callback's suppression request when a helper resets the global flag.
This is a flat texture preview, not a change to world/path-traced materials or saved configurations.

Preview implementation follow-up: weak Lua material keys were not stable across native lookups and
spent the material budget during the many outline draws. Cache by stable material/texture identity.
The DX7 studio path still lights indexed/submaterial overrides black, so use a representative base
map via the working global unlit override. Existing caller overrides are left alone; original
entity submaterials never change. This prioritizes a readable thumbnail over exact multi-material
or custom-shader fidelity, and remains confined to preview callbacks.
