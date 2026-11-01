# R8-C report: graphics add-on compatibility under RTX

Implementation and offline checks are complete on **r8-compat**, based on `fd82075`.
Claude owns integration and real GPU/listen-server QA. No game was launched, no PoC/field/Workshop
file was changed, no package was imported/uploaded, and nothing was pushed, merged or tagged.
The changes do not touch glass, runtime or the MMD alpha file.

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
- VMT Material lookup can create custom shaders before a subsequent GetShader check. Deferred
  reconstruction, world-mesh/lightmap builds and custom shader/RT material mutations can damage
  world capture or draw over the path-traced image. Recursive views add another native reentry risk.
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
- Known effect-origin Material calls skip native loading even when a remote VMT is unreadable.
  Preflight other disk VMTs and bounded Patch includes before native Material. Block unsupported shader
  families/custom programs, cycles, missing includes and depth references. Filter draws/bindings,
  copies, world/entity mutations, GShader builds, Life Mod module effects, Real CSM raster shadow
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

`tools/test.ps1 -Config Release` passes: **26 CTests, 488 Python tests, two existing symlink-related
skips**. All guard LuaJIT scenarios execute: **40 unittest methods / 43 scenario invocations**,
including **18 new add-on replay scenarios**. They execute the production guard with native-call
spies and original minimal API snippets, never third-party add-on code or a real renderer.

Replays cover GShader's Initialize-to-InitReconstruction dispatch, FXAA/SSDO/SSR targets/materials/
MRT/quads/copies, Quick Bloom Initialize, Real CSM's eight target upgrades/projectors, Life Mod's
module dispatch/direct calls, NikNaks normal color atlases, VMT/Patch/LUX preflight, shared light
metatables, name/byte limits, caller scopes, allocator Lua failure, cached multiplayer dispatch,
ordinary server errors and RTX-off delegation. Existing hook/cleanup/pin/off/proof regressions remain.
GLua ITexture type labels, late enum rewrites, NULs and supported normal/R32F targets are controls.

Local evidence: `out/r8-compat/release-test.log`, `out/r8-compat/release-final.log`, and the ignored
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
   records must stay empty for these paths. Shader-failure additions relative to baseline require
   attribution to preload/native bypass or a failed check; a loaded map alone is not acceptance.
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
`9dcaf0d` (projector-cache retirement), `83f0fe6` (ignored-pass caller state), plus the final
handover/verification commit. Every commit ends with the requested Codex co-author trailer.
Guard source SHA-256: `896dac746a94512adeeffdd95b4761f498854f4ebfa5d80d22a21a095eef34b1`.

The original tester crash and driver/device behavior remain unverified on that hardware. A foreign
server initializer can bypass the generated local early view, leaving the existing bootstrap later
than remote autoruns. Earlier native aliases, later API overrides, direct registry writes, native
modules, preloaded/opaque/unknown shaders, arbitrary native render state and infinite loops cannot
be universally protected. Only the eight indexed sources were inspected; other collection members
and renamed code are not full coverage. RTX-off/new-session controls matter because inert resources
cannot be retroactively restored by an off switch. No automatic native/GPU fault recovery is claimed.

Do not close the tester's native-crash report solely on this offline pass. Claude should retain the
above live acceptance and a follow-up run on the affected computer as the integration boundary.
