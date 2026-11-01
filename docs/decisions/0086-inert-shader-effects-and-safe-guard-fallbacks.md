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

Review correction before merge (2026-11-01): the original implementation replaced materials at
load/creation and preflighted every new Material path with file.Read. That broke the package's
ExoPBR/GPBR readers and hotloader shaders and added mount-count-dependent disk work. The evidence
does not establish a crash caused by loading/reading these materials: the PoC loads/exits normally
and some failed-shader messages precede Lua. The revised decision below keeps native loading and
applies the inert-material policy at untrusted drawing/binding boundaries.

## Decision

1. **Refusals return; they never raise a guard-created Lua error.** Invalid or unsupported target
   requests return one lazily created 1x1 RGBA8, depth-none engine ITexture. Exact reserved
   resolved-depth requests return Source's existing getter texture; other reserved names get the
   inert target. Unsupported material bindings use one transparent engine UnlitGeneric IMaterial.
   Unsupported state changes, copies, MRT binds, reloads and views return no values. Add-on
   initialization can continue. Real add-on errors still follow ADR 0056's reporting/quarantine.
2. **GShader-style screen-space shaders are inert under RTX by default.** No ps30/DX11 translation
   or visual parity is promised. Keep add-ons installed. Refuse DepthWrite, screenspace_general
   families, LUX shader families and custom vertex/pixel programs when untrusted Lua binds them.
   Material/CreateMaterial keep native objects, parameters, arguments and returns for every caller,
   including known effect sources; retain embedded-NUL protection. Loading/reading alone is not
   grounds for an inert stand-in. Inspect native shader/program metadata at an untrusted binding,
   cache the decision per material, and invalidate it on mutations. Creation hints retain custom
   programs even if the engine reports a fallback shader. Entity setters resolve names (including
   !CreateMaterial references) through native Material once per live cached path, never VMT text.
   Skip the audited GShader/FXAA/SSDO/SSR reconstruction/render/build
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
8. **Exempt the package's material callers by exact verified virtual paths.** The self-contained
   guard lists 344 paths from indexed package Lua plus this repository's companion and glass Lua;
   no substring, directory wildcard or material-creator exemption is used. Tests check equality
   with the input inventory, indexed SHA-256 values and no internal virtual-path collisions
   (retired Glass-Rewrite-Remix is excluded), then replay bindings/mutations at every listed path.
   Both PBR readers, mmdhl/client.lua, companion, nlglass, advanced material editor, bodygroup tools
   and motion importer therefore retain native material behavior. An untrusted caller reusing a
   material created by trusted code still encounters the binding policy. General target limits,
   critical session pins and other existing guards are unchanged.
9. **Do no material-preflight disk work.** No Material/CreateMaterial, image path, trusted caller,
   repeat lookup or binding reads VMT text through file.Read. Only the existing status/session
   startup reads remain. Per-material caches are weak-keyed; entity-path caches are weak-valued
   and may resolve again after collection. Trusted bindings skip metadata and extra native lookup.
   The [offline benchmark](../../tools/tests/bench_render_guard.py.md) compares 1,200-path batches
   with a double modeling 761 mounts and 1 ms per complete failed lookup. The old rule incurs
   1,200 reads/913,200 modeled mount probes per batch, including repeated misses and images; the
   revised rule incurs zero. Native cold loads still have engine/VFS cost; zero added guard reads
   is not a guarantee of zero game disk activity. Timing receipts and medians are in the report.

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

The package catalog verifies shipped bytes; it cannot authenticate which file won a shared Lua
virtual path at runtime. The bootstrap itself compiles owned chunks with @lua/<path> labels
(loader/client/bootstrap.lua:169), losing the add-on folder just as mounted Lua does. A third-party
file at exactly lua/mmdhl/client.lua, for example, or code compiling a forged identical chunk
label, can impersonate the material exemption and bind/mutate a custom shader. Lookalike prefixes,
suffixes and traversal labels do not match. There are no collisions among the current 344 shipped
entries, but third-party/server namespace collisions are possible; they could defeat these
material filters and reintroduce unsupported rendering. Already-running Lua can also replace
wrappers or disable the switch. This compatibility heuristic grants no Lua/native execution,
changes no package allowlist and does not exempt target/cvar guards. Authentic per-function
ownership would need a separate loader mechanism; no unproven source-path security claim is made.

## Alternatives considered

- Continue throwing inside add-on setup: recreates the observed error and prevents setup finishing.
- Permit all enum values or submit unsupported draws: valid-looking arguments do not establish
  D3D9/Remix capability, and native/GPU failures are beyond Lua containment.
- Render a black replacement post effect: can cover the path-traced image and still costs rendering.
- Disable every graphics add-on/hook or catch all server errors: breaks legitimate UI/content and
  violates the scoped multiplayer boundary. Apply reviewed capability filters instead.
- Port GShader/LUX or replace the shader API: a separate renderer project, outside this loader task.
