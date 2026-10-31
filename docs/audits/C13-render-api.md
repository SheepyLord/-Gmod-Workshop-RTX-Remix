# C13 render API audit

Snapshot date: **2026-10-31**. This durable copy separates the original static/API recommendations
from implementation and controlled runtime observations. [Compact provenance](C13-render-api.json)
contains source hashes, relative paths, URLs and confidence classes; it contains no game-source
bodies, private absolute paths or credentials. Full source snapshots stay in ignored evidence.

## Evidence and implementation boundary

The review records 17 API families and 43 primary URLs: 41 Facepunch wiki pages, Lua's manual and
Microsoft's SEH reference. Its 25 indexed call-site files are 12 stock/13 add-on files, alongside
the broader 228-file add-on inventory. Eight selected snapshots are available: three exact
archives and five author-linked repositories. The ledger's 17 unavailable selected sources are
QuickBloom/HDR plus 16 of the 22 collection members. Only FXAA and NikNaks have exact collection
archives; author-linked source availability does not prove current Workshop-byte identity.

| Layer | Implemented/measured path | Limits and pending work |
|---|---|---|
| Loader 0.10 backend | Process-only stock shaderapidx9 selection, preserving unrelated raw arguments, RTX-off behavior and exact W/A/PEB rollback | No DLL deletion or generic native-add-on ban; no arbitrary DX11 shader translation |
| Early client guard | Supported stock initializer view, after libraries/before autoruns; catalog-SHA-verified owner/V2 script, required early proof, executable redirect removed on activation fallback | Owned cache native-loader/presentation/render-guard-<sha>.lua. For selected gmod-rtx-remix, required stock/cache failure disables RTX after V2 verification; foreign preparation does no stock/cache reads, legacy V1 remains a nonfatal note |
| Reviewed Lua layer | Reserved-depth/MRT/depth-shader boundaries, recursion/cvar/callback checks and bounded cleanup/quarantine | Raw R32F27 is valid; cleanup preserves caller state, never mesh.Abort or assumed depth-zero/defaults; cached aliases/later overrides remain gaps |
| Controlled checks | Release 22 CTests/294 Python tests (7 skips), 17 guard cases/18 LuaJIT scenarios; final GMA SP, UI, corrupt-cache and secure dedicated acceptance pass | GPU tests remain local; earlier server autoruns and arbitrary native/GPU failures are outside the guarantee |

Fresh 0.9 controls load LifeMod defaults and RealCSM depth24/one controller on flatgrass, and
GShader/FXAA source inputs on flatgrass/construct. The original user failure is not reproduced.
Guarded construct-to-flatgrass transition loads both maps/exits zero. Combined2 confirms pinned
mat_hdr_level:SetInt blocking, one intentional HUD callback quarantine and restored RT state,
with normal/R32F targets working. CSM fallback is nonfatal; two rejected GShader autoruns still
appear in GMod reports. Successful map loading does not mean all shader effects work. RTX-off
loads/exits zero with no guard global, early redirect or RTX patches; vanilla verification passes.

The final remote-client test uses the existing native verified payload marker in a private
environment, explicitly updates _G.hook, and records later installation. A menu initializer read
hit alone did not prove client execution. Final acceptance is in the linked testing protocol.

The original body below describes a read-only audit phase. Its recommendations are **not** a
claim that every listed method has an implemented wrapper, or that every native/GPU fault is
recoverable. Current policy and acceptance are maintained in [ADR 0054](../decisions/0054-rtx-rendering-startup-boundaries.md)
and [the testing protocol](../TESTING.md#c13-graphics-add-ons-and-map-loading).

## Original read-only audit recommendations

The original 2026-10-31 static phase was a source/API audit, not a runtime pass. It used the official Facepunch wiki,
installed vanilla Lua under main/out/mpc/garrysmod, the exact cached LifeMod source and the
author-linked RealCSM/GShader repositories located by the independent source audit. No game, add-on code or native API was executed during that static phase. The [companion provenance](C13-render-api.json) binds inspected files to SHA-256 and records
URLs, evidence classes and gaps. Source IDs below resolve through that JSON.

## Findings that should drive implementation

1. Contain recoverable Lua errors separately from native fault prevention. pcall around addon
   loading does not protect a callback later invoked by the engine. A callback's own protected
   invocation can handle Lua errors, but does not establish recovery from native access violations,
   engine fatal errors, GPU faults or corrupted renderer state. The wiki expressly limits pcall
   for engine-invoked hooks; Lua's error protocol and Windows SEH are different mechanisms.
   [pcall](https://wiki.facepunch.com/gmod/Global.pcall),
   [Lua error handling](https://www.lua.org/manual/5.1/manual.html#2.7),
   [Microsoft SEH](https://learn.microsoft.com/en-us/cpp/cpp/structured-exception-handling-c-cpp?view=msvc-170).
2. The selected add-ons expose specific native resource/feature paths. RealCSM changes eight
   engine shadow targets to branch-specific depth formats and creates cascaded ProjectedTextures.
   GShader changes the shared resolved-depth format, requests DepthWrite, float targets and MRT,
   and replaces lighting globals/metatables. Neither a Lua exception wrapper nor generic finite
   argument checks prove these paths work on the current Remix/D3D backend. Prefer capability
   checks and narrowly scoped effect fallback before entering an unsupported native path.
3. Preserve stock API behavior. Vanilla frame blending uses -1/-1 dimensions with full-frame
   sizing. Stock stereoscopy performs two RenderView calls inside RenderScene. Stock toolgun
   code calls a custom DrawToolScreen while a parent RT/camera pair is already open. Blanket
   positive-dimension, one-view-per-frame, or reset-all-stacks rules would break legitimate code.
4. Preserve callback identity/return/self and state ownership. Stock hook.Call directly invokes
   callbacks, passes object IDs as self, and stops on the first non-nil result. A global guard must
   not turn an error into false when nil means continue, discard extra returns, or unwind a
   caller's RT/camera/model-matrix state. Captured aliases and later metatable replacements are
   explicit coverage gaps.

## Practical coverage matrix

Evidence labels: **crash** means the wiki explicitly names a crash; **contract** means a documented
limit/context/lifetime; **state** means a leak can affect following draws; **inference** is a
hardening recommendation rather than proof of a particular native fault. None means universally safe.

| API family | Primary contract / failure evidence | Concrete source exposure | Useful bounded guard / remaining limit |
|---|---|---|---|
| GetRenderTarget | **crash**: cubemap misuse; allocations persist to disconnect; names reuse targets. [API](https://wiki.facepunch.com/gmod/Global.GetRenderTarget) | V08:8 toolgun fixed 256 target; selected library effects use cached names | Check intended RT type/lifetime and bound new allocation growth. Do not manufacture unique RT names every frame or assume Lua GC frees VRAM. Cubemap misuse is a documented native-crash case. |
| GetRenderTargetEx / formats / size modes | **contract**: size/depth/texture/HDR/image-format arguments; additional formats can exist outside named enums. [API](https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx), [RT_SIZE](https://wiki.facepunch.com/gmod/Enums/RT_SIZE) | V05:62 uses -1,-1/full-frame/IMAGE_FORMAT_DEFAULT; S04:119-156 uses raw branch-specific formats 48/31 and RT_SIZE_LITERAL; S06:8-14 and S07:27-58 allocate depth/float targets | Validate by mode and backend capability, not one global positive/PO2/enum rule. Budget allocations; compare existing named targets. A fixed numeric image-format whitelist is incomplete. No unsupported-format native failure was executed here. |
| RT stack / SetRenderTarget / MRT | **state/contract**: Push stores RT+viewport, Pop restores; nil Push means main buffer; MRT indices 0..3, nil unbind supported, MSAA restriction. [Push](https://wiki.facepunch.com/gmod/render.PushRenderTarget), [Pop](https://wiki.facepunch.com/gmod/render.PopRenderTarget), [MRT](https://wiki.facepunch.com/gmod/render.SetRenderTargetEx) | V01:32-64 wraps ClearRenderTarget/CopyTexture; V08:51-72 owns a parent pair; S08:419-431 binds MRT slots 0/1 | Track only successful operations owned by the protected call and restore in reverse order. Preserve nil defaults and caller viewport. Error cleanup must not blindly Pop an unknown stack or replace an active MRT set with guessed defaults. |
| RenderView / nested scene work | **contract**: omitted view fields inherit current view; documented LOD/static-prop problems and RT-in-viewmodel flicker. [API](https://wiki.facepunch.com/gmod/render.RenderView), [RenderScene](https://wiki.facepunch.com/gmod/GM:RenderScene) | V04:30/35/45-52 legitimately performs two scene views; V07:200/228 does repeated DOF views; S06:48-59 comments on depth/CSM nested rendering | Per-invocation re-entry/depth and finite-view validation are reasonable **inferences**, not proof every nested RenderView crashes. Preserve ordinary sequential views and nil/current-view defaults. Avoid claiming the consulted RenderView page documents a universal recursion crash. |
| cam.Start/Start2D/Start3D, model matrices | **state/contract**: pair Start/End and Push/Pop; optional defaults are valid; zNear must be positive when supplied; Start3D2D has its own model matrix. [Start](https://wiki.facepunch.com/gmod/cam.Start), [Start3D](https://wiki.facepunch.com/gmod/cam.Start3D), [matrix](https://wiki.facepunch.com/gmod/cam.PushModelMatrix) | V01:106-139 constructs optional camera data and w/h aspect; V10:117-137 model panel; S02:41-47; LifeHUD:1087-1105 | Reject non-finite supplied values and impossible explicit viewports while preserving omitted fields. Track nested camera/matrix ownership. A Paint callback can be inside another context; generic End3D on failure can close its caller. |
| mesh.Begin/AdvanceVertex/End | **contract**: static IMesh limit 65,535 vertices; immediate dynamic limit 32,768; primitiveCount depends on primitive type; rebuilding cannot change stored vertex count. [Begin](https://wiki.facepunch.com/gmod/mesh.Begin), [Advance](https://wiki.facepunch.com/gmod/mesh.AdvanceVertex), [End](https://wiki.facepunch.com/gmod/mesh.End) | Installed RTX Water cl_splash.lua:177/629 and cl_surface.lua:336; GShader bump rebuilding in S11 | Validate complete vertex input and primitive-derived capacity before Begin. A blanket primitiveCount<=32768 is not a vertex bound. End renders/commits; no cancellation API was established in the consulted pages. Do not promise safe recovery from every half-written native builder by just calling End. |
| IMesh Build/Draw/Destroy | **contract**: BuildFromTriangles keeps original count, >65,535 can produce undefined rendering; Destroy frees storage; IsValid exists. [Build](https://wiki.facepunch.com/gmod/IMesh:BuildFromTriangles), [Draw](https://wiki.facepunch.com/gmod/IMesh:Draw), [Destroy](https://wiki.facepunch.com/gmod/IMesh:Destroy), [validity](https://wiki.facepunch.com/gmod/IMesh:IsValid) | GShader building meshes S11; installed water meshes cached/rebuilt | Own mesh lifetime, bound table/count/finite vertex data and chunk oversized batches. Do not infer safe destruction during an active builder, nor claim a destroyed draw's exact native behavior from these pages. |
| IMaterial/CreateMaterial/shader names | **contract**: names cache, CreateMaterial uses texture names rather than ITexture values; error material and missing shader are distinct checks; GetShader casing is unspecified. [Create](https://wiki.facepunch.com/gmod/Global.CreateMaterial), [IsError](https://wiki.facepunch.com/gmod/IMaterial:IsError), [shader](https://wiki.facepunch.com/gmod/IMaterial:GetShader) | S06:87 creates DepthWrite; S08 loads reconstruction materials; LifeMod effect modules load overlay/postprocess materials | Check material/error state and required shader capability before using the effect. A non-error material does not prove a custom shader is implemented by Remix. Never substitute arbitrary shaders while claiming visual parity. |
| ITexture lifetime/error/download | **contract**: checkerboard can be valid and IsError false; IsErrorTexture is the checkerboard check; Download reloads disk textures or clears RTs. [IsError](https://wiki.facepunch.com/gmod/ITexture:IsError), [checkerboard](https://wiki.facepunch.com/gmod/ITexture:IsErrorTexture), [Download](https://wiki.facepunch.com/gmod/ITexture:Download) | S06 reads the engine resolved-depth ITexture then reuses its name; S07 caches named targets | Validate intended object/type and availability without destroying shared contents. Do not call Download as a generic repair, or treat IsError=false as successful asset/feature verification. |
| ProjectedTexture create/update/remove | **contract**: client-side lifetime; Update applies pending values; FOV 0<fov<180; Remove invalidates object and object-ID hooks. [create](https://wiki.facepunch.com/gmod/Global.ProjectedTexture), [Update](https://wiki.facepunch.com/gmod/ProjectedTexture:Update), [FOV](https://wiki.facepunch.com/gmod/ProjectedTexture:SetFOV), [Remove](https://wiki.facepunch.com/gmod/ProjectedTexture:Remove) | S04:65-104 creates cascades/spread lamps, :1221-1227 sets near/far and updates; S09 replaces factory/metatable/remove | Check IsValid before use, finite projection parameters and controlled resource count; remove only owned lamps. Wiki does not establish a universal hardware-independent shadow count or guarantee allocation success. Preserve wrapper composition and object-ID semantics. |
| DynamicLight | **contract**: 32 dlights/64 elights; a retained reference can be repurposed by another light. [API](https://wiki.facepunch.com/gmod/Global.DynamicLight) | V11:65 allocates per entity; S10 captures C_DynamicLight and replaces light metatables/cache | Handle absent allocation, valid finite fields and reacquisition each update. Do not retain a native-backed light as permanent owned storage or assume one project's cache prevents engine reuse. |
| render.Override*, stencil, lighting, depth range | **state**: override affects subsequent draws; viewmodels use depth 0..0.1, so restoring 0..1 is not universal cleanup. [blend](https://wiki.facepunch.com/gmod/render.OverrideBlend), [depth override](https://wiki.facepunch.com/gmod/render.OverrideDepthEnable), [color write](https://wiki.facepunch.com/gmod/render.OverrideColorWriteEnable), [DepthRange](https://wiki.facepunch.com/gmod/render.DepthRange) | V09 halo.lua:60-136 nests stencil/lighting/IgnoreZ; S02 resets depth; custom tool screens run within V08's context | Snapshot observable caller state and track owned mutations; do not reset every setting to a stock constant after every callback. Some state has no read API established here: full recovery remains unproven. These pages describe state leaks, not proof every misuse is a native crash. |
| depth passes / resolved depth | **contract**: resolved SSAO depth updates when NeedsDepthPass is true and uses DepthWrite with a scene rerender. [getter](https://wiki.facepunch.com/gmod/render.GetResolvedFullFrameDepth), [hook](https://wiki.facepunch.com/gmod/GM:NeedsDepthPass) | S06 installs NeedsDepthPass, reallocates engine depth and creates DepthWrite; S08:374 reads it | Treat missing/incompatible depth/shader capability as an effect dependency, not a valid black texture to render indefinitely. Coordinate secondary views and depth work. The literal render.RenderDepth page was unavailable; no claim of that API's coverage is made. |
| model draws from Lua | **crash**: drawing the map model via Entity:DrawModel/render.Model is explicitly documented to crash; 3D context required. [DrawModel](https://wiki.facepunch.com/gmod/Entity:DrawModel), [render.Model](https://wiki.facepunch.com/gmod/render.Model) | V01:172-196 convenience helper creates/draws/removes model; V10:131 DrawModel; V09:79 entity halo draws | Reject map-model misuse before the native call and maintain valid entity/model/bones/context. A Lua wrapper cannot repair arbitrary model/native skinning faults; item24's specific native fix is separate. |
| hooks/timers/autorun callback boundaries | **contract**: pcall's dynamic extent only; engine hook errors are a documented limitation. [pcall](https://wiki.facepunch.com/gmod/Global.pcall), [hook.Call](https://wiki.facepunch.com/gmod/hook.Call), [timer.Create](https://wiki.facepunch.com/gmod/timer.Create) | V02:85-145 direct callback calls/object self/first-non-nil; V12 includes core libraries; S01:255-270 dispatches several LifeMod modules through one hook | Protect the callback itself, attribute errors, preserve returns/self and quarantine only the failing unit. Autorun load protection does not cover future timers/hooks. Native timer internals/autorun dispatch were not established by installed Lua source. |
| cvars.AddChangeCallback / asynchronous rebuilds | **contract**: callbacks have realm/flag exceptions; IDs pair with cvar names. [API](https://wiki.facepunch.com/gmod/cvars.AddChangeCallback) | V03:37-92 directly invokes callbacks; S08:214/315/443/457 installs rebuild callbacks; RealCSM schedules lightmap rebuilds via timers | Preserve callback name/old/new and ownership; validate changed values before native allocation/rebuild. A successful SetConVar or caught setter error does not prove a later engine/job callback is safe. Do not reset replicated/server/game cvars globally. |
| native/custom shader/DX backend requirements | **inference/capability gap**, not covered by Lua API range validation | GShader float/MRT/depth passes and external LUX/custom shader requirement; RealCSM branch-specific formats | Identify required shader/backend/DLL before enabling the effect. GetDXLevel or SupportsPixelShaders alone is not proof Remix implements all shaders/MRT/depth semantics. Do not auto-install a replacement shader API, change launch arguments or claim a universal compatibility layer from this audit. |

## Selected add-on source confidence and priority

| Item | What was actually inspected | Priority / unresolved gap |
|---|---|---|
| 2811767286 QuickBloom/HDR | Exact 429-byte source not yet available to this audit | Do not invent its code from title/size. Need exact cached payload or source capture, then inspect cvar/API calls and callback entry. |
| 1837527967 LifeMod | Exact cached source exported under addons/1837527967/source; S01-S03 | Module dispatcher means one broad hook quarantine could disable all modules. Depth/camera cleanup and engine cvar changes merit specific checks. No native failure reproduced. |
| 2817072898 RealCSM | Author-linked upstream commit 81cf47b8f90016f22b59b6aa9faae0134492040c; S04-S05 | Eight shadow-target format upgrades, projected lamp counts/spread and deferred rebuilds. Repository source is not proof of exact current Workshop bytes. |
| 3542644649 GShader Library | Author-linked upstream commit 512c666c560a890434436ce6f2ce2dedbb7dfe36; S06-S11 | Shared depth/MRT/float targets and early global/metatable wrappers are primary compatibility points. Exact current Workshop GMA is not established. |
| 3728139288 GShaders collection | All 22 child IDs enumerated in addons/collection-items.json. Exact FXAA source/VMTs inspected (3555378834, S12-S13); NikNaks cached sources are available but not reviewed here. Additional author-linked effect repos received a bounded call-site scan. | FXAA:85-119 uses screen texture/copy/full-screen draw and per-RT material caching; its VMT selects screenspace_general plus fxaa_ps30/vs30 programs. Library inspection and a single exact child are not coverage of every effect or backend. |

## Local source index

Vanilla and selected-source bases are identified by the logical source IDs below.
The JSON retains relative paths, file hashes, provenance and requested ranges.
Source bodies and private absolute paths are not included in this durable record.

| ID | Base | Source path / range |
|---|---|---|
| V01 | vanilla | lua/includes/extensions/client/render.lua:32-196 |
| V02 | vanilla | lua/includes/modules/hook.lua:85-145 |
| V03 | vanilla | lua/includes/modules/cvars.lua:37-92 |
| V04 | vanilla | lua/postprocess/stereoscopy.lua:10-52 |
| V05 | vanilla | lua/postprocess/frame_blend.lua:62 |
| V06 | vanilla | lua/postprocess/bloom.lua:25-75 |
| V07 | vanilla | lua/postprocess/super_dof.lua:174-250 |
| V08 | vanilla | gamemodes/sandbox/entities/weapons/gmod_tool/cl_viewscreen.lua:44-72 |
| V09 | vanilla | lua/includes/modules/halo.lua:41-136 |
| V10 | vanilla | lua/vgui/dmodelpanel.lua:103-140 |
| V11 | vanilla | gamemodes/sandbox/entities/entities/gmod_light.lua:58-79 |
| V12 | vanilla | lua/includes/init.lua:97-120 |
| S01 | selected | 1837527967/source/lua/lifemod/render/rendercore.lua:255-270 |
| S02 | selected | 1837527967/source/lua/lifemod/render/modules/dof.lua:31-50 |
| S03 | selected | 1837527967/source/lua/lifemod/render/modules/videodistortion.lua:152-226 |
| S04 | selected | 2817072898/upstream/lua/entities/edit_csm/cl_init.lua:65-156,1221-1227 |
| S05 | selected | 2817072898/upstream/lua/autorun/realcsm_client.lua |
| S06 | selected | 3542644649/upstream/lua/autorun/client/depthbuffer.lua:4-90 |
| S07 | selected | 3542644649/upstream/lua/autorun/client/worldpos.lua:27-58 |
| S08 | selected | 3542644649/upstream/lua/postprocess/shader_lib.lua:214-502 |
| S09 | selected | 3542644649/upstream/lua/autorun/!!projected_texture_wrapper.lua:19-84 |
| S10 | selected | 3542644649/upstream/lua/autorun/!!dynamic_light_wrapper.lua:62-97 |
| S11 | selected | 3542644649/upstream/lua/autorun/client/bumps_building.lua |
| S12 | selected | 3555378834/source/lua/postprocess/fxaa.lua:85-119 |
| S13 | selected | 3555378834/source/materials/pp/pp_fxaa_high.vmt |

## Specific false-positive tests to keep

- Preserve vanilla frame_blend's -1/-1 full-frame target and IMAGE_FORMAT_DEFAULT; preserve legal
  non-PO2 screen-sized modes and caller-selected raw format IDs when supported.
- Preserve two sequential stock stereoscopy RenderViews and super-DOF's multipass rendering.
  Per-callback recursion protection must distinguish nesting from ordinary repeated calls.
- Preserve nil PushRenderTarget/SetRenderTargetEx unbind, optional cam.Start3D arguments, and
  parent RT/camera pairs around a custom tool-screen callback.
- Preserve object-ID hook self, first non-nil override and all returned values; a Lua error must
  not silently become a meaningful false return. Preserve unaffected LifeMod modules.
- A synthetic Lua exception can verify callback containment/state bookkeeping; it cannot validate
  handling of a native access violation, GPU allocation failure, unsupported shader or driver loss.
- Before native mesh building, validate primitive-derived total vertices and complete input.
  Do not deliberately overrun native buffers as a hardening test.
- Install/reconcile guards before selected code captures originals, and test later replacement of
  factories/metatables. Runtime coverage of cached aliases remains partial unless measured.

## Original static-phase completion boundary

This pass covers the families above and concrete local call sites, not every Wiki method or
rendering add-on. It did not inspect engine implementations, reproduce a crash, allocate a GPU
resource, measure a driver limit, launch a game, or certify SEH continuation. Wiki constraints
can differ across game branches; the exact selected native DLL/shader/Workshop bytes and the
active Remix backend required separate implementation/live validation at that date. Source hashes
bind inspected inputs; they do not prove the scripts ran. Later measured checks are recorded above
and in the testing protocol, without retroactively certifying every recommendation or API.
