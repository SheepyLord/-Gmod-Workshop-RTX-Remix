# mainmenu.js

Two independent parts, appended to the stock control.Menu.js by the loader's exact read redirect.

**The verified RTX multiplayer bootstrap trigger** (ADR 0052). When the loader sets
`window.NativeLoaderClientBootstrap` (the committed generation holds the `gmsv_nlrtxclient` helper),
it runs `require( "nlrtxclient" )` once through the menu's Lua bridge, waiting up to two minutes
for that bridge. It does not depend on the diagnostics panel or its data, and the loader installs it
even when the stock menu controller the overlay decorates has changed (a GMod menu update): that
view carries only the trigger, with a startup note
([ADR 0056](../../../docs/decisions/0056-guard-and-startup-fallbacks.md)).

**The display-only diagnostics panel**, appended only beside the stock menu controller. Shows OS,
CPU/logical threads, physical RAM, graphics adapters/VRAM, the game's own version/branch, loader
version/file SHA-256 and deployed native package versions/manifest SHA-256. Hashes are
abbreviated visually, available in hover text and copied in full by the explicit copy button.
The panel appears on the main-menu home screen only and follows the menu language. Values use
textContent, never HTML. No upload, automatic URL opening, startup-log reading or disk writes.
The project link and clipboard functions run only on a click. Labels are in labels.json;
layout/style and project URL are edited here. Compiled into winmm.dll through CMake.

R6 adds local failure and memory notices in all seven languages. On the visible home panel, a
bounded request through the stock Lua bridge runs the embedded `read_notices.lua` and receives only
this process/start's `previous_session` and latest system commit snapshot. A failure other than
clean/unknown names what happened and its local evidence folder (or that saving failed). Both are
included by the existing explicit copy button.

Before the first map, a fresh commit snapshot (at most 30 seconds old, allowing five seconds of clock
skew) shows the warning below 32 GiB of commit limit or above 70 percent used. Text explains the risk,
a system-managed page file on a drive with room, and closing other programs. A visible warning is
acknowledged only in the menu Lua realm, keyed by PID plus process creation time, so page reloads do
not repeat it. It disappears when leaving home; language changes translate a still-visible notice.
No warning is consumed while hidden or shown after a map. Local read retries are bounded to 120 at
most once per second. Missing/stale/other-process data quietly gives no memory warning. These reads
and the acknowledgement perform no network actions or filesystem writes.
