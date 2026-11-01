# R8-C: graphics add-on compatibility, second audit

2026-11-01. Extends the [C13 audit](C13-render-api.md); its historical acceptance is not R8
acceptance. [Source ledger](R8-C-addon-compat.json), [brief](../handover/R8-C-addon-compat.md),
[policy](../decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md).

## Evidence

Claude's read-only `out/qa-poc/r8/07-gshader/console.log` loads gm_construct and exits normally.
It contains a guard-created error at `bumps_building.lua:35` (CreateMaterial), then another at
`worldpos.lua:27` (GetRenderTargetEx), dispatched by `!!shaderlib.lua:800` during Initialize.
The latter stops the add-on's initialization. There are 26 `Failed to create shader` lines;
their relationship to the tester's crash is not established. The crash itself was not reproduced.

The new inventory indexes **86 Lua/VMT files and 856 candidate API lines** across eight exact
installed Workshop archives: Life Mod 1837527967, Quick Bloom 2811767286, Real CSM 2817072898,
NikNaks 2861839844, GShader 3542644649, FXAA 3555378834, SSR 3586554495 and SSDO 3707449642.
Every indexed file's SHA-256 and archive-entry CRC matches the inspected source. This is a static
call inventory (including comments and examples), not 856 executed tests or an exhaustive call graph.
The ledger includes archive hashes and no third-party source bodies. Analysis copies are in this
worktree's ignored `out/r8-compat/src`; the provided main-checkout snapshots and Steam files were
read only. No add-on code or game was executed. The other collection members remain unreviewed.

Life Mod's installed legacy.bin has a raw-LZMA stream without an end marker. Bounded analysis
decoding produces seven extra non-archive bytes; exactly the header-declared 8,262,218 bytes have
the correct aggregate GMA CRC `374141b9` and all 98 entry CRCs. Only that verified analysis copy
was extracted. No change to the repository's strict archive reader or installed file is needed.

## Risk and boundary matrix

These are native-resource/state risks and documented capability conflicts, **not identified causes
of the tester's crash**. Lua exception containment cannot catch device loss or a native fault.

| Path in the exact source | Risk or observed failure | R8 boundary |
|---|---|---|
| GShader `!!shaderlib.lua:44-127`, `worldpos.lua:27-58`; SSDO `postprocess/ssdo.lua:194` | Add-on-defined enum values appear after the early snapshot. Raw 29 is a real Source format, not inherently an unknown/invalid number. RGB32F28, R16F38, depth/INTZ/NULL and branch-dependent IDs cannot be accepted merely because a Lua global names them. Some formats depend on D3D9Ex, which this package disables. | Reviewed color-format subset; all other formats use one small RGBA8 target. GShader/effect targets use that inert target regardless of format. Preserve supported raw R32F27 for MMDHL. |
| GShader `depthbuffer.lua:8-14,72-90`; Real CSM `entities/edit_csm/cl_init.lua:125-155` | Reconfiguring shared resolved-depth or eight live shadow targets changes resources used by the engine. A pcall does not contain a native resource failure. | No Lua recreation of reserved names. Exact resolved-depth requests return Source's getter texture; other reserved requests return the shared target. No depth-only allocation. |
| GShader `worldpos.lua:113-116,223-255`, `postprocess/shader_lib.lua:374-431`; FXAA/SSDO/SSR quads and copies | MRT resources can differ in size/format. Copying color into depth is not a depth-copy API. Custom ps30 draws can fail shader creation and overwrite the path-traced image. | No non-nil bindings to MRT slots 1-3. Depth/inert sources or destinations cannot be bound/copied. Rendering callbacks, effect copies and draws are inert. Nil MRT clears and ordinary slot-zero restoration pass. |
| GShader `materials/pp/*`, `materials/bumps/*`; FXAA/SSDO/SSR VMTs | Custom shader drawing can fail or overwrite RTX output. A load-only crash is not established, and native reading is required by the package's PBR conversion and hotloader. | Keep Material/CreateMaterial native. Inspect cached native shader/program metadata when untrusted callers bind; use the transparent fallback for incompatible bindings. Exact bundled callers keep material behavior. No VMT/Patch disk preflight; identical virtual-path collisions can bypass the compatibility exemption (ADR 0086). |
| GShader `bumps_building.lua:35-70,317-335,452-484`, `lightmaps_building.lua:21,531-608` | World-mesh/material reconstruction and replacement textures can corrupt the captured world or allocate persistent large atlases. | Skip these rendering/build callbacks, including timers; refuse effect-origin material mutations and entity replacements. Do not mutate the shared fallback material. Normal NikNaks color-atlas helpers remain usable. |
| GShader `!!projected_texture_wrapper.lua:19-52`, `!!dynamic_light_wrapper.lua:66-92` | The PT wrapper repeatedly nests a shared __index. Replacing native light metatables, or resetting the wrong cached native __index table, changes behavior for unrelated lights. | Give these exact wrapper sources private metatable copies and per-object readback; never replace the native metatable. Ordinary light callers still receive native objects. |
| Real CSM `cl_init.lua:51-119,644-669,699-748,1058-1084` and `realcsm/*` | Spread lamps multiply raster shadow work; deferred lightmap rebuilds and world-lighting cvar changes compete with RTX. This is a stability/performance risk, not a measured hardware fault. | Real CSM shadow-enable/Update calls and its raster-world lighting writes are inert. Keep native projector handles and harmless parameter setters. Pin depth resolution and renderer reconfiguration cvars to the RTX session. |
| Life Mod `render/modules/dof.lua:31-50`, `videodistortion.lua:152-226`, `rendercore.lua:255-270` | One module dispatcher shares hooks; generic quarantine can disable unrelated modules. Direct module calls still reach depth-range, sprite, copy and surface APIs. | Module-origin effects and render-state changes are inert at the API boundary too; retain the general dispatcher and normal UI. Stock PostFX functions stay suppressed. |
| Quick Bloom `autorun/client/cl_bloom_config.lua:1-5` | Exact source only writes mat_bloomscale=0 and mat_bloom_scalefactor_scalar=0.2 in Initialize. No RT/shader/native payload. | Ignore those raster bloom writes under RTX; Initialize continues. Do not invent a native-crash explanation for this payload. |
| Any RT allocation / nested view | Invalid, zero, nonfinite or huge resources; persistent names can consume memory; recursive views can reenter native rendering. | Bounded dimensions, names and estimated bytes; shared fallback without error. Four nested views, sequential stereo views allowed. Effect-origin RenderView is inert. Ignored pushes have ignored matching pops. |

## Primary contracts rechecked

- [GetRenderTargetEx](https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx) and
  [IMAGE_FORMAT](https://wiki.facepunch.com/gmod/Enums/IMAGE_FORMAT): the exported globals are not
  exhaustive; additional raw formats exist. Existence is separate from support on this backend.
- [MRT](https://wiki.facepunch.com/gmod/render.SetRenderTargetEx): slots 0-3, no MSAA; a custom
  DrawQuad is used for MRT rather than stock DrawScreenQuad.
- [CopyRenderTargetToTexture](https://wiki.facepunch.com/gmod/render.CopyRenderTargetToTexture):
  copies the active color target, not its depth buffer.
- [IMaterial](https://wiki.facepunch.com/gmod/IMaterial): SetShader is currently a removed/no-op
  feature after crashes. Its optional guard is defense for older/custom implementations, not a
  claim that today's vanilla setter switches shaders.
- [Projected shadows](https://wiki.facepunch.com/gmod/ProjectedTexture%3ASetEnableShadows): the
  normal shadow count is eight and more shadowed lights cost frame time.
- [LUX's own instructions](https://github.com/Akabenko/LUX-Gmod-shaderapidx11/): it requires an
  alternate DX11 backend. The existing process-only D3D9 selection remains; Lua does not port it.

## Limits

The policy requires guard installation. The existing catalog-verified generated initializer
embeds this entire self-contained file; a changed guard hash creates a new cache name automatically.
It protects supported local starts and matching listen-host/client initializer views before
autoruns. A foreign server initializer can bypass that view, leaving the existing verified
multiplayer bootstrap later than server autoruns. Older captured native aliases, overwritten
APIs, direct registry writes, material preloads outside Lua, unknown custom shader names/backends,
native modules, loops, driver faults and GPU failures remain outside a universal guarantee.
Capability filtering of known effect/depth callbacks also applies to server-delivered Lua once
installed; it does not add general exception containment to remote server callbacks.
