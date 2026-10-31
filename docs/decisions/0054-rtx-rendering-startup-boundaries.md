# 0054: RTX rendering compatibility at client startup

- Status: Accepted; implementation and local acceptance complete
- Decided by: the user's C13 graphics-add-on/map-load hardening request and the scoped implementation

## Context

The Source D3D9 capture path, third-party rendering APIs and initialization order are separate
compatibility boundaries. An explicit alternate shader backend can bypass the project's D3D9
device path. A later Lua autorun cannot protect aliases cached by earlier add-ons. Some effects
also request engine-owned depth targets, MRT, shaders or nested views outside the tested Remix
path. A pcall around add-on loading does not contain a later engine callback or a native/GPU fault.

The durable [API audit](../audits/C13-render-api.md), its
[source/URL provenance](../audits/C13-render-api.json) and
[RESEARCH.md](../RESEARCH.md#c13-graphics-add-ons-and-map-loading) record the confidence limits:
17 API families/43 primary URLs (41 wiki), 25 indexed call-site files (12 stock/13 add-on), a broader
228-file add-on inventory, eight available
snapshots (three exact archives/five author-linked repositories), and 17 unavailable items,
including QuickBloom plus sixteen collection members. Exact GMA coverage is narrower than upstream
source availability. Fresh 0.9 LifeMod-default, CSM depth24/one-controller and GShader-FXAA controls
load their tested maps; none reproduces the user's failure. Static risk paths are isolation targets,
not established causes. Controlled guarded transitions/assertions pass, with nonfatal CSM fallback
and two reported GShader autorun rejections. Final package and multiplayer acceptance are below.

## Decision

1. Loader 0.10.0 selects stock shaderapidx9 for every explicit shader-API option only in an active
   RTX process. Preserve unrelated raw arguments and exact reversible W/A/PEB descriptors. Leave
   Steam launch settings and RTX-off sessions alone. Keep the selected-runtime identity check;
   do not delete foreign DLLs, infer incompatibility from DLL presence, or loosen native trust.
2. Prepare an exact generated view of the supported stock client includes/init.lua. Install only
   the enabled, allowlisted owner's catalog-SHA-verified V2 guard after library setup and before
   autoruns. Use the owned `native-loader/presentation/render-guard-<sha>.lua` cache and require
   the verified early proof in the Lua guard; a late autorun alone cannot substitute. If runtime
   activation falls back, remove this executable redirect before passive presentation setup.
   For selected `gmod-rtx-remix`, once its owner/V2 script is catalog-verified, stock/cache failure
   is a required-protection failure that disables RTX with a clear reason and vanilla/hide-RTX
   fallback. Do not silently continue with unguarded V2 RTX. Foreign-runtime preparation performs
   no stock/cache reads here; legacy V1 marker failure remains a nonfatal note. The requirement
   itself never expands the native/package allowlist.
   Refuse unknown stock hashes, incompatible versions and altered/unsafe caches; keep
   inactive/server/menu contexts unchanged. The redirect is in-process, with an owned cache; the
   Steam initializer and user configs are never rewritten. A shipment using this path conditionally
   requires loader >=0.10.0. A Workshop-only update cannot give an older bootstrap this early stage.
3. Scope Lua protection to reviewed resource/capability and callback boundaries: reserved depth
   targets, unsupported depth shader/MRT work, RenderView recursion, protected cvar entry points,
   render/loading hook dispatch and bounded failure quarantine. Raw R32F format27 is valid and
   stays a positive control, separate from depth-name/MRT capability conflicts. The measured
   source/live probes, counterexamples and final package pass within the limits below.
   Preserve callback arguments, self,
   returns and legitimate stock API behavior rather than blanket-disabling every graphics add-on.
4. Cleanup may unwind only state added beyond a callback's recorded entry state. Do not call
   mesh.Abort, unwind caller-owned RT/camera/matrix layers or assume engine depth zero/defaults.
   Full-frame sizing, stereo views and nested toolgun callbacks are required counterexamples.
5. Treat recoverable Lua errors and native-fault prevention separately. No universal native
   exception, engine fatal, driver or GPU recovery is promised. Unknown payloads, cached aliases,
   later overrides and untested effect settings remain explicit limits. Keep diagnostics bounded
   and local, with normal session/privacy etiquette.

The remote client initializer can bypass the local file view. The existing catalog-verified
native bootstrap therefore supplies its private chunk marker as a separate, later install path.
The guard never accepts that marker through global/inherited lookup; it replaces the real global
hook dispatcher and records the later timing. This adds no native execution API or permissions.
The engine can retain an earlier dispatcher. Only the late route therefore wraps existing and
newly registered rendering callbacks. Their registry entries expose wrapper functions; the early
route preserves original function identities. Initialize, InitPostEntity and OnReloaded retain
their original callbacks for the verified payload's initialization replay. Cached hook.Add aliases,
direct registry writes and cached gamemode methods remain coverage gaps.

The work does not rebuild DXVK/Remix or change the accepted 5e626e34 native fixes DLL. It adds a
loader boundary and a verified Lua layer; it does not port arbitrary DX11 shaders to Remix.

## Consequences and acceptance

Supported early startup reduces third-party alias gaps without modifying depot files. Strict
stock/guard identity checks can refuse an early view after a game update or an edit; report that
condition and preserve the original view instead of guessing. Process-only backend normalization
allows the user's alternate backend choice to return on an RTX-off launch.

Release passes **22 CTests and 294 Python tests (7 skips)**, including 20 early-policy cases,
6 backend cases, 11 targeted command-line cases and 17 unittest cases running 18 actual-source
LuaJIT scenarios. CI builds pinned official LuaJIT and requires it, rather than skipping these
scenarios. CPU tests are separate from the real NVIDIA GPU sessions below.

The actual 998-file GMA reads back against every manifest SHA and matches all preview payloads.
Its construct session passes ten failure/positive controls: reserved RTs, invalid dimensions,
unsupported shader/MRT/depth work, pinned HDR writes, valid normal/R32F targets, one quarantined
HUD failure and restored RT state. Toolgun rendering and spawn-menu open controls pass. Corrupting only its owned
startup cache gives a clean vanilla map load/exit, no RTX patches or executable init redirect,
and preserves the changed cache; the fixture restores its original bytes afterward.

Secure dedicated multiplayer passes with no -insecure, sv_allowcslua 0 and cheats 0. The trusted
RTX payload, RTXDebug and guard load; unrelated local Lua remains excluded and the temporary
catalog API is absent. A normal server-delivered test verifies an unsupported-shader rejection,
one failing HUD callback, continuing healthy callbacks and restored RT state with zero cleanup
errors. It records installation="verified multiplayer bootstrap", with the early flag false.
This is a later readiness boundary, not protection before the remote server's autoruns.

Earlier controlled baselines load LifeMod defaults, CSM depth24/one controller and GShader/FXAA.
The guarded combined construct-to-flatgrass transition and explicit DX11-to-D3D9 process choice
pass. RTX-off loads/exits normally with the guard absent. Steam depot verification passes.

The original user crash was not reproduced with fresh defaults. Exact QuickBloom/HDR source and
sixteen collection members were unavailable; author-linked repositories are distinguished from
exact Workshop archives. Unsupported shader effects can be disabled or quarantined while the
map loads; this does not promise their original appearance or recovery from native/GPU faults.
Earlier aliases, later API replacements, unknown native state and already-completed camera/clip/
matrix pops remain explicit limits. Multiplayer installation is later than server autoruns.

## Alternatives considered

- Edit Steam launch options or replace core graphics files: persistent user/depot changes are
  unnecessary for a session-local choice and would complicate rollback.
- Block every graphics/native add-on or every DXGI/D3D DLL: normal runtime/dependency use and
  retained RTX-off DXVK are legitimate; presence does not identify an active conflict.
- Catch all faults or reset all render state after an error: Lua cannot guarantee native/GPU
  recovery, and global resets can damage valid caller-owned state.
- Install only from an ordinary late autorun: earlier captures can bypass the wrappers; retain
  the verified hash-supported early stage and document unsupported starts.
