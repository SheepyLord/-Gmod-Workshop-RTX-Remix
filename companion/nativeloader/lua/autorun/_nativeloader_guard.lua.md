# _nativeloader_guard.lua

Self-contained RTX-session renderer guard. Loader startup can append the verified source after
stock includes/init.lua, before community autoruns capture native APIs. The literal
NATIVELOADER_RENDER_GUARD_V2 marker identifies this entry. No include or require is needed.
The normal autorun is idempotent through NativeLoaderRenderGuard.version.

## Installation routes

`NativeLoaderRenderGuard.installation` names the route that installed it:

- **"early"**: the loader's generated initializer view sets __NATIVELOADER_RTX_GUARD_EARLY after
  the pinned stock initializer, and only when its own cache file exists on this machine
  (`file.Exists(..., "BASE_PATH")`).
- **"autorun"**: a local RTX start whose early view was not prepared or not installed (a GMod
  update changed the stock initializer, the catalog could not be verified, ...) installs from this
  ordinary autorun, late like ADR 0022's guard. The loader's status notes say why the early view
  was unavailable. The dispatcher replacement and API wrappers are those of the early route;
  aliases cached by add-ons that loaded before it are a stated limit.
- **"verified multiplayer bootstrap"**: the existing NATIVELOADER_VERIFIED_MULTIPLAYER marker
  raw-set only in the native bootstrap's private hash-verified chunk environment; an inherited
  marker or one set in the global environment is not accepted. It runs after the menu
  poll/bootstrap readiness checks (GAMEMODE and a valid local player), after the remote server's
  autoruns: it cannot protect first-load operations that happened before it, earlier native aliases
  may be cached and the late enum snapshot is not guaranteed pristine.

A listen host serves both this file (autorun files are sent to clients automatically) and its
generated initializer to remote clients. The early and autorun routes therefore also require
this machine's own loader to have reported an active RTX start: `native-loader/status.json` (DATA),
which the loader rewrites at every start before Lua runs, must hold the active activation outcome.
A remote vanilla client, or a loader user whose own start is RTX-off, installs nothing. Lua on a
server can write DATA files, so this is a local-session check against accidents, not a security
boundary; the guard has no native capability to grant. Without a route the client returns before
creating convars or replacing APIs, including in vanilla fallback. The SERVER realm returns
without `AddCSLuaFile`; the menu realm returns. The guard does not consult or expose the temporary
native catalog API. See [ADR 0056](../../../../docs/decisions/0056-guard-and-startup-fallbacks.md).

The saved nativeloader_guard 0 setting immediately delegates to original behavior, including
quarantined callbacks. Native allowlists, sv_allowcslua, user.conf and installed Steam files are
unchanged. There are no file writes or network operations. The only file reads are the loader's
session cfg and status.json.

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
Literal/non-PO2 modes and ordinary fresh targets remain usable. Fractional dimensions are checked
as the native API uses them, truncated toward zero (ScrW() / 3 is valid; 0.5 is not), and the
original arguments are forwarded. Limits are 16,384 per axis, 64 million pixels per target and
128 newly named targets per virtual caller. The name quota is not a measured VRAM budget;
repeated use of a cached name does not consume it again.

Lua recreation of engine-owned shadowdepthtexture and resolvedfullframedepth targets is refused,
including case/extension aliases. DepthWrite/screenspace_general creation, known unsupported
material draws, resolved-depth generation, lightmap rebuilding and binding a texture to MRT slots
1-3 are refused with a Lua error. Slot zero, nil restoration of slot zero and clearing slots 1-3
with nil remain valid; slots outside 0-3 are refused. Material-from-disk shaders can only be
checked after the native Material load; this remains an explicit native-load gap. Shader names
are cached per material object and texture validity per texture object (weak tables).

RenderView keeps ordinary sequential calls, optional/current-view fields and native returns.
It rejects non-finite supplied view data and limits nested views to four. This is not a claim
to catch native recursion faults or infinite Lua loops.

## Callback containment and state

The early and autorun routes contain loading/render/UI events through hook.Call while preserving
registry callback identity; hook.Call reads the switch only for these events. The verified
multiplayer route leaves the remote server's own Lua as it is (ADR 0052): it does not replace
hook.Call, and wraps only callbacks whose function environment is one of the owned private
environments (existing render entries, future hook.Add registrations, timer.Create, timer.Simple
and cvars.AddChangeCallback). Server-delivered callbacks keep their identity and their vanilla
error behaviour. Late owned render entries deliberately have wrapper identities, so a
pre-installation cached hook.Call still invokes the error boundary. Initialize, InitPostEntity
and OnReloaded entries are excluded from this late wrapping; the native bootstrap's equality check
and owned initialization replay remain valid. NativeLoaderRenderGuard.late_render_wrappers reports
that route. Registrations through an old cached hook.Add alias or direct registry writes after
installation can bypass it, as can gamemode or entity methods invoked outside these entries.

String IDs, object self, invalid-object removal, first non-nil override and six hook return values
are preserved. A failing callback is contained: its cleanup runs and its original error and stack
go to the engine's own error output (ErrorNoHaltWithStack), at most once per callback every ten
seconds, with a count of the errors suppressed meanwhile. Three consecutive failures within ten
seconds quarantine a hook ID/function, timer or cvar callback; a success resets the count. A
gamemode method is never quarantined (base GM:PostDrawViewModel draws the hands for every weapon):
each failure is contained and reported. Re-registering the same function keeps its late wrapper
and quarantine; a replacement function runs normally; guard zero delegates to the original
callback, including quarantined functions. Timer and cvar callbacks keep their original
arguments/IDs.

Protected callbacks cannot pop a tracked scope owned by an active ancestor or an unowned caller.
A successful completed Pre callback can deliberately leave a scope for a later Post callback;
that balance remains valid. On caught Lua errors, cleanup unwinds only extra tracked Lua
RT/camera/clip/model-matrix pushes owned by that callback, plus its known direct RT change.
Successful nested callbacks contribute their actions to the active parent's chronological undo
log, so an ancestor failure can unwind known nested pushes. Failed children clean up locally;
their restoration markers are not propagated or replayed a second time.
Nested successful direct RT changes also mark the parent for restoration to its recorded entry RT.
The entry render target is recorded when a callback first touches render targets, not on every
call. If the failed callback consumed a completed render-target scope, its recorded push arguments
are replayed only when the expected tracked stack still matches and the texture/viewport remain
valid. Completed camera/clip/matrix pops cannot be reconstructed reliably from implicit defaults or
mutable arguments; a subsequent Lua error records that cleanup limitation instead of inventing
native state. It never guesses native stack depths,
resets DepthRange to 0..1, or calls mesh.End as an abort. Unknown non-stack state, half-built
meshes and APIs overwritten later remain limitations. No arbitrary native SEH continuation,
GPU recovery or universal rendering-add-on compatibility is promised.

Code that fails outside a protected callback can leave a tracked push open (the stock toolgun
screen around a tool's DrawToolScreen, an ENT:Draw error between cam.Start3D2D and End3D2D). At
each frame boundary, a new FrameNumber or a top-level PreRender where FrameNumber is unavailable,
the guard forgets tracked entries no running callback owns; a later pop cannot consume them. Only
the running callback chain's own scopes count toward the 32-entry limit, so such leftovers never
make later pushes fail. Native state is not popped on anyone's behalf.

NativeLoaderRenderGuard exposes bounded local blocked/error/cleanup records and allocation
counts using virtual Lua source labels. Its records and MsgN lines omit raw exception text and
private paths; the original error text reaches only the engine's error output, as it would
without the guard. Messages are emitted once per category/API/source/reason, capped at 128
records per category.

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
