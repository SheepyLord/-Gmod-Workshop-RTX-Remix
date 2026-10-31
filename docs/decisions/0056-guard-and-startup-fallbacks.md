# 0056: Guard and start-up fallbacks

- Status: Accepted
- Decided by: the lead (Claude) under the user's instruction to decide autonomously, R4 review.
  The secure-launch default of [ADR 0052](0052-scoped-rtx-multiplayer-bootstrap.md) stays, by the
  user's decision (2026-10-31): RTX sessions do not request `-insecure`, and the seven-recipe
  exception stays on by default.
- Amends: ADR 0052's opt-out (`patch_sets.allow_rtx_render_patches: false`) and package loader
  requirement; [ADR 0054](0054-rtx-rendering-startup-boundaries.md)'s required-protection fallback
  and its late multiplayer dispatcher. Neither record is rewritten.

## Context

The R4 review verified these defects in the RTX start-up, the render guard and the multiplayer
bootstrap:

- **The opt-out crashes (M4).** With `allow_rtx_render_patches: false` and no `-insecure`, the
  runtime's reviewed rendering recipes are skipped and RTX still starts: the configuration ADR 0052
  recorded as a prototype crash.
- **Required protection disables RTX for everyone.** The stock initializer's hash is compiled into
  `winmm.dll`, so a GMod update that touches `lua/includes/init.lua`, or a changed owned cache file,
  disabled RTX until the bootstrap was replaced. Other preparation failures (an unverifiable
  catalog, another owner) left RTX running with no guard, because the V2 autorun refused to install
  without the early flag.
- **The proof travelled.** The guarded initializer view is redirected for every reader of the path
  and carried its own early flag, so a listen host served it to remote vanilla clients, which then
  installed the guard; `AddCSLuaFile()` sent the autorun as well (autorun files are sent anyway).
- **The guard's own bookkeeping failed.** Scopes left open outside protected callbacks (the stock
  toolgun screen around a failing DrawToolScreen, an ENT:Draw error inside cam.Start3D2D) stayed in
  the tracked stacks forever; after 32, every later push of that kind was refused. One Lua error
  quarantined a hook, timer or cvar callback permanently, or the gamemode method itself (base
  GM:PostDrawViewModel draws the hands), and the original error was discarded. The late multiplayer
  route wrapped the remote server's callbacks too. Fractional render-target sizes and clearing MRT
  slots with nil, both legal, were refused.
- **The multiplayer bootstrap could stop or run twice.** Its only trigger lived inside the
  diagnostics overlay, which a changed main menu controller drops. On a listen host, an
  `sv_allowcslua 1` server or a server shipping the add-ons, the owned payload ran a second time.
  The menu module read and wrote the client realm through metamethods and outside a protected call,
  recompiled the initializer on every menu Think when the realm lacked an API, and did not keep
  itself loaded although owned environments keep its callbacks. Only InitPostEntity registrations
  were replayed.

## Decision

1. **The crashing opt-out falls back to vanilla.** When `patch_sets.allow_rtx_render_patches` is
   false, `patch_sets.require_insecure` is true and `-insecure` is neither on the command line nor in
   the arguments the runtime adds, and the plan holds at least one reviewed recipe group
   (`secure_render_patch_set`), start-up does not activate RTX. The activation outcome is `failed`
   with a reason naming the key and `-insecure`; the existing vanilla fallback applies (RTX-only
   add-ons hidden, session values restored). `nlctl activation` previews the same refusal for its
   empty command line. A changed recipe never inherits the exception, so its skip is not this
   refusal.
2. **A guard that cannot be prepared early never disables RTX.** Every preparation failure is a
   note in status (`early render guard unavailable (...); the companion guard installs at autorun
   time instead`), and RTX activates. The companion's guard autorun then installs at autorun time
   (installation `"autorun"`), late like ADR 0022's guard, with the early route's dispatcher and API
   wrappers. A changed owned cache file, or a folder in its place, is moved to
   `native-loader/backup/render-guard/<name>.<n>`, never deleted, and the view is written again.
3. **The proof is local.** The cache file is named from its inputs (generator format, stock
   initializer and guard hashes), and the generated block sets the early flag and runs the guard only
   when that file exists on the machine running it (`file.Exists(<cache>, "BASE_PATH")`). Outside the
   private multiplayer environment, the guard also requires `native-loader/status.json` (DATA),
   which the loader rewrites at every start before Lua runs, to report an active activation. The
   SERVER branch no longer calls `AddCSLuaFile`. This is a local-session check against accidents, not
   a security boundary: server Lua can write DATA files, and the guard grants no capability.
4. **Containment reports and forgives.** A failing protected callback's original error and stack go
   to the engine's error output (`ErrorNoHaltWithStack`) at most once per callback every ten
   seconds, with a suppressed count; the guard's own records keep virtual sources only. Three
   consecutive failures within ten seconds quarantine a hook ID/function, timer or cvar callback; a
   success resets the count. Gamemode methods are never quarantined. Report records have a cap per
   category instead of one shared cap.
5. **The multiplayer route leaves the server's Lua alone.** It no longer replaces `hook.Call`, and it
   protects only callbacks whose function environment is an owned, private one (the raw verified
   marker): existing render entries, `hook.Add` registrations, timers and cvar callbacks. Server
   callbacks keep their identity and vanilla error behaviour, as ADR 0052 requires of global helpers.
6. **Tracked scopes are resynchronized.** At each frame boundary (a new `FrameNumber`, or a top-level
   PreRender where it is missing) the guard forgets tracked entries no running protected callback
   owns. Only the running callback chain's own scopes count toward the 32-entry limit. Native state
   is never popped or guessed.
7. **Legal stock calls pass.** Fractional render-target sizes are checked as the native API
   truncates them; clearing MRT slots 1-3 with nil is allowed (binding them is still refused). Hot
   paths read the switch only for protected events, record the entry render target and source only
   when needed, and cache shader names per material.
8. **The multiplayer bootstrap is robust.** The main menu view carries the bootstrap trigger as its
   own part; when the stock controller changed, the loader installs the trigger alone and notes it.
   The packaged `cl_rtx.lua` sets `NATIVELOADER_RTX_NORMAL_LOAD` when normal loading ran it. On a
   listen host or an `sv_allowcslua 1` server, where every local add-on loads normally, the
   initializer then finishes without a second run; on another server, which delivered its own copy
   of the fixes, only the add-on holding `autorun/cl_rtx.lua` is left out (cross-owner includes of
   its files fall back to the engine), so the companion and the other owned add-ons still load. A
   server-delivered entity class keeps its definition. A realm without `hook` or `CompileString`
   finishes at once. The module reaches the client realm only raw and inside one protected call
   there, polls at most every 250 ms, gives a realm at most 480 initializer runs (two minutes), and
   pins itself. Owned OnGamemodeLoaded, PostGamemodeLoaded and Initialize registrations are
   replayed, in that order, before InitPostEntity.
9. **Packaging follows the companion.** A fixes build that carries the companion (the V2 guard)
   requires loader `>=0.10.0` whether or not it carries the helper; without the companion it keeps
   `>=0.2.0`. `session.patches` in status.json counts only the patches the session applies.

## Consequences

- An RTX start whose early view is unavailable still renders with the guard, later: aliases
  captured by add-ons whose autoruns ran first, and an engine that cached the dispatcher earlier,
  bypass it. The status note says why the early view was unavailable.
- The local proof has limits: two instances of one install where the later one is RTX-off overwrite
  the report the earlier one's later map loads read; a status.json left by a loader removed without
  uninstalling still reports its last outcome; server Lua can write it. A start whose status.json
  cannot be written (already logged as a start-up error) runs RTX without the guard.
- In multiplayer, community and server callbacks are no longer contained by the guard; owned
  callbacks are. The guard's API checks (targets, shaders, MRT, views, pins) still apply to all code.
- A protected callback can still be limited by scopes that engine-invoked code leaked during it;
  that lasts until the callback returns and the next frame boundary.
- Server-delivered autorun files cannot be told apart reliably on the client, so only the add-on
  whose `cl_rtx.lua` reports itself (all of them on a listen host or an `sv_allowcslua 1` server) and
  entity classes (by `scripted_ents.GetStored`) are skipped; other add-ons a server also ships still
  run a second time.
- The relative order of OnGamemodeLoaded/PostGamemodeLoaded and Initialize replays was not measured
  in game; owned code uses only Initialize and InitPostEntity today.
- The bootstrap initializer is embedded in `gmsv_nlrtxclient_win64.dll`: shipping item 8's module
  and initializer changes needs that DLL rebuilt and imported into `packages/fixes/modules`.
- None of this was checked in a game session in this change; the Lua, JavaScript and C++ contracts
  are covered by the harnesses and CTests.

## Alternatives considered

- **Restoring `-insecure` by default with a secure-servers opt-in.** The user decided against it:
  multiplayer is required, upstream does not require `-insecure`, and VAC is not considered a risk.
- **Keeping required protection.** One GMod update would disable RTX for every player until a new
  bootstrap shipped; a late guard is better than none.
- **The cache file alone as proof.** A loader user whose own start is RTX-off but whose cache matches
  the host's would install the guard; the status report closes that.
- **A fake Lua interface for the module.** Its interface has well over a hundred virtual methods
  and would test the fake; a polling-policy unit test and a source contract check cover what can be
  checked without a game.
