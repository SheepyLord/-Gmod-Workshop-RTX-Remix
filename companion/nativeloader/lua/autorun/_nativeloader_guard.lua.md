# _nativeloader_guard.lua

Self-contained client RTX guard, identified by NATIVELOADER_RENDER_GUARD_V2. The loader embeds
this exact catalog-SHA-verified file after the supported stock initializer, before autoruns.
No include/require or additional runtime module is needed. The new content hash selects a new
generated cache automatically. NativeLoaderRenderGuard.version=2 makes installation idempotent.
R8 policy: [ADR 0086](../../../../docs/decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md);
[source audit](../../../../docs/audits/R8-C-addon-compat.md).

## Inputs and installation

- The generated initializer's __NATIVELOADER_RTX_GUARD_EARLY flag and local cache existence proof
  give installation="early". The local loader's DATA native-loader/status.json must report active
  RTX, preventing a listen host's served initializer/autorun from enabling the guard on vanilla clients.
- An active local start without the early view installs at ordinary autorun, installation="autorun".
- The verified native multiplayer bootstrap's raw marker in a private environment gives
  installation="verified multiplayer bootstrap". It can run after remote server autoruns. Global
  or inherited markers do not authorize installation. This route uses the real _G hook table.
- SERVER/MENU_DLL and RTX-off starts return without mutation or AddCSLuaFile. No native catalog API
  is exposed/consulted by this file. Status-file proof is an accident check, not a security boundary.

Read cfg/nativeloader_session.cfg for declared session pins. The saved nativeloader_guard convar
(default 1) delegates future calls/callbacks to originals at zero. A fresh RTX-off session restores
normal add-on setup; toggling the guard cannot recreate resources skipped earlier in that Lua state.

## Non-throwing capability policy

A deliberate refusal reports one bounded console note and returns safely. It never calls error,
ErrorNoHaltWithStack or callback quarantine. Actual add-on/native API Lua errors are separate.

| Request | Fallback under RTX |
|---|---|
| Invalid, oversized, unreviewed-format, cubemap, effect-owned or reserved shadow RT creation | Shared lazily created 1x1 RGBA8, depth-none engine ITexture; callers can use Width/Height/GetName normally |
| Exact reserved _rt_resolvedfullframedepth name (case/extension normalized) | Source's own getter texture; no recreation/reconfiguration |
| Allocator Lua error while creating the inert target | Reuse an engine screen-effect texture if available; not recovery from OOM/native/GPU failure |
| DepthWrite, screenspace_general families, LUX families, custom pixel/vertex programs | Shared transparent UnlitGeneric engine IMaterial; its mutators are ignored |
| Unsupported copy, MRT bind, material mutation, renderer reload, recursive/invalid view | No values, no native dispatch |
| Audited rendering/reconstruction/world-building callbacks | Inert; Initialize and API-definition hooks can finish |
| NeedsDepthPass | False, including filtered registrations reached by cached dispatchers |

Supported color IDs are -1,0,1,2,3,4,11,12,16,24,25,27; raw R32F27 is an explicit MMDHL control.
The stock size modes 0-9 and depth modes 0-3 are numeric policy constants, independent of later
add-on enum exports. Depth-only mode 3 is refused. Fractional dimensions follow native truncation;
full-frame/HDR modes preserve -1/-1. Rounded-up frame buffers are budgeted at rounded-up dimensions.
Bounds: 16,384 per axis, 64 Mi pixels, estimated 128 MiB color bytes per new target, 128 names and
512 MiB per virtual source file, 1 GiB total tracked Lua allocations. Canonical cache-name reuse
counts once. These estimates omit depth buffers/driver overhead/native allocations; they are not
measured VRAM availability. Exhaustion gets the same shared fallback, never another named target.

Known effect-origin Material calls return the inert material before any native/disk lookup, even
when a remote VMT is opaque. Other Material preflight reads GAME materials/*.vmt without executing
code, strips comments/BOM,
checks shader/custom programs and follows at most eight Patch includes. Cycles, unreadable includes
and unparseable/oversized VMTs become inert before native Material. Missing root files preserve
native virtual/image/cached lookup; shaders visible only after that lookup are suppressed on return
and binding. Native preloads and opaque lookups remain a load-time gap.

Depth/inert textures cannot be bound or copied. Non-nil MRT slots 1-3 are refused, so mismatched MRT
attachments never reach native. Valid slot zero, nil MRT clears, normal color copies and fresh
color targets pass. Suppress incompatible render/surface draws rather than drawing a black overlay
or accidentally drawing with the previously bound material. Unsupported world/brush/entity
material overrides/mutations are ignored; normal material setters and UI drawing remain usable.

The audited GShader, FXAA, SSDO and SSR virtual source paths identify effect callbacks. Life Mod
module-origin APIs are also filtered because its own dispatcher invokes methods directly. GShader's
world/mesh builds and Real CSM's raster shadow Update/enable work are inert. Normal NikNaks color
atlases and ordinary projected lights pass. The two GShader lighting wrappers receive private
FindMetaTable/debug metatable copies with per-object readback, preventing shared native __index
nesting and cached-light resets from editing native tables. Source labels are compatibility policy,
not trusted identity; renamed code needs fresh evidence.

## Session pins and stock helpers

RunConsoleCommand, Player:ConCommand, game.ConsoleCommand and typed ConVar setters enforce pins.
DX/HDR, r_flashlightdepthres, mat_antialias, mat_aaquality and mat_disable_d3d9ex keep the declared
session value or captured native value. The critical pins have no source-name exemption.
Quick Bloom's two raster bloom writes and Real CSM's competing raster-world lighting writes are
ignored. Existing noncritical source exemptions and motion-blur read compatibility remain.

Quoted command chains, newlines, toggle/incrementvar/multvar/cycle, alias/bind payloads (four levels)
and embedded NUL are checked before native dispatch. Renderer/video reloads require a fresh RTX
session. Interactive native console writes, existing native aliases and exec-file bodies are outside
this interception. Existing stock DrawBloom/ColorModify/Sharpen/MotionBlur/ToyTown/MaterialOverlay/
Sobel/Sunbeams/Texturize/BokehDOF and halo.Render remain suppressed; Initialize catches late definitions.
Ordinary drawing is not globally disabled.

## Callback and scope behavior

Early/autorun routes contain selected loading/render/UI callbacks through hook.Call. Unrelated hooks
keep registry identity, object self, arguments and first non-nil/six hook returns. The late multiplayer
route contains only callbacks from owned private environments; unrelated server callbacks retain
identity and vanilla errors. The separate capability filter wraps only known effects and depth
registrations, including existing entries/new hook.Add, timers and cvar callbacks. Thus a cached
original hook.Call still invokes those policy refusals. This is the narrow ADR 0086 exception to
ADR 0056's server-callback identity rule; it adds no general server-error containment.

Actual failures print original errors/stacks at most once per callback every ten seconds with a
suppressed count. Three consecutive failures within ten seconds quarantine hooks/timers/cvar
callbacks; success resets the streak. Gamemode methods never quarantine. Re-registering a different
function recovers the callback. Per-category records cap at 128; refusal flooding cannot hide errors.

Only observed Lua RT/camera/clip/model pushes are tracked. Ignored pushes create virtual scopes;
their matching pops do not consume caller-owned native scopes. Repeated virtual pushes share a
counter. A callback cannot pop an active ancestor's/unowned caller's state. Completed Pre/Post
balancing remains legal. Real-error cleanup unwinds only extra known owned scopes and restores
known direct target changes; successful children contribute their chronological actions. Never call
mesh.End as an abort, guess depth zero, or restore arbitrary camera/clip/matrix state. FrameNumber
(or top-level PreRender) forgets stale unowned bookkeeping without native pops. Only live callback
chains count toward the 32-native-scope limit. Sequential stereo RenderView calls pass; nested views
stop at four, and effect-origin views are inert.

## Outputs, side effects and verification

NativeLoaderRenderGuard reports policy, installation, enabled state, blocked/errors/cleanup_errors,
allocations_by_source, allocation_bytes_by_source and allocation_bytes. Notes contain virtual source
locations, one per API/call site, capped at 128 per category; no private paths or exception bodies
enter guard records. Real exception text goes only to the engine error output. APIs/convars/hooks
change in this Lua state. There are no file/config writes, network operations or Steam changes.
This autorun has no process exit code.

[The LuaJIT harness](../../../../tools/tests/render_guard_harness.lua.md) executes this complete
production file with fake engine functions. [R8 call replays](../../../../tools/tests/render_guard_addon_replays.lua.md)
use original minimal snippets reproducing eight add-ons' calls, never third-party add-on code.
Forty unittest methods invoke 43 scenarios (18 added for R8). They prove CPU policy/contract behavior,
not a GPU/native-fault fix. Foreign remote initializers, earlier native aliases, later API overrides,
direct registry mutations, unknown shaders, native modules, infinite loops and driver failures
remain explicit limits. See Claude's QA procedure in the R8-C report after integration.
