# mainmenu.js

Independent parts, appended to the stock control.Menu.js by the loader's exact read redirect.

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

## R6 performance tier

Shows one localized line for the effective performance tier and source (automatic, config override
or built-in fallback) only when an adapter description and a listed tier layer are present.
Startup prepares its data after tier writes; failed/vanilla activation has no tier row. High and
pre-R6 medium have no tier layer and no row. Read-only previews apply the rendering-recipe gate.
It never consumes GPU diagnostics or reads stale status.
The new non-English tier/source translations in `labels.json` are agent-written, awaiting review;
JSON catalogs do not permit comments. Inputs/outputs and exit behavior are unchanged.

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

## R20-A update and multiplayer modals

Only `rtx_active` menu data enables these notices. The C++ release reader verifies the active native
runtime owner's exact journaled record; JS rechecks its two fields, version grammar/precedence and
exact version-specific project URL before offering it. Home shows the update once per process,
with the installed/latest versions and DLL replacement/restart instructions. Open calls gui.OpenURL
with only that URL; Later is this start; Ignore writes just that version to DATA. No HTTP check.

`menu_choices.lua` reads bounded preferences and the menu Lua realm's process-token acknowledgement.
Fixed button snippets write only `native-loader/loader-update-ignored.txt` and
`native-loader/multiplayer-warning-dismissed.txt` under DATA. No cloud or loader settings writes.
The latter is saved only when Continue has its checkbox checked. Angular's location-change listener
intercepts every `/servers` entry, including descendants, query strings and code/history navigation
in main/pause menus. Continue permits the pending destination once; Back navigates home. Missing
bridge, changed controller or failed dialog creation leaves the browser available. The bootstrap
trigger remains independent. Text nodes, seven catalogs, viewport-scaled font/layout, keyboard
focus and a labeled dialog keep these modals readable. Harness: `menu_diagnostics_harness.js`.
