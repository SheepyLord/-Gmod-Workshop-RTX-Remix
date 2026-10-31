# _nativeloader_guard.lua

Self-contained RTX-session renderer guard. Loader startup can append the verified source after
stock includes/init.lua, before community autoruns capture native APIs. The literal
NATIVELOADER_RENDER_GUARD_V2 marker identifies this entry. No include or require is needed.
The normal autorun is idempotent through NativeLoaderRenderGuard.version.
Installation needs one of two existing verified native paths. Early startup supplies
__NATIVELOADER_RTX_GUARD_EARLY after the pinned stock initializer. Multiplayer can instead use the
existing NATIVELOADER_VERIFIED_MULTIPLAYER marker raw-set only in the native bootstrap's private
hash-verified chunk environment; an inherited marker or one set in the global environment is not
accepted. The guard explicitly binds _G.hook so its dispatcher replacement reaches the global
registry rather than only the bootstrap's scoped hook proxy. Without either proof the client
returns before creating convars or replacing APIs, including in vanilla fallback. SERVER/menu
behavior is unchanged. The guard does not consult or expose the temporary native catalog API.

NativeLoaderRenderGuard.installation distinguishes "early" from "verified multiplayer bootstrap".
The latter runs after the existing menu poll/bootstrap readiness checks (GAMEMODE and a valid local
player). It is not a pre-server/community-autorun boundary and cannot protect first-load operations
that happened before it. Earlier native aliases may already be cached, and image-format globals
may already have been changed; the late enum snapshot is not guaranteed to contain pristine
native values. This scoped regression fix does not change native client lifecycle hooks.
For the late route, selected registered render callbacks are also wrapped because the engine may
have cached its original hook.Call before installation. See the identity tradeoff below.

The saved nativeloader_guard 0 setting immediately delegates to original behavior, including
quarantined callbacks. Native allowlists, sv_allowcslua, user.conf and installed Steam files are
unchanged. There are no file writes or network operations. The only file read is the loader's
session cfg. SERVER keeps the existing AddCSLuaFile behavior; menu realm returns.

## Session settings and existing behavior

Read pins from cfg/nativeloader_session.cfg, retain engine motion blur at zero while its Lua
getters report one, and retain the existing stock PostFX/halo suppression. Normal fresh RT
drawing and DrawScreenQuad are not globally disabled. The Initialize hook also catches PostFX
functions defined after the early install.

RunConsoleCommand, Player:ConCommand, game.ConsoleCommand and ConVar SetInt/SetFloat/SetString/
SetBool enforce pins. Command parsing handles quoted semicolons, command chains, newlines,
indirect toggle/incrementvar/multvar/cycle and nested alias/bind payloads (four levels).
mat_dxlevel and mat_hdr_level are pinned to the declared session value or their early native
value, without the old source-name exemption. Other pins retain the earlier remixbinary,
remixlua and nativeloader exemption; these strings are not a security boundary.
Lua mat_reload*, mat_setvideomode, mat_restart and vid_restart commands are refused.
Console names/arguments and command strings reject embedded NUL before native dispatch, including
alias/bind payloads. Material paths and CreateMaterial names/shaders reject NUL before native
loading/creation, so Lua lookup cannot disagree with a truncated native C-string name.
Interactive native console commands and unseen preexisting aliases/exec-file bodies are outside
this Lua interception contract.

## Native call preconditions

Early installation captures image-format, RT-size and RT-depth enums before add-ons can rewrite
globals; the verified multiplayer route captures the values present at its later installation.
COUNT/NUM_FORMATS sentinels are excluded. Enums are not exhaustive: also permit backend-verified
R32F raw format 27, used by the shipped MMDHL 1024x1024 shadow target even on builds without the
IMAGE_FORMAT_R32F Lua constant. This is a format allowance, not an add-on prefix exemption.
Preserve IMAGE_FORMAT_DEFAULT and full-frame -1/-1
dimensions. GetRenderTargetEx requires known captured modes/formats and finite unsigned flags.
Literal/non-PO2 modes and ordinary fresh targets remain usable. Limits are 16,384 per axis,
64 million pixels per target and 128 newly named targets per virtual caller. The name quota is
not a measured VRAM budget; repeated use of a cached name does not consume it again.

Lua recreation of engine-owned shadowdepthtexture and resolvedfullframedepth targets is refused,
including case/extension aliases. DepthWrite/screenspace_general creation, known unsupported
material draws, resolved-depth generation, lightmap rebuilding and MRT slots above zero are
refused with a Lua error. Slot zero and nil restoration remain valid. Material-from-disk shaders
can only be checked after the native Material load; this remains an explicit native-load gap.

RenderView keeps ordinary sequential calls, optional/current-view fields and native returns.
It rejects non-finite supplied view data and limits nested views to four. This is not a claim
to catch native recursion faults or infinite Lua loops.

## Callback containment and state

Early installation contains loading/render/UI events through hook.Call while preserving registry
callback identity. The late verified-multiplayer route additionally wraps existing selected render
entries and future registrations through hook.Add, so a pre-installation cached hook.Call still
invokes the error boundary. The registry table stays the same, but late render entries deliberately
have wrapper identities. Initialize, InitPostEntity and OnReloaded entries are excluded from this
late wrapping; the native bootstrap's equality check and owned initialization replay remain valid.
NativeLoaderRenderGuard.late_render_wrappers reports that route. Registrations through an old
cached hook.Add alias or direct registry writes after installation can bypass it, as can gamemode
or entity methods invoked outside these wrapped registry entries.

String IDs, object self, invalid-object removal, first non-nil override and six hook return values
are preserved. Quarantine is per failing event/ID/function; re-registering the same function keeps
its late wrapper and quarantine. A replacement function runs normally; guard zero delegates to
the original callback, including quarantined functions. Future timer.Create,
timer.Simple and cvars.AddChangeCallback callbacks receive equivalent Lua-error boundaries,
with original arguments/IDs preserved.

Protected callbacks cannot pop a tracked scope owned by an active ancestor or an unowned caller.
A successful completed Pre callback can deliberately leave a scope for a later Post callback;
that balance remains valid. On caught Lua errors, cleanup unwinds only extra tracked Lua
RT/camera/clip/model-matrix pushes owned by that callback, plus its known direct RT change.
Successful nested callbacks contribute their actions to the active parent's chronological undo
log, so an ancestor failure can unwind known nested pushes. Failed children clean up locally;
their restoration markers are not propagated or replayed a second time.
Nested successful direct RT changes also mark the parent for restoration to its recorded entry RT.
If the failed callback consumed a completed render-target scope, its recorded push arguments are
replayed only when the expected tracked stack still matches and the texture/viewport remain valid.
Completed camera/clip/matrix pops cannot be reconstructed reliably from implicit defaults or
mutable arguments; a subsequent Lua error records that cleanup limitation instead of inventing
native state. It never guesses native stack depths,
resets DepthRange to 0..1, or calls mesh.End as an abort. Unknown non-stack state, half-built
meshes and APIs overwritten later remain limitations. No arbitrary native SEH continuation,
GPU recovery or universal rendering-add-on compatibility is promised.

NativeLoaderRenderGuard exposes bounded local blocked/error/cleanup records and allocation
counts using virtual Lua source labels. It omits raw exception text/private paths. Messages
are emitted once per category/API/source/reason, capped at 128 records.

## Verification

The actual-source LuaJIT harness is tools/tests/render_guard_harness.lua, invoked by
tools/tests/test_render_guard.py. It checks malformed native-call rejection and stock controls,
not recovery from real native faults. Primary contracts include
[RT creation](https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx),
[MRT](https://wiki.facepunch.com/gmod/render.SetRenderTargetEx),
[depth](https://wiki.facepunch.com/gmod/render.GetResolvedFullFrameDepth),
[hook returns](https://wiki.facepunch.com/gmod/hook.Call) and
[pcall limitations](https://wiki.facepunch.com/gmod/Global.pcall).
The broader read-only audit is under out/c13-evidence/wiki-api-audit.md.
