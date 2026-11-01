# R8-C report: graphics add-on compatibility under RTX

Implementation and offline checks are complete on **r8-compat**, based on `fd82075`.
Claude owns integration and real GPU/listen-server QA. No game was launched, no PoC/field/Workshop
file was changed, no package was imported/uploaded, and nothing was pushed, merged or tagged.
The changes do not touch glass, runtime or the MMD alpha file.

## Claude's pre-QA review: corrected material scope and measured cost

The material policy now operates at **untrusted drawing/binding**, preserving native loading and
inspection. Material/CreateMaterial return the real IMaterial, parameters, arguments and returns
for all callers, including known effect sources (embedded NUL still gets a safe fallback). The
PBR-reader replays at `remixlua/cl/cl_fix_pbr_materials.lua` and `cl_rtx_topbr_conversion.lua` read
real ExoPBR/GPBR fields and can update/convert the material. `mmdhl/client.lua` creates, edits and
binds its real screenspace_general/mmdhl_vs20/mmdhl_ps20b immediate material. An untrusted caller
binding that same object still gets the inert stand-in; caller provenance is checked at use.
Known effect draws, callbacks and world mutations stay inert.

No evidence establishes that merely loading or reading these materials causes the reported
Remix crash. The known PoC loaded/exited normally, and some shader warnings occur before Lua.
Consequently VMT/Patch loading remains native, without a load-time interception claim. New LuaJIT
regressions cover native reading/creation, all 344 package Lua virtual paths, untrusted use,
custom-program cache hints and mutation invalidation. Only original authored API snippets run.

The exact 344-path table is checked against indexed package paths/SHA-256 values plus current
companion/glass Lua; retired Glass-Rewrite-Remix is excluded and there are no internal collisions.
It covers the fixes, companion, nlglass, advanced material editor, bodygroup tools and motion
importer as well as the hotloader. No substring/directory-wildcard trust or creator-wide material
exemption is used. Existing target limits and critical pins remain.

This is a **compatibility exemption, not source authentication**. Mounted and private-bootstrap
Lua use `@lua/<path>` labels without the add-on directory (`loader/client/bootstrap.lua:169`).
Another add-on at exactly `lua/mmdhl/client.lua`, or code compiling that exact chunk label, can
impersonate the exemption and bind/mutate a custom shader, defeating these material filters.
Lookalike names and traversal labels fail the exact match. Catalog verification proves shipped
bytes, not which file won a virtual path at runtime. Already-running Lua could also replace the
wrappers or turn off the guard. This grants no new Lua/native execution or package allowlisting.
The collision regression demonstrates both the rejected lookalikes and the identical-label limit.

All guard VMT file.Read calls are removed, including entity setters. Native shader/program
metadata is inspected only at untrusted binding and cached with weak material keys. Entity-name
bindings resolve through native Material, including `!CreateMaterial` names, once per live cached
path; weak values permit collection. Repeats need no native resolution or metadata query while
the object remains live. Trusted bindings skip both. Plain/trusted/image/repeat Material loads
make zero guard disk reads or metadata queries. Only the existing status/session startup reads remain.

Measured with [bench_render_guard.py](../../tools/tests/bench_render_guard.py.md), three fresh
LuaJIT processes per guard and Windows QueryPerformanceCounter. The file.Read double models one
complete failed scan of **761 mounts taking at least 1 ms**; native Material is a separate cached
in-memory double. Mount probes are modeled, not real archive operations. Each row has 1,200 paths
(mixed: 400 PNG/400 JPG/400 extensionless; icons: 600 PNG/600 JPG). Medians:

| Workload | Before (60c2be5), ms | Reviewed, ms | Guard VMT reads, before / after |
|---|---:|---:|---:|
| Mixed new load paths | 1,205.573 | 0.299 | 1,200 / 0 |
| Repeat those paths | 1,204.843 | 0.247 | 1,200 / 0 |
| New PNG/JPG icons | 1,214.444 | 0.909 | 1,200 / 0 |
| Trusted new reads | 1,212.085 | 0.959 | 1,200 / 0 |
| First entity bindings | 1,210.206 | 2.167 | 1,200 / 0 |
| Repeat entity bindings | 1,209.841 | 1.284 | 1,200 / 0 |
| Trusted entity bindings | 1,211.365 | 0.939 | 1,200 / 0 |
| Fresh render bindings | 1.143 | 2.700 | 0 / 0 |
| Repeat render bindings | 0.664 | 2.213 | 0 / 0 |

Each old lookup row adds 913,200 modeled mount probes; the revised rows add zero. The old missing
root VMT branch was not cached, hence the repeated cost. Plain cases start with a warm fake native
cache; icons/trusted loads create new fake objects. First entity bindings inspect 1,200 native
objects; repeated ones add zero native resolutions and metadata queries. First render bindings
use separate fresh objects; repeats add zero metadata queries. Source checking adds approximately
1-2 microseconds per bind in this harness. Exact results are not a field FPS/startup prediction.

**Expected in-game cost:** no additional guard VMT searches, independent of the number of mounted
add-ons; plain loads add only switch/NUL checks, and bindings add cached metadata/source checks.
Native cold Material/VMT/Patch/image loading still has its ordinary engine/VFS cost. A first
untrusted entity name adds one native Material resolution; collection can require another later.
Real engine, GPU and field-menu timings remain Claude's QA. Receipt:
`out/r8-compat/material-cost.json`; reproduce with:

```powershell
python tools/tests/bench_render_guard.py --baseline-guard out/r8-compat/review-before-guard.lua --lookup-ms 1 --repeats 3 --out out/r8-compat/material-cost.json
```

The baseline evidence file is the guard extracted from commit 60c2be5. The regression uses the
same 1,200-path workload, asserts counts rather than timing, and needs no delayed lookups to pass.

## What can crash or destabilize, and why

The tester's crash is **not reproduced or diagnosed as one specific native fault**. Claude's
existing `r8/07-gshader` run loads/exits normally, but its guard-created exceptions stop GShader
setup at `bumps_building.lua:35` and `worldpos.lua:27` through `!!shaderlib.lua:800`. It also has
26 failed-shader lines; some precede client Lua startup, so their complete removal cannot be
promised by a Lua wrapper. Earlier C13 map-load success did not establish full compatibility.

The new [audit](../audits/R8-C-addon-compat.md) and [hash ledger](../audits/R8-C-addon-compat.json)
index **86 Lua/VMT files, 856 candidate API lines, eight exact Workshop archives**. Indexed source
SHA-256 and archive-entry CRCs all match. Those are static inventory counts, not executed calls.

The concrete resource/state risks are:

- GShader's late enum exports bypass the assumptions of an early enum snapshot. Raw RGBA32F29
  is a real Source format; its old “unknown image format” diagnostic confused enum visibility with
  backend capability. RGB32F28/R16F38, depth/INTZ/NULL/compressed/branch-dependent formats, D3D9Ex
  dependencies and unbounded persistent allocations can still fail native texture creation.
- GShader replaces engine resolved depth and Real CSM replaces eight live shadow targets. MRT
  attachment mismatches, depth-only work and color copies involving depth can enter unsupported
  native/D3D paths. A pcall cannot recover device loss, a native access violation or a driver fault.
- VMT Material lookup may produce shader-creation warnings, but there is no demonstrated load-only
  crash. Deferred reconstruction, world-mesh/lightmap builds and custom shader/RT material mutations
  can damage world capture or draw over the path-traced image. Recursive views add native reentry risk.
- GShader's projector wrapper repeatedly nests a shared __index; its light wrapper replaces
  native userdata metatables and resets cached field tables. Those edits affect unrelated lights.
- Real CSM spread shadows and deferred lightmap/world-lighting changes compete with RTX.
  Life Mod's DoF/distortion methods also run directly through its shared module dispatcher.
  Quick Bloom's exact payload only writes two bloom cvars; it supplies no demonstrated native-crash path.

These are grounded isolation targets, not proof that each caused the user's crash.

## What changed and the policy

[ADR 0086](../decisions/0086-inert-shader-effects-and-safe-guard-fallbacks.md) amends 0054/0056:
**GShader-style screen-space effects are inert under RTX by default, without guard-made Lua errors.**
Keep the add-ons installed; a fresh RTX-off launch retains their original behavior.

- Every intentional refusal now returns: a shared 1x1 RGBA8/depth-none engine ITexture, the engine's
  own exact resolved-depth texture, a shared transparent UnlitGeneric IMaterial, false for the depth
  hook, or no values for ignored work. Initialization continues. Real add-on errors retain the existing
  bounded reporting/quarantine; a refusal never creates an error stack or quarantine.
- Material/CreateMaterial stay native, including known effect-origin calls. No guard VMT preflight
  or post-load replacement remains. Filter unsupported shader families/custom programs at untrusted
  draws/bindings, including named entity replacements. Exact bundled paths retain their material
  behavior. Filter copies, world/entity mutations, GShader builds, Life Mod module effects, Real CSM raster shadow
  updates/world-lighting writes and Quick Bloom's two raster bloom writes. Ordinary UI, projectors,
  color copies, NikNaks atlases and supported R32F27/MMDHL calls remain usable.
- Pin renderer/depth-resolution/MSAA/D3D9Ex settings. RT bounds include finite/native-truncated
  dimensions, cubemap/depth rejection, 128 MiB estimated color bytes per target, 128 names/512 MiB
  per virtual file and 1 GiB tracked total. These are conservative estimates, not free-VRAM measurement.
- Ignore unsupported MRT binds while retaining nil clears. Virtual scopes balance ignored pushes
  and pops without consuming caller state. GShader's two light wrappers receive private metatable
  copies and per-object readback, keeping repeated cached-light acquisitions off native tables.
  Native projector removal also retires GShader's exported light-cache entries and rebuilds their
  indices; isolating its Remove override must not retain every removed lamp.
- Capability filters also cover known server-delivered effect/depth callbacks and cached dispatchers.
  Unrelated server hooks/timers keep vanilla errors and identity; general error containment remains
  owned-only on the late multiplayer route. Diagnostics are capped and identify virtual call sites.

The existing verified generated initializer embeds the entire new guard; its changed hash creates
a new cache name. No loader/bridge ABI change is required. `package_fixes.py` already takes the
companion from this repo, so Claude must build the test package from the integrated branch; there
is no new external binary/package input to import for this guard.

## Tests and evidence

`tools/test.ps1 -Config Release` passes: **26 CTests, 495 Python tests, two existing symlink-related
skips**. The guard suite has **47 unittest methods total: 49 LuaJIT scenario invocations and one
static path/hash check**, including **24 add-on replay scenarios**. The Lua cases execute the
production guard with native-call spies and original minimal API snippets, never third-party
add-on code or a real renderer.

Replays cover GShader's Initialize-to-InitReconstruction dispatch, FXAA/SSDO/SSR targets/materials/
MRT/quads/copies, Quick Bloom Initialize, Real CSM's eight target upgrades/projectors, Life Mod's
module dispatch/direct calls, NikNaks normal color atlases, native shader loading and filtered
bindings, shared light metatables, name/byte limits, caller scopes, allocator Lua failure, cached multiplayer dispatch,
ordinary server errors and RTX-off delegation. Existing hook/cleanup/pin/off/proof regressions remain.
GLua ITexture type labels, late enum rewrites, NULs and supported normal/R32F targets are controls.

Review evidence: `out/r8-compat/review-release.log` and `out/r8-compat/material-cost.json`.
Earlier evidence: `out/r8-compat/release-test.log`, `out/r8-compat/release-final.log`, and the ignored
analysis source copies. No GPU result or actual crash reproduction is inferred from these tests.

## QA for Claude: what each check must show

Use the integrated R8 package, only the PoC and disposable second-client/server fixtures. Retain
logs, status, guard notes, module list, screenshots and session outcomes beneath `out/qa-poc/r8/r8-c`.
Use [poc_session.py](../../tools/poc_session.py.md), its `--players`/`--extra`/`--console` helpers and
the existing [RTX session probe](../../tools/qa/rtx_session_probe.lua.md). For remote clients with
sv_allowcslua=0, deliver any additional inspection probe normally from the test server; do not relax
client Lua/native permissions to manufacture a pass. Use only owned fixture processes.

1. **Establish the baseline and package identity.** Build the integrated package; verify the deployed
   guard's SHA matches its catalog entry and this branch's source. Start RTX on gm_construct with
   none of the eight add-ons. Record the baseline shader warnings, cvars and guard route. It must
   report policy `inert screen-space shaders under RTX`, enabled=true and normally installation=early.
   Ordinary world/hands/spawn menu/toolgun screen must render, with no guard error/cleanup records.
2. **Run the SP matrix on gm_construct and gm_flatgrass.** Test (a) Quick Bloom + Real CSM + Life Mod,
   (b) GShader + FXAA + SSDO + SSR + NikNaks, (c) all eight. For each map, enable each effect in its UI,
   wait at least 60 seconds, move the view, use the toolgun and open the spawn menu. Both maps must
   load and quit normally, the RTX image/world/hands must remain intact, and no named add-on or
   guard-made Lua error may occur. Initialization must finish beyond GShader's old worldpos failure.
   Expected capability notes replace the old errors; effects stay visually inert. Error/cleanup
   records must stay empty for these paths. Attribute shader-failure additions to allowed native
   loading versus an unsafe draw reaching the backend; loading warnings alone are not a failed
   binding check. A loaded map alone is not acceptance. Also run an ExoPBR/GPBR map/model conversion
   and hotloader immediate preview with the guard enabled: original shader/texture fields must be
   visible before conversion, converted materials must remain correct and immediate rendering must
   use real materials. Exercise companion, glass, material-editor, bodygroup and motion tools.
   Open the spawn menu/model browser and compare frame timings against baseline; no guard VMT reads
   should appear. Offline timings above do not substitute for this field-size browser control.
3. **Exercise resource/rebuild controls.** With Real CSM, select depth format 24, create its controller,
   enable spread/multiple cascades, change its depth-resolution slider and remove/recreate it.
   With GShader toggle reconstruction/format choices and enable FXAA/SSDO/SSR. Reserved upgrades,
   raster shadows, deferred builds and incompatible draws must stay inert without errors, allocation
   growth or altered pinned resolution/HDR/DX values. Real CSM may print its own “upgrade succeeded”
   because pcall now returns true; inspect guard notes, not that message. Toolgun/NikNaks/R32F controls
   must still work. Observe the same call site repeatedly: diagnostics must stay bounded.
4. **Check transitions and recursive-view controls.** With each add-on set, change construct -> flatgrass
   -> construct and use available scope/camera views. Every transition must render normally; two
   sequential views must work, and effect-owned recursive views must stay inert without a guard error
   or stranded RT/camera state. Compare against baseline, including memory after settling; report growth or hangs.
5. **Listen server with a second client, both maps, all three sets.** Launch an RTX listen host using
   `--players 2`; join from a separate disposable RTX client/install with -multirun, using server-delivered
   add-ons, then change maps and reconnect. Both clients must show the correct policy/route, loaded
   gameplay, inert named effects and no new Lua/native/device-lost errors. Check that a benign server
   HUD callback still runs and retains its normal returns. A deliberately failing unrelated server
   callback on the verified late client must keep vanilla behavior, without being silently contained.
   The early/listen route retains its existing general hook containment. Normal
   secure launch settings and the existing native/Lua allowlists must remain unchanged.
6. **Prove route boundaries.** Record guard readiness before the first effect/resource callback, not
   only after joining. Matching local/served initializer views should install early. Also exercise
   the foreign-server-initializer/verified-late route: once installed, a cached dispatcher must hit
   the effect/depth filter and ordinary server callbacks must remain ordinary. If unsafe work precedes
   installation, record it as the existing startup coverage gap, not a compatibility pass. A vanilla
   second client served the companion must have no guard global/API mutations from the host's proof.
7. **Fresh RTX-off controls and integrity.** Restart with Remix off and all eight add-ons on each map.
   NativeLoaderRenderGuard must be absent and the add-ons must receive stock calls; their visual
   shader/backend support is the stock session's responsibility. Do not treat a live guard toggle
   as reconstruction of previously skipped resources. Verify Steam depot integrity and unchanged
   user.conf/launch settings. Every RTX test must exit normally with no new crash dump, device-lost
   marker or hang; archive failures for the tester-machine comparison instead of retrying them away.

Example SP run after Claude has prepared the package and isolated add-on set:

```powershell
python tools/poc_session.py --evidence out/qa-poc/r8/r8-c run --name gshader-construct --map gm_construct --players 1 --addons --settle 60 --lua tools/qa/rtx_session_probe.lua --lua-shots 90
```

## Limits and delivery

Commits: `c809272` (exact-source audit/ADR 0086), `3f074ae` (guard and replay tests),
`9dcaf0d` (projector-cache retirement), `83f0fe6` (ignored-pass caller state), `60c2be5`
(handover/verification), followed by this material-review correction. Every commit ends with
the requested Codex co-author trailer.
Guard source SHA-256: `6e6881431cbdbb93a4eaf14e725ca5aaa72391ab7a5115ab0583db3d56c04a93`.

The original tester crash and driver/device behavior remain unverified on that hardware. A foreign
server initializer can bypass the generated local early view, leaving the existing bootstrap later
than remote autoruns. Earlier native aliases, later API overrides, direct registry writes, native
modules, preloaded/opaque/unknown shaders, arbitrary native render state and infinite loops cannot
be universally protected. Only the eight indexed sources were inspected; other collection members
and renamed code are not full coverage. RTX-off/new-session controls matter because inert resources
cannot be retroactively restored by an off switch. No automatic native/GPU fault recovery is claimed.

Do not close the tester's native-crash report solely on this offline pass. Claude should retain the
above live acceptance and a follow-up run on the affected computer as the integration boundary.
