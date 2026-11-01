# 0086: Inert shader effects and non-throwing render guard fallbacks

- Status: Accepted 2026-11-01
- Decided by: the user's R8-C brief, with implementation choices delegated to Codex and Claude
- Amends: [0054](0054-rtx-rendering-startup-boundaries.md) and
  [0056](0056-guard-and-startup-fallbacks.md), only the incompatibility response and capability policy

## Context

The [R8 audit](../audits/R8-C-addon-compat.md) binds eight exact Workshop sources to their hashes.
Claude's PoC loads/exits normally but shows guard-created errors that interrupt GShader setup,
plus failed shader creations. The tester's native crash is not reproduced. Recoverable Lua
containment is separate from preventing unsupported native/GPU work.

## Decision

1. **Refusals return; they never raise a guard-created Lua error.** Invalid or unsupported target
   requests return one lazily created 1x1 RGBA8, depth-none engine ITexture. Exact reserved
   resolved-depth requests return Source's existing getter texture; other reserved names get the
   inert target. Unsupported materials return one transparent engine UnlitGeneric IMaterial.
   Unsupported state changes, copies, MRT binds, reloads and views return no values. Add-on
   initialization can continue. Real add-on errors still follow ADR 0056's reporting/quarantine.
2. **GShader-style screen-space shaders are inert under RTX by default.** No ps30/DX11 translation
   or visual parity is promised. Keep add-ons installed. Refuse DepthWrite, screenspace_general
   families, LUX shader families and custom vertex/pixel programs; preflight VMTs and bounded Patch
   includes before native loading. Skip the audited GShader/FXAA/SSDO/SSR reconstruction/render/build
   callbacks and Life Mod module effects. Initialization and ordinary UI remain available.
   Known module-origin direct native calls are filtered too. An RTX-off launch installs no guard;
   nativeloader_guard=0 delegates future calls, but restoring effects already initialized with
   fallback resources requires a fresh RTX-off session.
3. **Treat resources by backend capability, not exported enum membership.** Permit reviewed color
   IDs -1,0,1,2,3,4,11,12,16,24,25,27. Raw R32F27 stays a supported MMDHL control. Other formats,
   depth-only targets and cubemaps receive the fallback. Bounds are 16,384 per axis/64 Mi pixels,
   128 MiB estimated color bytes per allocation, 128 names/512 MiB per virtual source file and
   1 GiB across tracked Lua allocations. Cache-name reuse is counted once. These conservative
   estimates exclude native depth/backing allocations and are not a measured free-VRAM budget.
4. **Preserve shared engine resources and caller state.** Do not recreate reserved depth/shadow
   names, bind/copy depth or inert targets, rebuild lightmaps or bind non-nil MRT slots 1-3.
   Nil MRT clears, slot zero and valid stock color work pass. Ignored pushes create virtual scopes;
   their matching pops do not consume a caller's real native scope. Repeated ignored pushes use
   one counter. Real-error cleanup still unwinds only known owned extra scopes.
5. **Keep world/light integration intact.** Refuse effect-origin material mutations and incompatible
   entity material replacements. GShader's two native-light wrapper sources receive private
   metatable copies with per-object readback. Real CSM's raster projected-shadow updates, world
   raster-lighting writes and Quick Bloom's two bloom writes are inert. Pin depth resolution,
   MSAA and D3D9Ex settings to the current RTX session, alongside existing HDR/DX pins. Normal
   projectors, color targets, NikNaks helpers, toolgun screens and unrelated hooks remain usable.
6. **Capability refusal applies in multiplayer without broader containment.** Filter the reviewed
   effect callbacks and NeedsDepthPass at registration, including existing entries and cached
   dispatchers. Timers/cvar callbacks receive the same known-effect policy. Unrelated remote
   callbacks retain identity, returns and vanilla error behavior; only owned callbacks get general
   error containment. This narrow capability exception amends ADR 0056, not native/Lua trust.
7. **Bound local diagnostics.** One note per API and virtual source call site, at most 128 records
   per category. No error stack or quarantine for an intentional refusal. Record the policy,
   allocation estimates and installation route for QA. No disk writes, user.conf changes, network
   messages, native permissions or backend installation are added by the Lua guard.

## Consequences

The self-contained file still travels through the existing hash-verified early stage; no loader
or client-module ABI change/rebuild is needed for this policy. Its new content hash automatically
selects a new generated cache. The process-only DX11-to-stock-D3D9 choice remains unchanged.

Screen effects and raster CSM shadows lose their original appearance under RTX. Safe fallbacks
prevent guard-created errors; they do not emulate their data. Existing add-on messages may still
claim success (Real CSM prints that its depth upgrade succeeded because pcall now returns true).
The guard diagnostic is the authoritative record of the refusal.

Foreign server initializers can still precede the late verified bootstrap. No protection before
installation, native-alias recovery, arbitrary VMT/engine preload interception, GPU/native-fault
recovery or coverage of all 22 collection members is claimed. Source labels identify compatibility
policy, not trust or a security boundary. Unknown replacements need new source/QA evidence.

## Alternatives considered

- Continue throwing inside add-on setup: recreates the observed error and prevents setup finishing.
- Permit all enum values or let shader creation fail: valid-looking arguments do not establish
  D3D9/Remix capability, and native/GPU failures are beyond Lua containment.
- Render a black replacement post effect: can cover the path-traced image and still costs rendering.
- Disable every graphics add-on/hook or catch all server errors: breaks legitimate UI/content and
  violates the scoped multiplayer boundary. Apply reviewed capability filters instead.
- Port GShader/LUX or replace the shader API: a separate renderer project, outside this loader task.
